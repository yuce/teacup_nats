#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

main([]) ->
    io:format("Usage: ./pub.escript subject [payload]~n");

main([Subject]) ->
    main([Subject, <<>>]);

main([Subject, Payload]) ->
    application:start(teacup),
    {ok, Conn} = teacup_nats:connect_sync(<<"demo.nats.io">>, 4222),
    BinPayload = list_to_binary(Payload),
    teacup_nats:pub(Conn, Subject, #{payload => BinPayload}),
    application:stop(teacup).
