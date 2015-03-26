defmodule Hooks_eqc do

use ExUnit.Case
use EQC.ExUnit
use EQC.Component
require EQC.Mocking
require Record

# -- Issues -----------------------------------------------------------------

# - get_hooks_with_handlers returns hooks that have had handlers at some point,
#   not just hooks that currently have handlers.

# - The arity check for core_hooks doesn't work if the same handler is defined
#   for multiple arities.

# - Sorting handlers with the same sequence number on the fun value leads to
#   somewhat unpredictable behaviour.

# - The check if a module:function handler exists is done on the node where
#   ejabberd runs, not on the node where the function is supposed to run. It's
#   conceivable that you might have different code on different nodes.

# -- Generators -------------------------------------------------------------

Record.defrecord :hook, Record.extract(:hook, from_lib: "ejabberd/include/ejabberd_hooks.hrl")

def core_hooks() do
  for h <- :ejabberd_hooks_core.all() do
    kvs = hook(h)
    {kvs[:name], kvs[:arity]}
  end
end

@max_params 3
@max_sequence_number 5

def gen_arg,             do: elements [:a, :b, :c, :ok, :error, :stop]
def gen_hook_name,       do: elements([:hook1, :hook2] ++ for {h, _} <- core_hooks, do: h)

# Favour hooks with handlers.
def gen_hook_name(state) do
  case Map.keys(state.hooks) do
    []    -> gen_hook_name
    hooks -> frequency [{9, elements(hooks)}, {1, gen_hook_name}]
  end end

def gen_result           do
  EQC.lazy do
    shrink(
      frequency([{4, gen_arg},
                 {1, let(r <- gen_arg, do: return(exception(r)))},
                 {1, :stop},
                 {1, {:stop, gen_result}}]),
      [:ok])
  end
end

def gen_run_params,      do: gen_run_params(@max_params)
def gen_run_params(n),   do: :eqc_gen.list(n, gen_arg)
def gen_sequence_number, do: choose(0, @max_sequence_number)
def gen_host,            do: elements [:no_host, :global, this_host]
def gen_node,            do: elements [this_node() | child_nodes()]
def gen_module,          do: elements [:handlers, :zandlers]
def gen_fun_name,        do: elements [:fun0, :fun1, :fun2, :fun3, :funX]
def gen_handler,         do: oneof [{gen_module, gen_fun_name}, {:fn, choose(0, @max_params), gen_arg}]
def gen_faulty_handler,  do: oneof [{:bad_module, gen_fun_name}, {gen_module, :bad_fun}]

# Used in delete to test deleting things we haven't added.
defp gen_any_handler() do
  set_node = fn(nil, h) -> h; (n, h) -> Map.put(h, :node, n) end
  let {seq, host, fun} <- {gen_sequence_number, gen_host, gen_handler} do
    h = %{host: host, fun: fun}
    case fun do
      {:fn, _, _} -> return {seq, h}
      _ -> let node <- weighted_default({2, nil}, {1, gen_node}) do
             return {seq, set_node.(node, h)}
           end
    end end
end

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

def get_handlers(state, name) do
  case Map.fetch(state.hooks, name) do
    {:ok, handlers} -> handlers
    :error          -> []
  end
end

def get_handlers(state, name, host) do
  for h={_, d} <- get_handlers(state, name), d.host == host, do: h
end

def get_handlers(state, name, host, arity) do
  for h={_, d} <- get_handlers(state, name, host), arity in get_arity(d.fun), do: h
end

# This computes the unique key according to which handlers are ordered.
# There can be at most one handler with the same key for a given hook. This
# ordering is a little bit unpredictable for anonymous handlers since they are
# compared on the 'fun' values when they have the same sequence number.
def handler_key(name, {seq, handler}) do
  key =
    case handler do
      %{fun: {:fn, arity, id}} ->
        {seq, :undefined, anonymous_fun(name, arity, id, seq)}
      %{fun: {mod, fun}, node: node} ->
        {seq, mk_node(node), mod, fun}
      %{fun: {mod, fun}} ->
        {seq, mod, fun}
    end
  {handler.host, key}
end

