#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

main([]) ->
    io:format("Usage: ./pub_sync.escript subject [payload]~n");

main([Subject]) ->
    main([Subject, <<>>]);

main([Subject, Payload]) ->
    application:start(teacup),
    {ok, Conn} = tcnats:connect(<<"demo.nats.io">>, 4222, #{verbose => true}),
    BinPayload = list_to_binary(Payload),
    tcnats:pub(Conn, Subject, #{payload => BinPayload}),
    application:stop(teacup).
