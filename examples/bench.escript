#! /usr/bin/env escript
%%! -pa _build/default/lib/teacup/ebin -pa _build/default/lib/teacup_nats/ebin -pa _build/default/lib/simpre/ebin pa _build/default/lib/nats_msg/ebin -pa _build/default/lib/jsx/ebin

%%% Example, run 20 publishers, 10 subscribers, 10000 messages with subject: hello and payload: world per publisher
%%% escript examples/bench.escript 127.0.0.1:4222 10 5 10000 hello world

main([HostPort, Pubs, Subs, StrPublishCount, Subject, Payload]) ->
    [Host, StrPort] = string:tokens(HostPort, ":"),
    BinHost = list_to_binary(Host),
    Port = list_to_integer(StrPort),
    NPubs = list_to_integer(Pubs),
    NSubs = list_to_integer(Subs),
    PublishCount = list_to_integer(StrPublishCount),
    BinSubject =  list_to_binary(Subject),
    BinPayload = list_to_binary(Payload),
    io:format("Benching on server ~s:~p with ~p publishers (~p messages each) and ~p subscribers~n",
        [Host, Port, NPubs, PublishCount, NSubs]),
    application:start(teacup),
    start_bench(BinHost, Port, NPubs, NSubs, PublishCount, BinSubject, BinPayload),
    application:stop(teacup);

main([]) ->
    io:format("Usage: ./bench.escript host:port num_publishers num_subscribers messages_per_publisher subject payload~n").

start_bench(Host, Port, NPubs, NSubs, PublishCount, Subject, Payload) ->
    io:format("Spawning subscribers...~n"),
    _Subs = subscribers(self(), Host, Port, NSubs, Subject, NPubs * PublishCount),
    wait_for_subscribers(NSubs, 0),
    io:format("Spawning publishers...~n"),
    Pubs = publishers(self(), Host, Port, NPubs, PublishCount, Subject, Payload),
    wait_for_publishers(NPubs, 0),
    Tic = erlang:timestamp(),
    lists:foreach(fun(Pub) -> Pub ! start end, Pubs),
    MsgCount = case NSubs > 0 of
        true -> NPubs * PublishCount * NSubs;
        _ -> NPubs * PublishCount
    end,
    loop(NSubs, Tic, 0, MsgCount).

subscribers(Parent, Host, Port, NSubs, Subject, PublishCount) ->
    Connect = fun() ->
        {ok, Conn} = teacup_nats:connect(Host, Port),
        subscriber_ready_loop(Parent, Conn, Subject, PublishCount)
    end,
    lists:map(fun(_) -> spawn(Connect) end, lists:seq(1, NSubs)).

publishers(Parent, Host, Port, NPubs, PublishCount, Subject, Payload) ->
    Connect = fun() ->
        {ok, Conn} = teacup_nats:connect(Host, Port),
        publisher_ready_loop(Parent, Conn, PublishCount, Subject, Payload)
    end,
    lists:map(fun(_) -> spawn(Connect) end, lists:seq(1, NPubs)).

loop(NSubs, Tic, CompletedSubs, MsgCount) ->
    io:format("Subscriber ~p / ~p~n", [CompletedSubs, NSubs]),
    case NSubs == CompletedSubs of
        true ->
            Tac = erlang:timestamp(),
            Time = timer:now_diff(Tac, Tic),
            io:format("Took: ~p microsecs to pub/sub ~p messages~n", [Time, MsgCount]),
            MsgsPerSec = MsgCount * 1000000 / Time,
            io:format("~p messages per second~n", [MsgsPerSec]);
        _ ->
            receive
                {done, _MC} ->
                    loop(NSubs, Tic, CompletedSubs + 1, MsgCount);
                _Other ->
                    ok
            end
    end.

subscriber_ready_loop(Parent, Conn, Subject, PublishCount) ->
    receive
        {Conn, ready} ->
            teacup_nats:sub(Conn, Subject),
            Parent ! {Conn, subscriber_ready},
            subscriber_loop(Parent, Conn, Subject, PublishCount, 0);
        _Other ->
            subscriber_ready_loop(Parent, Conn, Subject, PublishCount)
    end.

subscriber_loop(Parent, Conn, Subject, PublishCount, MsgCount) ->
    case PublishCount == MsgCount of
        true ->
            Parent ! {done, MsgCount};
        _ ->
        receive
            {Conn, {msg, Subject, _, _Payload}} ->
                subscriber_loop(Parent, Conn, Subject, PublishCount, MsgCount + 1);
            Other ->
                io:format("Subscriber unexpected: ~p~n", [Other])
        end
    end.

publisher_ready_loop(Parent, Conn, PublishCount, Subject, Payload) ->
    receive
        {Conn, ready} ->
            Parent ! {Conn, publisher_ready},
            publisher_wait_loop(Conn, PublishCount, Subject, Payload);
        _Other ->
            publisher_ready_loop(Parent, Conn, PublishCount, Subject, Payload)
    end.

publisher_wait_loop(Conn, PublishCount, Subject, Payload) ->
    F = fun(_I) ->
        teacup_nats:pub(Conn, Subject, #{payload => Payload})
    end,
    receive
        start ->
            lists:foreach(fun(I) -> F(I) end, lists:seq(1, PublishCount));
        _Other ->
            publisher_wait_loop(Conn, PublishCount, Subject, Payload)
    end.

wait_for_subscribers(NSubs, ReadySubs) ->
    case NSubs == ReadySubs of
        true ->
            ok;
        _ ->
            receive
                {_, subscriber_ready} ->
                    wait_for_subscribers(NSubs, ReadySubs + 1);
                _Other ->
                    wait_for_subscribers(NSubs, ReadySubs)
            end
    end.

wait_for_publishers(NPubs, ReadyPubs) ->
    case NPubs == ReadyPubs of
        true ->
            ok;
        _ ->
            receive
                {_, publisher_ready} ->
                    wait_for_publishers(NPubs, ReadyPubs + 1);
                _Other ->
                    wait_for_publishers(NPubs, ReadyPubs)
            end
    end.