def add_handler(state, name, h, seq) do
  handler = {seq, h}
                 # usort handlers based on handler_key()
  new_handlers = :lists.usort(fn(h1, h2) -> handler_key(name, h1) <= handler_key(name, h2) end,
                              [handler|get_handlers(state, name)])
  %{state | hooks: Map.put(state.hooks, name, new_handlers),
            hooks_with_past_handlers: Map.put(state.hooks_with_past_handlers, name, true) }
end

def filter_handlers(state, name, pred) do
  new_hooks = :lists.filter(fn({seq, h}) -> pred.(seq, h) end, get_handlers(state, name))
  case new_hooks do
    [] -> %{state | hooks: Map.delete(state.hooks, name)}
    _  -> %{state | hooks: Map.put(state.hooks, name, new_hooks)}
  end
end

def delete_handler(state, name, handler, seq) do
  filter_handlers(state, name, fn(s, h) -> {s, h} != {seq, handler} end)
end

def get_arity({mod, fun}),      do: get_api_arity(mod, fun)
def get_arity({:fn, arity, _}), do: [arity]

def anonymous_fun(name, arity, id, seq) do
  case arity do
    0 -> fn          -> :handlers.anon(name, seq, [],        id) end
    1 -> fn(x)       -> :handlers.anon(name, seq, [x],       id) end
    2 -> fn(x, y)    -> :handlers.anon(name, seq, [x, y],    id) end
    3 -> fn(x, y, z) -> :handlers.anon(name, seq, [x, y, z], id) end
  end
end

def check_fun(fun), do: check_fun(this_node(), fun)
def check_fun(_, {:bad_module, _}), do: {:error, :module_not_found}
def check_fun(_, {_, :bad_fun}),    do: {:error, :undefined_function}
def check_fun(name, fun) do
  case core_hooks()[name] do
    nil   -> :ok
    arity ->
      case arity in get_arity(fun) do
        true  -> :ok
        false -> {:error, :incorrect_arity}
      end
  end
end

defp mk_list(xs) when is_list(xs), do: xs
defp mk_list(x), do: [x]

defp mk_host(:no_host), do: :global
defp mk_host(h),        do: h

# -- Commands ---------------------------------------------------------------

# --- add a handler ---

def add_args(state) do
  [gen_hook_name(state), gen_host,
   fault(gen_faulty_handler, gen_handler), gen_sequence_number]
end

## BUG: don't add :funX to core hooks since they don't work with multiple arity
##      functions
def add_pre(_state, [name, _, {_, :funX}, _]), do: nil == core_hooks()[name]
def add_pre(_state, _args), do: true

