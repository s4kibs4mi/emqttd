%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%%--------------------------------------------------------------------
%% MQTT SockOpts
%%--------------------------------------------------------------------

-define(MQTT_SOCKOPTS, [binary, {packet, raw}, {reuseaddr, true},
                        {backlog, 512}, {nodelay, true}]).

%%--------------------------------------------------------------------
%% MQTT Protocol Version and Names
%%--------------------------------------------------------------------

-define(MQTT_PROTO_V3, 3).
-define(MQTT_PROTO_V4, 4).
-define(MQTT_PROTO_V5, 5).

-define(PROTOCOL_NAMES, [
    {?MQTT_PROTO_V3, <<"MQIsdp">>},
    {?MQTT_PROTO_V4, <<"MQTT">>},
    {?MQTT_PROTO_V5, <<"MQTT">>}]).

-type(mqtt_version() :: ?MQTT_PROTO_V3 | ?MQTT_PROTO_V4 | ?MQTT_PROTO_V5).

%%--------------------------------------------------------------------
%% MQTT QoS Levels
%%--------------------------------------------------------------------

-define(QOS_0, 0). %% At most once
-define(QOS_1, 1). %% At least once
-define(QOS_2, 2). %% Exactly once

-define(QOS0, 0). %% At most once
-define(QOS1, 1). %% At least once
-define(QOS2, 2). %% Exactly once

-define(IS_QOS(I), (I >= ?QOS0 andalso I =< ?QOS2)).

-type(mqtt_qos() :: ?QOS0 | ?QOS1 | ?QOS2).

-type(mqtt_qos_name() :: qos0 | at_most_once  |
                         qos1 | at_least_once |
                         qos2 | exactly_once).

-define(QOS_I(Name),
    begin
        (case Name of
            ?QOS_0        -> ?QOS_0;
            qos0          -> ?QOS_0;
            at_most_once  -> ?QOS_0;
            ?QOS_1        -> ?QOS_1;
            qos1          -> ?QOS_1;
            at_least_once -> ?QOS_1;
            ?QOS_2        -> ?QOS_2;
            qos2          -> ?QOS_2;
            exactly_once  -> ?QOS_2
        end)
    end).

-define(IS_QOS_NAME(I),
        (I =:= qos0; I =:= at_most_once;
         I =:= qos1; I =:= at_least_once;
         I =:= qos2; I =:= exactly_once)).

%%--------------------------------------------------------------------
%% Maximum ClientId Length.
%%--------------------------------------------------------------------

-define(MAX_CLIENTID_LEN, 1024).

%%--------------------------------------------------------------------
%% MQTT Client
%%--------------------------------------------------------------------

-record(mqtt_client,
        { client_id     :: binary() | undefined,
          client_pid    :: pid(),
          username      :: binary() | undefined,
          peername      :: {inet:ip_address(), inet:port_number()},
          clean_sess    :: boolean(),
          proto_ver     :: mqtt_version(),
          keepalive = 0 :: non_neg_integer(),
          will_topic    :: undefined | binary(),
          mountpoint    :: undefined | binary(),
          connected_at  :: erlang:timestamp(),
          attributes    :: map()
        }).

