%
% Copyright (c) 2016, Yuce Tekol <yucetekol@gmail.com>.
% All rights reserved.

% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:

% * Redistributions of source code must retain the above copyright
%   notice, this list of conditions and the following disclaimer.

% * Redistributions in binary form must reproduce the above copyright
%   notice, this list of conditions and the following disclaimer in the
%   documentation and/or other materials provided with the distribution.

% * The names of its contributors may not be used to endorse or promote
%   products derived from this software without specific prior written
%   permission.

% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
% A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
% OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
% LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
% DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
% THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%

-module(nats_msg).
-author("Yuce Tekol").

-export([encode/1,
         decode/1,
         decode_all/1]).

-export([ping/0,
         pong/0,
         ok/0,
         err/1,
         info/1,
         connect/1,
         pub/1,
         pub/3,
         hpub/4,
         sub/2,
         sub/3,
         unsub/1,
         unsub/2,
         msg/2,
         msg/4]).

-define(CRLF, <<"/r/n">>).
-define(SPACE, <<" ">>).

-type error_param() :: {error, unknown_operation} |
                       {error, auth_violation} |
                       {error, auth_timeout} |
                       {error, parser_error} |
                       {error, stale_connection} |
                       {error, slow_consumer} |
                       {error, max_payload} |
                       {error, invalid_subject}.

-type pub_param() :: {pub, {Subject :: iodata(),
                            ReplyTo :: iodata() | undefined,
                            Payload :: iodata()}}.

-type sub_param() :: {sub, {Subject :: iodata(),
                            QueueGrp :: iodata() | undefined,
                            Sid :: iodata()}}.

-type unsub_param() :: {unsub, {Sid :: iodata(),
                                MaxMsg :: integer() | undefined}}.

-type msg_param() :: {msg, {Subject :: iodata(),
                            Sid :: iodata(),
                            ReplyTo :: iodata() | undefined,
                            Payload :: iodata()}}.

-type encode_param() :: ping | pong | ok | error |
                        {info, iodata()} | {connect, iodata()} |
                        error_param() |
                        pub_param() | sub_param() | unsub_param() | msg_param().

%% == API

%% == Encode API

ping() -> encode(ping).
pong() -> encode(pong).
ok() -> encode(ok).
err(Msg) -> encode({error, Msg}).
info(Info) -> encode({info, Info}).
connect(Info) -> encode({connect, Info}).

pub(Subject) ->
    encode({pub, {Subject, undefined, <<>>}}).
pub(Subject, ReplyTo, Payload) ->
    encode({pub, {Subject, ReplyTo, Payload}}).

hpub(Subject, ReplyTo, Headers, Payload) ->
    encode({hpub, {Subject, ReplyTo, Headers, Payload}}).

sub(Subject, Sid) ->
    encode({sub, {Subject, undefined, Sid}}).
sub(Subject, QueueGrp, Sid) ->
    encode({sub, {Subject, QueueGrp, Sid}}).

unsub(Sid) ->
    encode({unsub, {Sid, undefined}}).
unsub(Sid, MaxMsg) ->
    encode({unsub, {Sid, MaxMsg}}).

msg(Subject, Sid) ->
    encode({msg, {Subject, Sid, undefined, <<>>}}).
msg(Subject, Sid, ReplyTo, Payload) ->
    encode({msg, {Subject, Sid, ReplyTo, Payload}}).

-spec encode(Param :: encode_param()) -> iolist().

encode(ping) -> <<"PING\r\n">>;
encode(pong) -> <<"PONG\r\n">>;
encode(ok) -> <<"+OK\r\n">>;
encode({error, unknown_operation}) -> <<"-ERR 'Unknown Protocol Operation'\r\n">>;
encode({error, auth_violation}) -> <<"-ERR 'Authorization Violation'\r\n">>;
encode({error, auth_timeout}) -> <<"-ERR 'Authorization Timeout'\r\n">>;
encode({error, parser_error}) -> <<"-ERR 'Parser Error'\r\n">>;
encode({error, stale_connection}) -> <<"-ERR 'Stale Connection'\r\n">>;
encode({error, slow_consumer}) -> <<"-ERR 'Slow Consumer'\r\n">>;
encode({error, max_payload}) -> <<"-ERR 'Maximum Payload Exceeded'\r\n">>;
encode({error, invalid_subject}) -> <<"-ERR 'Invalid Subject'\r\n">>;
encode({info, BinInfo}) -> [<<"INFO">>, ?SPACE, BinInfo, ?CRLF];
encode({connect, BinConnect}) -> [<<"CONNECT">>, ?SPACE, BinConnect, ?CRLF];

