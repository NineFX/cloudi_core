%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Erlang Interface==
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2013-2014, Michael Truog <mjtruog at gmail dot com>
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%% 
%%%     * Redistributions of source code must retain the above copyright
%%%       notice, this list of conditions and the following disclaimer.
%%%     * Redistributions in binary form must reproduce the above copyright
%%%       notice, this list of conditions and the following disclaimer in
%%%       the documentation and/or other materials provided with the
%%%       distribution.
%%%     * All advertising materials mentioning features or use of this
%%%       software must display the following acknowledgment:
%%%         This product includes software developed by Michael Truog
%%%     * The name of the author may not be used to endorse or promote
%%%       products derived from this software without specific prior
%%%       written permission
%%% 
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
%%% CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
%%% INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
%%% OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
%%% CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
%%% DAMAGE.
%%%
%%% @author Michael Truog <mjtruog [at] gmail (dot) com>
%%% @copyright 2013-2014 Michael Truog
%%% @version 1.3.2 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi).
-author('mjtruog [at] gmail (dot) com').

%% external interface
-export([new/0,
         new/1,
         destinations_refresh/2,
         get_pid/2,
         get_pid/3,
         get_pids/2,
         get_pids/3,
         send_async/3,
         send_async/4,
         send_async/5,
         send_async/6,
         send_async/7,
         send_async_passive/3,
         send_async_passive/4,
         send_async_passive/5,
         send_async_passive/6,
         send_async_passive/7,
         send_sync/3,
         send_sync/4,
         send_sync/5,
         send_sync/6,
         send_sync/7,
         mcast_async/3,
         mcast_async/4,
         mcast_async/6,
         mcast_async_passive/3,
         mcast_async_passive/4,
         mcast_async_passive/6,
         recv_async/1,
         recv_async/2,
         recv_async/3,
         recv_asyncs/2,
         recv_asyncs/3,
         timeout_async/1,
         timeout_sync/1,
         timeout_max/1,
         priority_default/1,
         destination_refresh_immediate/1,
         destination_refresh_lazy/1,
         trans_id/1,
         trans_id_age/1]).

-include("cloudi_logger.hrl").
-include("cloudi_constants.hrl").
-include("cloudi_configuration_defaults.hrl").

-type service_name() :: string().
-type service_name_pattern() :: string().
-type request_info() :: any().
-type request() :: any().
-type response_info() :: any().
-type response() :: any().
-type timeout_value_milliseconds() :: 0..?TIMEOUT_MAX.
-type timeout_milliseconds() :: timeout_value_milliseconds() |
                                undefined | immediate.
-type priority() :: cloudi_service_api:priority() | undefined.
-type trans_id() :: <<_:128>>. % version 1 UUID
-type pattern_pid() :: {service_name_pattern(), pid()}.
-export_type([service_name/0,
              service_name_pattern/0,
              request_info/0, request/0,
              response_info/0, response/0,
              timeout_value_milliseconds/0,
              timeout_milliseconds/0,
              priority/0,
              trans_id/0,
              pattern_pid/0]).

-type error_reason() :: timeout.
-type error_reason_sync() :: error_reason() |
                             cloudi_service:error_reason_sync().
-export_type([error_reason/0,
              error_reason_sync/0]).

-type dest_refresh_delay_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-export_type([dest_refresh_delay_milliseconds/0]).

-record(cloudi_context,
        {
            dest_refresh :: cloudi_service_api:dest_refresh(),
            dest_refresh_delay
                :: cloudi_service_api:dest_refresh_delay_milliseconds(),
            timeout_async :: cloudi_service_api:timeout_milliseconds(),
            timeout_sync :: cloudi_service_api:timeout_milliseconds(),
            priority_default :: cloudi_service_api:priority(),
            scope :: atom(),
            receiver :: pid(),
            uuid_generator :: uuid:state(),
            cpg_data :: any(),
            cpg_data_stale = false :: boolean()
        }).

-type options() ::
    list({dest_refresh, cloudi_service_api:dest_refresh()} |
         {dest_refresh_start, dest_refresh_delay_milliseconds()} |
         {dest_refresh_delay,
          cloudi_service_api:dest_refresh_delay_milliseconds()} |
         {timeout_async, cloudi_service_api:timeout_milliseconds()} |
         {timeout_sync, cloudi_service_api:timeout_milliseconds()} |
         {priority_default, priority()} |
         {scope, atom()} |
         % advanced:
         % options for internal coordination with cloudi_service
         {uuid, uuid:state()} |
         {groups, any()} |
         {groups_scope, atom()} |
         {groups_static, boolean()}).
-type context() :: #cloudi_context{}.
-export_type([options/0,
              context/0]).

% only relevant to service modules, but some people just want the shorter names
-type request_type() :: cloudi_service:request_type().
-type dispatcher() :: cloudi_service:dispatcher().
-export_type([request_type/0,
              dispatcher/0]).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @doc
%% ===Create a CloudI context.===
%% @end
%%-------------------------------------------------------------------------
-spec new() ->
    #cloudi_context{}.

new() ->
    new([]).

%%-------------------------------------------------------------------------
%% @doc
%% ===Create a CloudI context.===
%% If a lazy destination refresh method is used, make sure to receive the
%% {cloudi_cpg_data, Groups} message and pass it to the
%% destinations_refresh/2 function.
%% @end
%%-------------------------------------------------------------------------
-spec new(Options :: options()) ->
    #cloudi_context{}.

