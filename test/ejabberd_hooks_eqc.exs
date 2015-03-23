defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking

@host <<"domain.net">>

# -- Generators -------------------------------------------------------------

def arg,             do: elements [:a, :b, :c, :d, :e]
def hook_name,       do: elements [:hook1, :hook2, :hook3]
def hook_result,     do: elements [:ok, :stop, :error, {:"$eqc_exception", :fail}]
def run_params,      do: run_params(3)
def run_params(n),   do: :eqc_gen.list(n, arg)
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

def get_hooks(state, name, arity) do
  for h={_, _, _, a} <- get_hooks(state, name), a == arity, do: h
end

def add_hook(state, name, hook) do
  hooks = get_hooks(state, name)
  %{state | hooks: Map.put(state.hooks, name, :lists.keymerge(2, hooks, [hook]))}
end

def delete_hook(state, name, hook) do
  hooks = get_hooks(state, name) -- [hook]
  case hooks do
    [] -> %{state | hooks: Map.delete(state.hooks, name)}
    _  -> %{state | hooks: Map.put(state.hooks, name, hooks)}
  end
end

# -- Commands ---------------------------------------------------------------

# --- add an anonymous handler ---

def add_anonymous_args(_state) do
  [hook_name, choose(0, 3), :eqc_gen.noshrink(choose(1, 1000)), sequence_number]
end

# Don't add more than one hook with the same sequence number. The system allows
# that but does a usort on the hooks when running them, which gets super weird
# for anonymous functions.
def add_anonymous_pre(state, [name, _, _, seq]) do
  not :lists.keymember(seq, 2, get_hooks(state, name))
end

def add_anonymous(name, arity, id, seq) do
  :ejabberd_hooks.add(name, @host, anonymous_fun(name, arity, id, seq), seq)
end

def anonymous_fun(name, arity, id, seq) do
  case arity do
    0 -> fn          -> :hook.anon(name, seq, [],        id) end
    1 -> fn(x)       -> :hook.anon(name, seq, [x],       id) end
    2 -> fn(x, y)    -> :hook.anon(name, seq, [x, y],    id) end
    3 -> fn(x, y, z) -> :hook.anon(name, seq, [x, y, z], id) end
  end
end

def add_anonymous_next(state, _, [name, arity, id, seq]) do
  add_hook(state, name, {:fun, seq, id, arity})
end

# -- add an mf -------------------------------------------------------------

def mf_arity(:fun0), do: 0
def mf_arity(:fun1), do: 1
def mf_arity(:fun2), do: 2
def mf_arity(:fun3), do: 3

def add_mf_args(_state) do
  [hook_name, elements([:fun0, :fun1, :fun2, :fun3]), sequence_number]
end

def add_mf_pre(state, [name, _fun, seq]) do
  not :lists.keymember(seq, 2, get_hooks(state, name))
end

def add_mf(name, fun, seq) do
  :ejabberd_hooks.add(name, @host, :hook, fun, seq)
end

def add_mf_next(state, _, [name, fun, seq]) do
  add_hook(state, name, {:mf, seq, fun, mf_arity(fun)})
end

# -- delete a hook ----------------------------------------------------------

def delete_args(state) do
  let {name, hooks}          <- elements(Map.to_list(state.hooks)) do
  let {type, seq, id, arity} <- elements(hooks) do
    return([name, type, seq, id, arity])
  end end
end

def delete_pre(state) do
  %{} != state.hooks
end

def delete_pre(state, [name, type, seq, id, arity]) do
  {type, seq, id, arity} in get_hooks(state, name)
end

def delete(name, :fun, seq, id, arity) do
  :ejabberd_hooks.delete(name, @host, anonymous_fun(name, arity, id, seq), seq)
end
def delete(name, :mf, seq, fun, _arity) do
  :ejabberd_hooks.delete(name, @host, :hook, fun, seq)
end

def delete_next(state, _, [name, type, seq, id, arity]) do
  delete_hook(state, name, {type, seq, id, arity})
end

# --- running a handler ---

def run_args(_state), do: [hook_name, run_params]

def run(hookname, params) do
  :ejabberd_hooks.run(hookname, @host, params)
end

def run_callouts(state, [name, args]) do
  call call_hooks(name, args, get_hooks(state, name, length(args)))
end

def call_hooks_callouts(_state, [_name, _, []]), do: :empty
def call_hooks_callouts(_state, [name, args, [{type, seq, id, _arity}|hooks]]) do
  match res =
    case type do
      :mf  -> callout(:hook, id, args, hook_result)
      :fun -> callout :hook.anon(name, seq, args, id), return: hook_result
    end
  case res do
    :stop -> :empty
    _     -> call call_hooks(name, args, hooks)
  end
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
