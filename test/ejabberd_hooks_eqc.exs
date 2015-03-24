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
def sequence_number, do: choose(0, 20)
def host,            do: elements [:global, 'domain.net']
def hook_module,     do: elements [:hook, :zook]
def hook_fun,        do: elements [:fun0, :fun1, :fun2]
def handler,         do: oneof [{hook_module, hook_fun}, {:fn, choose(0, 2), arg}]

# -- State ------------------------------------------------------------------

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
  for h={_, d} <- get_hooks(state, name, host), get_arity(d.fun) == arity, do: h
end

# This computes the unique key according to which handlers are ordered.
# There can be at most one handler with the same key for a given hook. This
# ordering is a little bit unpredictable for anonymous handlers since they are
# compared on the 'fun' values when they have the same sequence number.
def hook_ref(name, {seq, hook}) do
  case hook.fun do
    {:fn, arity, id} -> {hook.host, seq, :undefined, anonymous_fun(name, arity, id, seq)}
    {mod, fun}       -> {hook.host, seq, mod, fun}
  end
end

def add_hook(state, name, hook) do
  new_hooks = :lists.usort(fn(h1, h2) -> hook_ref(name, h1) <= hook_ref(name, h2) end,
                           [hook|get_hooks(state, name)])
  %{state | hooks: Map.put(state.hooks, name, new_hooks)}
end

def filter_hooks(state, name, pred) do
  new_hooks = :lists.filter(fn({seq, h}) -> pred.(seq, h) end, get_hooks(state, name))
  case new_hooks do
    [] -> %{state | hooks: Map.delete(state.hooks, name)}
    _  -> %{state | hooks: Map.put(state.hooks, name, new_hooks)}
  end
end

def delete_hook(state, name, hook) do
  filter_hooks(state, name, fn(seq, h) -> {seq, h} != hook end)
end

def get_arity({mod, fun}),      do: get_api_arity(mod, fun)
def get_arity({:fn, arity, _}), do: arity

def anonymous_fun(name, arity, id, seq) do
  case arity do
    0 -> fn          -> :hook.anon(name, seq, [],        id) end
    1 -> fn(x)       -> :hook.anon(name, seq, [x],       id) end
    2 -> fn(x, y)    -> :hook.anon(name, seq, [x, y],    id) end
    3 -> fn(x, y, z) -> :hook.anon(name, seq, [x, y, z], id) end
  end
end

# -- Commands ---------------------------------------------------------------

# --- add a handler ---

def add_args(_state), do: [hook_name, host, handler, sequence_number]

def add(name, host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.add(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def add(name, host, {mod, fun}, seq) do
  :ejabberd_hooks.add(name, host, mod, fun, seq)
end

def add_next(state, _, [name, host, fun, seq]) do
  add_hook(state, name, {seq, %{host: host, fun: fun}})
end

# -- delete a hook ----------------------------------------------------------

def delete_args(state) do
  let {name, hooks} <- elements(Map.to_list(state.hooks)) do
  let {seq, h}      <- elements(hooks) do
    [name, host, h.fun, seq]
  end end
end

def delete_pre(state) do
  %{} != state.hooks
end

def delete(name, host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.delete(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def delete(name, host, {mod, fun}, seq) do
  :ejabberd_hooks.delete(name, host, mod, fun, seq)
end

def delete_next(state, _, [name, host, fun, seq]) do
  delete_hook(state, name, {seq, %{host: host, fun: fun}})
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
    case hook.fun do
      {mod, fun}   -> callout(mod, fun, args, hook_result)
      {:fn, _, id} -> callout :hook.anon(name, seq, args, id), return: hook_result
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
    case hook.fun do
      {mod, fun}   -> callout(mod, fun, [val|args], hook_result)
      {:fn, _, id} -> callout :hook.anon(name, seq, [val|args], id), return: hook_result
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
    case hook.fun do
      {:fn, arity, id} -> {seq, :undefined, anonymous_fun(name, arity, id, seq)}
      {mod, fun}       -> {seq, mod, fun}
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
      EQC.Mocking.api_module(name: :hook,
        functions:
          [ EQC.Mocking.api_fun(name: :anon,       arity: 4),
            EQC.Mocking.api_fun(name: :fun0,       arity: 0),
            EQC.Mocking.api_fun(name: :fun1,       arity: 1),
            EQC.Mocking.api_fun(name: :fun2,       arity: 2) ]),
      EQC.Mocking.api_module(name: :zook,
        functions:
          [ EQC.Mocking.api_fun(name: :fun0,       arity: 0),
            EQC.Mocking.api_fun(name: :fun1,       arity: 1),
            EQC.Mocking.api_fun(name: :fun2,       arity: 2) ])
    ]
  ]
end

def get_api_arity(mod, fun) do
  as =
    for m <- EQC.Mocking.api_spec(api_spec)[:modules],
        EQC.Mocking.api_module(m, :name) == mod,
        f <- EQC.Mocking.api_module(m, :functions),
        EQC.Mocking.api_fun(f, :name) == fun do
      EQC.Mocking.api_fun(f, :arity)
    end
  case as do
    [a] -> a
    []  -> :erlang.error({:not_in_api_spec, mod, fun})
    _   -> :erlang.error({:ambiguous_arity, mod, fun, as})
  end
end

end