new(Options)
    when is_list(Options) ->
    Defaults = [
        {dest_refresh,                     ?DEFAULT_DEST_REFRESH},
        {dest_refresh_start,         ?DEFAULT_DEST_REFRESH_START},
        {dest_refresh_delay,         ?DEFAULT_DEST_REFRESH_DELAY},
        {timeout_async,                   ?DEFAULT_TIMEOUT_ASYNC},
        {timeout_sync,                     ?DEFAULT_TIMEOUT_SYNC},
        {priority_default,                     ?DEFAULT_PRIORITY},
        {scope,                                   ?DEFAULT_SCOPE},
        {uuid,                                         undefined},
        {groups,            cpg_data:get_empty_groups()},
        {groups_scope,                                 undefined},
        {groups_static,                                    false}
        ],
    [DestRefresh, DestRefreshStart, DestRefreshDelay,
     DefaultTimeoutAsync, DefaultTimeoutSync, PriorityDefault, Scope,
     OldUUID, OldGroups, GroupsScope, GroupsStatic] =
        cloudi_proplists:take_values(Defaults, Options),
    true = (DestRefresh =:= immediate_closest) orelse
           (DestRefresh =:= lazy_closest) orelse
           (DestRefresh =:= immediate_furthest) orelse
           (DestRefresh =:= lazy_furthest) orelse
           (DestRefresh =:= immediate_random) orelse
           (DestRefresh =:= lazy_random) orelse
           (DestRefresh =:= immediate_local) orelse
           (DestRefresh =:= lazy_local) orelse
           (DestRefresh =:= immediate_remote) orelse
           (DestRefresh =:= lazy_remote) orelse
           (DestRefresh =:= immediate_newest) orelse
           (DestRefresh =:= lazy_newest) orelse
           (DestRefresh =:= immediate_oldest) orelse
           (DestRefresh =:= lazy_oldest),
    true = is_integer(DestRefreshStart) andalso
           (DestRefreshStart >= 0) andalso % immediate cache is possible here
           (DestRefreshStart =< ?TIMEOUT_MAX_ERLANG),
    true = is_integer(DestRefreshDelay) andalso
           (DestRefreshDelay > ?TIMEOUT_DELTA) andalso
           (DestRefreshDelay =< ?TIMEOUT_MAX_ERLANG),
    true = is_integer(DefaultTimeoutAsync) andalso
           (DefaultTimeoutAsync > ?TIMEOUT_DELTA) andalso
           (DefaultTimeoutAsync =< ?TIMEOUT_MAX),
    true = is_integer(DefaultTimeoutSync) andalso
           (DefaultTimeoutSync > ?TIMEOUT_DELTA) andalso
           (DefaultTimeoutSync =< ?TIMEOUT_MAX),
    true = (PriorityDefault >= ?PRIORITY_HIGH) andalso
           (PriorityDefault =< ?PRIORITY_LOW),
    true = is_atom(Scope),
    true = (OldUUID =:= undefined) orelse
           (element(1, OldUUID) =:= uuid_state),
    true = is_atom(GroupsScope),
    true = is_boolean(GroupsStatic),
    ConfiguredScope = if
        GroupsScope =:= undefined ->
            CpgScope = ?SCOPE_ASSIGN(Scope),
            ok = cpg:scope_exists(CpgScope),
            CpgScope;
        true ->
            GroupsScope
    end,
    Self = self(),
    UUID = if
        OldUUID =:= undefined ->
            {ok, MacAddress} = application:get_env(cloudi_core, mac_address),
            {ok, TimestampType} = application:get_env(cloudi_core,
                                                      timestamp_type),
            uuid:new(Self, [{timestamp_type, TimestampType},
                                     {mac_address, MacAddress}]);
        true ->
            OldUUID
    end,
    Groups = if
        GroupsStatic =:= true ->
            OldGroups;
        GroupsStatic =:= false ->
            ok = destination_refresh_first(DestRefresh,
                                           DestRefreshStart,
                                           Scope),
            if
                ((DestRefresh =:= lazy_closest) orelse
                 (DestRefresh =:= lazy_furthest) orelse
                 (DestRefresh =:= lazy_random) orelse
                 (DestRefresh =:= lazy_local) orelse
                 (DestRefresh =:= lazy_remote) orelse
                 (DestRefresh =:= lazy_newest) orelse
                 (DestRefresh =:= lazy_oldest)),
                DestRefreshStart < ?DEFAULT_DEST_REFRESH_START ->
                    receive
                        {cloudi_cpg_data, G} ->
                            ok = destination_refresh_start(DestRefresh,
                                                           DestRefreshDelay,
                                                           Scope),
                            G
                    after
                        ?DEFAULT_DEST_REFRESH_START ->
                            OldGroups
                    end;
                true ->
                    OldGroups
            end
    end,
    #cloudi_context{
        dest_refresh = DestRefresh,
        dest_refresh_delay = DestRefreshDelay,
        timeout_async = DefaultTimeoutAsync,
        timeout_sync = DefaultTimeoutSync,
        priority_default = PriorityDefault,
        scope = ConfiguredScope,
        receiver = Self,
        uuid_generator = UUID,
        cpg_data = Groups
    }.

%%-------------------------------------------------------------------------
%% @doc
%% ===Refresh destination lookup data.===
%% Must be called if using a lazy destination refresh method.
%% The {cloudi_cpg_data, Groups} message must be received and processed
%% by this function.  However, if it isn't processed, the other function
%% calls will attempt to update the Context based on any pending
%% destination refresh messages that haven't yet been received.
%% @end
%%-------------------------------------------------------------------------

-spec destinations_refresh(Context :: context(),
                           Message :: {cloudi_cpg_data, any()}) ->
    context().

destinations_refresh(#cloudi_context{
                         dest_refresh = DestRefresh,
                         dest_refresh_delay = DestRefreshDelay,
                         scope = Scope} = Context,
                     {cloudi_cpg_data, Groups}) ->
    ok = destination_refresh_start(DestRefresh, DestRefreshDelay, Scope),
    Context#cloudi_context{cpg_data = Groups}.

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a service destination based on a service name.===
%% @end
%%-------------------------------------------------------------------------

-spec get_pid(Context :: context() | cloudi_service:dispatcher(),
              Name :: service_name()) ->
    {ok, PatternPid :: pattern_pid()} |
    {error, Reason :: error_reason()}.

get_pid(Dispatcher, Name)
    when is_pid(Dispatcher) ->
    cloudi_service:get_pid(Dispatcher, Name);

get_pid(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context, Name) ->
    get_pid(Context, Name, DefaultTimeoutSync).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a service destination based on a service name.===
%% @end
%%-------------------------------------------------------------------------

-spec get_pid(Context :: context() | cloudi_service:dispatcher(),
              Name :: service_name(),
              Timeout :: timeout_milliseconds()) ->
    {ok, PatternPid :: pattern_pid()} |
    {error, Reason :: error_reason()}.

