defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking

# -- Generators -------------------------------------------------------------

def gen_arg,             do: elements [:a, :b, :c, :d, :e]
def gen_hook_name,       do: elements [:hook1, :hook2, :hook3]
def gen_hook_result,     do: elements [:ok, :stop, :error, exception(:fail)]
def gen_run_params,      do: gen_run_params(2)
def gen_run_params(n),   do: :eqc_gen.list(n, gen_arg)
def gen_sequence_number, do: choose(0, 20)
def gen_host,            do: elements [:global, this_host]
def gen_node,            do: elements [this_node() | child_nodes()]
def gen_hook_module,     do: elements [:hook, :zook]
def gen_hook_fun,        do: elements [:fun0, :fun1, :fun2]
def gen_handler,         do: oneof [{gen_hook_module, gen_hook_fun}, {:fn, choose(0, 2), gen_arg}]

# -- Distribution -----------------------------------------------------------

def child_nodes, do: [:node1, :node2]

def this_node do
  [name, _] = :string.tokens(:erlang.atom_to_list(node), '@')
  :erlang.list_to_atom(name)
end

def this_host() do
  [_, host] = :string.tokens(:erlang.atom_to_list(node), '@')
  host
end

def mk_node(name),       do: mk_node(name, this_host)
def mk_node(name, host), do: :erlang.list_to_atom(:lists.concat([name, '@', host]))

# -- State ------------------------------------------------------------------

# hooks_with_past_handlers are used to model the buggy behaviour of
# get_hooks_with_handlers (see below).
def initial_state, do: %{hooks: %{}, hooks_with_past_handlers: %{}}

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
  key =
    case hook do
      %{fun: {:fn, arity, id}} ->
        {seq, :undefined, anonymous_fun(name, arity, id, seq)}
      %{fun: {mod, fun}, node: node} ->
        {seq, mk_node(node), mod, fun}
      %{fun: {mod, fun}} ->
        {seq, mod, fun}
    end
  {hook.host, key}
end

def add_hook(state, name, hook) do
  new_hooks = :lists.usort(fn(h1, h2) -> hook_ref(name, h1) <= hook_ref(name, h2) end,
                           [hook|get_hooks(state, name)])
  %{state | hooks: Map.put(state.hooks, name, new_hooks),
            hooks_with_past_handlers: Map.put(state.hooks_with_past_handlers, name, true) }
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

def add_args(_state), do: [gen_hook_name, gen_host, gen_handler, gen_sequence_number]

