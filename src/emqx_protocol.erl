%%%===================================================================
%%% Copyright (c) 2013-2018 EMQ Inc. All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%===================================================================

-module(emqx_protocol).

-include("emqx.hrl").

-include("emqx_mqtt.hrl").

-include("emqx_misc.hrl").

-import(proplists, [get_value/2, get_value/3]).

%% API
-export([init/3, init/5, get/2, info/1, stats/1, clientid/1, client/1, session/1]).

-export([subscribe/2, unsubscribe/2, pubrel/2, shutdown/2]).

-export([received/2, send/2]).

-export([process/2]).

-ifdef(TEST).
-compile(export_all).
-endif.

-record(proto_stats, {enable_stats = false, recv_pkt = 0, recv_msg = 0,
                      send_pkt = 0, send_msg = 0}).

%% Protocol State
%% ws_initial_headers: Headers from first HTTP request for WebSocket Client.
-record(proto_state, {peername, sendfun, connected = false, client_id, client_pid,
                      clean_start, proto_ver, proto_name, username, is_superuser,
                      will_msg, keepalive, keepalive_backoff, max_clientid_len,
                      session, stats_data, mountpoint, ws_initial_headers,
                      peercert_username, is_bridge, connected_at}).

-type(proto_state() :: #proto_state{}).

-define(INFO_KEYS, [client_id, username, clean_start, proto_ver, proto_name,
                    keepalive, will_msg, ws_initial_headers, mountpoint,
                    peercert_username, connected_at]).

-define(STATS_KEYS, [recv_pkt, recv_msg, send_pkt, send_msg]).

-define(LOG(Level, Format, Args, State),
            emqx_logger:Level([{client, State#proto_state.client_id}], "Client(~s@~s): " ++ Format,
                              [State#proto_state.client_id, esockd_net:format(State#proto_state.peername) | Args])).

%% @doc Init protocol
init(Peername, SendFun, Opts) ->
    Backoff = get_value(keepalive_backoff, Opts, 0.75),
    EnableStats = get_value(client_enable_stats, Opts, false),
    MaxLen = get_value(max_clientid_len, Opts, ?MAX_CLIENTID_LEN),
    WsInitialHeaders = get_value(ws_initial_headers, Opts),
    #proto_state{peername           = Peername,
                 sendfun            = SendFun,
                 max_clientid_len   = MaxLen,
                 is_superuser       = false,
                 client_pid         = self(),
                 peercert_username  = undefined,
                 ws_initial_headers = WsInitialHeaders,
                 keepalive_backoff  = Backoff,
                 stats_data         = #proto_stats{enable_stats = EnableStats}}.

init(_Transport, _Sock, Peername, SendFun, Opts) ->
    init(Peername, SendFun, Opts).
    %%enrich_opt(Conn:opts(), Conn, ).

enrich_opt([], _Conn, State) ->
    State;
enrich_opt([{mountpoint, MountPoint} | ConnOpts], Conn, State) ->
    enrich_opt(ConnOpts, Conn, State#proto_state{mountpoint = MountPoint});
enrich_opt([{peer_cert_as_username, N} | ConnOpts], Conn, State) ->
    enrich_opt(ConnOpts, Conn, State#proto_state{peercert_username = peercert_username(N, Conn)});
enrich_opt([_ | ConnOpts], Conn, State) ->
    enrich_opt(ConnOpts, Conn, State).

peercert_username(cn, Conn) ->
    Conn:peer_cert_common_name();
peercert_username(dn, Conn) ->
    Conn:peer_cert_subject().

repl_username_with_peercert(State = #proto_state{peercert_username = undefined}) ->
    State;
repl_username_with_peercert(State = #proto_state{peercert_username = PeerCert}) ->
    State#proto_state{username = PeerCert}.

%%TODO::
get(proto_ver, #proto_state{proto_ver = Ver}) ->
    Ver;
get(_, _ProtoState) ->
    undefined.

info(ProtoState) ->
    ?record_to_proplist(proto_state, ProtoState, ?INFO_KEYS).

stats(#proto_state{stats_data = Stats}) ->
    tl(?record_to_proplist(proto_stats, Stats)).

clientid(#proto_state{client_id = ClientId}) ->
    ClientId.

client(#proto_state{client_id          = ClientId,
                    client_pid         = ClientPid,
                    peername           = Peername,
                    username           = Username,
                    clean_start        = CleanStart,
                    proto_ver          = ProtoVer,
                    keepalive          = Keepalive,
                    will_msg           = WillMsg,
                    ws_initial_headers = WsInitialHeaders,
                    mountpoint         = MountPoint,
                    connected_at       = Time}) ->
    WillTopic = if
                    WillMsg =:= undefined -> undefined;
                    true -> WillMsg#message.topic
                end,
    #client{id  = ClientId,
            pid = ClientPid,
            username = Username,
            peername = Peername}.

session(#proto_state{session = Session}) ->
    Session.

%% CONNECT – Client requests a connection to a Server

%% A Client can only send the CONNECT Packet once over a Network Connection.
-spec(received(mqtt_packet(), proto_state()) -> {ok, proto_state()} | {error, term()}).
received(Packet = ?PACKET(?CONNECT),
         State = #proto_state{connected = false, stats_data = Stats}) ->
    trace(recv, Packet, State), Stats1 = inc_stats(recv, ?CONNECT, Stats),
    process(Packet, State#proto_state{connected = true, stats_data = Stats1});

received(?PACKET(?CONNECT), State = #proto_state{connected = true}) ->
    {error, protocol_bad_connect, State};

%% Received other packets when CONNECT not arrived.
received(_Packet, State = #proto_state{connected = false}) ->
    {error, protocol_not_connected, State};

received(Packet = ?PACKET(Type), State = #proto_state{stats_data = Stats}) ->
    trace(recv, Packet, State), Stats1 = inc_stats(recv, Type, Stats),
    case validate_packet(Packet) of
        ok ->
            process(Packet, State#proto_state{stats_data = Stats1});
        {error, Reason} ->
            {error, Reason, State}
    end.

subscribe(RawTopicTable, ProtoState = #proto_state{client_id = ClientId,
                                                   username  = Username,
                                                   session   = Session}) ->
    TopicTable = parse_topic_table(RawTopicTable),
    case emqx_hooks:run('client.subscribe', [ClientId, Username], TopicTable) of
        {ok, TopicTable1} ->
            emqx_session:subscribe(Session, TopicTable1);
        {stop, _} ->
            ok
    end,
    {ok, ProtoState}.

unsubscribe(RawTopics, ProtoState = #proto_state{client_id = ClientId,
                                                 username  = Username,
                                                 session   = Session}) ->
    case emqx_hooks:run('client.unsubscribe', [ClientId, Username], parse_topics(RawTopics)) of
        {ok, TopicTable} ->
            emqx_session:unsubscribe(Session, TopicTable);
        {stop, _} ->
            ok
    end,
    {ok, ProtoState}.

%% @doc Send PUBREL
pubrel(PacketId, State) -> send(?PUBREL_PACKET(PacketId), State).

process(?CONNECT_PACKET(Var), State0) ->

    #mqtt_packet_connect{proto_ver  = ProtoVer,
                         proto_name = ProtoName,
                         username   = Username,
                         password   = Password,
                         clean_start= CleanStart,
                         keepalive  = KeepAlive,
                         client_id  = ClientId,
                         is_bridge  = IsBridge} = Var,

    State1 = repl_username_with_peercert(
               State0#proto_state{proto_ver    = ProtoVer,
                                  proto_name   = ProtoName,
                                  username     = Username,
                                  client_id    = ClientId,
                                  clean_start  = CleanStart,
                                  keepalive    = KeepAlive,
                                  will_msg     = willmsg(Var, State0),
                                  is_bridge    = IsBridge,
                                  connected_at = os:timestamp()}),

    {ReturnCode1, SessPresent, State3} =
    case validate_connect(Var, State1) of
        ?RC_SUCCESS ->
            case authenticate(client(State1), Password) of
                {ok, IsSuperuser} ->
                    %% Generate clientId if null
                    State2 = maybe_set_clientid(State1),

                    %% Start session
                    case emqx_sm:open_session(#{clean_start => CleanStart,
                                                client_id   => clientid(State2),
                                                username    => Username,
                                                client_pid  => self()}) of
                        {ok, Session} -> %% TODO:...
                            SP = true, %% TODO:...
                            %% TODO: Register the client
                            emqx_cm:register_client(clientid(State2)),
                            %%emqx_cm:reg(client(State2)),
                            %% Start keepalive
                            start_keepalive(KeepAlive, State2),
                            %% Emit Stats
                            self() ! emit_stats,
                            %% ACCEPT
                            {?RC_SUCCESS, SP, State2#proto_state{session = Session, is_superuser = IsSuperuser}};
                        {error, Error} ->
                            {stop, {shutdown, Error}, State2}
                    end;
                {error, Reason}->
                    ?LOG(error, "Username '~s' login failed for ~p", [Username, Reason], State1),
                    {?RC_BAD_USER_NAME_OR_PASSWORD, false, State1}
            end;
        ReturnCode ->
            {ReturnCode, false, State1}
    end,
    %% Run hooks
    emqx_hooks:run('client.connected', [ReturnCode1], client(State3)),
    %%TODO: Send Connack
    send(?CONNACK_PACKET(ReturnCode1, sp(SessPresent)), State3),
    %% stop if authentication failure
    stop_if_auth_failure(ReturnCode1, State3);

process(Packet = ?PUBLISH_PACKET(_Qos, Topic, _PacketId, _Payload), State = #proto_state{is_superuser = IsSuper}) ->
    case IsSuper orelse allow == check_acl(publish, Topic, client(State)) of
        true  -> publish(Packet, State);
        false -> ?LOG(error, "Cannot publish to ~s for ACL Deny", [Topic], State)
    end,
    {ok, State};

process(?PUBACK_PACKET(PacketId), State = #proto_state{session = Session}) ->
    emqx_session:puback(Session, PacketId),
    {ok, State};

process(?PUBREC_PACKET(PacketId), State = #proto_state{session = Session}) ->
    emqx_session:pubrec(Session, PacketId),
    send(?PUBREL_PACKET(PacketId), State);

process(?PUBREL_PACKET(PacketId), State = #proto_state{session = Session}) ->
    emqx_session:pubrel(Session, PacketId),
    send(?PUBCOMP_PACKET(PacketId), State);

process(?PUBCOMP_PACKET(PacketId), State = #proto_state{session = Session})->
    emqx_session:pubcomp(Session, PacketId), {ok, State};

%% Protect from empty topic table
process(?SUBSCRIBE_PACKET(PacketId, []), State) ->
    send(?SUBACK_PACKET(PacketId, []), State);

%% TODO: refactor later...
process(?SUBSCRIBE_PACKET(PacketId, RawTopicTable),
        State = #proto_state{client_id    = ClientId,
                             username     = Username,
                             is_superuser = IsSuperuser,
                             mountpoint   = MountPoint,
                             session      = Session}) ->
    Client = client(State), TopicTable = parse_topic_table(RawTopicTable),
    AllowDenies = if
                    IsSuperuser -> [];
                    true -> [check_acl(subscribe, Topic, Client) || {Topic, _Opts} <- TopicTable]
                  end,
    case lists:member(deny, AllowDenies) of
        true ->
            ?LOG(error, "Cannot SUBSCRIBE ~p for ACL Deny", [TopicTable], State),
            send(?SUBACK_PACKET(PacketId, [16#80 || _ <- TopicTable]), State);
        false ->
            case emqx_hooks:run('client.subscribe', [ClientId, Username], TopicTable) of
                {ok, TopicTable1} ->
                    emqx_session:subscribe(Session, PacketId, mount(replvar(MountPoint, State), TopicTable1)),
                    {ok, State};
                {stop, _} ->
                    {ok, State}
            end
    end;

%% Protect from empty topic list
process(?UNSUBSCRIBE_PACKET(PacketId, []), State) ->
    send(?UNSUBACK_PACKET(PacketId), State);

process(?UNSUBSCRIBE_PACKET(PacketId, RawTopics),
        State = #proto_state{client_id  = ClientId,
                             username   = Username,
                             mountpoint = MountPoint,
                             session    = Session}) ->
    case emqx_hooks:run('client.unsubscribe', [ClientId, Username], parse_topics(RawTopics)) of
        {ok, TopicTable} ->
            emqx_session:unsubscribe(Session, mount(replvar(MountPoint, State), TopicTable));
        {stop, _} ->
            ok
    end,
    send(?UNSUBACK_PACKET(PacketId), State);

process(?PACKET(?PINGREQ), State) ->
    send(?PACKET(?PINGRESP), State);

process(?PACKET(?DISCONNECT), State) ->
    % Clean willmsg
    {stop, normal, State#proto_state{will_msg = undefined}}.

publish(Packet = ?PUBLISH_PACKET(?QOS_0, _PacketId),
        State = #proto_state{client_id  = ClientId,
                             username   = Username,
                             mountpoint = MountPoint,
                             session    = Session}) ->
    Msg = emqx_packet:to_message(Packet),
    Msg1 = Msg#message{from = #client{id = ClientId, username = Username}},
    emqx_session:publish(Session, mount(replvar(MountPoint, State), Msg1));

publish(Packet = ?PUBLISH_PACKET(?QOS_1, _PacketId), State) ->
    with_puback(?PUBACK, Packet, State);

publish(Packet = ?PUBLISH_PACKET(?QOS_2, _PacketId), State) ->
    with_puback(?PUBREC, Packet, State).

with_puback(Type, Packet = ?PUBLISH_PACKET(_Qos, PacketId),
            State = #proto_state{client_id  = ClientId,
                                 username   = Username,
                                 mountpoint = MountPoint,
                                 session    = Session}) ->
    %% TODO: ...
    Msg = emqx_packet:to_message(Packet),
    Msg1 = Msg#message{from = #client{id = ClientId, username = Username}},
    case emqx_session:publish(Session, mount(replvar(MountPoint, State), Msg1)) of
        ok ->
            case Type of
                ?PUBACK -> send(?PUBACK_PACKET(PacketId), State);
                ?PUBREC -> send(?PUBREC_PACKET(PacketId), State)
            end;
        {error, Error} ->
            ?LOG(error, "PUBLISH ~p error: ~p", [PacketId, Error], State)
    end.

-spec(send(message() | mqtt_packet(), proto_state()) -> {ok, proto_state()}).
send(Msg, State = #proto_state{client_id  = ClientId,
                               username   = Username,
                               mountpoint = MountPoint,
                               is_bridge  = IsBridge})
        when is_record(Msg, message) ->
    emqx_hooks:run('message.delivered', [ClientId, Username], Msg),
    send(emqx_packet:from_message(unmount(MountPoint, clean_retain(IsBridge, Msg))), State);

send(Packet = ?PACKET(Type), State = #proto_state{sendfun = SendFun, stats_data = Stats}) ->
    trace(send, Packet, State),
    emqx_metrics:sent(Packet),
    SendFun(Packet),
    {ok, State#proto_state{stats_data = inc_stats(send, Type, Stats)}}.

trace(recv, Packet, ProtoState) ->
    ?LOG(info, "RECV ~s", [emqx_packet:format(Packet)], ProtoState);

trace(send, Packet, ProtoState) ->
    ?LOG(info, "SEND ~s", [emqx_packet:format(Packet)], ProtoState).

inc_stats(_Direct, _Type, Stats = #proto_stats{enable_stats = false}) ->
    Stats;

inc_stats(recv, Type, Stats) ->
    #proto_stats{recv_pkt = PktCnt, recv_msg = MsgCnt} = Stats,
    inc_stats(Type, #proto_stats.recv_pkt, PktCnt, #proto_stats.recv_msg, MsgCnt, Stats);

inc_stats(send, Type, Stats) ->
    #proto_stats{send_pkt = PktCnt, send_msg = MsgCnt} = Stats,
    inc_stats(Type, #proto_stats.send_pkt, PktCnt, #proto_stats.send_msg, MsgCnt, Stats).

inc_stats(Type, PktPos, PktCnt, MsgPos, MsgCnt, Stats) ->
    Stats1 = setelement(PktPos, Stats, PktCnt + 1),
    case Type =:= ?PUBLISH of
        true  -> setelement(MsgPos, Stats1, MsgCnt + 1);
        false -> Stats1
    end.

stop_if_auth_failure(?RC_SUCCESS, State) ->
    {ok, State};
stop_if_auth_failure(RC, State) when RC =/= ?RC_SUCCESS ->
    {stop, {shutdown, auth_failure}, State}.

shutdown(_Error, #proto_state{client_id = undefined}) ->
    ignore;
shutdown(conflict, _State = #proto_state{client_id = ClientId}) ->
    emqx_cm:unregister_client(ClientId),
    ignore;
shutdown(mnesia_conflict, _State = #proto_state{client_id = ClientId}) ->
    emqx_cm:unregister_client(ClientId),
    ignore;
shutdown(Error, State = #proto_state{client_id = ClientId,
                                     will_msg  = WillMsg}) ->
    ?LOG(info, "Shutdown for ~p", [Error], State),
    Client = client(State),
    %% Auth failure not publish the will message
    case Error =:= auth_failure of
        true -> ok;
        false -> send_willmsg(Client, WillMsg)
    end,
    emqx_hooks:run('client.disconnected', [Error], Client),
    emqx_cm:unregister_client(ClientId),
    ok.

willmsg(Packet, State = #proto_state{mountpoint = MountPoint})
    when is_record(Packet, mqtt_packet_connect) ->
    case emqx_packet:to_message(Packet) of
        undefined -> undefined;
        Msg -> mount(replvar(MountPoint, State), Msg)
    end.

%% Generate a client if if nulll
maybe_set_clientid(State = #proto_state{client_id = NullId})
        when NullId =:= undefined orelse NullId =:= <<>> ->
    {_, NPid, _} = emqx_guid:new(),
    ClientId = iolist_to_binary(["emqx_", integer_to_list(NPid)]),
    State#proto_state{client_id = ClientId};

maybe_set_clientid(State) ->
    State.

send_willmsg(_Client, undefined) ->
    ignore;
send_willmsg(Client, WillMsg) ->
    emqx_broker:publish(WillMsg#message{from = Client}).

start_keepalive(0, _State) -> ignore;

start_keepalive(Sec, #proto_state{keepalive_backoff = Backoff}) when Sec > 0 ->
    self() ! {keepalive, start, round(Sec * Backoff)}.

%%--------------------------------------------------------------------
%% Validate Packets
%%--------------------------------------------------------------------

validate_connect(Connect = #mqtt_packet_connect{}, ProtoState) ->
    case validate_protocol(Connect) of
        true ->
            case validate_clientid(Connect, ProtoState) of
                true  -> ?RC_SUCCESS;
                false -> ?RC_CLIENT_IDENTIFIER_NOT_VALID
            end;
        false ->
            ?RC_UNSUPPORTED_PROTOCOL_VERSION
    end.

validate_protocol(#mqtt_packet_connect{proto_ver = Ver, proto_name = Name}) ->
    lists:member({Ver, Name}, ?PROTOCOL_NAMES).

validate_clientid(#mqtt_packet_connect{client_id = ClientId},
                  #proto_state{max_clientid_len = MaxLen})
    when (byte_size(ClientId) >= 1) andalso (byte_size(ClientId) =< MaxLen) ->
    true;

%% Issue#599: Null clientId and clean_start = false
validate_clientid(#mqtt_packet_connect{client_id   = ClientId,
                                       clean_start = CleanStart}, _ProtoState)
    when byte_size(ClientId) == 0 andalso (not CleanStart) ->
    false;

%% MQTT3.1.1 allow null clientId.
validate_clientid(#mqtt_packet_connect{proto_ver =?MQTT_PROTO_V4,
                                       client_id = ClientId}, _ProtoState)
    when byte_size(ClientId) =:= 0 ->
    true;

validate_clientid(#mqtt_packet_connect{proto_ver   = ProtoVer,
                                       clean_start = CleanStart}, ProtoState) ->
    ?LOG(warning, "Invalid clientId. ProtoVer: ~p, CleanStart: ~s",
         [ProtoVer, CleanStart], ProtoState),
    false.

validate_packet(?PUBLISH_PACKET(_Qos, Topic, _PacketId, _Payload)) ->
    case emqx_topic:validate({name, Topic}) of
        true  -> ok;
        false -> {error, badtopic}
    end;

validate_packet(?SUBSCRIBE_PACKET(_PacketId, TopicTable)) ->
    validate_topics(filter, TopicTable);

validate_packet(?UNSUBSCRIBE_PACKET(_PacketId, Topics)) ->
    validate_topics(filter, Topics);

validate_packet(_Packet) ->
    ok.

validate_topics(_Type, []) ->
    {error, empty_topics};

validate_topics(Type, TopicTable = [{_Topic, _SubOpts}|_])
    when Type =:= name orelse Type =:= filter ->
    Valid = fun(Topic, Qos) ->
              emqx_topic:validate({Type, Topic}) and validate_qos(Qos)
            end,
    case [Topic || {Topic, SubOpts} <- TopicTable,
                   not Valid(Topic, proplists:get_value(qos, SubOpts))] of
        [] -> ok;
        _  -> {error, badtopic}
    end;

validate_topics(Type, Topics = [Topic0|_]) when is_binary(Topic0) ->
    case [Topic || Topic <- Topics, not emqx_topic:validate({Type, Topic})] of
        [] -> ok;
        _  -> {error, badtopic}
    end.

validate_qos(undefined) ->
    true;
validate_qos(Qos) when ?IS_QOS(Qos) ->
    true;
validate_qos(_) ->
    false.

parse_topic_table(TopicTable) ->
    lists:map(fun({Topic0, SubOpts}) ->
                {Topic, Opts} = emqx_topic:parse(Topic0),
                %%TODO:
                {Topic, lists:usort(lists:umerge(Opts, SubOpts))}
        end, TopicTable).

parse_topics(Topics) ->
    [emqx_topic:parse(Topic) || Topic <- Topics].

authenticate(Client, Password) ->
    case emqx_access_control:auth(Client, Password) of
        ok             -> {ok, false};
        {ok, IsSuper}  -> {ok, IsSuper};
        {error, Error} -> {error, Error}
    end.

%% PUBLISH ACL is cached in process dictionary.
check_acl(publish, Topic, Client) ->
    IfCache = emqx_config:get_env(cache_acl, true),
    case {IfCache, get({acl, publish, Topic})} of
        {true, undefined} ->
            AllowDeny = emqx_access_control:check_acl(Client, publish, Topic),
            put({acl, publish, Topic}, AllowDeny),
            AllowDeny;
        {true, AllowDeny} ->
            AllowDeny;
        {false, _} ->
            emqx_access_control:check_acl(Client, publish, Topic)
    end;

check_acl(subscribe, Topic, Client) ->
    emqx_access_control:check_acl(Client, subscribe, Topic).

sp(true)  -> 1;
sp(false) -> 0.

%%--------------------------------------------------------------------
%% The retained flag should be propagated for bridge.
%%--------------------------------------------------------------------

clean_retain(false, Msg = #message{flags = #{retain := true}, headers = Headers}) ->
    case maps:get(retained, Headers, false) of
        true  -> Msg;
        false -> emqx_message:set_flag(retain, false, Msg)
    end;
clean_retain(_IsBridge, Msg) ->
    Msg.

%%--------------------------------------------------------------------
%% Mount Point
%%--------------------------------------------------------------------

replvar(undefined, _State) ->
    undefined;
replvar(MountPoint, #proto_state{client_id = ClientId, username = Username}) ->
    lists:foldl(fun feed_var/2, MountPoint, [{<<"%c">>, ClientId}, {<<"%u">>, Username}]).

feed_var({<<"%c">>, ClientId}, MountPoint) ->
    emqx_topic:feed_var(<<"%c">>, ClientId, MountPoint);
feed_var({<<"%u">>, undefined}, MountPoint) ->
    MountPoint;
feed_var({<<"%u">>, Username}, MountPoint) ->
    emqx_topic:feed_var(<<"%u">>, Username, MountPoint).

mount(undefined, Any) ->
    Any;
mount(MountPoint, Msg = #message{topic = Topic}) ->
    Msg#message{topic = <<MountPoint/binary, Topic/binary>>};
mount(MountPoint, TopicTable) when is_list(TopicTable) ->
    [{<<MountPoint/binary, Topic/binary>>, Opts} || {Topic, Opts} <- TopicTable].

unmount(undefined, Any) ->
    Any;
unmount(MountPoint, Msg = #message{topic = Topic}) ->
    case catch split_binary(Topic, byte_size(MountPoint)) of
        {MountPoint, Topic0} -> Msg#message{topic = Topic0};
        _ -> Msg
    end.

