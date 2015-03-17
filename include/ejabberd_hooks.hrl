%%%----------------------------------------------------------------------
%%% File    : ejabberd_hooks.hrl
%%% Author  : Mickael Remond <mremond@process-one.net>
%%% Purpose : Provide types for ejabberd standard hooks.
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

-ifndef(EJABBERD_HOOKS_HRL).
-define(EJABBERD_HOOKS_HRL, true).

%% jlib.hrl is needed only for type xmlel()
-include("jlib.hrl").

-type hook_type()  :: run | run_fold.
-type hook_scope() :: global | host.

-record(hook, {name  :: atom(),
               arity :: pos_integer(),
               handler_arity :: pos_integer(),
               type  :: hook_type(),
               scope :: hook_scope()}).

%% Filter packet is run_fold
%% handler is called as filter_packet_handler(filter_packet, #filter_packet)
-type filter_packet() :: {From :: jlib:jid(), To :: jlib:jid(), xmlel()} | drop.
-record(filter_packet, {}).

-type c2s_loop_debug() :: {route, jlib:jid(), jlib:jid(), xmlel()} | {xmlstreamelement, xmlel()} | binary().
-record(c2s_loop_debug, {data = <<"">> :: c2s_loop_debug()}).

-type c2s_stream_features() :: [xmlel()].
-record(c2s_stream_features, {host :: binary()}).

-endif.