def add(name, :no_host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.add(name, anonymous_fun(name, arity, id, seq), seq)
end
def add(name, :no_host, {mod, fun}, seq) do
  :ejabberd_hooks.add(name, mod, fun, seq)
end
def add(name, host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.add(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def add(name, host, {mod, fun}, seq) do
  :ejabberd_hooks.add(name, host, mod, fun, seq)
end

def add_callouts(_state, [name, host, fun, seq]) do
  case check_fun(name, fun) do
    :ok -> call do_add(name, %{host: mk_host(host), fun: fun}, seq)
    err -> {:return, err}
  end
end

def do_add_next(state, _, [name, handler, seq]) do
  add_handler(state, name, handler, seq)
end

# --- add a distributed handler ---

def add_dist_args(state) do
  [gen_hook_name(state), gen_host, gen_node,
   gen_module, gen_fun_name, gen_sequence_number]
end

## BUG: don't add :funX to core hooks since they don't work with multiple arity
##      functions
def add_dist_pre(_state, [name, _, _, _, :funX, _]), do: nil == core_hooks()[name]
def add_dist_pre(_state, _args), do: true

def add_dist(name, :no_host, node, mod, fun, seq) do
  :ejabberd_hooks.add_dist(name, mk_node(node), mod, fun, seq)
end
def add_dist(name, host, node, mod, fun, seq) do
  :ejabberd_hooks.add_dist(name, host, mk_node(node), mod, fun, seq)
end

def add_dist_callouts(_state, [name, host, node, mod, fun, seq]) do
  case check_fun(name, {mod, fun}) do
    :ok -> call do_add(name, %{host: mk_host(host), node: node, fun: {mod, fun}}, seq)
    err -> {:return, err}
  end
end

# --- delete a handler ---

def delete_args(state) do
  let {name, handlers} <- elements(Map.to_list(state.hooks)) do
  let {seq, h}         <- fault(gen_any_handler, elements(handlers)) do
    hosts = case h.host do :global -> [:no_host, :global]; _ -> [h.host] end
    case Map.has_key?(h, :node) do
      true  -> [name, elements(hosts), h.node, h.fun, seq]
      false -> [name, elements(hosts), h.fun, seq]
    end
  end end
end

def delete_pre(state) do
  %{} != state.hooks
end

def delete(name, :no_host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.delete(name, anonymous_fun(name, arity, id, seq), seq)
end
def delete(name, :no_host, {mod, fun}, seq) do
  :ejabberd_hooks.delete(name, mod, fun, seq)
end
def delete(name, host, {:fn, arity, id}, seq) do
  :ejabberd_hooks.delete(name, host, anonymous_fun(name, arity, id, seq), seq)
end
def delete(name, host, {mod, fun}, seq) do
  :ejabberd_hooks.delete(name, host, mod, fun, seq)
end

def delete(name, :no_host, node, {mod, fun}, seq) do
  :ejabberd_hooks.delete_dist(name, mk_node(node), mod, fun, seq)
end
def delete(name, host, node, {mod, fun}, seq) do
  :ejabberd_hooks.delete_dist(name, host, mk_node(node), mod, fun, seq)
end

def delete_next(state, _, [name, host, fun, seq]) do
  delete_handler(state, name, %{host: mk_host(host), fun: fun}, seq)
end
def delete_next(state, _, [name, host, node, fun, seq]) do
  delete_handler(state, name, %{host: mk_host(host), node: node, fun: fun}, seq)
end

# --- removing all handlers for a module ---

def remove_module_handlers_args(state) do
  [gen_hook_name(state), gen_host, gen_module]
end

def remove_module_handlers(name, :no_host, module) do
  :ejabberd_hooks.remove_module_handlers(name, module)
end
def remove_module_handlers(name, host, module) do
  :ejabberd_hooks.remove_module_handlers(name, host, module)
end

def remove_module_handlers_next(state, _, [name, host0, module]) do
  host = mk_host(host0)
  filter_handlers(state, name,
    fn (_, %{host: h}) when h != host -> true
       (_, %{fun: {mod, _}})          -> mod != module
       (_, _)                         -> true end)
end

# --- running a handler ---

def run_args(state), do: [gen_hook_name(state), gen_host, gen_run_params]

def run(name, :no_host, params), do: :ejabberd_hooks.run(name, params)
def run(name, host, params),     do: :ejabberd_hooks.run(name, host, params)

def run_callouts(state, [name, host, args0]) do
  args = mk_list(args0)
  call run_handlers(name,
    fn(_, :stop) -> {:stop, :ok}
      (args, _)  -> args end,
    fn(_) -> :ok end,
    args, get_handlers(state, name, mk_host(host), length(args)))
end

# --- run_fold ---

def run_fold_args(state) do
  args = let xs <- gen_run_params(@max_params - 1) do
           elements([xs, :erlang.list_to_tuple(xs)])
         end
  [gen_hook_name(state), gen_host, gen_arg, args]
end

def run_fold(name, :no_host, val, args), do: :ejabberd_hooks.run_fold(name, val, args)
def run_fold(name, host, val, args),     do: :ejabberd_hooks.run_fold(name, host, val, args)

def run_fold_callouts(state, [name, host, val, args0]) do
  args = mk_list(args0)
  call run_handlers(name,
    fn(_, :stop)        -> {:stop, :stopped}
      (_, {:stop, val}) -> {:stop, val}
      ([_|args], res)   -> [res|args] end,
    fn([val|_]) -> val end, [val|args],
    get_handlers(state, name, mk_host(host), length(args) + 1))
end

# This helper command generalises run and run_fold. It takes two functions:
#   next(args, res) - computes the arguments for the next handler from the
#                     current arguments and the result of the current handler,
#                     or {:stop, val} to stop and return val
#   ret(args)       - computes the final result given the current arguments
def run_handlers_callouts(_state, [_, _, ret, args, []]), do: {:return, ret.(args)}
def run_handlers_callouts(_state, [name, next, ret, args, [{seq, h}|handlers]]) do
  match res =
    case h.fun do
      {mod, fun}   -> callout(mod, fun, args, gen_result)
      {:fn, _, id} -> callout :handlers.anon(name, seq, args, id), return: gen_result
    end
  case res do
    exception(_) -> call run_handlers(name, next, ret, args, handlers)
    _            ->
      case next.(args, res) do
        {:stop, val} -> {:return, val}
        args1        -> call run_handlers(name, next, ret, args1, handlers)
      end
  end
end

# --- get info on a handler ---

def get_args(state), do: [gen_hook_name(state), gen_host]

def get(name, :no_host), do: :ejabberd_hooks.get_handlers(name)
def get(name, host),     do: :ejabberd_hooks.get_handlers(name, host)

def get_return(state, [name, host]) do
  for h <- get_handlers(state, name, mk_host(host)) do
    {_, key} = handler_key(name, h)
    key
  end
end

# --- get_hooks_with_handlers ---

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

weight _state,
  add:                     3,
  add_dist:                2,
  delete:                  1,
  run:                     2,
  run_fold:                2,
  get_hooks_with_handlers: 1,
  remove_module_handlers:  1,
  get:                     1

# -- Property ---------------------------------------------------------------

property "Ejabberd Hooks" do
  EQC.setup_teardown setup do
  fault_rate(1, 10,
  forall cmds <- commands(__MODULE__) do
    {:ok, pid} = :ejabberd_hooks.start_link
    :erlang.unlink(pid)
    :true = :ejabberd_hooks.delete_all_hooks
    res = run_commands(__MODULE__, cmds)
    :erlang.exit(pid, :kill)
    pretty_commands(__MODULE__, cmds, res,
      :eqc.aggregate(command_names(cmds),
        res[:result] == :ok))
    end)
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
  for name <- child_nodes do
    :slave.stop(mk_node(name))
  end
  :eqc_mocking.stop_mocking()
end


# -- API spec ---------------------------------------------------------------

def api_spec do
  EQC.Mocking.api_spec [
    modules: [
      EQC.Mocking.api_module(name: :handlers,
        functions:
          [ EQC.Mocking.api_fun(name: :anon,       arity: 4),
            EQC.Mocking.api_fun(name: :fun0,       arity: 0),
            EQC.Mocking.api_fun(name: :fun1,       arity: 1),
            EQC.Mocking.api_fun(name: :fun2,       arity: 2),
            EQC.Mocking.api_fun(name: :fun3,       arity: 3),
            EQC.Mocking.api_fun(name: :funX,       arity: 0),
            EQC.Mocking.api_fun(name: :funX,       arity: 1),
            EQC.Mocking.api_fun(name: :funX,       arity: 2),
            EQC.Mocking.api_fun(name: :funX,       arity: 3) ]),
      EQC.Mocking.api_module(name: :zandlers,
        functions:
          [ EQC.Mocking.api_fun(name: :fun0,       arity: 0),
            EQC.Mocking.api_fun(name: :fun1,       arity: 1),
            EQC.Mocking.api_fun(name: :fun2,       arity: 2),
            EQC.Mocking.api_fun(name: :fun3,       arity: 3),
            EQC.Mocking.api_fun(name: :funX,       arity: 0),
            EQC.Mocking.api_fun(name: :funX,       arity: 1),
            EQC.Mocking.api_fun(name: :funX,       arity: 2),
            EQC.Mocking.api_fun(name: :funX,       arity: 3) ]),
    ]
  ]
end

def get_api_arity(mod, fun) do
  for m <- EQC.Mocking.api_spec(api_spec)[:modules],
      EQC.Mocking.api_module(m, :name) == mod,
      f <- EQC.Mocking.api_module(m, :functions),
      EQC.Mocking.api_fun(f, :name) == fun do
    EQC.Mocking.api_fun(f, :arity)
  end
end

end
