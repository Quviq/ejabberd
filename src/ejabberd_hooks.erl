%%%----------------------------------------------------------------------
%%% File    : ejabberd_hooks.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Manage hooks
%%% Created :  8 Aug 2004 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2015   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_hooks).
-author('alexey@process-one.net').

-behaviour(gen_server).

%% External exports
-export([start_link/0,
         add_handler/3,
         add_handler/4,
	 add_handler/5,
	 add_dist_handler/5,
	 add_dist_handler/6,
	 delete/3,
	 delete/4,
	 delete/5,
         remove_module_handlers/2,
         remove_module_handlers/3,
	 delete_dist/5,
	 delete_dist/6,
	 run/2,
	 run/3,
	 run_fold/3,
	 run_fold/4,
	 get_handlers/1,
	 get_handlers/2,
         get_hooks_with_handlers/0]).

-export([delete_all_hooks/0]).

%% Legacy API
-export([add/3,
	 add/4,
	 add/5,
	 add_dist/5,
	 add_dist/6]).

%% gen_server callbacks
-export([init/1,
	 handle_call/3,
	 handle_cast/2,
	 code_change/3,
	 handle_info/2,
	 terminate/2]).

-include("logger.hrl").
-include("ejabberd_hooks.hrl").

%% Timeout of 5 seconds in calls to distributed hooks
-define(TIMEOUT_DISTRIBUTED_HOOK, 5000).

-record(state, {}).
%% TODO: Use record for hook structure and unify local and distributed hooks
-type local_hook() :: { Seq :: integer(), Module :: atom(), Function :: atom(), CallType :: record|args }.
-type distributed_hook() :: { Seq :: integer(), Node :: atom(), Module :: atom(), Function :: atom(), CallType :: record|args }.

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ejabberd_hooks}, ejabberd_hooks, [], []).

-spec add_handler(atom(), fun(), number()) -> ok.

add_handler(Hook, Function, Seq) when is_function(Function) ->
    add_handler(Hook, global, undefined, Function, Seq).

-spec add_handler(atom(), HostOrModule :: binary() | atom(), fun() | atom() , number()) -> ok | {error, atom()}.
add_handler(Hook, Host, Function, Seq) when is_function(Function) ->
    add_handler(Hook, Host, undefined, Function, Seq);

%% @doc Add a module and function to this hook.
%% The integer sequence is used to sort the calls: low number is called before high number.
add_handler(Hook, Module, Function, Seq) ->
    add_handler(Hook, global, Module, Function, Seq).

-spec add_handler(atom(), binary() | global, atom(), atom() | fun(), number()) -> ok.

add_handler(Hook, Host, Module, Function, Seq) ->
    add_handler(Hook, Host, Module, Function, Seq, record).

add_handler(Hook, Host, Module, Function, Seq, CallType) -> 
    gen_server:call(ejabberd_hooks, {add, Hook, Host, Module, Function, Seq, CallType}).

-spec add(atom(), fun(), number()) -> ok.

%% @doc See add/4. Deprecated in favor of add_handler/3
add(Hook, Function, Seq) when is_function(Function) ->
    add_handler(Hook, global, undefined, Function, Seq, args).

-spec add(atom(), HostOrModule :: binary() | atom(), fun() | atom() , number()) -> ok | {error, atom()}.
add(Hook, Host, Function, Seq) when is_function(Function) ->
    add_handler(Hook, Host, undefined, Function, Seq, args);

%% @doc Add a module and function to this hook.
%% The integer sequence is used to sort the calls: low number is called before high number.
add(Hook, Module, Function, Seq) ->
    add_handler(Hook, global, Module, Function, Seq, args).

-spec add(atom(), binary() | global, atom(), atom() | fun(), number()) -> ok.

add(Hook, Host, Module, Function, Seq) ->
    add_handler(Hook, Host, Module, Function, Seq, args).

-spec add_dist(atom(), atom(), atom(), atom() | fun(), number()) -> ok.

add_dist(Hook, Node, Module, Function, Seq) ->
    add_dist(Hook, global, Node, Module, Function, Seq).

-spec add_dist(atom(), binary() | global, atom(), atom(), atom() | fun(), number()) -> ok.

add_dist(Hook, Host, Node, Module, Function, Seq) ->
    gen_server:call(ejabberd_hooks, {add, Hook, Host, Node, Module, Function, Seq, args}).

-spec add_dist_handler(atom(), atom(), atom(), atom() | fun(), number()) -> ok.

