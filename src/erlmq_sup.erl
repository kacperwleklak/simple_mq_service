%%%-------------------------------------------------------------------
%% @doc erlmq top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(erlmq_sup).
-behaviour(supervisor).

-export([start_link/0, start_socket/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    {ok, Port} = application:get_env(app_port),
    {ok, ListenSocket} = gen_tcp:listen(Port, [{active,once}, {packet,line}]),
    {ok, MongoEventHandler} = gen_event:start_link({local, mongo_handler}),
    gen_event:add_handler(MongoEventHandler, mongo_event_handler, []),
    {ok, SubscriptionHandler} = gen_event:start_link({local, subscription_handler}),
    gen_event:add_handler(SubscriptionHandler, erlmq_sub_handler, []),
    spawn_link(fun empty_listeners/0),
    {ok, {{simple_one_for_one, 60, 3600},
        [
            {socket, {erlmq_clients_server, start_link, [ListenSocket]}, temporary, 1000, worker, [erlmq_clients_server]}
        ]}}.

%% internal functions

start_socket() ->
    supervisor:start_child(?MODULE, []).

empty_listeners() ->
    [start_socket() || _ <- lists:seq(1,20)],
    ok.
