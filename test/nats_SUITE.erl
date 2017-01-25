-module(nats_SUITE).
-include_lib("common_test/include/ct.hrl").
-compile(export_all).

% NOTE: a gnatsd instance must be running at 127.0.0.1:4222

all() ->
    [connect_ok,
     connect_fail_no_host,
     connect_fail_no_port,
     connect_verbose_ok,
     connect_verbose_fail,
     connect_fail_reconnect_infinity,
     disconnect_ok,
     pub_ok,
     pub_verbose_ok,
     pub_with_buffer_size,
     sub_ok,
     sub_verbose_ok,
     unsub_verbose_ok].

init_per_testcase(_TestCase, Config) ->
    application:start(teacup),
    Config.

end_per_testcase(_TestCase, Config) ->
    application:stop(teacup),
    Config.

connect_ok(_) ->
    % When connecting with verbose := false
    % always {ok, Connection} is returned.
    % If the connection succeeds, a {Connection, ready} message
    % is sent to the owner
    
    {ok, C} = nats:connect(<<"127.0.0.1">>, 4222),
    receive
        {C, ready} -> ok
    after 1000 ->
        throw(ready_msg_not_sent)
    end.        

connect_fail_no_host(_) ->
    % When connecting with verbose := false
    % always {ok, Connection} is returned.
    % If the connection fails (host not found),
    % a {Connection, {error, nxdomain}} message is sent to the owner
    
    {ok, C} = nats:connect(<<"doesnt-exist.google.com">>, 4222),
    receive
        {C, {error, nxdomain}} -> ok
    after 1000 ->
            throw(error_on_fail_not_sent)
    end.

connect_fail_no_port(_) ->
    % When connecting with verbose := false
    % always {ok, Connection} is returned.
    % If the connection fails (port is not open),
    % a {Connection, {error, econnrefused}} message is sent to the owner
    
    NonExistingPort = 4444,
    {ok, C} = nats:connect(<<"127.0.0.1">>, NonExistingPort),
    receive
        {C, {error, econnrefused}} -> ok
    after 1000 ->
            throw(error_on_fail_not_sent)
    end.

connect_verbose_ok(_) ->
    % When connecting with verbose := true
    % If the connection succeeds, {ok, Connection}
    % is returned

    {ok, _C} = nats:connect(<<"127.0.0.1">>, 4222,
                              #{verbose => true}).

connect_verbose_fail(_) ->
    % When connecting with verbose := false
    % if the connection fails (host not found),
    % the connection dies with {nats@teacup, econnrefused}, _}

    NonExistingPort = 4444,
    try nats:connect(<<"127.0.0.1">>, NonExistingPort,
                       #{verbose => true}) of
        _ ->
            throw(econnrefused_not_sent)
    catch
        _:{{nats@teacup, econnrefused}, _} -> ok
    end.

connect_fail_reconnect_infinity(_) ->
    % When connecting with verbose := false
    % and reconnect := {infinity, 1},
    % if the connection fails (host not found),
    % no errors are returned and no messages sent
    % to the owner.
    % You can use `nats:is_ready/1` to check whether
    % the connection is OK to use
    
    NonExistingPort = 4444,
    {ok, C} = nats:connect(<<"127.0.0.1">>, NonExistingPort,
                              #{reconnect => {infinity, 1}}),
    receive
        _ -> throw(didnt_expect_a_msg)
    after 1000 ->
        ok
    end,
    false = nats:is_ready(C).

disconnect_ok(_) ->
    Host = <<"127.0.0.1">>,
    Port = 4222,
    {ok, C} = nats:connect(Host, Port, #{verbose => true}),
    ok = nats:disconnect(C),
    {error, not_found} = nats:is_ready(C).


    pub_ok(_) ->
        {ok, C} = nats:connect(<<"127.0.0.1">>, 4222),
        receive {C, ready} -> ok end,
        nats:pub(C, <<"foo.bar">>, #{payload => <<"My payload">>}),
        timer:sleep(100).

    pub_verbose_ok(_) ->
        {ok, C} = nats:connect(<<"127.0.0.1">>, 4222,
                               #{verbose => true}),
        ok = nats:pub(C, <<"foo.bar">>, #{payload => <<"My payload">>}).
    
    pub_with_buffer_size(_) ->
        {ok, C} = nats:connect(<<"127.0.0.1">>, 4222, #{buffer_size => 1}),
        nats:pub(C, <<"foo.bar">>, #{payload => <<"My payload">>}),
        timer:sleep(100).
    
    sub_ok(_) ->
        Host = <<"127.0.0.1">>,
        Port = 4222,
        {ok, C} = nats:connect(Host, Port),
        receive {C, ready} -> ok end,
        nats:sub(C, <<"foo.*">>),
        timer:sleep(100),
        send_tcp_msg(Host, Port, <<"PUB foo.bar 0\r\n\r\n">>),
        receive
            {C, {msg, <<"foo.bar">>, _, <<>>}} -> ok
        after 1000 ->
            throw(did_not_receive_a_msg)
        end.

    sub_verbose_ok(_) ->
        Host = <<"127.0.0.1">>,
        Port = 4222,
        {ok, C} = nats:connect(Host, Port, #{verbose => true}),
        nats:sub(C, <<"foo.*">>),
        send_tcp_msg(Host, Port, <<"PUB foo.bar 0\r\n\r\n">>),
        receive
            {C, {msg, <<"foo.bar">>, _, <<>>}} -> ok
        after 1000 ->
            throw(did_not_receive_a_msg)
        end.
    
    unsub_verbose_ok(_) ->
        {ok, C} = nats:connect(<<"127.0.0.1">>, 4222,
                               #{verbose => true}),
        nats:sub(C, <<"foo.*">>),
        nats:unsub(C, <<"foo.*">>),
        nats:pub(C, <<"foo.bar">>),
        receive
            {C, {msg, _, _, _}} ->
                throw(didnt_expect_a_msg)
        after 1000 ->
            ok
        end.
        
send_tcp_msg(BinHost, Port, BinMsg) ->
    Host = binary_to_list(BinHost),
    {ok, Socket} = gen_tcp:connect(Host, Port, [binary, {packet, 0}]),
    ok = gen_tcp:send(Socket, BinMsg),
    ok = gen_tcp:close(Socket).
