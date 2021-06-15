-module(mongo_worker).
-author("kacper").

%% API
-export([connect/0, insert/3, get_one/2, get_one/3, delete/3, find/3, get_and_delete/3]).

-record(conn, {
    connection = undefined
}).

%%====================
%% Exported functions
%%====================

connect() ->
    Config = [{host, "localhost"},
        {login, list_to_binary("root")},
        {password, list_to_binary("root")},
        {database, <<"local">>},
        {port, 27017}],
    {ok, Connection} = mc_worker_api:connect(Config),
    {ok, #conn{connection = Connection}}.

insert(#conn{connection = Connection}, Collection, Document) ->
    mc_worker_api:insert(Connection, erlmq_utils:to_bin(Collection), erlmq_utils:to_bin(Document)).

get_one(#conn{connection = Connection} = State, Collection) ->
    get_one(#conn{connection = Connection} = State, Collection, #{}).

get_one(#conn{connection = Connection}, Collection, Query) ->
    mc_worker_api:find_one(Connection, erlmq_utils:to_bin(Collection), Query).

delete(#conn{connection = Connection}, Collection, Selector) ->
    mc_worker_api:insert(Connection, erlmq_utils:to_bin(Collection), Selector).

find(#conn{connection = Connection}, Collection, Selector) ->
    mc_worker_api:find(Connection, erlmq_utils:to_bin(Collection), Selector).

get_and_delete(#conn{connection = Connection}, Collection, Query) ->
    Command = #{<<"findAndModify">> => erlmq_utils:to_bin(Collection),
                <<"query">> => Query,
                <<"remove">> => true},
    mc_worker_api:command(Connection, Command).
