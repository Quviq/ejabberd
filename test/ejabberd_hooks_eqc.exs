defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking

@host <<"domain.net">>

# -- Generators -------------------------------------------------------------

def hook_name,       do: elements [:hook1, :hook2, :hook3]
def hook_result,     do: elements [:ok, :stop, :error, :zzz]
def run_params,      do: []
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

def add_hook(state, name, hook) do
  hooks = get_hooks(state, name)
  %{state | hooks: Map.put(state.hooks, name, :lists.merge(hooks, [hook]))}
end

# -- Commands ---------------------------------------------------------------

# --- add an anonymous handler ---

def add_anonymous_args(_state) do
  [hook_name, hook_result, sequence_number]
end

# Don't add more than one hook with the same sequence number. The system allows
# that but does a usort on the hooks when running them, which gets super weird
# for anonymous functions.
def add_anonymous_pre(state, [name, _, seq]) do
  not :lists.keymember(seq, 1, get_hooks(state, name))
end

def add_anonymous(name, res, seq) do
  fun = fn -> :hook.call(name, seq, res); res end
  :ejabberd_hooks.add(name, @host, fun, seq)
end

def add_anonymous_next(state, _, [name, res, seq]) do
  add_hook(state, name, {seq, res})
end

# -- add an mf -------------------------------------------------------------

def add_mf_args(_state) do
  [hook_name, elements([:ok, :stop]), sequence_number]
end

def add_mf_pre(state, [name, _, seq]) do
  not :lists.keymember(seq, 1, get_hooks(state, name))
end

def add_mf(name, res, seq) do
  :ejabberd_hooks.add(name, @host, :hook, res, seq)
end

def add_mf_next(state, _, [name, res, seq]) do
  add_hook(state, name, {seq, {:mf, res}})
end

# --- running a handler ---

def run_args(_state) do [hook_name, run_params] end

def run(hookname, params) do
  :ejabberd_hooks.run(hookname, @host, params)
end

def run_callouts(state, [name, _params]) do
  {:seq, call_hooks(name, get_hooks(state, name))}
end

defp call_hooks(_name, []), do: []
defp call_hooks(name, [{seq, res}|hooks]) do
  call =
    case res do
      {:mf, res} -> :eqc_component.callout(:hook, res, [], res)
      _          -> :eqc_component.callout(:hook, :call, [name, seq, res], res)
    end
  case res do
    :stop        -> [call]
    {:mf, :stop} -> [call]
    _            -> [call|call_hooks(name, hooks)]
  end
end

def run_post(_state, [_name, _params], res) do
  eq(res, :ok)
end

# --- get info on a handler ---

def get_args(_state), do: [ hook_name ]

def get(hookname) do
  :ejabberd_hooks.get_handlers(hookname, @host)
end

def get_post(state, [name], res) do
  expected = for {seq, _} <- get_hooks(state, name), do: seq
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
          [ EQC.Mocking.api_fun(name: :call, arity: 3),
            EQC.Mocking.api_fun(name: :ok,   arity: 0),
            EQC.Mocking.api_fun name: :stop, arity: 0 ]
    ]
  ]
end


end