def add(name, host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.add(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def add(name, host, {mod, fun}, seq) do
  :ejabberd_hooks.add(name, host, mod, fun, seq)
end

def add_next(state, _, [name, host, fun, seq]) do
  add_hook(state, name, {seq, %{host: host, fun: fun}})
end

# --- add a distributed handler ---

def add_dist_args(_state) do
  [gen_hook_name, gen_host, gen_node,
   gen_hook_module, gen_hook_fun, gen_sequence_number]
end

def add_dist(name, host, node, mod, fun, seq) do
  :ejabberd_hooks.add_dist(name, host, mk_node(node), mod, fun, seq)
end

def add_dist_next(state, _, [name, host, node, mod, fun, seq]) do
  add_hook(state, name, {seq, %{host: host, node: node, fun: {mod, fun}}})
end

# -- delete a handler -------------------------------------------------------

def delete_args(state) do
  let {name, hooks} <- elements(Map.to_list(state.hooks)) do
  let {seq, h}      <- elements(hooks) do
    case Map.has_key?(h, :node) do
      true  -> return [name, h.host, h.node, h.fun, seq]
      false -> return [name, h.host, h.fun, seq]
    end
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
def delete(name, host, node, {mod, fun}, seq) do
  :ejabberd_hooks.delete_dist(name, host, mk_node(node), mod, fun, seq)
end

def delete_next(state, _, [name, host, fun, seq]) do
  delete_hook(state, name, {seq, %{host: host, fun: fun}})
end
def delete_next(state, _, [name, host, node, fun, seq]) do
  delete_hook(state, name, {seq, %{host: host, node: node, fun: fun}})
end

# -- removing all hooks for a module ----------------------------------------

def remove_module_handlers_args(_state), do: [gen_hook_name, gen_host, gen_hook_module]

def remove_module_handlers(name, host, module) do
  :ejabberd_hooks.remove_module_handlers(name, host, module)
end

def remove_module_handlers_next(state, _, [name, host, module]) do
  filter_hooks(state, name,
    fn (_, %{host: h}) when h != host -> true
       (_, %{fun: {mod, _}})          -> mod != module
       (_, _)                         -> true end)
end

# --- running a handler ---

def run_args(_state), do: [gen_hook_name, gen_host, gen_run_params]

def run(name, host, params) do
  :ejabberd_hooks.run(name, host, params)
end

def run_callouts(state, [name, host, args]) do
  call run_handlers(name, fn(args, _) -> args end, fn(_) -> :ok end,
                    args, get_hooks(state, name, host, length(args)))
  {:return, :ok}
end

# This helper command generalises run and run_fold. It takes two functions:
#   next(args, res) - computes the arguments for the next handler from the
#                     current arguments and the result of the current handler
#   ret(args)       - computes the final result given the current arguments
def run_handlers_callouts(_state, [_, _, ret, args, []]), do: {:return, ret.(args)}
def run_handlers_callouts(_state, [name, next, ret, args, [{seq, hook}|hooks]]) do
  match res =
    case hook.fun do
      {mod, fun}   -> callout(mod, fun, args, gen_hook_result)
      {:fn, _, id} -> callout :hook.anon(name, seq, args, id), return: gen_hook_result
    end
  case res do
    :stop        -> {:return, :stopped}
    exception(_) -> call run_handlers(name, next, ret, args, hooks)
    _            -> call run_handlers(name, next, ret, next.(args, res), hooks)
  end
end

# -- run_fold ---------------------------------------------------------------

def run_fold_args(_state) do
  [gen_hook_name, gen_host, gen_arg, gen_run_params(1)]
end

def run_fold(name, host, val, args) do
  :ejabberd_hooks.run_fold(name, host, val, args)
end

def run_fold_callouts(state, [name, host, val, args]) do
  # call fold_hooks(name, val, args, get_hooks(state, name, host, length(args) + 1))
  call run_handlers(name,
                    fn([_val|args], res) -> [res|args] end,
                    fn([val|_]) -> val end,
                    [val|args], get_hooks(state, name, host, length(args) + 1))
end

# --- get info on a handler ---

def get_args(_state), do: [gen_hook_name, gen_host]

def get(name, host) do
  :ejabberd_hooks.get_handlers(name, host)
end

def get_return(state, [name, host]) do
  for hook <- get_hooks(state, name, host) do
    {_, key} = hook_ref(name, hook)
    key
  end
end

# -- get_hooks_with_handlers ------------------------------------------------

def get_hooks_with_handlers_args(_state), do: []

def get_hooks_with_handlers, do: :ejabberd_hooks.get_hooks_with_handlers

# BUG: get_hooks_with_handlers returns hooks that have had handlers at some
#      point. They don't necessarily have any handlers at the moment.
def get_hooks_with_handlers_return(state, []), do: Map.keys state.hooks_with_past_handlers

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
    EQC.setup_teardown setup do
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
    after _ -> teardown
    end
end

def setup() do
  :eqc_mocking.start_mocking(api_spec)
  for name <- child_nodes do
    :slave.start(this_host(), name)
    :rpc.call(mk_node(name), :eqc_mocking, :start_mocking, [api_spec])
  end
end

def teardown() do
  # for name <- child_nodes do
  #   :slave.stop(mk_node(name))
  # end
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
