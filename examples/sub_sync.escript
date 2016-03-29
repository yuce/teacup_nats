#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

main([]) ->
    io:format("Usage: ./sub_sync.escript subject1 [subject2, ...]~n");

main(Subjects) ->
    application:start(teacup),
    {ok, Conn} = tcnats@sync:connect(<<"demo.nats.io">>, 4222),
    NewSubjects = [<<"teacup.*">> | Subjects],
    subscribe(Conn, NewSubjects),
    io:format("Subscribed to given subjects.~nSend an `exit` message to subject `teacup.control` to quit.~n"),
    loop(Conn),
    application:stop(teacup).

loop(Conn) ->
    receive
        {Conn, {msg, <<"teacup.control">>, _, <<"exit">>}} ->
            io:format("Received exit msg.~n");
        {Conn, Msg} ->
            io:format("Received NATS msg: ~p~n", [Msg]),
            loop(Conn);
        Other ->
            io:format("Received other msg: ~p~n", [Other])
    end.
    
subscribe(Conn, Subjects) ->
    lists:foreach(fun(S) -> tcnats@sync:sub(Conn, S) end, Subjects).