encode({pub, {Subject, undefined, Payload}}) ->
    BinPS = integer_to_binary(iolist_size(Payload)),
    [<<"PUB">>, ?SPACE, Subject, ?SPACE, BinPS, ?CRLF,
      Payload, ?CRLF];

encode({pub, {Subject, ReplyTo, Payload}}) ->
    BinPS = integer_to_binary(iolist_size(Payload)),
    [<<"PUB">>, ?SPACE, Subject, ?SPACE, ReplyTo, ?SPACE, BinPS, ?CRLF,
      Payload, ?CRLF];

encode({hpub, {Subject, undefined, Headers0, Payload}}) ->
    BinHeaders = encode_headers(Headers0),
    HS = iolist_size(BinHeaders) + 4,
    TPS = HS + iolist_size(Payload),

    [<<"HPUB">>, ?SPACE, 
        Subject, ?SPACE,
        integer_to_binary(HS), ?SPACE,
        integer_to_binary(TPS), ?CRLF,
        BinHeaders, ?CRLF, ?CRLF,
        Payload, ?CRLF];

encode({hpub, {Subject, ReplyTo, Headers0, Payload}}) ->
    BinHeaders = encode_headers(Headers0),
    HS = iolist_size(BinHeaders) + 4,
    TPS = HS + iolist_size(Payload),

    [<<"HPUB">>, ?SPACE, 
        Subject, ?SPACE, 
        ReplyTo, ?SPACE, 
        integer_to_binary(HS), ?SPACE, 
        integer_to_binary(TPS), ?CRLF,
        BinHeaders, ?CRLF, ?CRLF,
        Payload, ?CRLF];

encode({sub, {Subject, undefined, Sid}}) ->
    [<<"SUB">>, ?SPACE, Subject, ?SPACE, Sid, ?CRLF];

encode({sub, {Subject, QueueGrp, Sid}}) ->
    [<<"SUB">>, ?SPACE, Subject, ?SPACE, QueueGrp, ?SPACE, Sid, ?CRLF];

encode({unsub, {Subject, undefined}}) ->
    [<<"UNSUB">>, ?SPACE, Subject, ?CRLF];

encode({unsub, {Subject, MaxMsg}}) ->
    BinMaxMsg = integer_to_binary(MaxMsg),
    [<<"UNSUB">>, ?SPACE, Subject, ?SPACE, BinMaxMsg, ?CRLF];

encode({msg, {Subject, Sid, undefined, Payload}}) ->
    BinPS = integer_to_binary(iolist_size(Payload)),
    [<<"MSG">>, ?SPACE, Subject, ?SPACE, Sid, ?SPACE, BinPS, ?CRLF,
      Payload, ?CRLF];

encode({msg, {Subject, Sid, ReplyTo, Payload}}) ->
    BinPS = integer_to_binary(iolist_size(Payload)),
    [<<"MSG">>, ?SPACE, Subject, ?SPACE, Sid, ?SPACE, ReplyTo, ?SPACE, BinPS, ?CRLF,
      Payload, ?CRLF].

% == Decode API

decode_all(Bin) ->
    {RevMsgs, Rest} = decode_messages(Bin, []),
    {lists:reverse(RevMsgs), Rest}.

-spec decode(Param :: iodata()) ->
    {term(), binary()}.

decode(L) when is_list(L) ->
    decode(iolist_to_binary(L));

