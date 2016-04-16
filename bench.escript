#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

-mode(compile).

main([Address, StrMsgCount]) ->
    <<"nats://", HostPort/binary>> = list_to_binary(Address),
    [Host, BinPort] = binary:split(HostPort, <<":">>),
    Port = binary_to_integer(BinPort),
    MsgCount = list_to_integer(StrMsgCount),
    Subject =  <<"0123456789012345">>,
    Payload = <<"0123456789012345012345678901234501234567890123450123456789012345">>,
    application:start(teacup),
    prepare_bench(Host, Port, MsgCount, Subject, Payload),
    application:stop(teacup);

 main(_) ->
     io:format("Usage: escript bench.escript nats://HOST:PORT message_count~n").
   
prepare_bench(Host, Port, MsgCount, Subject, Payload) ->
    {Pub, Sub} = create_conns(Host, Port),
    F = fun() ->
        bench(Pub, Sub, MsgCount, Subject, Payload)
    end,
    {Time, ok} = timer:tc(F),
     MsgsPerSec = round(MsgCount / (Time / 1000000)),
     io:format("~p ~p ~p~n", [MsgCount, Time, MsgsPerSec]).
    
create_conns(Host, Port) ->
    {ok, Sub} = tcnats:connect(Host, Port, #{verbose => true}), 
    {ok, Pub} = tcnats:connect(Host, Port),
    loop_conn_ready(Pub),
    {Pub, Sub}.

bench(Pub, Sub, MsgCount, Subject, Payload) ->
    Me = self(),
    F = fun() ->
        tcnats:sub(Sub, Subject),
        Me ! start,
        sub_loop(Sub, MsgCount),
        Me ! done
    end,
    spawn(F),
    receive start -> ok end,
    spawn(fun() -> publish(Pub, Subject, Payload, MsgCount) end),
    receive 
        done -> ok
    end.

loop_conn_ready(Conn) ->
    receive
        {Conn, ready} -> ok
    after 1000 ->
        throw(conn_not_ready)     
    end.

publish(_, _, _, 0) ->
    ok;
    
publish(Pub, Subject, Payload, Left) ->
    tcnats:pub(Pub, Subject, #{payload => Payload}),
    publish(Pub, Subject, Payload, Left - 1).

sub_loop(_Sub, 0) ->
    ok;
    
sub_loop(Sub, Left) ->
    receive
        {Sub, {msg, _Subject, _ReplyTo, _Payload}} ->
            sub_loop(Sub, Left - 1);
        _Other ->
            sub_loop(Sub, Left)
    end.
