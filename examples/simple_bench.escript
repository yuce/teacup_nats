#! /usr/bin/env escript

%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

-mode(compile).

main([HostPort, StrPublishCount, StrSubject, StrPayload]) ->
    [StrHost, StrPort] = string:tokens(HostPort, ":"),
    Host = list_to_binary(StrHost),
    Port = list_to_integer(StrPort),
    PublishCount = list_to_integer(StrPublishCount),
    Subject =  list_to_binary(StrSubject),
    Payload = list_to_binary(StrPayload),
    io:format("Benching on server ~s:~p with ~p messages.~n",
              [Host, Port, PublishCount]),
    application:start(teacup),
    prepare_bench(Host, Port, PublishCount, Subject, Payload),
    application:stop(teacup);
    
main(_) ->
    io:format("Usage: ./simple_bench.escript host:port message_count subject payload~n").
    
prepare_bench(Host, Port, PublishCount, Subject, Payload) ->
    {Pub, Sub} = create_conns(Host, Port),
    F = fun() ->
        bench(Pub, Sub, PublishCount, Subject, Payload)
    end,
    {Time, ok} = timer:tc(F),
    io:format("Took: ~p microsecs to pub/sub ~p messages~n", [Time, PublishCount]),
    MsgsPerSec = round(PublishCount / (Time / 1000000)),
    io:format("~p messages per second~n", [MsgsPerSec]).
    
create_conns(Host, Port) ->
    {ok, Sub} = nats:connect(Host, Port, #{verbose => true}),
    {ok, Pub} = nats:connect(Host, Port),
    loop_conn_ready(Pub),
    {Pub, Sub}.

bench(Pub, Sub, PublishCount, Subject, Payload) ->
    Me = self(),
    F = fun() ->
        ok = nats:sub(Sub, Subject),
        Me ! start,
        sub_loop(Sub, PublishCount),
        Me ! done
    end,
    spawn(F),
    receive
        start -> ok
    end,
    io:format("Publishing...~n"),
    spawn(fun() -> publish(Pub, Subject, Payload, PublishCount) end),
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
    nats:pub(Pub, Subject, #{payload => Payload}),
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