decode(<<>>) -> <<>>;
decode(<<"+OK\r\n", Rest/binary>>) -> {ok, Rest};
decode(<<"PING\r\n", Rest/binary>>) -> {ping, Rest};
decode(<<"PONG\r\n", Rest/binary>>) -> {pong, Rest};
decode(<<"-ERR 'Unknown Protocol Operation'\r\n", Rest/binary>>) -> {{error, unknown_operation}, Rest};
decode(<<"-ERR 'Authorization Violation'\r\n", Rest/binary>>) -> {{error, auth_violation}, Rest};
decode(<<"-ERR 'Authorization Timeout'\r\n", Rest/binary>>) -> {{error, auth_timeout}, Rest};
decode(<<"-ERR 'Parser Error'\r\n", Rest/binary>>) -> {{error, parser_error}, Rest};
decode(<<"-ERR 'Stale Connection'\r\n", Rest/binary>>) -> {{error, stale_connection}, Rest};
decode(<<"-ERR 'Slow Consumer'\r\n", Rest/binary>>) -> {{error, slow_consumer}, Rest};
decode(<<"-ERR 'Maximum Payload Exceeded'\r\n", Rest/binary>>) -> {{error, max_payload}, Rest};
decode(<<"-ERR 'Invalid Subject'\r\n", Rest/binary>>) -> {{error, invalid_subject}, Rest};
decode(<<"MSG ", Rest/binary>> = OrigMsg) -> decode_slow(msg, OrigMsg, Rest);
decode(<<"HMSG ", Rest/binary>> = OrigMsg) -> decode_slow(hmsg, OrigMsg, Rest);
decode(<<"PUB ", Rest/binary>> = OrigMsg) -> decode_slow(pub, OrigMsg, Rest);
decode(<<"SUB ", Rest/binary>> = OrigMsg) -> decode_slow(sub, OrigMsg, Rest);
decode(<<"UNSUB ", Rest/binary>> = OrigMsg) -> decode_slow(unsub, OrigMsg, Rest);
decode(<<"CONNECT ", Rest/binary>> = OrigMsg) -> decode_slow(connect, OrigMsg, Rest);
decode(<<"INFO ", Rest/binary>> = OrigMsg) -> decode_slow(info, OrigMsg, Rest);
decode(Other) -> {[], Other}.

%% == Internal - decode

decode_messages(<<>>, Acc) ->
    {Acc, <<>>};

decode_messages(Bin, Acc) ->
    case decode(Bin) of
        {[], Rest} ->
            {Acc, Rest};
        {M, Rest} ->
            decode_messages(Rest, [M | Acc])
    end.

