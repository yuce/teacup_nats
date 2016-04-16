% Copyright 2016 Yuce Tekol <yucetekol@gmail.com>

% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at

%     http://www.apache.org/licenses/LICENSE-2.0

% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.

-module(tcnats).

-export([new/0,
         new/1]).
-export([connect/2,
         connect/3,
         pub/2,
         pub/3,
         sub/2,
         sub/3,
         unsub/2,
         unsub/3]).

-include("teacup_nats_common.hrl").

%% == API

new() ->
    new(#{}).
 
new(Opts) ->
    teacup:new(?HANDLER, Opts).

connect(Host, Port) ->
    connect(Host, Port, #{}).
    
connect(Host, Port, #{verbose := true} = Opts) ->
    {ok, Conn} = teacup:new(?HANDLER, Opts),
    case teacup:call(Conn, {connect, Host, Port}) of
        ok ->
            {ok, Conn};
        {error, _Reason} = Error ->
            Error
    end;
  
connect(Host, Port, Opts) ->
    {ok, Conn} = teacup:new(?HANDLER, Opts),
    teacup:connect(Conn, Host, Port),
    {ok, Conn}.
    
pub(Ref, Subject) ->
    pub(Ref, Subject, #{}).

-spec pub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.

pub({teacup@ref, ?VERBOSE_SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:call(Ref, {pub, Subject, Opts});

pub({teacup@ref, ?SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:cast(Ref, {pub, Subject, Opts}).                        

sub(Ref, Subject) ->
    sub(Ref, Subject, #{}).

-spec sub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.

sub({teacup@ref, ?VERBOSE_SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:call(Ref, {sub, Subject, Opts, self()});

sub({teacup@ref, ?SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:cast(Ref, {sub, Subject, Opts, self()}).    

unsub(Ref, Subject) ->
    unsub(Ref, Subject, #{}).

-spec unsub(Ref :: teacup:teacup_ref(), Subject :: binary(), Opts :: map()) ->
    ok | {error, Reason :: term()}.

unsub({teacup@ref, ?VERBOSE_SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:call(Ref, {unsub, Subject, Opts, self()});

unsub({teacup@ref, ?SIGNATURE, _} = Ref, Subject, Opts) ->
    teacup:cast(Ref, {unsub, Subject, Opts, self()}).
