#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin _build/default/lib/jsx/ebin

-mode(compile).

main([Address, StrMsgCount]) ->
    <<"nats://", HostPort/binary>> = list_to_binary(Address),
    [Host, BinPort] = binary:split(HostPort, <<":">>),
    Port = binary_to_integer(BinPort),
    MsgCount = list_to_integer(StrMsgCount),
    Subject =  <<"0123456789012345">>,
    Payload = <<"0123456789012345012345678901234501234567890123450123456789012345">>,
    application:start(teacup),
    {ok, Pub} = tcnats:connect(Host, Port),
    receive {Pub, ready} -> ok end,
    Time = bench(Pub, MsgCount, Subject, Payload),
    MsgsPerSec = round(MsgCount / (Time / 1000000)),
    io:format("~p ~p ~p~n", [MsgCount, Time, MsgsPerSec]),
    application:stop(teacup);

main(_) ->
    io:format("Usage: ./sub_count.escript host message_count~n").

bench(Pub, MsgCount, Subject, Payload) ->
    F1 = fun(_) ->
        tcnats:pub(Pub, Subject, #{payload => Payload})
    end,
    F2 = fun() ->
        lists:foreach(F1, lists:seq(1, MsgCount)),
        timer:sleep(10)    
    end,
    {Time, ok} = timer:tc(F2),
    Time.
