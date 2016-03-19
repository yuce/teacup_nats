% Copyright (c) 2016, Yuce Tekol <yucetekol@gmail.com>.
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
%
% * Redistributions of source code must retain the above copyright
%   notice, this list of conditions and the following disclaimer.
%
% * Redistributions in binary form must reproduce the above copyright
%   notice, this list of conditions and the following disclaimer in the
%   documentation and/or other materials provided with the distribution.
%
% * The names of its contributors may not be used to endorse or promote
%   products derived from this software without specific prior written
%   permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
% A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
% OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
% LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
% DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
% THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-module(nats@tc).
-behaviour(teacup_server).

-export([new/0,
         new/1,
         ping/1,
         pub/2,
         pub/3,
         sub/2,
         sub/3,
         unsub/2,
         unsub/3]).
-export([teacup@init/1,
         teacup@status/2,
         teacup@data/2,
         teacup@cast/2]).

-define(MSG, ?MODULE).
-define(VERSION, <<"0.1.0">>).

%% == API

new() ->
    teacup:new(?MODULE).
    
new(#{verbose := _,
      pedantic := _,
      ssl_required := _,
      auth_token := _,
      user := _,
      pass := _} = Opts) ->
    teacup:new(?MODULE, Opts).
    
ping(Ref) ->
    teacup:cast(Ref, ping).

pub(Ref, Subject) ->
    pub(Ref, Subject, #{}).

pub(Ref, Subject, Opts) ->
    teacup:cast(Ref, {pub, Subject, Opts}).                        

sub(Ref, Subject) ->
    sub(Ref, Subject, #{}).

sub(Ref, Subject, Opts) ->
    teacup:cast(Ref, {sub, Subject, Opts, self()}).    

unsub(Ref, Subject) ->
    unsub(Ref, Subject, #{}).

unsub(Ref, Subject, Opts) ->
    teacup:cast(Ref, {unsub, Subject, Opts, self()}).

%% == Callbacks
    
teacup@init(Opts) ->
    NewOpts = maps:merge(default_opts(), Opts),
    {ok, NewOpts}.
    
teacup@status(connect, State) ->
    NewState = State#{data_acc => <<>>,
                      info_received => false,
                      server_info => #{},
                      next_sid => 0,
                      sid_to_key => #{},
                      key_to_sid => #{}},
    {ok, NewState};
    
teacup@status(disconnect, State) ->
    {reconnect, State}.
    
teacup@data(Data, #{data_acc := DataAcc} = State) ->
    NewData = <<DataAcc/binary, Data/binary>>,
    {Messages, Remaining} = nats_msg:decode(NewData),
    State1 = interp_messages(Messages, State),
    {ok, State1#{data_acc => Remaining}}.

teacup@cast(ping, State) ->
    teacup_server:send(self(), nats_msg:ping()),
    {noreply, State};
    
teacup@cast({pub, Subject, Opts}, State) ->
    ReplyTo = maps:get(reply_to, Opts, undefined),
    Payload = maps:get(payload, Opts, <<>>),
    BinMsg = nats_msg:pub(Subject, ReplyTo, Payload),
    teacup_server:send(self(), BinMsg),
    {noreply, State};
    
teacup@cast({sub, Subject, Opts, Pid}, #{next_sid := DefaultSid,
                                         sid_to_key := SidToKey,
                                         key_to_sid := KeyToSid} = State) ->
    K = {Subject, Pid},
    Sid = maps:get(K, KeyToSid, integer_to_binary(DefaultSid)),
    NewKeyToSid = maps:put(K, Sid, KeyToSid),
    NewSidToKey = maps:put(Sid, K, SidToKey),
    QueueGrp = maps:get(queue_group, Opts, undefined),
    BinMsg = nats_msg:sub(Subject, QueueGrp, Sid),
    teacup_server:send(self(), BinMsg),
    NewState = State#{next_sid => DefaultSid + 1,
                      sid_to_key => NewSidToKey,
                      key_to_sid => NewKeyToSid},
    {noreply, NewState};
    
teacup@cast({unsub, Subject, Opts, Pid}, #{key_to_sid := KeyToSid} = State) ->
    % Should we crash if Sid for Pid not found?
    Sid = maps:get({Subject, Pid}, KeyToSid, undefined),
    case Sid of
        undefined ->
            ok;
        _ ->
            MaxMsgs = maps:get(max_messages, Opts, undefined),
            BinMsg = nats_msg:unsub(Sid, MaxMsgs),
            teacup_server:send(self(), BinMsg)
    end,
    {noreply, State}.

%% == Internal

default_opts() ->
    #{verbose => false,
      pedantic => false,
      ssl_required => false,
      auth_token => undefined,
      user => undefined,
      pass => undefined,
      name => <<"teacup_nats">>,
      lang => <<"erlang">>,
      version => ?VERSION}.
    
interp_messages(Messages, State) ->
    F = fun(M, {Rs, S}) ->
        case interp_message(M, S) of
            {[], NS} -> {Rs, NS};
            {NR, NS} -> {[NR|Rs], NS}
        end
    end,
    {Response, NewState} = lists:foldl(F, {[], State}, Messages),
    case Response of
        [] -> ok;
        _ -> teacup_server:send(self(), lists:reverse(Response))
    end,
    NewState.

interp_message(ping, State) ->
    % Send pong messages immediately
    teacup_server:send(self(), nats_msg:pong()),
    {[], State};

interp_message(pong, State) ->
    % TODO: reset ping timer
    {[], State};
    
interp_message({info, BinInfo}, State) ->
    Info = jsx:decode(BinInfo, [return_maps]),
    NewState = State#{server_info => Info,
                      info_received => true},
    {client_info(NewState), NewState};
    
interp_message({msg, {_Subject, Sid, _ReplyTo, _PayloadSize}, _Payload} = Msg,
               #{ref@ := Ref,
                 sid_to_key := SidToKey} = State) ->
    case maps:get(Sid, SidToKey, undefined) of
        undefined -> ok;
        {_, Pid} -> Pid ! {?MSG, teacup:ref(Ref), Msg}
    end,
    {[], State}.    
    
client_info(State) ->
    Nats = maps:with([verbose, pedantic, ssl_required, auth_token, user,
                      pass, name, lang, version], State),
    nats_msg:connect(jsx:encode(Nats)).