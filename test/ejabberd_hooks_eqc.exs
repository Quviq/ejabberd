defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking

# -- Generators -------------------------------------------------------------

def arg,             do: elements [:a, :b, :c, :d, :e]
def hook_name,       do: elements [:hook1, :hook2, :hook3]
def hook_result,     do: elements [:ok, :stop, :error, exception(:fail)]
def run_params,      do: run_params(2)
def run_params(n),   do: :eqc_gen.list(n, arg)
def sequence_number, do: choose(0, 100)
def host,            do: elements [:global, 'domain.net']

# -- State ------------------------------------------------------------------

## use maps Elixir has maps anyway and testing is done on R17
def initial_state, do: %{hooks: %{}}

def get_hooks(state, name) do
  case Map.fetch(state.hooks, name) do
    {:ok, hooks} -> hooks
    :error       -> []
  end
end

def get_hooks(state, name, host) do
  for h={_, d} <- get_hooks(state, name), d.host == host, do: h
end

def get_hooks(state, name, host, arity) do
  for h={_, d} <- get_hooks(state, name, host), d.arity == arity, do: h
end

def add_hook(state, name, hook) do
  hooks = get_hooks(state, name)
  %{state | hooks: Map.put(state.hooks, name, :lists.keymerge(1, hooks, [hook]))}
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
  [hook_name, host, choose(0, 3), :eqc_gen.noshrink(choose(1, 1000)), sequence_number]
end

# Don't add more than one hook with the same sequence number. The system allows
# that but does a usort on the hooks when running them, which gets super weird
# for anonymous functions.
def add_anonymous_pre(state, [name, _, _, _, seq]) do
  not :lists.keymember(seq, 1, get_hooks(state, name))
end

def add_anonymous(name, host, arity, id, seq) do
  :ejabberd_hooks.add(name, host, anonymous_fun(name, arity, id, seq), seq)
end

def anonymous_fun(name, arity, id, seq) do
  case arity do
    0 -> fn          -> :hook.anon(name, seq, [],        id) end
    1 -> fn(x)       -> :hook.anon(name, seq, [x],       id) end
    2 -> fn(x, y)    -> :hook.anon(name, seq, [x, y],    id) end
    3 -> fn(x, y, z) -> :hook.anon(name, seq, [x, y, z], id) end
  end
end

def add_anonymous_next(state, _, [name, host, arity, id, seq]) do
  add_hook(state, name, {seq, %{type: :fun, id: id, arity: arity, host: host}})
end

# -- add an mf -------------------------------------------------------------

def mf_arity(:fun0), do: 0
def mf_arity(:fun1), do: 1
def mf_arity(:fun2), do: 2
def mf_arity(:fun3), do: 3

def add_mf_args(_state) do
  [hook_name, host, elements([:fun0, :fun1, :fun2, :fun3]), sequence_number]
end

def add_mf_pre(state, [name, _host, _fun, seq]) do
  not :lists.keymember(seq, 1, get_hooks(state, name))
end

def add_mf(name, host, fun, seq) do
  :ejabberd_hooks.add(name, host, :hook, fun, seq)
end

def add_mf_next(state, _, [name, host, fun, seq]) do
  add_hook(state, name, {seq, %{type: :mf, mod: :hook, fun: fun, arity: mf_arity(fun), host: host}})
end

# -- delete a hook ----------------------------------------------------------

def delete_args(state) do
  let {name, hooks} <- elements(Map.to_list(state.hooks)) do
  let {seq, h}      <- elements(hooks) do
    id = case h.type do :fun -> h.id; :mf -> {h.mod, h.fun} end
    [name, host, h.type, seq, id, h.arity]
  end end
end

def delete_pre(state) do
  %{} != state.hooks
end

def delete(name, host, :fun, seq, id, arity) do
  :ejabberd_hooks.delete(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def delete(name, host, :mf, seq, {mod, fun}, _arity) do
  :ejabberd_hooks.delete(name, host, mod, fun, seq)
end

def delete_next(state, _, [name, host, :mf, seq, {mod, fun}, arity]) do
  delete_hook(state, name, {seq, %{type: :mf, mod: mod, fun: fun, arity: arity, host: host}})
end
def delete_next(state, _, [name, host, :fun, seq, id, arity]) do
  delete_hook(state, name, {seq, %{type: :fun, id: id, arity: arity, host: host}})
end

# --- running a handler ---

def run_args(_state), do: [hook_name, host, run_params]

def run(name, host, params) do
  :ejabberd_hooks.run(name, host, params)
end

def run_callouts(state, [name, host, args]) do
  call call_hooks(name, args, get_hooks(state, name, host, length(args)))
end

def call_hooks_callouts(_state, [_name, _, []]), do: :empty
def call_hooks_callouts(_state, [name, args, [{seq, hook}|hooks]]) do
  match res =
    case hook.type do
      :mf  -> callout(hook.mod, hook.fun, args, hook_result)
      :fun -> callout :hook.anon(name, seq, args, hook.id), return: hook_result
    end
  case res do
    :stop -> :empty
    _     -> call call_hooks(name, args, hooks)
  end
end

# -- run_fold ---------------------------------------------------------------

def run_fold_args(_state) do
  [hook_name, host, arg, run_params(1)]
end

def run_fold(name, host, val, args) do
  :ejabberd_hooks.run_fold(name, host, val, args)
end

def run_fold_callouts(state, [name, host, val, args]) do
  call fold_hooks(name, val, args, get_hooks(state, name, host, length(args) + 1))
end

def fold_hooks_callouts(_state, [_name, val, _, []]), do: {:return, val}
def fold_hooks_callouts(_state, [name, val, args, [{seq, hook}|hooks]]) do
  match res =
    case hook.type do
      :mf  -> callout(hook.mod, hook.fun, [val|args], hook_result)
      :fun -> callout :hook.anon(name, seq, [val|args], hook.id), return: hook_result
    end
  case res do
    :stop        -> {:return, :stopped}
    exception(_) -> call fold_hooks(name, val, args, hooks)
    _            -> call fold_hooks(name, res, args, hooks)
  end
end

# --- get info on a handler ---

def get_args(_state), do: [hook_name, host]

def get(name, host) do
  :ejabberd_hooks.get_handlers(name, host)
end

def get_return(state, [name, host]) do
  for {seq, hook} <- get_hooks(state, name, host) do
    case hook.type do
      :fun -> {seq, :undefined, anonymous_fun(name, hook.arity, hook.id, seq)}
      :mf  -> {seq, hook.mod, hook.fun}
    end
  end
end

# -- Common -----------------------------------------------------------------

def postcondition_common(state, call, res) do
  eq(res, return_value(state, call))
end

# -- Weights ----------------------------------------------------------------

weight _hooks,
  add_anonymous: 1,
  get:           1,
  run:           1

# -- Property ---------------------------------------------------------------

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