get_pid(Dispatcher, Name, Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:get_pid(Dispatcher, Name, Timeout);

get_pid(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context,
        Name, undefined) ->
    get_pid(Context, Name, DefaultTimeoutSync);

get_pid(#cloudi_context{} = Context, Name, immediate) ->
    get_pid(Context, Name, ?SEND_SYNC_INTERVAL - 1);

get_pid(#cloudi_context{} = Context, Name, Timeout)
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX ->
    NewContext = destinations_refresh_check(Context),
    #cloudi_context{
        dest_refresh = DestRefresh,
        scope = Scope,
        cpg_data = Groups} = NewContext,
    case destination_get(DestRefresh, Scope, Name, Groups,
                         Timeout + ?TIMEOUT_DELTA) of
        {error, {Reason, Name}}
        when (Reason =:= no_process orelse Reason =:= no_such_group),
             Timeout >= ?SEND_SYNC_INTERVAL ->
            get_pid(sleep(NewContext, ?SEND_SYNC_INTERVAL), Name,
                    Timeout - ?SEND_SYNC_INTERVAL);
        {error, _} ->
            result(NewContext, {error, timeout});
        {ok, Pattern, Pid} ->
            result(NewContext, {ok, {Pattern, Pid}})
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Get all service destinations based on a service name.===
%% @end
%%-------------------------------------------------------------------------

-spec get_pids(Context :: context() | cloudi_service:dispatcher(),
               Name :: service_name()) ->
    {ok, PatternPids :: list(pattern_pid())} |
    {error, Reason :: error_reason()}.

get_pids(Dispatcher, Name)
    when is_pid(Dispatcher) ->
    cloudi_service:get_pids(Dispatcher, Name);

get_pids(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context, Name) ->
    get_pids(Context, Name, DefaultTimeoutSync).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get all service destinations based on a service name.===
%% @end
%%-------------------------------------------------------------------------

-spec get_pids(Context :: context() | cloudi_service:dispatcher(),
               Name :: service_name(),
               Timeout :: timeout_milliseconds()) ->
    {ok, PatternPids :: list(pattern_pid())} |
    {error, Reason :: error_reason()}.

get_pids(Dispatcher, Name, Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:get_pids(Dispatcher, Name, Timeout);

get_pids(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context,
         Name, undefined) ->
    get_pids(Context, Name, DefaultTimeoutSync);

get_pids(#cloudi_context{} = Context, Name, immediate) ->
    get_pids(Context, Name, ?SEND_SYNC_INTERVAL - 1);

get_pids(#cloudi_context{} = Context, Name, Timeout)
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX ->
    NewContext = destinations_refresh_check(Context),
    #cloudi_context{
        dest_refresh = DestRefresh,
        scope = Scope,
        cpg_data = Groups} = NewContext,
    case destination_all(DestRefresh, Scope, Name, Groups,
                         Timeout + ?TIMEOUT_DELTA) of
        {error, {no_such_group, Name}}
        when Timeout >= ?SEND_SYNC_INTERVAL ->
            get_pids(sleep(NewContext, ?SEND_SYNC_INTERVAL), Name,
                     Timeout - ?SEND_SYNC_INTERVAL);
        {error, _} ->
            result(NewContext, {error, timeout});
        {ok, Pattern, Pids} ->
            result(NewContext, {ok, [{Pattern, Pid} || Pid <- Pids]})
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_async(Context :: context() | cloudi_service:dispatcher(),
                 Name :: service_name(),
                 Request :: request()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async(Dispatcher, Name, Request)
    when is_pid(Dispatcher) ->
    cloudi_service:send_async(Dispatcher, Name, Request);

send_async(Context, Name, Request) ->
    send_async(Context, Name, <<>>, Request,
               undefined, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_async(Context :: context() | cloudi_service:dispatcher(),
                 Name :: service_name(),
                 Request :: request(),
                 Timeout :: timeout_milliseconds()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async(Dispatcher, Name, Request, Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:send_async(Dispatcher, Name, Request, Timeout);

send_async(Context, Name, Request, Timeout) ->
    send_async(Context, Name, <<>>, Request,
               Timeout, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_async(Context :: context() | cloudi_service:dispatcher(),
                 Name :: service_name(),
                 Request :: request(),
                 Timeout :: timeout_milliseconds(),
                 PatternPid :: pattern_pid() | undefined) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async(Dispatcher, Name, Request, Timeout, PatternPid)
    when is_pid(Dispatcher) ->
    cloudi_service:send_async(Dispatcher, Name, Request, Timeout, PatternPid);

send_async(Context, Name, Request, Timeout, PatternPid) ->
    send_async(Context, Name, <<>>, Request,
               Timeout, undefined, PatternPid).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_async(Context :: context() | cloudi_service:dispatcher(),
                 Name :: service_name(),
                 RequestInfo :: request_info(),
                 Request :: request(),
                 Timeout :: timeout_milliseconds(),
                 Priority :: priority()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async(Dispatcher, Name, RequestInfo, Request,
           Timeout, Priority)
    when is_pid(Dispatcher) ->
    cloudi_service:send_async(Dispatcher, Name, RequestInfo, Request,
                              Timeout, Priority);

send_async(Context, Name, RequestInfo, Request,
           Timeout, Priority) ->
    send_async(Context, Name, RequestInfo, Request,
               Timeout, Priority, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_async(Context :: context() | cloudi_service:dispatcher(),
                 Name :: service_name(),
                 RequestInfo :: request_info(),
                 Request :: request(),
                 Timeout :: timeout_milliseconds(),
                 Priority :: priority(),
                 PatternPid :: pattern_pid() | undefined) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async(Dispatcher, Name, RequestInfo, Request,
           Timeout, Priority, PatternPid)
    when is_pid(Dispatcher) ->
    cloudi_service:send_async(Dispatcher, Name, RequestInfo, Request,
                              Timeout, Priority, PatternPid);

send_async(#cloudi_context{timeout_async = DefaultTimeoutAsync} = Context,
           Name, RequestInfo, Request,
           undefined, Priority, PatternPid) ->
    send_async(Context, Name, RequestInfo, Request,
               DefaultTimeoutAsync, Priority, PatternPid);

send_async(#cloudi_context{} = Context,
           Name, RequestInfo, Request,
           immediate, Priority, PatternPid) ->
    send_async(Context, Name, RequestInfo, Request,
               ?SEND_ASYNC_INTERVAL - 1, Priority, PatternPid);

send_async(#cloudi_context{priority_default = PriorityDefault} = Context,
           Name, RequestInfo, Request,
           Timeout, undefined, PatternPid) ->
    send_async(Context, Name, RequestInfo, Request,
               Timeout, PriorityDefault, PatternPid);

send_async(#cloudi_context{} = Context,
           Name, RequestInfo, Request,
           Timeout, Priority, undefined)
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX ->
    NewContext = destinations_refresh_check(Context),
    #cloudi_context{
        dest_refresh = DestRefresh,
        scope = Scope,
        cpg_data = Groups} = NewContext,
    case destination_get(DestRefresh, Scope, Name, Groups,
                         Timeout + ?TIMEOUT_DELTA) of
        {error, {Reason, Name}}
        when (Reason =:= no_process orelse Reason =:= no_such_group),
             Timeout >= ?SEND_ASYNC_INTERVAL ->
            send_async(sleep(NewContext, ?SEND_ASYNC_INTERVAL), Name,
                       RequestInfo, Request,
                       Timeout - ?SEND_ASYNC_INTERVAL,
                       Priority, undefined);
        {error, _} ->
            result(NewContext, {error, timeout});
        {ok, Pattern, Pid} ->
            send_async(NewContext, Name, RequestInfo, Request,
                       Timeout, Priority, {Pattern, Pid})
    end;

send_async(#cloudi_context{receiver = Receiver,
                           uuid_generator = UUID} = Context,
           Name, RequestInfo, Request,
           Timeout, Priority, {Pattern, Pid})
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX, is_integer(Priority),
         Priority >= ?PRIORITY_HIGH, Priority =< ?PRIORITY_LOW ->
    TransId = uuid:get_v1(UUID),
    Pid ! {'cloudi_service_send_async',
           Name, Pattern, RequestInfo, Request,
           Timeout, Priority, TransId, Receiver},
    result(Context, {ok, TransId}).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% An alias for send_async.  The asynchronous service request is returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec send_async_passive(Context :: context() | cloudi_service:dispatcher(),
                         Name :: service_name(),
                         Request :: request()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async_passive(Context, Name, Request) ->
    send_async(Context, Name, Request).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% An alias for send_async.  The asynchronous service request is returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec send_async_passive(Context :: context() | cloudi_service:dispatcher(),
                         Name :: service_name(),
                         Request :: request(),
                         Timeout :: timeout_milliseconds()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async_passive(Context, Name, Request, Timeout) ->
    send_async(Context, Name, Request, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% An alias for send_async.  The asynchronous service request is returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec send_async_passive(Context :: context() | cloudi_service:dispatcher(),
                         Name :: service_name(),
                         Request :: request(),
                         Timeout :: timeout_milliseconds(),
                         PatternPid :: pattern_pid() | undefined) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async_passive(Context, Name, Request, Timeout, PatternPid) ->
    send_async(Context, Name, Request, Timeout, PatternPid).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% An alias for send_async.  The asynchronous service request is returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec send_async_passive(Context :: context() | cloudi_service:dispatcher(),
                         Name :: service_name(),
                         RequestInfo :: request_info(),
                         Request :: request(),
                         Timeout :: timeout_milliseconds(),
                         Priority :: priority()) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async_passive(Context, Name, RequestInfo, Request,
                   Timeout, Priority) ->
    send_async(Context, Name, RequestInfo, Request,
               Timeout, Priority).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send an asynchronous service request.===
%% An alias for send_async.  The asynchronous service request is returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec send_async_passive(Context :: context() | cloudi_service:dispatcher(),
                         Name :: service_name(),
                         RequestInfo :: request_info(),
                         Request :: request(),
                         Timeout :: timeout_milliseconds(),
                         Priority :: priority(),
                         PatternPid :: pattern_pid() | undefined) ->
    {ok, TransId :: trans_id()} |
    {error, Reason :: error_reason()}.

send_async_passive(Context, Name, RequestInfo, Request,
                   Timeout, Priority, PatternPid) ->
    send_async(Context, Name, RequestInfo, Request,
               Timeout, Priority, PatternPid).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a synchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_sync(Context :: context() | cloudi_service:dispatcher(),
                Name :: service_name(),
                Request :: request()) ->
    {ok, ResponseInfo :: response_info(), Response :: response()} |
    {ok, Response :: response()} |
    {error, Reason :: error_reason_sync()}.

send_sync(Dispatcher, Name, Request)
    when is_pid(Dispatcher) ->
    cloudi_service:send_sync(Dispatcher, Name, Request);

send_sync(Context, Name, Request) ->
    send_sync(Context, Name, <<>>, Request,
              undefined, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a synchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_sync(Context :: context() | cloudi_service:dispatcher(),
                Name :: service_name(),
                Request :: request(),
                Timeout :: timeout_milliseconds()) ->
    {ok, ResponseInfo :: response_info(), Response :: response()} |
    {ok, Response :: response()} |
    {error, Reason :: error_reason_sync()}.

send_sync(Dispatcher, Name, Request, Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:send_sync(Dispatcher, Name, Request, Timeout);

send_sync(Context, Name, Request, Timeout) ->
    send_sync(Context, Name, <<>>, Request,
              Timeout, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a synchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_sync(Context :: context() | cloudi_service:dispatcher(),
                Name :: service_name(),
                Request :: request(),
                Timeout :: timeout_milliseconds(),
                PatternPid :: pattern_pid() | undefined) ->
    {ok, ResponseInfo :: response_info(), Response :: response()} |
    {ok, Response :: response()} |
    {error, Reason :: error_reason_sync()}.

send_sync(Dispatcher, Name, Request, Timeout, PatternPid)
    when is_pid(Dispatcher) ->
    cloudi_service:send_sync(Dispatcher, Name, Request, Timeout, PatternPid);

send_sync(Context, Name, Request, Timeout, PatternPid) ->
    send_sync(Context, Name, <<>>, Request,
              Timeout, undefined, PatternPid).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a synchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_sync(Context :: context() | cloudi_service:dispatcher(),
                Name :: service_name(),
                RequestInfo :: request_info(),
                Request :: request(),
                Timeout :: timeout_milliseconds(),
                Priority :: priority()) ->
    {ok, ResponseInfo :: response_info(), Response :: response()} |
    {ok, Response :: response()} |
    {error, Reason :: error_reason_sync()}.

send_sync(Dispatcher, Name, RequestInfo, Request,
          Timeout, Priority)
    when is_pid(Dispatcher) ->
    cloudi_service:send_sync(Dispatcher, Name, RequestInfo, Request,
                             Timeout, Priority);

send_sync(Context, Name, RequestInfo, Request,
          Timeout, Priority) ->
    send_sync(Context, Name, RequestInfo, Request,
              Timeout, Priority, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a synchronous service request.===
%% @end
%%-------------------------------------------------------------------------

-spec send_sync(Context :: context() | cloudi_service:dispatcher(),
                Name :: service_name(),
                RequestInfo :: request_info(),
                Request :: request(),
                Timeout :: timeout_milliseconds(),
                Priority :: priority(),
                PatternPid :: pattern_pid() | undefined) ->
    {ok, ResponseInfo :: response_info(), Response :: response()} |
    {ok, Response :: response()} |
    {error, Reason :: error_reason_sync()}.

send_sync(Dispatcher, Name, RequestInfo, Request,
          Timeout, Priority, PatternPid)
    when is_pid(Dispatcher) ->
    cloudi_service:send_sync(Dispatcher, Name, RequestInfo, Request,
                             Timeout, Priority, PatternPid);

send_sync(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context,
          Name, RequestInfo, Request,
          undefined, Priority, PatternPid) ->
    send_sync(Context, Name, RequestInfo, Request,
              DefaultTimeoutSync, Priority, PatternPid);

send_sync(#cloudi_context{} = Context,
          Name, RequestInfo, Request,
          immediate, Priority, PatternPid) ->
    send_sync(Context, Name, RequestInfo, Request,
              ?SEND_SYNC_INTERVAL - 1, Priority, PatternPid);

send_sync(#cloudi_context{priority_default = PriorityDefault} = Context,
          Name, RequestInfo, Request,
          Timeout, undefined, PatternPid) ->
    send_sync(Context, Name, RequestInfo, Request,
              Timeout, PriorityDefault, PatternPid);

send_sync(#cloudi_context{} = Context,
          Name, RequestInfo, Request,
          Timeout, Priority, undefined)
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX ->
    NewContext = destinations_refresh_check(Context),
    #cloudi_context{
        dest_refresh = DestRefresh,
        scope = Scope,
        cpg_data = Groups} = NewContext,
    case destination_get(DestRefresh, Scope, Name, Groups,
                         Timeout + ?TIMEOUT_DELTA) of
        {error, {Reason, Name}}
        when (Reason =:= no_process orelse Reason =:= no_such_group),
             Timeout >= ?SEND_SYNC_INTERVAL ->
            send_sync(sleep(NewContext, ?SEND_SYNC_INTERVAL), Name,
                      RequestInfo, Request,
                      Timeout - ?SEND_SYNC_INTERVAL,
                      Priority, undefined);
        {error, _} ->
            result(NewContext, {error, timeout});
        {ok, Pattern, Pid} ->
            send_sync(NewContext, Name, RequestInfo, Request,
                      Timeout, Priority, {Pattern, Pid})
    end;

send_sync(#cloudi_context{receiver = Receiver,
                          uuid_generator = UUID} = Context,
          Name, RequestInfo, Request,
          Timeout, Priority, {Pattern, Pid})
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX, is_integer(Priority),
         Priority >= ?PRIORITY_HIGH, Priority =< ?PRIORITY_LOW ->
    TransId = uuid:get_v1(UUID),
    Pid ! {'cloudi_service_send_sync',
           Name, Pattern, RequestInfo, Request,
           Timeout, Priority, TransId, Receiver},
    send_sync_receive(Context, Timeout, TransId).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% Asynchronous service requests are sent to all services that have
%% subscribed to the service name pattern that matches the destination.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async(Context :: context() | cloudi_service:dispatcher(),
                  Name :: service_name(),
                  Request :: request()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async(Dispatcher, Name, Request)
    when is_pid(Dispatcher) ->
    cloudi_service:mcast_async(Dispatcher, Name, Request);

mcast_async(Context, Name, Request) ->
    mcast_async(Context, Name, <<>>, Request,
                undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% Asynchronous service requests are sent to all services that have
%% subscribed to the service name pattern that matches the destination.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async(Context :: context() | cloudi_service:dispatcher(),
                  Name :: service_name(),
                  Request :: request(),
                  Timeout :: timeout_milliseconds()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async(Dispatcher, Name, Request, Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:mcast_async(Dispatcher, Name, Request, Timeout);

mcast_async(Context, Name, Request, Timeout) ->
    mcast_async(Context, Name, <<>>, Request,
                Timeout, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% Asynchronous service requests are sent to all services that have
%% subscribed to the service name pattern that matches the destination.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async(Context :: context() | cloudi_service:dispatcher(),
                  Name :: service_name(),
                  RequestInfo :: request_info(),
                  Request :: request(),
                  Timeout :: timeout_milliseconds(),
                  Priority :: priority()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async(Dispatcher, Name, RequestInfo, Request,
            Timeout, Priority)
    when is_pid(Dispatcher) ->
    cloudi_service:mcast_async(Dispatcher, Name, RequestInfo, Request,
                               Timeout, Priority);

mcast_async(#cloudi_context{timeout_async = DefaultTimeoutAsync} = Context,
            Name, RequestInfo, Request, undefined, Priority) ->
    mcast_async(Context, Name, RequestInfo, Request,
                DefaultTimeoutAsync, Priority);

mcast_async(#cloudi_context{} = Context,
            Name, RequestInfo, Request, immediate, Priority) ->
    mcast_async(Context, Name, RequestInfo, Request,
                ?MCAST_ASYNC_INTERVAL - 1, Priority);

mcast_async(#cloudi_context{priority_default = PriorityDefault} = Context,
            Name, RequestInfo, Request, Timeout, undefined) ->
    mcast_async(Context, Name, RequestInfo, Request,
                Timeout, PriorityDefault);

mcast_async(#cloudi_context{} = Context,
            Name, RequestInfo, Request, Timeout, Priority)
    when is_list(Name), is_integer(Timeout),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX, is_integer(Priority),
         Priority >= ?PRIORITY_HIGH, Priority =< ?PRIORITY_LOW ->
    NewContext = destinations_refresh_check(Context),
    #cloudi_context{
        dest_refresh = DestRefresh,
        scope = Scope,
        receiver = Receiver,
        uuid_generator = UUID,
        cpg_data = Groups} = NewContext,
    case destination_all(DestRefresh, Scope, Name, Groups,
                         Timeout + ?TIMEOUT_DELTA) of
        {error, {no_such_group, Name}}
        when Timeout >= ?MCAST_ASYNC_INTERVAL ->
            mcast_async(sleep(NewContext, ?MCAST_ASYNC_INTERVAL), Name,
                        RequestInfo, Request,
                        Timeout - ?MCAST_ASYNC_INTERVAL, Priority);
        {error, _} ->
            result(NewContext, {error, timeout});
        {ok, Pattern, PidList} ->
            TransIdList = lists:map(fun(Pid) ->
                TransId = uuid:get_v1(UUID),
                Pid ! {'cloudi_service_send_async',
                       Name, Pattern, RequestInfo, Request,
                       Timeout, Priority, TransId, Receiver},
                TransId
            end, PidList),
            result(NewContext, {ok, TransIdList})
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% An alias for mcast_async.  The asynchronous service requests are returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async_passive(Context :: context() | cloudi_service:dispatcher(),
                          Name :: service_name(),
                          Request :: request()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async_passive(Context, Name, Request) ->
    mcast_async(Context, Name, Request).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% An alias for mcast_async.  The asynchronous service requests are returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async_passive(Context :: context() | cloudi_service:dispatcher(),
                          Name :: service_name(),
                          Request :: request(),
                          Timeout :: timeout_milliseconds()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async_passive(Context, Name, Request, Timeout) ->
    mcast_async(Context, Name, Request, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Send a multicast asynchronous service request.===
%% An alias for mcast_async.  The asynchronous service requests are returned
%% and handled the same way as within external services.
%% @end
%%-------------------------------------------------------------------------

-spec mcast_async_passive(Context :: context() | cloudi_service:dispatcher(),
                          Name :: service_name(),
                          RequestInfo :: request_info(),
                          Request :: request(),
                          Timeout :: timeout_milliseconds(),
                          Priority :: priority()) ->
    {ok, TransIdList :: list(trans_id())} |
    {error, Reason :: error_reason()}.

mcast_async_passive(Context, Name, RequestInfo, Request,
                    Timeout, Priority) ->
    mcast_async(Context, Name, RequestInfo, Request,
                Timeout, Priority).

%%-------------------------------------------------------------------------
%% @doc
%% ===Receive an asynchronous service request.===
%% Use a null TransId to receive the oldest service request.  Consume is
%% implicitly true.
%% @end
%%-------------------------------------------------------------------------

-spec recv_async(Context :: context() | cloudi_service:dispatcher()) ->
    {ok, ResponseInfo :: response_info(), Response :: response(),
     TransId :: trans_id()} |
    {error, Reason :: error_reason_sync()}.

recv_async(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:recv_async(Dispatcher);

recv_async(Context) ->
    recv_async(Context, undefined, <<0:128>>).

%%-------------------------------------------------------------------------
%% @doc
%% ===Receive an asynchronous service request.===
%% Either use the supplied TransId to receive the specific service request
%% or use a null TransId to receive the oldest service request.  Consume is
%% implicitly true.
%% @end
%%-------------------------------------------------------------------------

-spec recv_async(Context :: context() | cloudi_service:dispatcher(),
                 trans_id() | timeout_milliseconds()) ->
    {ok, ResponseInfo :: response_info(), Response :: response(),
     TransId :: trans_id()} |
    {error, Reason :: error_reason_sync()}.

recv_async(Dispatcher, TransId_Timeout)
    when is_pid(Dispatcher) ->
    cloudi_service:recv_async(Dispatcher, TransId_Timeout);

recv_async(Context, TransId)
    when is_binary(TransId) ->
    recv_async(Context, undefined, TransId);

recv_async(Context, undefined) ->
    recv_async(Context, undefined, <<0:128>>);

recv_async(Context, immediate) ->
    recv_async(Context, ?RECV_ASYNC_INTERVAL - 1, <<0:128>>);

recv_async(Context, Timeout)
    when is_integer(Timeout), Timeout >= 0 ->
    recv_async(Context, Timeout, <<0:128>>).

%%-------------------------------------------------------------------------
%% @doc
%% ===Receive an asynchronous service request.===
%% Either use the supplied TransId to receive the specific service request
%% or use a null TransId to receive the oldest service request.  Consume is
%% implicitly true.
%% @end
%%-------------------------------------------------------------------------

-spec recv_async(Context :: context() | cloudi_service:dispatcher(),
                 Timeout :: timeout_milliseconds(),
                 TransId :: trans_id()) ->
    {ok, ResponseInfo :: response_info(), Response :: response(),
     TransId :: trans_id()} |
    {error, Reason :: error_reason_sync()}.

recv_async(Dispatcher, Timeout, TransId)
    when is_pid(Dispatcher) ->
    cloudi_service:recv_async(Dispatcher, Timeout, TransId);

recv_async(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context,
           undefined, TransId) ->
    recv_async(Context, DefaultTimeoutSync, TransId);

recv_async(#cloudi_context{} = Context, immediate, TransId) ->
    recv_async(Context, ?RECV_ASYNC_INTERVAL - 1, TransId);

recv_async(#cloudi_context{receiver = Receiver} = Context,
           Timeout, <<0:128>>)
    when is_integer(Timeout), Timeout >= 0 ->
    if
        self() /= Receiver ->
            ?LOG_ERROR("recv_async called outside of context", []),
            erlang:exit(badarg);
        true ->
            ok
    end,
    recv_async_receive_any(Context, Timeout);

recv_async(#cloudi_context{receiver = Receiver} = Context,
           Timeout, TransId)
    when is_integer(Timeout), is_binary(TransId), Timeout >= 0 ->
    if
        self() /= Receiver ->
            ?LOG_ERROR("recv_async called outside of context", []),
            erlang:exit(badarg);
        true ->
            ok
    end,
    recv_async_receive_id(Context, Timeout, TransId).

%%-------------------------------------------------------------------------
%% @doc
%% ===Receive asynchronous service requests.===
%% @end
%%-------------------------------------------------------------------------

-spec recv_asyncs(Context :: context() | cloudi_service:dispatcher(),
                  TransIdList :: list(trans_id())) ->
    {ok, list({ResponseInfo :: response_info(), Response :: response(),
               TransId :: trans_id()})} |
    {error, Reason :: error_reason_sync()}.

recv_asyncs(Dispatcher, TransIdList)
    when is_pid(Dispatcher) ->
    cloudi_service:recv_asyncs(Dispatcher, TransIdList);

recv_asyncs(Context, TransIdList) ->
    recv_asyncs(Context, undefined, TransIdList).

%%-------------------------------------------------------------------------
%% @doc
%% ===Receive asynchronous service requests.===
%% @end
%%-------------------------------------------------------------------------

-spec recv_asyncs(Context :: context() | cloudi_service:dispatcher(),
                  Timeout :: timeout_milliseconds(),
                  TransIdList :: list(trans_id())) ->
    {ok, list({ResponseInfo :: response_info(), Response :: response(),
               TransId :: trans_id()})} |
    {error, Reason :: error_reason_sync()}.

recv_asyncs(Dispatcher, Timeout, TransIdList)
    when is_pid(Dispatcher) ->
    cloudi_service:recv_asyncs(Dispatcher, Timeout, TransIdList);

recv_asyncs(#cloudi_context{timeout_sync = DefaultTimeoutSync} = Context,
            undefined, TransIdList) ->
    recv_asyncs(Context, DefaultTimeoutSync, TransIdList);

recv_asyncs(#cloudi_context{} = Context, immediate, TransIdList) ->
    recv_asyncs(Context, ?RECV_ASYNC_INTERVAL - 1, TransIdList);

recv_asyncs(#cloudi_context{receiver = Receiver} = Context,
            Timeout, TransIdList)
    when is_integer(Timeout), is_list(TransIdList),
         Timeout >= 0, Timeout =< ?TIMEOUT_MAX ->
    if
        self() /= Receiver ->
            ?LOG_ERROR("recv_asyncs called outside of context", []),
            erlang:exit(badarg);
        true ->
            ok
    end,
    recv_asyncs_receive_ids([{<<>>, <<>>, TransId} || TransId <- TransIdList],
                            Timeout, Context).

%%-------------------------------------------------------------------------
%% @doc
%% ===Configured service default asynchronous timeout (in milliseconds).===
%% @end
%%-------------------------------------------------------------------------

-spec timeout_async(Context :: context() | cloudi_service:dispatcher()) ->
    TimeoutAsync :: cloudi_service_api:timeout_milliseconds().

timeout_async(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:timeout_async(Dispatcher);

timeout_async(#cloudi_context{timeout_async = DefaultTimeoutAsync}) ->
    DefaultTimeoutAsync.

%%-------------------------------------------------------------------------
%% @doc
%% ===Configured service default synchronous timeout (in milliseconds).===
%% @end
%%-------------------------------------------------------------------------

-spec timeout_sync(Context :: context() | cloudi_service:dispatcher()) ->
    TimeoutSync :: cloudi_service_api:timeout_milliseconds().

timeout_sync(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:timeout_sync(Dispatcher);

timeout_sync(#cloudi_context{timeout_sync = DefaultTimeoutSync}) ->
    DefaultTimeoutSync.

%%-------------------------------------------------------------------------
%% @doc
%% === Maximum possible service request timeout (in milliseconds).===
%% @end
%%-------------------------------------------------------------------------

-spec timeout_max(Context :: context() | cloudi_service:dispatcher()) ->
    TimeoutMax :: cloudi_service_api:timeout_milliseconds().

timeout_max(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:timeout_max(Dispatcher);

timeout_max(#cloudi_context{}) ->
    ?TIMEOUT_MAX.

%%-------------------------------------------------------------------------
%% @doc
%% ===Configured service default priority.===
%% @end
%%-------------------------------------------------------------------------

-spec priority_default(Context :: context() | cloudi_service:dispatcher()) ->
    PriorityDefault :: cloudi_service_api:priority().

priority_default(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:priority_default(Dispatcher);

priority_default(#cloudi_context{priority_default = PriorityDefault}) ->
    PriorityDefault.

%%-------------------------------------------------------------------------
%% @doc
%% ===Configured service destination refresh is immediate.===
%% @end
%%-------------------------------------------------------------------------

-spec destination_refresh_immediate(Context :: context() |
                                               cloudi_service:dispatcher()) ->
    boolean().

destination_refresh_immediate(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:destination_refresh_immediate(Dispatcher);

destination_refresh_immediate(#cloudi_context{
                                  dest_refresh = DestRefresh}) ->
    (DestRefresh =:= immediate_closest orelse
     DestRefresh =:= immediate_furthest orelse
     DestRefresh =:= immediate_random orelse
     DestRefresh =:= immediate_local orelse
     DestRefresh =:= immediate_remote orelse
     DestRefresh =:= immediate_newest orelse
     DestRefresh =:= immediate_oldest).

%%-------------------------------------------------------------------------
%% @doc
%% ===Configured service destination refresh is lazy.===
%% @end
%%-------------------------------------------------------------------------

-spec destination_refresh_lazy(Context :: context() |
                                          cloudi_service:dispatcher()) ->
    boolean().

destination_refresh_lazy(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:destination_refresh_lazy(Dispatcher);

destination_refresh_lazy(#cloudi_context{
                             dest_refresh = DestRefresh}) ->
    (DestRefresh =:= lazy_closest orelse
     DestRefresh =:= lazy_furthest orelse
     DestRefresh =:= lazy_random orelse
     DestRefresh =:= lazy_local orelse
     DestRefresh =:= lazy_remote orelse
     DestRefresh =:= lazy_newest orelse
     DestRefresh =:= lazy_oldest).

%%-------------------------------------------------------------------------
%% @doc
%% ===Return a new transaction id.===
%% The same data as used when sending service requests is used.
%% @end
%%-------------------------------------------------------------------------

-spec trans_id(Context :: context() |
                          cloudi_service:dispatcher()) ->
    <<_:128>>.

trans_id(Dispatcher)
    when is_pid(Dispatcher) ->
    cloudi_service:trans_id(Dispatcher);

trans_id(#cloudi_context{uuid_generator = UUID}) ->
    uuid:get_v1(UUID).

%%-------------------------------------------------------------------------
%% @doc
%% ===Return the age of the transaction id.===
%% The result is microseconds since the Unix epoch 1970-01-01 00:00:00.
%% @end
%%-------------------------------------------------------------------------

-spec trans_id_age(TransId :: <<_:128>>) ->
    non_neg_integer().

trans_id_age(TransId)
    when is_binary(TransId) ->
    uuid:get_v1_time(TransId).

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

destinations_refresh_check(#cloudi_context{
                               dest_refresh = DestRefresh,
                               receiver = Receiver} = Context)
    when (DestRefresh =:= lazy_closest orelse
          DestRefresh =:= lazy_furthest orelse
          DestRefresh =:= lazy_random orelse
          DestRefresh =:= lazy_local orelse
          DestRefresh =:= lazy_remote orelse
          DestRefresh =:= lazy_newest orelse
          DestRefresh =:= lazy_oldest) ->
    if
        self() /= Receiver ->
            ?LOG_ERROR("called outside of context", []),
            erlang:exit(badarg);
        true ->
            ok
    end,
    receive
        {cloudi_cpg_data, Groups} ->
            % clear queue of all destination_refreshes that are pending
            destinations_refresh_check(Context#cloudi_context{
                                           cpg_data = Groups,
                                           cpg_data_stale = true})
    after
        0 ->
            Context
    end;

destinations_refresh_check(#cloudi_context{
                               receiver = Receiver} = Context) ->
    if
        self() /= Receiver ->
            ?LOG_ERROR("called outside of context", []),
            erlang:exit(badarg);
        true ->
            ok
    end,
    Context.

sleep(#cloudi_context{} = Context, Delay) ->
    receive
        {cloudi_cpg_data, Groups} ->
            sleep(Context#cloudi_context{
                      cpg_data = Groups,
                      cpg_data_stale = true}, Delay)
    after
        Delay ->
            Context
    end.

send_sync_receive(#cloudi_context{
                      receiver = Receiver} = Context,
                  Timeout, TransId) ->
    receive
        {'cloudi_service_return_sync',
         _, _, <<>>, <<>>, _, TransId, Receiver} ->
            result(Context, {error, timeout});
        {'cloudi_service_return_sync',
         _, _, <<>>, Response, _, TransId, Receiver} ->
            result(Context, {ok, Response});
        {'cloudi_service_return_sync',
         _, _, ResponseInfo, Response, _, TransId, Receiver} ->
            result(Context, {ok, ResponseInfo, Response});
        {cloudi_cpg_data, Groups} ->
            send_sync_receive(Context#cloudi_context{
                                  cpg_data = Groups,
                                  cpg_data_stale = true},
                              Timeout, TransId)
    after
        Timeout ->
            result(Context, {error, timeout})
    end.

recv_async_receive_any(#cloudi_context{
                           receiver = Receiver} = Context,
                       Timeout) ->
    receive
        {'cloudi_service_return_async',
         _, _, <<>>, <<>>, _, _, Receiver} ->
            result(Context, {error, timeout});
        {'cloudi_service_return_async',
         _, _, ResponseInfo, Response, _, TransId, Receiver} ->
            result(Context, {ok, ResponseInfo, Response, TransId});
        {cloudi_cpg_data, Groups} ->
            recv_async_receive_any(Context#cloudi_context{
                                       cpg_data = Groups,
                                       cpg_data_stale = true},
                                   Timeout)
    after
        Timeout ->
            result(Context, {error, timeout})
    end.

recv_async_receive_id(#cloudi_context{
                          receiver = Receiver} = Context,
                      Timeout, TransId) ->
    receive
        {'cloudi_service_return_async',
         _, _, <<>>, <<>>, _, TransId, Receiver} ->
            result(Context, {error, timeout});
        {'cloudi_service_return_async',
         _, _, ResponseInfo, Response, _, TransId, Receiver} ->
            result(Context, {ok, ResponseInfo, Response, TransId});
        {cloudi_cpg_data, Groups} ->
            recv_async_receive_id(Context#cloudi_context{
                                      cpg_data = Groups,
                                      cpg_data_stale = true},
                                  Timeout, TransId)
    after
        Timeout ->
            result(Context, {error, timeout})
    end.

recv_asyncs_receive_ids(Results, Timeout, Context) ->
    case recv_asyncs_receive_ids(Results, [], true, false, Context) of
        {true, _, NewResults, NewContext} ->
            result(NewContext, {ok, NewResults});
        {false, _, NewResults, NewContext}
            when Timeout >= ?RECV_ASYNC_INTERVAL ->
            recv_asyncs_receive_ids(NewResults,
                                    Timeout - ?RECV_ASYNC_INTERVAL,
                                    sleep(NewContext, ?RECV_ASYNC_INTERVAL));
        {false, false, NewResults, NewContext} ->
            result(NewContext, {ok, NewResults});
        {false, true, _, NewContext} ->
            result(NewContext, {error, timeout})
    end.

recv_asyncs_receive_ids([], L, Done, FoundOne, Context) ->
    {Done, not FoundOne, lists:reverse(L), Context};

recv_asyncs_receive_ids([{<<>>, <<>>, TransId} = Entry | Results] = OldResults,
                        L, Done, FoundOne,
                        #cloudi_context{
                            receiver = Receiver} = Context) ->
    receive
        {'cloudi_service_return_async',
         _, _, <<>>, <<>>, _, TransId, Receiver} ->
            recv_asyncs_receive_ids(Results,
                                    [Entry | L],
                                    Done, FoundOne, Context);
        {'cloudi_service_return_async',
         _, _, ResponseInfo, Response, _, TransId, Receiver} ->
            recv_asyncs_receive_ids(Results,
                                    [{ResponseInfo, Response, TransId} | L],
                                    Done, true, Context);
        {cloudi_cpg_data, Groups} ->
            recv_asyncs_receive_ids(OldResults, L, Done, FoundOne,
                                    Context#cloudi_context{
                                        cpg_data = Groups,
                                        cpg_data_stale = true})
    after
        0 ->
            recv_asyncs_receive_ids(Results,
                                    [Entry | L],
                                    false, FoundOne, Context)
    end;

recv_asyncs_receive_ids([{_, _, _} = Entry | Results],
                        L, Done, _FoundOne, Context) ->
    recv_asyncs_receive_ids(Results,
                            [Entry | L],
                            Done, true, Context).

result(#cloudi_context{
           dest_refresh = DestRefresh,
           dest_refresh_delay = DestRefreshDelay,
           scope = Scope,
           receiver = Receiver,
           cpg_data = Groups,
           cpg_data_stale = SendGroups}, Result) ->
    if
        SendGroups =:= true ->
            % Context is not returned,
            % so sent the updated Groups that were used
            Receiver ! {cloudi_cpg_data, Groups},
            ok = destination_refresh_start(DestRefresh,
                                           DestRefreshDelay, Scope),
            Result;
        SendGroups =:= false ->
            Result
    end.

destination_refresh_first(DestRefresh, Delay, Scope)
    when (DestRefresh =:= lazy_closest orelse
          DestRefresh =:= lazy_furthest orelse
          DestRefresh =:= lazy_random orelse
          DestRefresh =:= lazy_local orelse
          DestRefresh =:= lazy_remote orelse
          DestRefresh =:= lazy_newest orelse
          DestRefresh =:= lazy_oldest) ->
    cpg_data:get_groups(Scope, Delay);

destination_refresh_first(DestRefresh, _, _)
    when (DestRefresh =:= immediate_closest orelse
          DestRefresh =:= immediate_furthest orelse
          DestRefresh =:= immediate_random orelse
          DestRefresh =:= immediate_local orelse
          DestRefresh =:= immediate_remote orelse
          DestRefresh =:= immediate_newest orelse
          DestRefresh =:= immediate_oldest) ->
    ok.

destination_refresh_start(DestRefresh, Delay, Scope)
    when (DestRefresh =:= lazy_closest orelse
          DestRefresh =:= lazy_furthest orelse
          DestRefresh =:= lazy_random orelse
          DestRefresh =:= lazy_local orelse
          DestRefresh =:= lazy_remote orelse
          DestRefresh =:= lazy_newest orelse
          DestRefresh =:= lazy_oldest) ->
    cpg_data:get_groups(Scope, Delay);

destination_refresh_start(DestRefresh, _, _)
    when (DestRefresh =:= immediate_closest orelse
          DestRefresh =:= immediate_furthest orelse
          DestRefresh =:= immediate_random orelse
          DestRefresh =:= immediate_local orelse
          DestRefresh =:= immediate_remote orelse
          DestRefresh =:= immediate_newest orelse
          DestRefresh =:= immediate_oldest) ->
    ok.

-define(CATCH_EXIT(F),
        try F catch exit:{Reason, _} -> {error, Reason} end).

lazy_check_get(Name, {ok, _, Pid} = Result) ->
    if
        node() =:= node(Pid) ->
            case erlang:is_process_alive(Pid) of
                true ->
                    Result;
                false ->
                    % stale lookup: give the function call a chance to
                    %               do a destination refresh
                    {error, {no_process, Name}}
            end;
        true ->
            Result
    end;

lazy_check_get(_, {error, _} = Result) ->
    Result.

destination_get(lazy_closest, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_closest_pid(Name, Groups));

destination_get(lazy_furthest, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_furthest_pid(Name, Groups));

destination_get(lazy_random, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_random_pid(Name, Groups));

destination_get(lazy_local, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_local_pid(Name, Groups));

destination_get(lazy_remote, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_remote_pid(Name, Groups));

destination_get(lazy_newest, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_newest_pid(Name, Groups));

destination_get(lazy_oldest, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_get(Name, cpg_data:get_oldest_pid(Name, Groups));

destination_get(immediate_closest, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_closest_pid(Scope, Name, Timeout));

destination_get(immediate_furthest, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_furthest_pid(Scope, Name, Timeout));

destination_get(immediate_random, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_random_pid(Scope, Name, Timeout));

destination_get(immediate_local, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_local_pid(Scope, Name, Timeout));

destination_get(immediate_remote, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_remote_pid(Scope, Name, Timeout));

destination_get(immediate_newest, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_newest_pid(Scope, Name, Timeout));

destination_get(immediate_oldest, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_oldest_pid(Scope, Name, Timeout));

destination_get(DestRefresh, _, _, _, _) ->
    ?LOG_ERROR("unable to send with invalid destination refresh: ~p",
               [DestRefresh]),
    erlang:exit(badarg).

lazy_check_all(Name, {ok, _, PidList} = Result) ->
    Check = fun(Pid) ->
        if
            node() =:= node(Pid) ->
                erlang:is_process_alive(Pid);
            true ->
                true
        end
    end,
    case lists:all(Check, PidList) of
        true ->
            Result;
        false ->
            % stale lookup: give the function call a chance to
            %               do a destination refresh
            {error, {no_such_group, Name}}
    end;

lazy_check_all(_, {error, _} = Result) ->
    Result.

destination_all(DestRefresh, _, Name, Groups, _)
    when is_list(Name),
         (DestRefresh =:= lazy_closest orelse
          DestRefresh =:= lazy_furthest orelse
          DestRefresh =:= lazy_random orelse
          DestRefresh =:= lazy_newest orelse
          DestRefresh =:= lazy_oldest) ->
    lazy_check_all(Name, cpg_data:get_members(Name, Groups));

destination_all(lazy_local, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_all(Name, cpg_data:get_local_members(Name, Groups));

destination_all(lazy_remote, _, Name, Groups, _)
    when is_list(Name) ->
    lazy_check_all(Name, cpg_data:get_remote_members(Name, Groups));

destination_all(DestRefresh, Scope, Name, _, Timeout)
    when (DestRefresh =:= immediate_closest orelse
          DestRefresh =:= immediate_furthest orelse
          DestRefresh =:= immediate_random orelse
          DestRefresh =:= immediate_newest orelse
          DestRefresh =:= immediate_oldest),
         is_list(Name) ->
    ?CATCH_EXIT(cpg:get_members(Scope, Name, Timeout));

destination_all(immediate_local, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_local_members(Scope, Name, Timeout));

destination_all(immediate_remote, Scope, Name, _, Timeout)
    when is_list(Name) ->
    ?CATCH_EXIT(cpg:get_remote_members(Scope, Name, Timeout));

destination_all(DestRefresh, _, _, _, _) ->
    ?LOG_ERROR("unable to send with invalid destination refresh: ~p",
               [DestRefresh]),
    erlang:exit(badarg).

