defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking

@host <<"domain.net">>

# -- Generators -------------------------------------------------------------

def hook_name,       do: elements [:hook1, :hook2, :hook3]
def hook_result,     do: elements [:ok, :stop, :error, {:"$eqc_exception", :fail}]

def run_params(:undefined) do
  let n <- choose(0, 3), do: run_params(n)
end
def run_params(n),   do: vector(n, choose(0, 100))

def sequence_number, do: choose(0, 100)

# -- State ------------------------------------------------------------------

## use maps Elixir has maps anyway and testing is done on R17
def initial_state, do: %{hooks: %{}}

def get_hooks(state, name) do
  case Map.fetch(state.hooks, name) do
    {:ok, hooks} -> hooks
    :error       -> []
  end
end

def hook_arity(state, name) do
  case get_hooks(state, name) do
    []                -> :undefined
    [{_, _, _, arity}|_] -> arity
  end
end

def add_hook(state, name, hook) do
  hooks = get_hooks(state, name)
  %{state | hooks: Map.put(state.hooks, name, :lists.keymerge(2, hooks, [hook]))}
end

# -- Commands ---------------------------------------------------------------

# --- add an anonymous handler ---

def add_anonymous_args(state) do
  let name <- hook_name do
    arity = case hook_arity(state, name) do
              :undefined -> choose(0, 3)
              n          -> n
            end
    [hook_name, arity, :eqc_gen.noshrink(choose(1, 1000)), sequence_number]
  end
end

# Don't add more than one hook with the same sequence number. The system allows
# that but does a usort on the hooks when running them, which gets super weird
# for anonymous functions.
def add_anonymous_pre(state, [name, arity, _, seq]) do
  not :lists.keymember(seq, 2, get_hooks(state, name)) and
  hook_arity(state, name) in [:undefined, arity]
end

def add_anonymous(name, arity, id, seq) do
  fun = case arity do
          0 -> fn          -> :hook.anon(name, seq, [],        id) end
          1 -> fn(x)       -> :hook.anon(name, seq, [x],       id) end
          2 -> fn(x, y)    -> :hook.anon(name, seq, [x, y],    id) end
          3 -> fn(x, y, z) -> :hook.anon(name, seq, [x, y, z], id) end
        end
  :ejabberd_hooks.add(name, @host, fun, seq)
end

def add_anonymous_next(state, _, [name, arity, id, seq]) do
  add_hook(state, name, {:fun, seq, id, arity})
end

# -- add an mf -------------------------------------------------------------

def mf_arity(:fun0), do: 0
def mf_arity(:fun1), do: 1
def mf_arity(:fun2), do: 2
def mf_arity(:fun3), do: 3

def add_mf_args(state) do
  let name <- hook_name do
  let fun  <- elements(for f <- [:fun0, :fun1, :fun2, :fun3],
                           hook_arity(state, name) in [:undefined, mf_arity(f)],
                           do: f) do
  [name, fun, sequence_number]
  end end
end

def add_mf_pre(state, [name, fun, seq]) do
  not :lists.keymember(seq, 2, get_hooks(state, name)) and
  hook_arity(state, name) in [:undefined, mf_arity(fun)]
end

def add_mf(name, fun, seq) do
  :ejabberd_hooks.add(name, @host, :hook, fun, seq)
end

def add_mf_next(state, _, [name, fun, seq]) do
  add_hook(state, name, {:mf, seq, fun, mf_arity(fun)})
end

# --- running a handler ---

def run_args(state) do
  let name <- hook_name, do: [hook_name, run_params(hook_arity(state, name))]
end

def run_pre(state, [name, args]) do
  hook_arity(state, name) in [:undefined, length(args)]
end

def run(hookname, params) do
  :ejabberd_hooks.run(hookname, @host, params)
end

def run_callouts(state, [name, args]) do
  {:self_callout, __MODULE__, :call_hooks, [name, args, get_hooks(state, name)]}
end

def call_hooks_callouts(_state, [_name, _, []]), do: :empty
def call_hooks_callouts(_state, [name, args, [{type, seq, id, arity}|hooks]]) do
  call =
    case type do
      _ when length(args) != arity -> {:fail, {:bad_arguments, args, arity}}
      :mf  -> :eqc_component.callout(:hook, id, args, hook_result)
      :fun -> :eqc_component.callout(:hook, :anon, [name, seq, args, id], hook_result)
    end
  {:bind, call,
    fn(:stop) -> :empty
      (_)     -> {:self_callout, __MODULE__, :call_hooks, [name, args, hooks]}
    end}
end

def run_post(_state, [_name, _args], res) do
  eq(res, :ok)
end

# --- get info on a handler ---

def get_args(_state), do: [ hook_name ]

def get(hookname) do
  :ejabberd_hooks.get_handlers(hookname, @host)
end

def get_post(state, [name], res) do
  expected = for {_, seq, _, _} <- get_hooks(state, name), do: seq
  actual   = for r <- res do
               case r do
                {seq, :undefined, fun} when is_function(fun) -> seq
                {seq, :hook, _}                              -> seq
                _                                            -> :bad
               end end
  :eqc_statem.conj([:eqc_statem.eq(length(res), length(expected)),
                    :eqc_statem.eq(actual, expected)])
end

# -- Property ---------------------------------------------------------------

weight _hooks,
  add_anonymous: 1,
  get:           1,
  run:           1

property "Ejabberd Hooks" do
  # :eqc_statem.show_states(
    EQC.setup :eqc_mocking.start_mocking(api_spec)  do
    forall cmds <- commands(__MODULE__) do
      {:ok, pid} = :ejabberd_hooks.start_link
      :erlang.unlink(pid)
      :true = :ejabberd_hooks.delete_all_hooks
      res = run_commands(__MODULE__, cmds)
      :erlang.exit(pid, :kill)
      pretty_commands(__MODULE__, cmds, res,
        :eqc.aggregate(command_names(cmds),
          res[:result] == :ok))
      end
    end
end

# -- API spec ---------------------------------------------------------------

def api_spec do
  EQC.Mocking.api_spec [
    modules: [
      EQC.Mocking.api_module name: :hook,
        functions:
          [ EQC.Mocking.api_fun(name: :anon,       arity: 4),
            EQC.Mocking.api_fun(name: :fun0,       arity: 0),
            EQC.Mocking.api_fun(name: :fun1,       arity: 1),
            EQC.Mocking.api_fun(name: :fun2,       arity: 2),
            EQC.Mocking.api_fun(name: :fun3,       arity: 3) ]
    ]
  ]
end


end
