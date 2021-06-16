-module(erlmq_clients_server).

-behaviour(gen_server).

-record(state, {id,
    state,
    mode,
    queue,
    socket}).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

start_link(Socket) ->
    gen_server:start_link(?MODULE, Socket, []).

init(Socket) ->
    <<A:32, B:32, C:32>> = crypto:strong_rand_bytes(12),
    random:seed({A,B,C}),
    gen_server:cast(self(), accept),
    {ok, #state{socket=Socket}}.

%% Handle calls
handle_call(_E, _From, State) ->
    {noreply, State}.

%% Handle casts
handle_cast(accept, S = #state{socket=ListenSocket}) ->
    {ok, AcceptSocket} = gen_tcp:accept(ListenSocket),
    erlmq_sup:start_socket(),
    send(AcceptSocket, "What's your ID?", []),
    {noreply, S#state{socket=AcceptSocket, state=id}};

handle_cast(queue_selector, S = #state{socket=Socket}) ->
    Queues = erlmq_queue_manager:get_queues_string(),
    send(Socket, "Select queue by name~s", [Queues]),
    {noreply, S#state{state={queue_select}}};

handle_cast(mode_selector, S = #state{socket=Socket}) ->
    send(Socket, "Select mode", []),
    {noreply, S#state{state={mode_select}}};

handle_cast(req, S = #state{id=Id}) ->
    io:fwrite("Clients ~s choosed mode req!~n", [Id]),
    {noreply, S#state{state={messaging_req}}};

handle_cast(rep, S = #state{id=Id}) ->
    io:fwrite("Clients ~s choosed mode rep!~n", [Id]),
    {noreply, S#state{state={messaging_rep}}};

handle_cast(sub, S = #state{id=Id}) ->
    io:fwrite("Clients ~s choosed mode sub!~n", [Id]),
    gen_event:notify(subscription_handler, {register_subscriber, self()}),
    {noreply, S#state{state={messaging_sub}}};

handle_cast(pub, S = #state{id=Id}) ->
    io:fwrite("Clients ~s choosed mode pub!~n", [Id]),
    {noreply, S#state{state={messaging_pub}}}.

%% Handle infos

handle_info({tcp, _Socket, "quit"++_}, S = #state{state={messaging_sub}}) ->
    gen_event:notify(subscription_handler, {unregister_subscriber, self()}),
    {stop, normal, S};

handle_info({tcp, _Socket, "quit"++_}, S) ->
    {stop, normal, S};

handle_info({tcp, _Socket, Str}, S = #state{state=id}) ->
    Id = line(Str),
    io:fwrite("Clients id is ~s!~n", [Id]),
    gen_server:cast(self(), queue_selector),
    {noreply, S#state{id=Id, state=queue_select}};

handle_info({tcp, Socket, Str}, S = #state{socket=Socket, state={queue_select}}) ->
    Queue = line(Str),
    FoundQueue = erlmq_queue_manager:exist_queue(Queue),
    case FoundQueue of
        undefined ->
            send(Socket, "Incorrect queue!", []),
            NewS = S;
        _ ->
            #{<<"type">> := QTypeBin} = FoundQueue,
            gen_server:cast(self(), mode_selector),
            NewS = S#state{queue=Queue, state=mode_select, mode=binary_to_atom(QTypeBin, utf8)}
    end,
    {noreply, NewS};

handle_info({tcp, Socket, Str}, S = #state{socket=Socket, state={mode_select}, mode=pubsub}) ->
    case line(Str) of
        "pub" ->
            send(Socket, "You can send messages to subscribers", []),
            gen_server:cast(self(), pub);
        "sub" ->
            send(Socket, "Waiting for messages...", []),
            gen_server:cast(self(), sub);
        _ ->
            send(Socket, "Select mode pub / sub", [])
    end,
    {noreply, S};

handle_info({tcp, Socket, Str}, S = #state{socket=Socket, state={mode_select}, mode=reqrep}) ->
    case line(Str) of
        "req" ->
            send(Socket, "Send anything to get message", []),
            gen_server:cast(self(), req);
        "rep" ->
            send(Socket, "You can send messages now", []),
            gen_server:cast(self(), rep);
        _ ->
            send(Socket, "Select mode req / rep", [])
    end,
    {noreply, S};

handle_info({tcp, Socket, Str}, S = #state{socket = Socket, state={messaging_rep}, id=ID, queue = Queue}) ->
    io:fwrite("Received message from ~s!~n", [ID]),
    Msg = #{
        to_bin("author") => to_bin(ID),
        to_bin("queue") => to_bin(Queue),
        to_bin("content")  => to_bin(Str)},
    gen_event:call(mongo_handler, mongo_event_handler, {insert, "messages", Msg}),
    send(Socket, "Message received!", []),
    {noreply, S};

handle_info({tcp, Socket, _}, S = #state{socket=Socket, state={messaging_req}, id=ID, queue = Queue}) ->
    Request = #{to_bin("queue") => to_bin(Queue)},
    io:fwrite("Request from ~s!~n", [ID]),
    {true, Response} = gen_event:call(mongo_handler, mongo_event_handler, {get_and_delete, "messages", Request}),
    #{ <<"value">> := Value} = Response,
    case Value of
        undefined ->
            send(Socket, "Queue is empty!", []);
        _ ->
            #{<<"content">> := Message} = Value,
            gen_event:call(mongo_handler, mongo_event_handler, {insert, "messages_archive", Value}),
            send(Socket, "~s", [binary_to_list(Message)])
    end,
    {noreply, S};

handle_info({tcp, Socket, Str}, S = #state{socket = Socket, state={messaging_pub}, id=ID, queue = Queue}) ->
    io:fwrite("Received message from ~s!~n", [ID]),
    Msg = #{
        to_bin("author") => to_bin(ID),
        to_bin("queue") => to_bin(Queue),
        to_bin("content")  => to_bin(Str)},
    gen_event:call(mongo_handler, mongo_event_handler, {insert, "messages_archive", Msg}),
    gen_event:notify(subscription_handler, {notify_subs, Str, Queue}),
    send(Socket, "Message received!", []),
    {noreply, S};

handle_info({tcp_closed, _Socket}, S = #state{state={messaging_sub}}) ->
    gen_event:notify(subscription_handler, {unregister_subscriber, self()}),
    {stop, normal, S};
handle_info({tcp_error, _Socket, _}, S = #state{state={messaging_sub}}) ->
    gen_event:notify(subscription_handler, {unregister_subscriber, self()}),
    {stop, normal, S};

handle_info({notify, {subscription, Message, Queue}}, S = #state{socket=Socket, state={messaging_sub}, queue = Queue}) ->
    io:fwrite("Received subscribed message ~s!~n", [Message]),
    send(Socket, "~s", [Message]),
    {noreply, S};

handle_info({tcp_closed, _Socket}, S) ->
    {stop, normal, S};
handle_info({tcp_error, _Socket, _}, S) ->
    {stop, normal, S};

handle_info(E, S) ->
    io:format("unexpected: ~p~n", [E]),
    {noreply, S}.

%% Utils
send(Socket, Str, Args) ->
    ok = gen_tcp:send(Socket, io_lib:format(Str++"~n", Args)),
    ok = inet:setopts(Socket, [{active, once}]),
    ok.

to_bin(Elem) ->
    erlmq_utils:to_bin(Elem).

line(Str) ->
    hd(string:tokens(Str, "\r\n ")).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(normal, _State) ->
    ok;

terminate(_Reason, _State) ->
    io:format("terminate reason: ~p~n", [_Reason]).
