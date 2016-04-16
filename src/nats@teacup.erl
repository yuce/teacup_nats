% Copyright 2016 Yuce Tekol <yucetekol@gmail.com>

% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at

%     http://www.apache.org/licenses/LICENSE-2.0

% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.

-module(nats@teacup).
-behaviour(teacup_server).

-export([teacup@signature/1,
         teacup@init/1,
         teacup@status/2,
         teacup@data/2,
         teacup@error/2,
         teacup@call/3,
         teacup@cast/2,
         teacup@info/2]).


-include("teacup_nats_common.hrl").

-define(MSG, ?MODULE).
-define(VERSION, <<"0.3.8">>).
-define(SEND_TIMEOUT, 10).
-define(DEFAULT_MAX_BATCH_SIZE, 100).

%% == Callbacks

teacup@signature(#{verbose := true}) ->
    {ok, ?VERBOSE_SIGNATURE};

teacup@signature(_) ->
    {ok, ?SIGNATURE}.

teacup@init(Opts) ->
    NewOpts = maps:merge(default_opts(), Opts),
    {ok, reset_state(NewOpts)}.

teacup@status(connect, State) ->
    nats_msg:init(),
    NewState = reset_state(State),
    notify_parent({status, connect}, State),
    {noreply, NewState};

teacup@status({disconnect, ForceDisconnect},
              #{reconnect := {Interval, MaxTrials},
                reconnect_try := Trial} = State) ->
    notify_parent({status, disconnect}, State),
    case ForceDisconnect of
        false when MaxTrials /= Trial ->
            reconnect_timer(Interval);
        _ ->
            ok
    end,
    {noreply, State#{ready => false,
                    batch_timer => undefined}};

teacup@status({disconnect, _}, State) ->
    notify_parent({status, disconnect}, State),
    {noreply, State#{ready => false,
                     batch_timer => undefined}};

teacup@status(Status, State) ->
    notify_parent({status, Status}, State),
    {noreply, State}.

