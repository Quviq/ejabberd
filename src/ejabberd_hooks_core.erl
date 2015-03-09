%%%----------------------------------------------------------------------
%%% File    : ejabberd_hooks_core.erl
%%% Author  : Mickael Remond <mremond@process-one.net>
%%% Purpose : Provide types and functions for ejabberd standard hooks.
%%%           It should allow developer to get a more robust
%%%           and clear API when developing ejabberd modules.
%%% Created :  4 Mar 2015 by Mickael Remond <mremond@process-one.net>
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

-module(ejabberd_hooks_core).

-compile(export_all).

-include("ejabberd_hooks.hrl").

%% jlib.hrl is needed only for type xmlel()
%% -include("jlib.hrl").

all() ->
    [ #hook{name = filter_packet,  type = run_fold, scope = global},
      #hook{name = c2s_loop_debug, type = run,      scope = global} ].

-spec get_hook_type(HookName :: atom()) -> undefined | hook_type().

get_hook_type(HookName) ->
    case lists:keyfind(HookName, 2, all()) of
        #hook{type = Type} -> Type;
        false -> undefined
    end.

%% ejabberd core hooks definition

-spec filter_packet(filter_packet(), #filter_packet{}) -> filter_packet().
filter_packet({_, _, _} = State, #filter_packet{} = Arg) ->
    ejabberd_hooks:run_fold(filter_packet, State, Arg).

-spec c2s_loop_debug(#c2s_loop_debug{}) -> ok.
c2s_loop_debug(#c2s_loop_debug{} = Arg) ->
    ejabberd_hooks:run(c2s_loop_debug, Arg).

-spec c2s_stream_features(binary(), c2s_stream_features(), #c2s_stream_features{}) -> c2s_stream_features().
c2s_stream_features(Host, State, Arg) ->
    ejabberd_hooks:run_fold(c2s_stream_features, Host, [], Arg).

