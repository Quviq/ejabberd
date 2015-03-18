-module(ejabberd_hooks_transform).

-export([parse_transform/2]).
-include("ejabberd_hooks.hrl").

-spec parse_transform([erl_parse:abstract_form()], [compile:option()]) -> [erl_parse:abstract_form()].
parse_transform(Forms, _Options) ->
    gather_hooks(Forms, [], [], undefined).

gather_hooks([{eof, Line}], ExistingCode, Hooks, _LatestSpec) ->
    ExistingCode ++ 
        [{function,Line,all,0,
          [{clause,Line,[],[],
            %% TODO: Implement wrapper to generate list:
           list_to_nested_cons(lists:map(fun(Hook) ->
                                                 {record,Line,hook,
                                                  [{record_field,Line,{atom,Line,name},{atom,Line,Hook#hook.name}},
                                                   {record_field,Line,{atom,Line,type},{atom,Line,Hook#hook.type}},
                                                   {record_field,Line,{atom,Line,arity},{integer,Line,Hook#hook.arity}},
                                                   {record_field,Line,{atom,Line,handler_arity},{integer,Line,Hook#hook.handler_arity}},
                                                   {record_field,Line,{atom,Line,scope},{atom,Line,Hook#hook.scope}}]}
                                         end, Hooks),                                        
                               Line)
           }]}] ++
        [{eof, Line + 1}];

%% Return is atom ok: This is a run hook
gather_hooks([{attribute,Line,spec,{{Name,Arity},[{type,_,'fun',[_Params,{atom,_,ok}]}]}} = Code|T],
             ExistingCode, Hooks, _LatestSpec) ->
    Type = run,
    Scope = hook_scope(Line, Name, Type, Arity),
    HArity = handler_arity(Type, Scope),
    gather_hooks(T, ExistingCode ++ [Code], Hooks,
                 #hook{name = Name, arity = Arity, type = Type, scope = Scope, handler_arity = HArity});

%% Return is a type: This is a run_fold hook
gather_hooks([{attribute,Line,spec,{{Name,Arity},[{type,_,'fun',[_Params,_Return]}]}} = Code|T],
             ExistingCode, Hooks, _LatestSpec) ->
    Type = run_fold,
    Scope = hook_scope(Line, Name, Type, Arity),
    HArity = handler_arity(Type, Scope),
    gather_hooks(T, ExistingCode ++ [Code], Hooks,
                 #hook{name = Name, arity = Arity, type = Type, scope = Scope, handler_arity = HArity});

%% Check that hook implementation matches name / arity ...
gather_hooks([{function,_Line,Name,Arity,_Clause} = Code|T],
             ExistingCode, Hooks, #hook{name = Name, arity = Arity} = HookSpec) ->
    gather_hooks(T, ExistingCode ++ [Code], Hooks ++ [HookSpec], undefined);

%% ... Otherwise, refuse to compile
gather_hooks([{function,Line,Name,Arity,_Clause}|_],
             _ExistingCode, _Hooks, LatestSpec) ->
    case LatestSpec of
        undefined ->
            io:format("No spec defined for hook: ~p/~p on line ~p~n", [Name, Arity, Line]);
        #hook{arity = Arity} ->
            io:format("Spec ~p does not match function ~p on line ~p~n", [LatestSpec#hook.name, Name, Line]);
        #hook{name = Name} ->
            io:format("Spec ~p arity ~p does not match function arity ~p on line ~p~n",
                      [Name, LatestSpec#hook.arity, Arity, Line])
    end,
    throw(compile_error);

gather_hooks([Code|T], ExistingCode, Hooks, LatestSpec) ->
    gather_hooks(T, ExistingCode ++ [Code], Hooks, LatestSpec).

hook_scope(_Line, _Name, run, 1) -> global;
hook_scope(_Line, _Name, run, 2) -> local;
hook_scope(_Line, _Name, run_fold, 2) -> global;
hook_scope(_Line, _Name, run_fold, 3) -> local;
hook_scope(Line, Name, run, Arity) ->
    io:format("Hook ~p of type 'run' must be of arity 1 or 2 (was: ~p). Line: ~p~n", [Name, Arity, Line]),
    throw(compile_error);
hook_scope(Line, Name, run_fold, Arity) ->
    io:format("Hook ~p of type 'run_fold' must be of arity 2 or 3 (was: ~p)~n Line: ~p~n", [Name, Arity, Line]),
    throw(compile_error).

%% TODO For now local hook do not pass always the host (it is passed as args) 
%% Do we want to always pass it as an extra parameter for consistency ?
handler_arity(run, local)      -> 1;  %% May become 2 if we always pass host
handler_arity(run, global)      -> 1;
handler_arity(run_fold, local) -> 2;  %% May become 3 if we always pass host
handler_arity(run_fold, global) -> 2.

list_to_nested_cons([], Line) ->
    [{nil, Line}];
list_to_nested_cons(ListOfASTSnippets, Line) ->
    [list_to_nested_cons(lists:reverse(ListOfASTSnippets), {nil, Line}, Line)].

list_to_nested_cons([], Structure, _Line) ->
    Structure;
list_to_nested_cons([H|T], Structure, Line) ->
    list_to_nested_cons(T, {cons, Line, H, Structure}, Line).
        
%% TODO:
%% - Add a method to generate hooks implementation template (to help developer, he can copy paste) 