add_dist_handler(Hook, Node, Module, Function, Seq) ->
    add_dist_handler(Hook, global, Node, Module, Function, Seq).

-spec add_dist_handler(atom(), binary() | global, atom(), atom(), atom() | fun(), number()) -> ok.

add_dist_handler(Hook, Host, Node, Module, Function, Seq) ->
    gen_server:call(ejabberd_hooks, {add, Hook, Host, Node, Module, Function, Seq, record}).

-spec delete(atom(), fun(), number()) -> ok.

%% @doc See delete/4.
delete(Hook, Function, Seq) when is_function(Function) ->
    delete(Hook, global, undefined, Function, Seq).

-spec delete(atom(), binary() | atom(), atom() | fun(), number()) -> ok.

delete(Hook, Host, Function, Seq) when is_function(Function) ->
    delete(Hook, Host, undefined, Function, Seq);

%% @doc Delete a module and function from this hook.
%% It is important to indicate exactly the same information than when the call was added.
delete(Hook, Module, Function, Seq) ->
    delete(Hook, global, Module, Function, Seq).

-spec delete(atom(), binary() | global, atom(), atom() | fun(), number()) -> ok.

delete(Hook, Host, Module, Function, Seq) ->
    gen_server:call(ejabberd_hooks, {delete, Hook, Host, Module, Function, Seq}).

-spec remove_module_handlers(atom(), atom()) -> ok.
%% @doc see remove_module_handlers/3
remove_module_handlers(Hook, Module) ->
    remove_module_handlers(Hook, global, Module).

%% @doc Remove all handler set by module for given hook.
remove_module_handlers(Hook, Host, Module) ->
    gen_server:call(ejabberd_hooks, {remove_module_handlers, Hook, Host, Module}).

-spec delete_dist(atom(), atom(), atom(), atom() | fun(), number()) -> ok.

delete_dist(Hook, Node, Module, Function, Seq) ->
    delete_dist(Hook, global, Node, Module, Function, Seq).

-spec delete_dist(atom(), binary() | global, atom(), atom(), atom() | fun(), number()) -> ok.

delete_dist(Hook, Host, Node, Module, Function, Seq) ->
    gen_server:call(ejabberd_hooks, {delete, Hook, Host, Node, Module, Function, Seq}).

-spec delete_all_hooks() -> true. 

%% @doc Primarily for testing / instrumentation
delete_all_hooks() ->
    gen_server:call(ejabberd_hooks, {delete_all}).

-spec get_handlers(atom()) -> [local_hook() | distributed_hook()].

%% @doc see get_handlers/2
get_handlers(Hookname) ->
    get_handlers(Hookname, global).

-spec get_handlers(atom(), binary() | global) -> [local_hook() | distributed_hook()].
%% @doc Returns currently set handlers for hook name 
get_handlers(Hookname, Host) ->
    gen_server:call(ejabberd_hooks, {get_handlers, Hookname, Host}).

-spec get_hooks_with_handlers() -> [atom()].

get_hooks_with_handlers() ->
    gen_server:call(ejabberd_hooks, {get_hooks_with_handlers}).

-spec run(atom(), list()|tuple()) -> ok.

%% @doc Run the calls of this hook in order, don't care about function results.
%% If a call returns stop, no more calls are performed.
run(Hook, Args) ->
    run(Hook, global, Args).

-spec run(atom(), binary() | global, list()|tuple()) -> ok.

run(Hook, Host, Args) ->
    case ets:lookup(hooks, {Hook, Host}) of
	[{_, Ls}] ->
	    run1(Ls, Hook, Args);
	[] ->
	    ok
    end.

-spec run_fold(atom(), any(), list()|tuple()) -> any().

%% @doc Run the calls of this hook in order.
%% The arguments passed to the function are: [Val | Args].
%% The result of a call is used as Val for the next call.
%% If a call returns 'stop', no more calls are performed and 'stopped' is returned.
%% If a call returns {stop, NewVal}, no more calls are performed and NewVal is returned.
run_fold(Hook, Val, Args) ->
    run_fold(Hook, global, Val, Args).

-spec run_fold(atom(), binary() | global, any(), list()|tuple()) -> any().

