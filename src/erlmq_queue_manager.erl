-module(erlmq_queue_manager).
-author("kacper").

%% API
-export([add_queue/2, get_queues_string/0, exist_queue/1]).

add_queue(QueueName, pubsub) ->
    Queue = #{
        to_bin("type") => to_bin("pubsub"),
        to_bin("name") => to_bin(QueueName)},
    gen_event:call(mongo_handler, mongo_event_handler, {insert, "queues", Queue}),
    io:fwrite("Added new queue - ~s, type pubsub!~n", [QueueName]);

add_queue(QueueName, reqrep) ->
    Queue = #{
        to_bin("type") => to_bin("reqrep"),
        to_bin("name") => to_bin(QueueName)},
    gen_event:call(mongo_handler, mongo_event_handler, {insert, "queues", Queue}),
    io:fwrite("Added new queue - ~s, type reqrep!~n", [QueueName]);

add_queue(_, _) ->
    io:fwrite("Invalid queue type!~n", []).

get_queues_string() ->
    {ok, Cursor} = gen_event:call(mongo_handler, mongo_event_handler, {find, "queues", {}}),
    Queues = [],
    form_queues_string(Queues, mc_cursor:next(Cursor), Cursor).

exist_queue(QueueName) ->
    Query = #{
        to_bin("name") => to_bin(QueueName)},
    gen_event:call(mongo_handler, mongo_event_handler, {find_one, "queues", Query}).

form_queues_string(L, error, Cursor) ->
    mc_cursor:close(Cursor),
    L;
form_queues_string(L, Queue, Cursor) ->
    {#{<<"_id">> := _, <<"name">> := QNameBin, <<"type">> := QTypeBin}} = Queue,
    QueueDesc = io_lib:format("~n    ~s [~s]",[binary_to_list(QNameBin), binary_to_list(QTypeBin)]),
    NewL = lists:append(L, QueueDesc),
    form_queues_string(NewL, mc_cursor:next(Cursor), Cursor).
to_bin(X) ->
    erlmq_utils:to_bin(X).
