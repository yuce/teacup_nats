% Copyright (c) 2016, Yuce Tekol <yucetekol@gmail.com>.
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
%
% * Redistributions of source code must retain the above copyright
%   notice, this list of conditions and the following disclaimer.
%
% * Redistributions in binary form must reproduce the above copyright
%   notice, this list of conditions and the following disclaimer in the
%   documentation and/or other materials provided with the distribution.
%
% * The names of its contributors may not be used to endorse or promote
%   products derived from this software without specific prior written
%   permission.
%
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

-module(teacup_nats@sync).

-export([new/0,
         new/1]).
-export([connect/0,
         connect/2,
         connect/3,
         pub/2,
         pub/3,
         sub/2,
         sub/3,
         unsub/2,
         unsub/3]).

-define(DEFAULT_HOST, <<"127.0.0.1">>).
-define(DEFAULT_PORT, 4222).
-define(HANDLER, nats@teacup).

%% == API

new() ->
    new(#{}).
 
new(Opts) ->
    teacup:new(?HANDLER, Opts).

connect() ->
    connect(?DEFAULT_HOST, ?DEFAULT_PORT, #{}).
    
connect(Host, Port) ->
    connect(Host, Port, #{}).
    
connect(Host, Port, Opts) ->    
    NewOpts = Opts#{verbose => true},
    {ok, Conn} = teacup:new(?HANDLER, NewOpts),
    case teacup:call(Conn, {connect, Host, Port}) of
        ok -> {ok, Conn};
        {error, _Reason} = Error -> Error
    end.

pub(Ref, Subject) ->
    pub(Ref, Subject, #{}).
    
-spec pub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.
pub(Ref, Subject, Opts) ->
    teacup:call(Ref, {pub, Subject, Opts}).

sub(Ref, Subject) ->
    sub(Ref, Subject, #{}).

-spec sub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.
sub(Ref, Subject, Opts) ->
    teacup:call(Ref, {sub, Subject, Opts, self()}).    

unsub(Ref, Subject) ->
    unsub(Ref, Subject, #{}).

-spec unsub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.
unsub(Ref, Subject, Opts) ->
    teacup:call(Ref, {unsub, Subject, Opts, self()}).
