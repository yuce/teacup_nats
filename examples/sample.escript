#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

% Note: you need to compile the project with `rebar3 compile` first.


main([]) ->
    application:ensure_all_started(teacup),
    main(),
    application:ensure_all_started(teacup).

main() ->
    % Connect to the NATS server
    {ok, Conn} = nats:connect(<<"demo.nats.io">>, 4222, #{buffer_size => 10}),
    % We set the buffer_size, so messages will be collected on the client side
    %   until the connection is OK to use 
    % Publish some message
    nats:pub(Conn, <<"teacup.control">>, #{payload => <<"start">>}),
    % subscribe to some subject
    nats:sub(Conn, <<"foo.*">>),
    loop(Conn).

loop(Conn) ->
    receive
        {Conn, {msg, Subject, _ReplyTo, Payload}} ->
            % Do something with the received message
            io:format("~p: ~p~n", [Subject, Payload]),
            % Wait for/retrieve the next message
            loop(Conn)
    end.