run_fold(Hook, Host, Val, Args) ->
    case ets:lookup(hooks, {Hook, Host}) of
	[{_, Ls}] ->
	    run_fold1(Ls, Hook, Val, Args);
	[] ->
	    Val
    end.

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%----------------------------------------------------------------------
init([]) ->
    ets:new(hooks, [named_table]),
    {ok, #state{}}.

%%----------------------------------------------------------------------
%% Func: handle_call/3
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_call({add, Hook, Host, Module, Function, Seq, CallType}, _From, State) ->
    HookFormat = {Seq, Module, Function, CallType},
    Reply = handle_add(Hook, Host, HookFormat),
    {reply, Reply, State};
handle_call({add, Hook, Host, Node, Module, Function, Seq, CallType}, _From, State) ->
    HookFormat = {Seq, Node, Module, Function, CallType},
    Reply = handle_add(Hook, Host, HookFormat),
    {reply, Reply, State};

handle_call({delete, Hook, Host, Module, Function, Seq}, _From, State) ->
    Reply = handle_delete(Hook, Host, Seq, undefined, Module, Function),
    {reply, Reply, State};
handle_call({delete, Hook, Host, Node, Module, Function, Seq}, _From, State) ->
    Reply = handle_delete(Hook, Host, Seq, Node, Module, Function),
    {reply, Reply, State};

handle_call({remove_module_handlers, Hook, Host, Module}, _From, State) ->
    Reply = remove_module_handler(Hook, Host, Module),
    {reply, Reply, State};    

handle_call({get_handlers, Hook, Host}, _From, State) ->
    Reply = case ets:lookup(hooks, {Hook, Host}) of
                [{_, Handlers}] -> Handlers;
                []              -> []
            end,
    {reply, Reply, State};

handle_call({delete_all}, _From, State) ->
    Reply = ets:delete_all_objects(hooks),
    {reply, Reply, State};

handle_call({get_hooks_with_handlers}, _From, State) ->
    Hooks = ets:foldl(fun({{Hook, _Host}, _}, Acc) -> [Hook|Acc] end, [], hooks),
    %% This is in case a hook is both global / local, but I do not think this can be the case:
    Reply = lists:usort(Hooks),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

-spec handle_add(atom(), atom(), local_hook() | distributed_hook()) -> ok | {error, atom()}.
%% Do a bit of consistency check before adding the hook
handle_add(HookName, Host, HookTuple) ->
    Hooks = ejabberd_hooks_core:all(),
    case lists:keyfind(HookName, 2, Hooks) of
        false -> %% This may be a custom hook, we may have no info on it
            case extract_module_function(HookTuple) of
                {undefined, Fun} when is_function(Fun) ->
                    do_handle_add(HookName, Host, HookTuple);
                {Module, Function} ->
                    case catch Module:module_info(exports) of
                        Exports when is_list(Exports) ->
                            case lists:keyfind(Function, 1, Exports) of
                                false ->
                                    ?ERROR_MSG("Cannot add hook ~p. Function ~p not exported from module ~p",
                                               [HookName, Function, Module]),
                                    {error, undefined_function};
                                _ ->
                                    do_handle_add(HookName, Host, HookTuple)
                            end;
                        _ ->
                            ?ERROR_MSG("Cannot add hook ~p. Module ~p not found",
                                       [HookName, Module]),
                            {error, module_not_found}
                    end
            end;
        #hook{handler_arity = Arity} ->
            case extract_module_function(HookTuple) of
                {undefined, Fun} when is_function(Fun) ->
                    case erlang:fun_info(Fun, arity) of
                        {arity, Arity} -> do_handle_add(HookName, Host, HookTuple);
                        {arity, FunArity} ->
                            ?ERROR_MSG("Cannot add hook ~p with fun. Incorrect arity ~p (expected ~p)",
                                       [HookName, FunArity, Arity]),
                            {error, incorrect_arity}
                    end;
                {Module, Function} ->
                    case catch Module:module_info(exports) of
                        Exports when is_list(Exports) ->
                            case lists:keyfind(Function, 1, Exports) of
                                false ->
                                    ?ERROR_MSG("Cannot add hook ~p. Function ~p not exported from module ~p",
                                               [HookName, Function, Module]),
                                    {error, undefined_function};
                                {Function, Arity} ->
                                    do_handle_add(HookName, Host, HookTuple);
                                {Function, WrongArity} ->
                                    ?ERROR_MSG("Cannot add hook ~p with fun. Incorrect arity ~p (expected ~p)",
                                               [HookName, WrongArity, Arity]),
                                    {error, incorrect_arity}
                            end;
                        _ ->
                            ?ERROR_MSG("Cannot add hook ~p. Module ~p not found",
                                       [HookName, Module]),
                            {error, module_not_found}
                    end
            end
    end.
    
-spec do_handle_add(atom(), atom(), local_hook() | distributed_hook()) -> ok.
%% in-memory storage operation: Handle adding hook in ETS table
do_handle_add(Hook, Host, El) ->
    case ets:lookup(hooks, {Hook, Host}) of
        [{_, Ls}] ->
            case lists:member(El, Ls) of
                true ->
                    ok;
                false ->
                    NewLs = lists:merge(Ls, [El]),
                    ets:insert(hooks, {{Hook, Host}, NewLs}),
                    ok
            end;
        [] ->
            NewLs = [El],
            ets:insert(hooks, {{Hook, Host}, NewLs}),
            ok
    end.

-spec handle_delete(atom(), atom(), integer(), atom(), atom(), atom()) -> ok.
%% in-memory storage operation: Handle deleting hook from ETS table
handle_delete(Hook, Host, Seq, Node, Module, Function) ->
    case ets:lookup(hooks, {Hook, Host}) of
        [{_, Ls}] ->
            Filter = fun(HookTuple) ->
                             case HookTuple of
                                 {Seq, Module, Function, _CallType} -> false;
                                 {Seq, Node, Module, Function, _CallType} -> false;
                                 _ -> true
                             end
                     end,
            NewLs = lists:filter(Filter, Ls), 
            ets:insert(hooks, {{Hook, Host}, NewLs}),
            ok;
        [] ->
            ok
    end. 

%% Drop all handlers for given module
remove_module_handler(Hook, Host, Module) ->
    case ets:lookup(hooks, {Hook, Host}) of
        [{_, Ls}] ->
            Filter = fun(HookTuple) ->
                             case HookTuple of
                                 {_Seq, Module, _Function, _CallType} -> false;
                                 {_Seq, _Node, Module, _Function, _CallType} -> false;
                                 _ -> true
                             end
                     end,
            NewLs = lists:filter(Filter, Ls), 
            ets:insert(hooks, {{Hook, Host}, NewLs}),
            ok;
        [] -> ok
    end. 

%%----------------------------------------------------------------------
%% Func: handle_cast/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any (ignored by gen_server)
%%----------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

-spec run1([local_hook()|distributed_hook()], atom(), list() | tuple()) -> ok.

run1([], _Hook, _Args) ->
    ok;
%% Run distributed hook on target node.
%% It is not attempted again in case of failure. Next hook will be executed
run1([{_Seq, Node, Module, Function, CallType} | Ls], Hook, Args) ->
    case remote_apply(Node, Module, Function, format_args(Hook, CallType, Args)) of
	timeout ->
            io:format("Timeout on RPC to ~p~nrunning hook: ~p",
		       [Node, {Hook, Args}]),
	    ?ERROR_MSG("Timeout on RPC to ~p~nrunning hook: ~p",
		       [Node, {Hook, Args}]),
	    run1(Ls, Hook, Args);
	{badrpc, Reason} ->
            io:format("Bad RPC error to ~p: ~p~nrunning hook: ~p",
		       [Node, Reason, {Hook, Args}]),
	    ?ERROR_MSG("Bad RPC error to ~p: ~p~nrunning hook: ~p",
		       [Node, Reason, {Hook, Args}]),
	    run1(Ls, Hook, Args);
	stop ->
            io:format("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "Stop.", [self(), node(), Node]), % debug code
	    ?INFO_MSG("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "Stop.", [self(), node(), Node]), % debug code
	    ok;
	Res ->
            io:format("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "The response is: ~n~p", [self(), node(), Node, Res]), % debug code
	    ?INFO_MSG("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "The response is: ~n~p", [self(), node(), Node, Res]), % debug code
	    run1(Ls, Hook, Args)
    end;
run1([{_Seq, Module, Function, CallType} | Ls], Hook, Args) ->
    io:format("MREMOND1\n",[]),
    Res = safe_apply(Module, Function, format_args(Hook, CallType, Args)),
    case Res of
	{'EXIT', Reason} ->
            io:format("~p~nrunning hook: ~p", [Reason, {Hook, Args}]),
	    ?ERROR_MSG("~p~nrunning hook: ~p", [Reason, {Hook, Args}]),
	    run1(Ls, Hook, Args);
	stop ->
            io:format("stop", []),
	    ok;
	_ ->
            io:format("run 1 loop", []),
	    run1(Ls, Hook, Args)
    end.

-spec run_fold1([local_hook()|distributed_hook()], atom(), any(), list() | tuple()) -> any().

run_fold1([], _Hook, Val, _Args) ->
    Val;
run_fold1([{_Seq, Node, Module, Function, CallType} | Ls], Hook, Val, Args) ->
    case remote_apply(Node, Module, Function, format_args(Hook, CallType, Val, Args)) of
	{badrpc, Reason} ->
	    ?ERROR_MSG("Bad RPC error to ~p: ~p~nrunning hook: ~p",
		       [Node, Reason, {Hook, Args}]),
	    run_fold1(Ls, Hook, Val, Args);
	timeout ->
	    ?ERROR_MSG("Timeout on RPC to ~p~nrunning hook: ~p",
		       [Node, {Hook, Args}]),
	    run_fold1(Ls, Hook, Val, Args);
	stop ->
	    stopped;
	{stop, NewVal} ->
	    ?INFO_MSG("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "Stop, and the NewVal is:~n~p", [self(), node(), Node, NewVal]), % debug code
	    NewVal;
	NewVal ->
	    ?INFO_MSG("~nThe process ~p in node ~p ran a hook in node ~p.~n"
		      "The NewVal is:~n~p", [self(), node(), Node, NewVal]), % debug code
	    run_fold1(Ls, Hook, NewVal, Args)
    end;
run_fold1([{_Seq, Module, Function, CallType} | Ls], Hook, Val, Args) ->
    Res = safe_apply(Module, Function, format_args(Hook, CallType, Val, Args)),
    case Res of
	{'EXIT', Reason} ->
	    ?ERROR_MSG("~p~nrunning hook: ~p", [Reason, {Hook, Args}]),
	    run_fold1(Ls, Hook, Val, Args);
	stop ->
	    stopped;
	{stop, NewVal} ->
	    NewVal;
	NewVal ->
	    run_fold1(Ls, Hook, NewVal, Args)
    end.

extract_module_function({_Seq, Module, Function, _CallType}) ->
    {Module, Function};
extract_module_function({_Seq, _Node, Module, Function, _CallType}) ->
    {Module, Function}.

is_core_hook(HookName) ->
    Hooks = ejabberd_hooks_core:all(),
    case lists:keyfind(HookName, 2, Hooks) of
        false   -> false;
        #hook{} -> true
    end.

%% Compliance layer (Can be removed in the future)
%% ===============================================

%% This introduce backward compatible change for parameters (Args can be record or list)
format_args(Hook, CallType, Args) ->
    case is_core_hook(Hook) of
        %% Do not change "custom" hooks type (Can be not yet migrated hooks)
        false -> Args;
        true  -> do_format_args(Hook, CallType, Args)
    end.
    
do_format_args(Hook, args, Args) ->
    case Args of
        A when is_list(A)  -> Args;
        R when is_tuple(R) ->
            case tuple_to_list(R) of
                [Hook|RecordArgs] -> RecordArgs;
                _ -> Args
            end
    end;
do_format_args(Hook, record, Args) ->
    case Args of
        R when is_tuple(R) -> [R];
        [] -> []; %% Do not convert empty parameter list to "empty record tuple"
        A when is_list(A)  -> [list_to_tuple([Hook | Args])]
    end.

format_args(Hook, CallType, Val, Args) ->
    case is_core_hook(Hook) of
        %% Do not change "custom" hooks type (Can be not yet migrated hooks)
        false -> [Val|Args];
        true  -> do_format_args(Hook, CallType, Val, Args)
    end.

do_format_args(Hook, args, Val, Args) ->
    case Args of
        A when is_list(A)  -> [Val | Args];
        R when is_tuple(R) ->
            case tuple_to_list(R) of
                [Hook|RecordArgs] -> [Val|RecordArgs];
                _ -> [Val | Args ]
            end
    end;
do_format_args(Hook, record, Val, Args) ->
    case Args of
        R when is_tuple(R) -> [Val, R];
        A when is_list(A)  -> [Val, list_to_tuple([Hook | Args])]
    end.


%% Perform hooks calls (actually)
%% ==============================

safe_apply(Module, Function, Args) ->
    if is_function(Function) ->
            catch apply(Function, Args);
       true ->
            catch apply(Module, Function, Args)
    end.

%% We do not need to catch here as the RPC module is already catching
%% the error to wrap the return in a {badrpc, Error} tuple.
%% Error can be {'EXIT', Reason}
remote_apply(Node, Module, Function, Args) ->
    if is_function(Function) ->
            rpc:call(Node, erlang, apply, [Function, Args], ?TIMEOUT_DISTRIBUTED_HOOK);
       true ->
            rpc:call(Node, Module, Function, Args, ?TIMEOUT_DISTRIBUTED_HOOK)
    end.
