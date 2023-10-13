# Teacup NATS

A [Teacup](https://github.com/yuce/teacup.git) based Erlang client library for [NATS](http://nats.io/)
high performance messaging platform.

## NEWS

* Added hpub, hmsg, headers, example with pull + ack
* Previous Versions check `https://github.com/yuce/teacup_nats`

## Getting Started

**teacup_nats** requires Erlang/OTP 18.0+. It uses [rebar3](http://www.rebar3.org/)
as the build tool and is available on [hex.pm](https://hex.pm/). Just include the following
in your `rebar.config`:

```erlang
{deps, [teacup_nats]}.
```

## API

* To do pull on consumer

```erlang
%% make an inbox
UUID = uuid:uuid_to_string(uuid:get_v4()),
Inbox = iolist_to_binary(["_INBOX." UUID]),
nats:sub(Conn, Inbox),

%% ask to get 1 message from consumer into inbox and delivered to us
nats:pub(Conn, <<"$JS.API.CONSUMER.MSG.NEXT.<stream>.<consumer>">>, #{
    reply_to    => Inbox,
    payload     => jsx:encode(#{no_wait => true, batch => 1})
}),
%% to ack +ACK, NACK, ...
nats:pub(Conn, ReplyTo, #{payload => <<"+ACK">>}).
```

* Connection

```erlang
main() ->
    ConnectOpts = #{buffer_size => 10},
    % Connect to the NATS server
    {ok, Conn} = nats:connect(<<"demo.nats.io">>, 4222, ConnectOpts),
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

`ConnectOpts` support

* `verbose => true`
* `headers => true`

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
