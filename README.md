# Teacup NATS

A [Teacup](https://github.com/yuce/teacup.git) based Erlang client library for [NATS](http://nats.io/)
high performance messaging platform.

## NEWS

* **2016-04-17**: Version 0.3.8:

    * Renamed `tcnats` module to `nats`.
    * Added `nats:is_ready/1` function to check whether a NATS connection
    is ready (to pub, sub, unsub).
    * Added initial tests.

* **2016-04-16**: Version 0.3.7:

    * Re-licenced the project under [Apache 2.0 License](http://www.apache.org/licenses/LICENSE-2.0).    
    * This version fixes performance problems introduced in version 0.3.3.

* **2016-04-07**: Version 0.3.4:

    * Rudimentary TLS/SSL support. Currently, this is auto-activated when the server
    sends `tls_required => true` in an `INFO` message. 

* **2016-04-03**: Version 0.3.3:

    * Using [teacup 0.3.3](https://github.com/yuce/teacup/tree/0.3.3),
    which boosts the performance by 50%.
    * Implemented connect retry / reconnect strategy.
    * Implemented message buffering.
    * Sub and Unsub messages are queued.

* **2016-03-27**: You can check how the performance of **teacup_nats** compares to other NATS clients
[here](https://github.com/yuce/nats-client-benchmarks).

* **2016-03-19**: Initial release.

## Getting Started

**teacup_nats** requires Erlang/OTP 18.0+. It uses [rebar3](http://www.rebar3.org/)
as the build tool and is available on [hex.pm](https://hex.pm/). Just include the following
in your `rebar.config`:

```erlang
{deps, [teacup_nats]}.
```

If you are upgrading from an earlier version, you need to:

```
$ rebar3 update && rebar3 upgrade
```

**teacup_nats** depends on the `teacup` app to be started. Include it in your `.app.src` file:

```erlang
...
  {applications,
   [kernel,
    stdlib,
    teacup
   ]},
...
```

Or, start it manually:

```erlang
ok = application:start(teacup).
```

**rebar3** has a nice way of starting apps in the shell, you can try:

```
$ rebar3 shell --apps teacup
```

## Running the Tests

```
$ rebar3 ct
```

## TODO

* Clustering

## API

### Aysnchronous Connection

When using asycnhronous connections, you need to wait for a `{Conn, ready}`
message before publishing messages, subcribing to/unsubscribing from subjects.

* Connection functions:
    * `nats:connect()`: Connect to the NATS server at address `127.0.0.1`, port `4222`,
    * `nats:connect(Host :: binary(), Port :: integer())`: Connect to the NATS server
    at `Host` and port `PORT`,
    * `nats:connect(Host :: binary(), Port :: integer(), Opts :: map())`: Similar to
    above, but also takes an `Opts` map. Currently usable keys:
        * `verbose => true | false`: If `verbose == true`, NATS server
        sends an acknowledgement message on `pub`, `sub`, `unsub` operations and
        `connect` operation becomes synchronous.
        * `user => User :: binary()`,
        * `pass => Password :: binary()`,
        * `buffer_size => MessageBufferSize :: non_neg_integer()`: The number of publish messages
        to buffer before quitting. The default is 0. Setting `MesssageBufferSize` to
        `infinity` enables unlimited buffering.
        * `reconnect => {Interval :: non_neg_integer(), MaxRetry :: non_neg_integer()}`: Specifies
        reconnect strategy. `Interval` is the time in milliseconds between retrials, and `MaxRetry` is
        the number of retrials before quitting. You can set `MaxRetry` to `infinity` to try reconnecting
        forever. The default is `{undefined, 0}`, "don't try to reconnect".
* Publish functions:
    * `nats:pub(Conn :: teacup_ref(), Subject :: binary())`: Publish message with only
    the subject,
    * `nats:pub(Conn :: teacup_ref(), Subject :: binary()), Opts :: map()`: Publish message
    the subject with `Options`. Valid options:
        * `payload => Payload :: binary()`,
        * `reply_to => Subject :: binary()`
* Subscribe functions:
    * `nats:sub(Conn :: teacup_ref(), Subject :: binary())`: Subscribe to the `Subject`,
    * `nats:sub(Conn :: teacup_ref(), Subject :: binary(), Opts :: map())`: Subscribe to the `Subject`, with
    `Options`. Valid options:
        * `queue_group => QGroup :: binary()`
* Unsubscribe functions:
    * `nats:unsub(Conn :: teacup_ref(), Subject :: binary())`: Unsubscribe from `Subject`,
    * `nats:unsub(Conn :: teacup_ref(), Subject :: binary(), Opts :: map())`: Unsubscribe from `Subject`, with
    `Options`. Valid options:
        * `max_messages => MaxMessages :: integer()`: Automatically unsubscribe after receiving `MaxMessages`.

#### Sample

```erlang
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
```

### Synchronous Connection

In order to activate the synchronous mode, just pass `#{verbose => true` to `nats:connect`.

Connect, publish, subscribe and unsubscribe operations block and return either `ok` on
success or `{error, Reason :: term()}` on failure.

#### Sample

```erlang
main() ->
    % Connect to the NATS server
    {ok, Conn} = nats:connect(<<"demo.nats.io">>, 4222, #{verbose => true}),
    % The connection is OK to use
    % Publish some message
    ok = nats:pub(Conn, <<"teacup.control">>, #{payload => <<"start">>}),
    % subscribe to some subject
    ok = nats:sub(Conn, <<"foo.*">>),
    loop(Conn).

loop(Conn) ->
    receive
        {Conn, {msg, Subject, _ReplyTo, Payload}} ->
            % Do something with the received message
            io:format("~p: ~p~n", [Subject, Payload]),
            loop(Conn)
    end.

```

## License

```
Copyright 2016 Yuce Tekol <yucetekol@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
