-module(erlmq_sub_handler).
-behaviour(gen_event).

%% API
-export([init/1, handle_event/2, handle_call/2, handle_info/2, code_change/3,
    terminate/2]).

-record(state, {
    subscribers
}).

init([]) ->
    io:fwrite("Subscribers handler started!~n", []),
    {ok, #state{subscribers = []}}.

%% Handle events
handle_event({register_subscriber, SubPid}, #state{subscribers = SubList}) ->
    io:fwrite("SubHandler - new subscriber registered: ~p!~n", [SubPid]),
    NewSubs = lists:append(SubList, [SubPid]),
    {ok, #state{subscribers=NewSubs}};
handle_event({unregister_subscriber, SubPid}, #state{subscribers = SubList}) ->
    io:fwrite("SubHandler - subscriber unregistered!~n", []),
    NewSubs = lists:delete(SubPid, SubList),
    {ok, #state{subscribers=NewSubs}};
handle_event({notify_subs, Message, Queue}, S = #state{subscribers = SubList}) ->
    io:fwrite("SubHandler - notifying all subs about message!~n", []),
    lists:foreach(fun(SubscriberPid) -> gen_event:notify(SubscriberPid, {subscription, Message, Queue}) end, SubList),
    {ok, S};
handle_event(_, State) ->
    io:fwrite("SubHandler - unknown message!~n", []),
    {ok, State}.

% Handle calls
handle_call({get_and_delete, Collection, Query}, State) ->
    Result = mongo_worker:get_and_delete(State, Collection, Query),
    {ok, Result, State};


handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
