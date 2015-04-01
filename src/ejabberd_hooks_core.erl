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

-compile([export_all,
          {parse_transform, ejabberd_hooks_transform}]).
%% MR: Compile manually with:
%% erlc -pa . -I include -I ../ejabberd-mremond/deps/p1_xml/include/ src/ejabberd_hooks_core.erl

-include("ejabberd_hooks.hrl").

%%-spec get_hook_type(HookName :: atom()) -> undefined | hook_type().
%%
%% get_hook_type(HookName) ->
%%    case lists:keyfind(HookName, 2, all()) of
%%        #hook{type = Type} -> Type;
%%        false -> undefined
%%        false -> undefined
%%    end.

%% ejabberd core hooks definition
%% Important notes:
%% - Type specs are mandatory to know if we deal with run_fold or run hook during parse_transform

-spec filter_packet(filter_packet(), #filter_packet{}) -> filter_packet().
filter_packet({_, _, _} = State, #filter_packet{} = Arg) ->
    ejabberd_hooks:run_fold(filter_packet, State, Arg).

-spec c2s_loop_debug(#c2s_loop_debug{}) -> ok.
c2s_loop_debug(#c2s_loop_debug{} = Arg) ->
    ejabberd_hooks:run(c2s_loop_debug, Arg).

-spec c2s_stream_features(binary(), c2s_stream_features(), #c2s_stream_features{}) -> c2s_stream_features().
c2s_stream_features(Host, _State, Arg) ->
    ejabberd_hooks:run_fold(c2s_stream_features, Host, [], Arg).

%% all() will be added at compile time by parse_transform
%% It return the list of core hooks alongs with there specifications
%% as a list of hooks records

%% TODO:
%% - Generate function call wrapper from spec

