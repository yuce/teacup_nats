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
     connect_fail_reconnect_infinity].

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

    