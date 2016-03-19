#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

main([]) ->
    io:format("Usage: ./sub2.escript subject1 [subject2, ...]~n");

main(Subjects) ->
    application:start(teacup),
    {ok, Conn} = teacup_nats:connect_sync(<<"demo.nats.io">>, 4222),
    NewSubjects = [<<"teacup.*">> | Subjects],
    subscribe(Conn, NewSubjects),
    loop(Conn),
    application:stop(teacup).

loop(Conn) ->
    receive
        {nats@tc, Conn, {msg, <<"teacup.control">>, _, <<"exit">>}} ->
            io:format("received exit msg.");
        {nats@tc, Conn, Msg} ->
            io:format("Received NATS msg: ~p~n", [Msg]),
            loop(Conn);
        Other ->
            io:format("Received other msg: ~p~n", [Other])
    end.
    
subscribe(Conn, Subjects) ->
    lists:foreach(fun(S) -> teacup_nats:sub(Conn, S) end, Subjects).