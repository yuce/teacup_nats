#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

main([]) ->
    io:format("Usage: ./sub.escript subject1 [subject2, ...]~n");

main(Subjects) ->
    application:start(teacup),
    {ok, Conn} = teacup_nats:new(),
    teacup:connect(Conn, <<"127.0.0.1">>, 4222),
    loop_ready(Conn, Subjects),
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
    
loop_ready(Conn, Subjects) ->
    receive
        {nats@tc, Conn, ready} ->
            NewSubjects = [<<"teacup.*">> | Subjects],
            subscribe(Conn, NewSubjects),
            loop(Conn);
        Other ->
            io:format("Received unexpected msg: ~p~n", [Other]),
            loop_ready(Conn, Subjects)
    after 1000 ->
        throw(cannot_connect)
    end.

subscribe(Conn, Subjects) ->
    lists:foreach(fun(S) -> teacup_nats:sub(Conn, S) end, Subjects).