-type(mqtt_client() :: #mqtt_client{}).

%%--------------------------------------------------------------------
%% MQTT Control Packet Types
%%--------------------------------------------------------------------

-define(RESERVED,     0). %% Reserved
-define(CONNECT,      1). %% Client request to connect to Server
-define(CONNACK,      2). %% Server to Client: Connect acknowledgment
-define(PUBLISH,      3). %% Publish message
-define(PUBACK,       4). %% Publish acknowledgment
-define(PUBREC,       5). %% Publish received (assured delivery part 1)
-define(PUBREL,       6). %% Publish release (assured delivery part 2)
-define(PUBCOMP,      7). %% Publish complete (assured delivery part 3)
-define(SUBSCRIBE,    8). %% Client subscribe request
-define(SUBACK,       9). %% Server Subscribe acknowledgment
-define(UNSUBSCRIBE, 10). %% Unsubscribe request
-define(UNSUBACK,    11). %% Unsubscribe acknowledgment
-define(PINGREQ,     12). %% PING request
-define(PINGRESP,    13). %% PING response
-define(DISCONNECT,  14). %% Client or Server is disconnecting
-define(AUTH,        15). %% Authentication exchange

-define(TYPE_NAMES, [
        'CONNECT',
        'CONNACK',
        'PUBLISH',
        'PUBACK',
        'PUBREC',
        'PUBREL',
        'PUBCOMP',
        'SUBSCRIBE',
        'SUBACK',
        'UNSUBSCRIBE',
        'UNSUBACK',
        'PINGREQ',
        'PINGRESP',
        'DISCONNECT',
        'AUTH']).

-type(mqtt_packet_type() :: ?RESERVED..?AUTH).

%%--------------------------------------------------------------------
%% MQTT Reason Codes
%%--------------------------------------------------------------------

-define(RC_SUCCESS,                                16#00).
-define(RC_NORMAL_DISCONNECTION,                   16#00).
-define(RC_GRANTED_QOS_0,                          16#00).
-define(RC_GRANTED_QOS_1,                          16#01).
-define(RC_GRANTED_QOS_2,                          16#02).
-define(RC_DISCONNECT_WITH_WILL_MESSAGE,           16#04).
-define(RC_NO_MATCHING_SUBSCRIBERS,                16#10).
-define(RC_NO_SUBSCRIPTION_EXISTED,                16#11).
-define(RC_CONTINUE_AUTHENTICATION,                16#18).
-define(RC_RE_AUTHENTICATE,                        16#19).
-define(RC_UNSPECIFIED_ERROR,                      16#80).
-define(RC_MALFORMED_PACKET,                       16#81).
-define(RC_PROTOCOL_ERROR,                         16#82).
-define(RC_IMPLEMENTATION_SPECIFIC_ERROR,          16#83).
-define(RC_UNSUPPORTED_PROTOCOL_VERSION,           16#84).
-define(RC_CLIENT_IDENTIFIER_NOT_VALID,            16#85).
-define(RC_BAD_USER_NAME_OR_PASSWORD,              16#86).
-define(RC_NOT_AUTHORIZED,                         16#87).
-define(RC_SERVER_UNAVAILABLE,                     16#88).
-define(RC_SERVER_BUSY,                            16#89).
-define(RC_BANNED,                                 16#8A).
-define(RC_SERVER_SHUTTING_DOWN,                   16#8B).
-define(RC_BAD_AUTHENTICATION_METHOD,              16#8C).
-define(RC_KEEP_ALIVE_TIMEOUT,                     16#8D).
-define(RC_SESSION_TAKEN_OVER,                     16#8E).
-define(RC_TOPIC_FILTER_INVALID,                   16#8F).
-define(RC_TOPIC_NAME_INVALID,                     16#90).
-define(RC_PACKET_IDENTIFIER_IN_USE,               16#91).
-define(RC_PACKET_IDENTIFIER_NOT_FOUND,            16#92).
-define(RC_RECEIVE_MAXIMUM_EXCEEDED,               16#93).
-define(RC_TOPIC_ALIAS_INVALID,                    16#94).
-define(RC_PACKET_TOO_LARGE,                       16#95).
-define(RC_MESSAGE_RATE_TOO_HIGH,                  16#96).
-define(RC_QUOTA_EXCEEDED,                         16#97).
-define(RC_ADMINISTRATIVE_ACTION,                  16#98).
-define(RC_PAYLOAD_FORMAT_INVALID,                 16#99).
-define(RC_RETAIN_NOT_SUPPORTED,                   16#9A).
-define(RC_QOS_NOT_SUPPORTED,                      16#9B).
-define(RC_USE_ANOTHER_SERVER,                     16#9C).
-define(RC_SERVER_MOVED,                           16#9D).
-define(RC_SHARED_SUBSCRIPTIONS_NOT_SUPPORTED,     16#9E).
-define(RC_CONNECTION_RATE_EXCEEDED,               16#9F).
-define(RC_MAXIMUM_CONNECT_TIME,                   16#A0).
-define(RC_SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED, 16#A1).
-define(RC_WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED,   16#A2).

%%--------------------------------------------------------------------
%% Maximum MQTT Packet Length
%%--------------------------------------------------------------------

-define(MAX_PACKET_SIZE, 16#fffffff).

%%--------------------------------------------------------------------
%% MQTT Frame Mask
%%--------------------------------------------------------------------

-define(HIGHBIT, 2#10000000).
-define(LOWBITS, 2#01111111).

%%--------------------------------------------------------------------
%% MQTT Packet Fixed Header
%%--------------------------------------------------------------------

-record(mqtt_packet_header,
        { type   = ?RESERVED :: mqtt_packet_type(),
          dup    = false     :: boolean(),
          qos    = ?QOS_0    :: mqtt_qos(),
          retain = false     :: boolean()
        }).

%%--------------------------------------------------------------------
%% MQTT Packets
%%--------------------------------------------------------------------

-type(mqtt_topic() :: binary()).

-type(mqtt_client_id() :: binary()).

-type(mqtt_username()  :: binary() | undefined).

-type(mqtt_packet_id() :: 1..16#FFFF | undefined).

-type(mqtt_reason_code() :: 0..16#FF | undefined).

-type(mqtt_properties() :: #{atom() => term()} | undefined).

%% nl: no local, rap: retain as publish, rh: retain handling
-record(mqtt_subopts, {rh = 0, rap = 0, nl = 0, qos = ?QOS_0}).

-type(mqtt_subopts() :: #mqtt_subopts{}).

-record(mqtt_packet_connect,
        { proto_name   = <<"MQTT">>     :: binary(),
          proto_ver    = ?MQTT_PROTO_V4 :: mqtt_version(),
          is_bridge    = false          :: boolean(),
          clean_start  = true           :: boolean(),
          will_flag    = false          :: boolean(),
          will_qos     = ?QOS_0         :: mqtt_qos(),
          will_retain  = false          :: boolean(),
          keepalive    = 0              :: non_neg_integer(),
          properties   = undefined      :: mqtt_properties(),
          client_id    = <<>>           :: mqtt_client_id(),
          will_props   = undefined      :: undefined | map(),
          will_topic   = undefined      :: undefined | binary(),
          will_payload = undefined      :: undefined | binary(),
          username     = undefined      :: undefined | binary(),
          password     = undefined      :: undefined | binary()
        }).

-record(mqtt_packet_connack,
        { ack_flags   :: 0 | 1,
          reason_code :: mqtt_reason_code(),
          properties  :: mqtt_properties()
        }).

-record(mqtt_packet_publish,
        { topic_name :: mqtt_topic(),
          packet_id  :: mqtt_packet_id(),
          properties :: mqtt_properties()
        }).

-record(mqtt_packet_puback,
        { packet_id   :: mqtt_packet_id(),
          reason_code :: mqtt_reason_code(),
          properties  :: mqtt_properties()
        }).

-record(mqtt_packet_subscribe,
        { packet_id     :: mqtt_packet_id(),
          properties    :: mqtt_properties(),
          topic_filters :: [{mqtt_topic(), mqtt_subopts()}]
        }).

-record(mqtt_packet_suback,
        { packet_id    :: mqtt_packet_id(),
          properties   :: mqtt_properties(),
          reason_codes :: list(mqtt_reason_code())
        }).

-record(mqtt_packet_unsubscribe,
        { packet_id     :: mqtt_packet_id(),
          properties    :: mqtt_properties(),
          topic_filters :: [mqtt_topic()]
        }).

-record(mqtt_packet_unsuback,
        { packet_id    :: mqtt_packet_id(),
          properties   :: mqtt_properties(),
          reason_codes :: list(mqtt_reason_code())
        }).

-record(mqtt_packet_disconnect,
        { reason_code :: mqtt_reason_code(),
          properties  :: mqtt_properties()
        }).

-record(mqtt_packet_auth,
        { reason_code :: mqtt_reason_code(),
          properties  :: mqtt_properties()
        }).

%%--------------------------------------------------------------------
%% MQTT Control Packet
%%--------------------------------------------------------------------

-record(mqtt_packet,
        { header   :: #mqtt_packet_header{},
          variable :: #mqtt_packet_connect{}
                    | #mqtt_packet_connack{}
                    | #mqtt_packet_publish{}
                    | #mqtt_packet_puback{}
                    | #mqtt_packet_subscribe{}
                    | #mqtt_packet_suback{}
                    | #mqtt_packet_unsubscribe{}
                    | #mqtt_packet_unsuback{}
                    | #mqtt_packet_disconnect{}
                    | #mqtt_packet_auth{}
                    | mqtt_packet_id()
                    | undefined,
          payload  :: binary() | undefined
        }).

-type(mqtt_packet() :: #mqtt_packet{}).

%%--------------------------------------------------------------------
%% MQTT Packet Match
%%--------------------------------------------------------------------

-define(CONNECT_PACKET(Var),
    #mqtt_packet{header = #mqtt_packet_header{type = ?CONNECT}, variable = Var}).

-define(CONNACK_PACKET(ReasonCode),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?CONNACK},
                 variable = #mqtt_packet_connack{ack_flags   = 0,
                                                 reason_code = ReasonCode}}).

-define(CONNACK_PACKET(ReasonCode, SessPresent),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?CONNACK},
                 variable = #mqtt_packet_connack{ack_flags   = SessPresent,
                                                 reason_code = ReasonCode}}).

-define(CONNACK_PACKET(ReasonCode, SessPresent, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?CONNACK},
                 variable = #mqtt_packet_connack{ack_flags   = SessPresent,
                                                 reason_code = ReasonCode,
                                                 properties  = Properties}}).

-define(AUTH_PACKET(),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?AUTH},
                 variable = #mqtt_packet_auth{reason_code = 0}}).

-define(AUTH_PACKET(ReasonCode),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?AUTH},
                 variable = #mqtt_packet_auth{reason_code = ReasonCode}}).

-define(AUTH_PACKET(ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?AUTH},
                 variable = #mqtt_packet_auth{reason_code = ReasonCode,
                                              properties = Properties}}).

-define(PUBLISH_PACKET(Qos, PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBLISH,
                                                qos = Qos},
                 variable = #mqtt_packet_publish{packet_id = PacketId}}).

-define(PUBLISH_PACKET(QoS, Topic, PacketId, Payload),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBLISH,
                                                qos  = QoS},
                 variable = #mqtt_packet_publish{topic_name = Topic,
                                                 packet_id  = PacketId},
                 payload  = Payload}).

-define(PUBLISH_PACKET(QoS, Topic, PacketId, Properties, Payload),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBLISH,
                                                qos  = QoS},
                 variable = #mqtt_packet_publish{topic_name = Topic,
                                                 packet_id  = PacketId,
                                                 properties = Properties},
                 payload  = Payload}).

-define(PUBACK_PACKET(PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBACK},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = 0}}).

-define(PUBACK_PACKET(PacketId, ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBACK},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = ReasonCode,
                                                properties  = Properties}}).

-define(PUBREC_PACKET(PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBREC},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = 0}}).

-define(PUBREC_PACKET(PacketId, ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBREC},
                 variable = #mqtt_packet_puback{packet_id = PacketId,
                                                reason_code = ReasonCode,
                                                properties  = Properties}}).

-define(PUBREL_PACKET(PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBREL, qos = ?QOS_1},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = 0}}).

-define(PUBREL_PACKET(PacketId, ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBREL, qos = ?QOS_1},
                 variable = #mqtt_packet_puback{packet_id = PacketId,
                                                reason_code = ReasonCode,
                                                properties  = Properties}}).

-define(PUBCOMP_PACKET(PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBCOMP},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = 0}}).

-define(PUBCOMP_PACKET(PacketId, ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBCOMP},
                 variable = #mqtt_packet_puback{packet_id   = PacketId,
                                                reason_code = ReasonCode,
                                                properties  = Properties}}).

-define(SUBSCRIBE_PACKET(PacketId, TopicFilters),
    #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE, qos = ?QOS_1},
                 variable = #mqtt_packet_subscribe{packet_id     = PacketId,
                                                   topic_filters = TopicFilters}}).

-define(SUBSCRIBE_PACKET(PacketId, Properties, TopicFilters),
    #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE, qos = ?QOS_1},
                 variable = #mqtt_packet_subscribe{packet_id     = PacketId,
                                                   properties    = Properties,
                                                   topic_filters = TopicFilters}}).

-define(SUBACK_PACKET(PacketId, ReasonCodes),
    #mqtt_packet{header = #mqtt_packet_header{type = ?SUBACK},
                 variable = #mqtt_packet_suback{packet_id    = PacketId,
                                                reason_codes = ReasonCodes}}).

-define(SUBACK_PACKET(PacketId, Properties, ReasonCodes),
    #mqtt_packet{header = #mqtt_packet_header{type = ?SUBACK},
                 variable = #mqtt_packet_suback{packet_id    = PacketId,
                                                properties   = Properties,
                                                reason_codes = ReasonCodes}}).
-define(UNSUBSCRIBE_PACKET(PacketId, TopicFilters),
    #mqtt_packet{header = #mqtt_packet_header{type = ?UNSUBSCRIBE, qos = ?QOS_1},
                 variable = #mqtt_packet_unsubscribe{packet_id     = PacketId,
                                                     topic_filters = TopicFilters}}).

-define(UNSUBSCRIBE_PACKET(PacketId, Properties, TopicFilters),
    #mqtt_packet{header = #mqtt_packet_header{type = ?UNSUBSCRIBE, qos = ?QOS_1},
                 variable = #mqtt_packet_unsubscribe{packet_id     = PacketId,
                                                     properties    = Properties,
                                                     topic_filters = TopicFilters}}).

-define(UNSUBACK_PACKET(PacketId),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?UNSUBACK},
                 variable = #mqtt_packet_unsuback{packet_id = PacketId}}).

-define(UNSUBACK_PACKET(PacketId, Properties, ReasonCodes),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?UNSUBACK},
                 variable = #mqtt_packet_unsuback{packet_id    = PacketId,
                                                  properties   = Properties,
                                                  reason_codes = ReasonCodes}}).

-define(DISCONNECT_PACKET(),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?DISCONNECT},
                 variable = #mqtt_packet_disconnect{reason_code = 0}}).

-define(DISCONNECT_PACKET(ReasonCode),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?DISCONNECT},
                 variable = #mqtt_packet_disconnect{reason_code = ReasonCode}}).

-define(DISCONNECT_PACKET(ReasonCode, Properties),
    #mqtt_packet{header   = #mqtt_packet_header{type = ?DISCONNECT},
                 variable = #mqtt_packet_disconnect{reason_code = ReasonCode,
                                                    properties  = Properties}}).

-define(PACKET(Type),
    #mqtt_packet{header = #mqtt_packet_header{type = Type}}).

%%--------------------------------------------------------------------
%% MQTT Message
%%--------------------------------------------------------------------

-type(mqtt_msg_id() :: binary() | undefined).

-type(mqtt_msg_from() :: atom() | {binary(), undefined | binary()}).

-record(mqtt_message,
        { %% Global unique message ID
          id              :: mqtt_msg_id(),
          %% PacketId
          packet_id       :: mqtt_packet_id(),
          %% ClientId and Username
          from            :: mqtt_msg_from(),
          %% Topic that the message is published to
          topic           :: binary(),
          %% Message QoS
          qos     = ?QOS0 :: mqtt_qos(),
          %% Message Flags
          flags   = []    :: [retain | dup | sys],
          %% Retain flag
          retain  = false :: boolean(),
          %% Dup flag
          dup     = false :: boolean(),
          %% $SYS flag
          sys     = false :: boolean(),
          %% Properties
          properties = [] :: list(),
          %% Payload
          payload         :: binary(),
          %% Timestamp
          timestamp       :: erlang:timestamp()
        }).

-type(mqtt_message() :: #mqtt_message{}).

-define(WILL_MSG(Qos, Retain, Topic, Props, Payload),
        #mqtt_message{qos = Qos, retain = Retain, topic = Topic, properties = Props, payload = Payload}).

