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

-module(emqx_message).

-include("emqx.hrl").
-include("emqx_mqtt.hrl").

-export([new/2, new/3, new/4, new/5]).
-export([get_flag/2, get_flag/3, set_flag/2, set_flag/3, unset_flag/2]).
-export([get_header/2, get_header/3, set_header/3]).
-export([get_user_property/2, get_user_property/3, set_user_property/3]).

-spec(new(topic(), payload()) -> message()).
new(Topic, Payload) ->
    new(undefined, Topic, Payload).

-spec(new(atom() | client(), topic(), payload()) -> message()).
new(From, Topic, Payload) when is_atom(From); is_record(From, client) ->
    new(From, #{qos => ?QOS0}, Topic, Payload).

-spec(new(atom() | client(), message_flags(), topic(), payload()) -> message()).
new(From, Flags, Topic, Payload) when is_atom(From); is_record(From, client) ->
    new(From, Flags, #{}, Topic, Payload).

-spec(new(atom() | client(), message_flags(), message_headers(), topic(), payload()) -> message()).
new(From, Flags, Headers, Topic, Payload) when is_atom(From); is_record(From, client) ->
    #message{id         = msgid(),
             from       = From,
             sender     = self(),
             flags      = Flags,
             headers    = Headers,
             topic      = Topic,
             properties = #{},
             payload    = Payload,
             timestamp  = os:timestamp()}.

msgid() -> emqx_guid:gen().

%% @doc Get flag
get_flag(Flag, Msg) ->
    get_flag(Flag, Msg, false).
get_flag(Flag, #message{flags = Flags}, Default) ->
    maps:get(Flag, Flags, Default).

%% @doc Set flag
-spec(set_flag(message_flag(), message()) -> message()).
set_flag(Flag, Msg = #message{flags = Flags}) when is_atom(Flag) ->
    Msg#message{flags = maps:put(Flag, true, Flags)}.

-spec(set_flag(message_flag(), boolean() | integer(), message()) -> message()).
set_flag(Flag, Val, Msg = #message{flags = Flags}) when is_atom(Flag) ->
    Msg#message{flags = maps:put(Flag, Val, Flags)}.

%% @doc Unset flag
-spec(unset_flag(message_flag(), message()) -> message()).
unset_flag(Flag, Msg = #message{flags = Flags}) ->
    Msg#message{flags = maps:remove(Flag, Flags)}.

%% @doc Get header
get_header(Hdr, Msg) ->
    get_header(Hdr, Msg, undefined).
get_header(Hdr, #message{headers = Headers}, Default) ->
    maps:get(Hdr, Headers, Default).

%% @doc Set header
set_header(Hdr, Val, Msg = #message{headers = Headers}) ->
    Msg#message{headers = maps:put(Hdr, Val, Headers)}.

%% @doc Get user property
get_user_property(Key, Msg) ->
    get_user_property(Key, Msg, undefined).
get_user_property(Key, #message{properties = Props}, Default) ->
    maps:get(Key, Props, Default).

set_user_property(Key, Val, Msg = #message{properties = Props}) ->
    Msg#message{properties = maps:put(Key, Val, Props)}.