teacup@data(Data, #{data_acc := DataAcc} = State) ->
    NewData = <<DataAcc/binary, Data/binary>>,
    {Messages, Remaining} = nats_msg:decode_all(NewData),
    case interp_messages(Messages, State) of
        {noreply, NewState} ->
            {noreply, NewState#{data_acc => Remaining}};
        Other ->
            Other
    end.

teacup@error(econnrefused = Reason,
             #{reconnect := {_, MaxTrials},
               reconnect_try := MaxTrials} = State) ->
    notify_parent({error, Reason}, State),
    {stop, {nats@teacup, Reason}, State};
    
teacup@error(econnrefused, #{reconnect := {Interval, _}} = State) ->
    reconnect_timer(Interval),
    {noreply, State};

teacup@error(Reason, State) ->
    notify_parent({error, Reason}, State),
    {stop, Reason, State}.

teacup@call({connect, Host, Port}, From, State) ->
    NewState = State#{from => From},
    do_connect(Host, Port),
    {noreply, NewState};

teacup@call({pub, Subject, Opts}, From, State) ->
    do_pub(Subject, Opts, State#{from := From});

teacup@call({sub, Subject, Opts, Pid}, From, State) ->
    do_sub(Subject, Opts, Pid, State#{from := From});

teacup@call({unsub, Subject, Opts, Pid}, From, State) ->
    do_unsub(Subject, Opts, Pid, State#{from := From}).

teacup@cast({connect, Host, Port}, State) ->
    do_connect(Host, Port),
    {noreply, State};

teacup@cast(ping, #{ready := true} = State) ->
    teacup_server:send(self(), nats_msg:ping()),
    {noreply, State};

teacup@cast({pub, Subject, Opts}, State) ->
    do_pub(Subject, Opts, State);

teacup@cast({sub, Subject, Opts, Pid}, State) ->
    do_sub(Subject, Opts, Pid, State);

teacup@cast({unsub, Subject, Opts, Pid}, State) ->
    do_unsub(Subject, Opts, Pid, State).

teacup@info(ready, #{ready := false,
                     from := undefined} = State) ->
    notify_parent(ready, State),
    BatchTimer = batch_timer(State),
    {noreply, State#{ready => true,
                     batch_timer => BatchTimer}};

teacup@info(ready, State) ->
    % Ignore other ready messages
    {noreply, State};

teacup@info(batch_timeout, #{ready := false} = State) ->
    {noreply, State#{batch_timer => undefined}};

teacup@info(batch_timeout, #{batch := Batch} = State) ->
    NewState = send_batch(Batch, State),
    {noreply, NewState};

teacup@info(reconnect_timeout, #{reconnect_try := ReconnectTry} = State) ->
    NewState = State#{reconnect_try => ReconnectTry + 1},
    do_connect(),
    {noreply, NewState}.

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
      version => ?VERSION,
      buffer_size => 0,
      max_batch_size => ?DEFAULT_MAX_BATCH_SIZE,
      reconnect => {undefined, 0}}.

reset_state(State) ->
    Default = #{data_acc => <<>>,
                server_info => #{},
                next_sid => 0,
                sid_to_key => #{},
                key_to_sid => #{},
                ready => false,
                batch => [],
                batch_timer => undefined,
                batch_size => 0,
                from => undefined,
                reconnect_try => 0},    
    maps:merge(Default, State#{ready => false}).

interp_messages([], State) ->
    {noreply, State};

interp_messages([H|T], #{callbacks@ := #{teacup@error := TError}} = State) ->
    try interp_message(H, State) of
        {ok, NewState} ->
            interp_messages(T, NewState);
        {error, Reason} ->
            case TError(Reason, State) of
                {noreply, NewState1} ->
                    interp_messages(T, NewState1);
                Other ->
                    Other
            end
    catch
        disconnect ->
            {stop, normal, State}
    end.

interp_message(ping, State) ->
    % Send pong messages immediately
    teacup_server:send(self(), nats_msg:pong()),
    {ok, State};

interp_message(pong, State) ->
    % TODO: reset ping timer
    {ok, State};

interp_message({info, BinInfo},
               #{from := From} = State) ->
    % Send connect messages immediately
    Info = jsx:decode(BinInfo, [return_maps]),
    case ssl_upgrade(Info, State#{server_info => Info}) of
        {ok, NewState} ->
            teacup_server:send(self(), client_info(NewState)),
            case From of
                undefined -> self() ! ready;
                _ -> ok
            end,
            {ok, NewState};
        {error, Reason} ->
            {error, Reason}
    end;            

interp_message({msg, {Subject, Sid, ReplyTo, Payload}},
               #{ref@ := Ref,
                 sid_to_key := SidToKey} = State) ->
    case maps:get(Sid, SidToKey, undefined) of
        undefined -> ok;
        {_, Pid} ->
            Resp = {msg, Subject, ReplyTo, Payload},
            Pid ! {Ref, Resp}
    end,
    {ok, State};

interp_message(ok, #{from := From} = State)
        when From /= undefined ->
    gen_server:reply(From, ok),
    {ok, State#{from => undefined,
                ready => true}};

interp_message({error, Reason}, #{from := From} = State)
        when From /= undefined ->
    gen_server:reply(From, {error, Reason}),
    {ok, State#{from => undefined}};

interp_message({error, Reason} = Error, State) ->
    notify_parent(Error, State),
    case error_disconnect(Reason) of
        true -> throw(disconnect);
        _ -> {ok, State}
    end.

error_disconnect(invalid_subject) -> false;
error_disconnect(_) -> true.

client_info(#{server_info := ServerInfo} = State) ->
    % Include user and name iff the server requires it
    FieldsList = [verbose, pedantic, ssl_required, auth_token, name, lang, version],
    NewFieldsList = case maps:get(<<"auth_required">>, ServerInfo, false) of
        true -> [user, pass | FieldsList];
        _ -> FieldsList
    end,
    Nats = maps:with(NewFieldsList, State),
    nats_msg:connect(jsx:encode(Nats)).

notify_parent(What, #{parent@ := Parent,
                      ref@ := Ref}) ->
    Parent ! {Ref, What}.

do_connect() ->
    teacup_server:connect(self()).

do_connect(Host, Port) ->
    teacup_server:connect(self(), Host, Port).

do_pub(Subject, Opts, State) ->
    ReplyTo = maps:get(reply_to, Opts, undefined),
    Payload = maps:get(payload, Opts, <<>>),
    BinMsg = nats_msg:pub(Subject, ReplyTo, Payload),
    queue_msg(BinMsg, State).

do_sub(Subject, Opts, Pid, #{next_sid := DefaultSid,
                             sid_to_key := SidToKey,
                             key_to_sid := KeyToSid} = State) ->
    K = {Subject, Pid},
    Sid = maps:get(K, KeyToSid, integer_to_binary(DefaultSid)),
    NewKeyToSid = maps:put(K, Sid, KeyToSid),
    NewSidToKey = maps:put(Sid, K, SidToKey),
    QueueGrp = maps:get(queue_group, Opts, undefined),
    BinMsg = nats_msg:sub(Subject, QueueGrp, Sid),
    queue_msg(BinMsg, State#{next_sid => DefaultSid + 1,
                             sid_to_key => NewSidToKey,
                             key_to_sid => NewKeyToSid}).

do_unsub(Subject, Opts, Pid, #{key_to_sid := KeyToSid} = State) ->
    % Should we crash if Sid for Pid not found?
    Sid = maps:get({Subject, Pid}, KeyToSid, undefined),
    case Sid of
        undefined ->
            {noreply, State};
        _ ->
            MaxMsgs = maps:get(max_messages, Opts, undefined),
            BinMsg = nats_msg:unsub(Sid, MaxMsgs),
            queue_msg(BinMsg, State)
    end.

send_batch([], State) ->
    State#{batch => [],
           batch_size => 0,
           batch_timer => undefined};

send_batch(Batch, State) ->
    teacup_server:send(self(), lists:reverse(Batch)),
    State#{batch => [],
           batch_size => 0,
           batch_timer => undefined}.

queue_msg(_, #{ready := false,
               buffer_size := Size,
               batch_size := Size} = State) ->
    Reason = buffer_overflow,
    notify_parent({error, Reason}, State),
    {stop, {nats@teacup, Reason}, State};

% queue_msg(BinMsg, #{ready := true,
%                     batch := Batch,
%                     batch_size := MaxBatchSize,
%                     max_batch_size := MaxBatchSize} = State) ->
%     NewState = send_batch(Batch, State),
%     {noreply, NewState#{batch => [BinMsg],
%                         batch_size => 1}};
    
queue_msg(BinMsg, #{batch := Batch,
                    batch_timer := BatchTimer,
                    batch_size := BatchSize,
                    ready := Ready} = State) ->
    NewBatch = [BinMsg | Batch],
    NewBatchTimer = case {Ready, BatchTimer} of
        {true, undefined} ->
            erlang:send_after(?SEND_TIMEOUT,
                              self(),
                              batch_timeout);
        _ ->
            BatchTimer
    end,
    {noreply, State#{batch => NewBatch,
                     batch_timer => NewBatchTimer,
                     batch_size => BatchSize + 1}}.

batch_timer(#{batch := []}) ->
    undefined;

batch_timer(#{batch_timer := BatchTimer}) when BatchTimer /= undefined ->
    undefined;
   
batch_timer(_) ->
    erlang:send_after(?SEND_TIMEOUT,
                      self(),
                      batch_timeout).

reconnect_timer(infinity) ->
    ok;

reconnect_timer(Interval) ->
    erlang:send_after(Interval, self(), reconnect_timeout).

ssl_upgrade(#{<<"tls_required">> := true}, #{socket@ := Socket,
                                             transport := Transport} = State) ->
    case ssl:connect(Socket, []) of
        {ok, NewSocket} ->
            {ok, State#{socket@ => NewSocket,
                        transport => Transport#{tls => true}}};
        {error, _Reason} = Error ->
            Error
    end;

ssl_upgrade(_, State) ->
    {ok, State}.