decode_slow(connect, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false -> {[], OrigMsg};
        {Flip, Rest} -> {{connect, Flip}, Rest}
    end;

decode_slow(info, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false -> {[], OrigMsg};
        {Flip, Rest} -> {{info, Flip}, Rest}
    end;

decode_slow(hmsg, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false ->
            {[], OrigMsg};
        {Flip, Rest} ->
            {Subject, Sid, ReplyTo, HSLen, TSLen} = parse_hmsg_flip(Flip),
            HLen = HSLen - 4,
            PLen = TSLen - HLen,
            <<Headers0:HLen/binary, "\r\n\r\n", Payload:PLen/binary, "\r\n", Rest1/binary>> = Rest,
            Headers1 = decode_headers(Headers0),
            {{hmsg, {Subject, Sid, ReplyTo, Headers1, Payload}}, Rest1}
    end;

decode_slow(msg, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false ->
            {[], OrigMsg};
        {Flip, Rest} ->
            {Subject, Sid, ReplyTo, PS} = parse_msg_flip(Flip),
            case byte_size(Rest) >= PS + 2 of
                true ->
                    {Payload, NewRest} = extract_line(Rest, PS),
                    {{msg, {Subject, Sid, ReplyTo, Payload}}, NewRest};
                _ ->
                    {[], OrigMsg}
            end
    end;

decode_slow(pub, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false ->
            {[], OrigMsg};
        {Flip, Rest} ->
            {Subject, ReplyTo, PS} = parse_pub_flip(Flip),
            case byte_size(Rest) >= PS + 2 of
                true ->
                    {Payload, NewRest} = extract_line(Rest, PS),
                    {{pub, {Subject, ReplyTo, Payload}}, NewRest};
                _ ->
                    {[], OrigMsg}
            end
    end;

decode_slow(sub, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false ->
            {[], OrigMsg};
        {Flip, Rest} ->
            {{sub, parse_sub_flip(Flip)}, Rest}
    end;

decode_slow(unsub, OrigMsg, Bin) ->
    case extract_flip(Bin) of
        false ->
            {[], OrigMsg};
        {Flip, Rest} ->
            {{unsub, parse_unsub_flip(Flip)}, Rest}
    end.

encode_headers([], Acc) -> Acc;
encode_headers([{K, V} | Tail], Acc0) ->
    R0 = iolist_to_binary([?CRLF, K, ":", V]),
    encode_headers(Tail, <<Acc0/binary, R0/binary>>).

encode_headers(Headers0) ->
    encode_headers(Headers0, <<"NATS/1.0">>).

decode_headers([], Acc0) -> Acc0;
decode_headers([<<"NATS/1.0", _/binary>>| Tail], Acc0) ->
    decode_headers(Tail, [{<<"NATS/1.0">>, true} | Acc0]);
decode_headers([H1 | Tail], Acc0) ->
    case binary:split(H1, <<":">>) of
        [K, V|_] -> decode_headers(Tail, [{K, V} | Acc0]);
        [K |_ ] -> decode_headers(Tail, [{K, true} | Acc0]);
        _ -> decode_headers(Tail, Acc0)
    end.

decode_headers(Headers0) ->
    Headers1 = binary:split(Headers0, ?CRLF, [global]),
    decode_headers(Headers1, []).

extract_flip(Bin) ->
    case binary:match(Bin, ?CRLF) of
        nomatch -> false;
        {Pos, _Len} -> extract_line(Bin, Pos)
    end.

extract_line(Bin, Len) ->
    <<Ret:Len/binary, "\r\n", Rest/binary>> = Bin,
    {Ret, Rest}.

parse_hmsg_flip(Flip) ->
     case binary:split(Flip, ?SPACE, [global]) of
        [Subject, Sid, HeaderBytes, BinBytes] ->
            {Subject, Sid, undefined, binary_to_integer(HeaderBytes), binary_to_integer(BinBytes)};
        [Subject, Sid, ReplyTo, HeaderBytes, BinBytes] ->
            {Subject, Sid, ReplyTo, binary_to_integer(HeaderBytes), binary_to_integer(BinBytes)};
        _ ->
            throw(parse_error)
    end.

parse_msg_flip(Flip) ->
     case binary:split(Flip, ?SPACE, [global]) of
        [Subject, Sid, BinBytes] ->
            {Subject, Sid, undefined, binary_to_integer(BinBytes)};
        [Subject, Sid, ReplyTo, BinBytes] ->
            {Subject, Sid, ReplyTo, binary_to_integer(BinBytes)};
        _ ->
            throw(parse_error)
    end.

parse_pub_flip(Flip) ->
    case binary:split(Flip, ?SPACE, [global]) of
        [Subject, BinBytes] ->
            {Subject, undefined, binary_to_integer(BinBytes)};
        [Subject, ReplyTo, BinBytes] ->
            {Subject, ReplyTo, binary_to_integer(BinBytes)};
        _ ->
            throw(parse_error)
    end.

parse_sub_flip(Flip) ->
    case binary:split(Flip, ?SPACE, [global]) of
        [Subject, Sid] ->
            {Subject, undefined, Sid};
        [Subject, QueueGrp, Sid] ->
            {Subject, QueueGrp, Sid};
        _ ->
            throw(parse_error)
    end.

parse_unsub_flip(Flip) ->
    case binary:split(Flip, ?SPACE, [global]) of
        [Subject] ->
            {Subject, undefined};
        [Subject, BinMaxMsg] ->
            {Subject, binary_to_integer(BinMaxMsg)};
        _ ->
            throw(parse_error)
    end.

% upper_case(Bin) ->
%     list_to_binary(string:to_upper(binary_to_list(Bin))).

%% == Tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    io:format("setup called"),
    nats_msg:init().

%% == Encode Tests

ping_test() ->
    R = ping(),
    E = <<"PING\r\n">>,
    ?assertEqual(E, R).

pong_test() ->
    R = pong(),
    E = <<"PONG\r\n">>,
    ?assertEqual(E, R).

ok_test() ->
    R = ok(),
    E = <<"+OK\r\n">>,
    ?assertEqual(E, R).

err_test() ->
    R = err(auth_timeout),
    E = <<"-ERR 'Authorization Timeout'\r\n">>,
    ?assertEqual(E, R).

info_test() ->
    R = iolist_to_binary(info(<<"{\"auth_required\":true,\"server_id\":\"0001-SERVER\"}">>)),
    E = <<"INFO {\"auth_required\":true,\"server_id\":\"0001-SERVER\"}\r\n">>,
    ?assertEqual(E, R).

connect_test() ->
    R = iolist_to_binary(connect(<<"{\"name\":\"sample-client\",\"verbose\":true}">>)),
    E = <<"CONNECT {\"name\":\"sample-client\",\"verbose\":true}\r\n">>,
    ?assertEqual(E, R).

pub_1_test() ->
    R = iolist_to_binary(pub(<<"NOTIFY">>)),
    E = <<"PUB NOTIFY 0\r\n\r\n">>,
    ?assertEqual(E, R).

pub_2_test() ->
    R = iolist_to_binary(pub(<<"FRONT.DOOR">>, <<"INBOX.22">>, <<"Knock Knock">>)),
    E = <<"PUB FRONT.DOOR INBOX.22 11\r\nKnock Knock\r\n">>,
    ?assertEqual(E, R).

sub_1_test() ->
    R = iolist_to_binary(sub(<<"FOO">>, <<"1">>)),
    E = <<"SUB FOO 1\r\n">>,
    ?assertEqual(E, R).

sub_2_test() ->
    R = iolist_to_binary(sub(<<"BAR">>, <<"G1">>, <<"44">>)),
    E = <<"SUB BAR G1 44\r\n">>,
    ?assertEqual(E, R).

unsub_1_test() ->
    R = iolist_to_binary(unsub(<<"1">>)),
    E = <<"UNSUB 1\r\n">>,
    ?assertEqual(E, R).

unsub_2_test() ->
    R = iolist_to_binary(unsub(<<"1">>, 10)),
    E = <<"UNSUB 1 10\r\n">>,
    ?assertEqual(E, R).

msg_4_test() ->
    R = iolist_to_binary(msg(<<"FOO.BAR">>, <<"9">>, <<"INBOX.34">>, <<"Hello, World!">>)),
    E = <<"MSG FOO.BAR 9 INBOX.34 13\r\nHello, World!\r\n">>,
    ?assertEqual(E, R).

%% == Decode Tests

dec_ping_test() ->
    {ping, <<>>} = decode(<<"PING\r\n">>).

dec_pong_test() ->
    {pong, <<>>} = decode(<<"PONG\r\n">>).

dec_ok_test() ->
    {ok, <<>>} = decode(<<"+OK\r\n">>).

dec_err_test() ->
    R = decode(<<"-ERR 'Authorization Timeout'\r\n">>),
    E = {{error, auth_timeout}, <<>>},
    ?assertEqual(E, R).

dec_info_test() ->
    setup(),
    {{info, Info}, <<>>} = decode(<<"INFO {\"auth_required\":true,\"server_id\":\"0001-SERVER\"}\r\n">>),
    Info = <<"{\"auth_required\":true,\"server_id\":\"0001-SERVER\"}">>.

dec_connect_test() ->
    setup(),
    R = decode(<<"CONNECT {\"name\":\"sample-client\",\"verbose\":true}\r\n">>),
    E = {{connect, <<"{\"name\":\"sample-client\",\"verbose\":true}">>}, <<>>},
    ?assertEqual(E, R).

dec_pub_1_test() ->
    R = decode(<<"PUB NOTIFY 0\r\n\r\n">>),
    E = {{pub, {<<"NOTIFY">>, undefined, <<>>}}, <<>>},
    ?assertEqual(E, R).

dec_pub_2_test() ->
    R = decode(<<"PUB FOO 11\r\nHello NATS!\r\n">>),
    E = {{pub, {<<"FOO">>, undefined, <<"Hello NATS!">>}}, <<>>},
    ?assertEqual(E, R).

dec_pub_3_test() ->
    R = decode(<<"PUB FRONT.DOOR INBOX.22 11\r\nKnock Knock\r\n">>),
    E = {{pub, {<<"FRONT.DOOR">>, <<"INBOX.22">>, <<"Knock Knock">>}}, <<>>},
    ?assertEqual(E, R).

dec_sub_1_test() ->
    R = decode(<<"SUB FOO 1\r\n">>),
    E = {{sub, {<<"FOO">>, undefined, <<"1">>}}, <<>>},
    ?assertEqual(E, R).

dec_sub_2_test() ->
    R = decode(<<"SUB BAR G1 44\r\n">>),
    E = {{sub,{<<"BAR">>,<<"G1">>,<<"44">>}}, <<>>},
    ?assertEqual(E, R).

dec_unsub_1_test() ->
    R = decode(<<"UNSUB 1\r\n">>),
    E = {{unsub, {<<"1">>, undefined}}, <<>>},
    ?assertEqual(E, R).

dec_unsub_2_test() ->
    R = decode(<<"UNSUB 1 10\r\n">>),
    E = {{unsub, {<<"1">>, 10}}, <<>>},
    ?assertEqual(E, R).

dec_msg_1_test() ->
    R = decode(<<"MSG FOO.BAR 9 13\r\nHello, World!\r\n">>),
    E = {{msg, {<<"FOO.BAR">>, <<"9">>, undefined, <<"Hello, World!">>}}, <<>>},
    ?assertEqual(E, R).

dec_msg_2_test() ->
    R = decode(<<"MSG FOO.BAR 9 INBOX.34 13\r\nHello, World!\r\n">>),
    E = {{msg, {<<"FOO.BAR">>, <<"9">>, <<"INBOX.34">>, <<"Hello, World!">>}}, <<>>},
    ?assertEqual(E, R).

dec_many_lines_test() ->
    R = decode(<<"PING\r\nMSG FOO.BAR 9 INBOX.34 13\r\nHello, World!\r\n">>),
    E = {ping, <<"MSG FOO.BAR 9 INBOX.34 13\r\nHello, World!\r\n">>},
    ?assertEqual(E, R).

dec_nl_in_payload_test() ->
    R = decode(<<"PUB FOO 12\r\nHello\r\nNATS!\r\n">>),
    E = {{pub, {<<"FOO">>, undefined, <<"Hello\r\nNATS!">>}}, <<>>},
    ?assertEqual(E, R).

dec_incomplete_payload_test() ->
    R = decode(<<"PUB FOO 12\r\nHello\r\nNATS!">>),
    E = {[], <<"PUB FOO 12\r\nHello\r\nNATS!">>},
    ?assertEqual(E, R).

dec_all_messages_1_test() ->
    R = decode_all(<<"+OK\r\nPING\r\nM">>),
    E = {[ok, ping], <<"M">>},
    ?assertEqual(E, R).

dec_all_messages_2_test() ->
    R = decode_all(<<"INFO {\"server_id\":\"b379e32c3cd3dd8515c919a42d813eaf\",\"version\":\"0.7.2\",\"go\":\"go1.5.2\",\"host\":\"127.0.0.1\",\"port\":4222,\"auth_required\":false,\"ssl_required\":false,\"tls_required\":false,\"tls_verify\":false,\"max_payload\":1048576} \r\n">>),
    E = {[{info, <<"{\"server_id\":\"b379e32c3cd3dd8515c919a42d813eaf\",\"version\":\"0.7.2\",\"go\":\"go1.5.2\",\"host\":\"127.0.0.1\",\"port\":4222,\"auth_required\":false,\"ssl_required\":false,\"tls_required\":false,\"tls_verify\":false,\"max_payload\":1048576}">>, ?SPACE}], <<>>},
    ?assertEqual(E, R).

% % == Other Tests

decode_encode_1_test() ->
    E = <<"MSG FOO.BAR 9 INBOX.34 13\r\nHello, World!\r\n">>,
    {R1, _} = decode(E),
    io:format("R1: ~p~n", [R1]),
    R2 = iolist_to_binary(encode(R1)),
    ?assertEqual(E, R2).

-endif.