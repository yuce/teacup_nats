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
    {ok, Pub} = gen_tcp:connect(binary_to_list(Host), Port, [binary, {packet, 0}]),
    timer:sleep(100),
    ok = gen_tcp:send(Pub, <<"CONNECT {\"verbose\":false}\r\n">>),
    timer:sleep(100),
    Time = bench(Pub, MsgCount, Subject, Payload),
    MsgsPerSec = round(MsgCount / (Time / 1000000)),
    io:format("~p ~p ~p~n", [MsgCount, Time, MsgsPerSec]),
    application:stop(teacup);

main(_) ->
    io:format("Usage: ./sub_count.escript host message_count~n").

bench(Pub, MsgCount, Subject, Payload) ->
    BinMsg = nats_msg:pub(Subject, undefined, Payload),
    F1 = fun(_) ->
        ok = gen_tcp:send(Pub, BinMsg)
    end,
    F2 = fun() ->
        lists:foreach(F1, lists:seq(1, MsgCount))
    end,
    {Time, ok} = timer:tc(F2),
    Time.
