-module(mongo_event_handler).
-behaviour(gen_event).

%% API
-export([init/1, handle_event/2, handle_call/2, handle_info/2, code_change/3,
    terminate/2]).

init([]) ->
    application:ensure_all_started(mongodb),
    io:fwrite("Mongo event handler started!~n", []),
    {ok, State} = mongo_worker:connect(),
    {ok, State}.

%% Handle events
handle_event({insert, Collection, Document}, State) ->
    io:fwrite("MongoEventHandler - notify, insert!~n", []),
    mongo_worker:insert(State, Collection, Document),
    {ok, State};
handle_event({get_one, Collection}, State) ->
    mongo_worker:get_one(State, Collection),
    {ok, State};
handle_event({delete, Collection, Selector}, State) ->
    mongo_worker:get_one(State, Collection, Selector),
    {ok, State};
handle_event(_, State) ->
    io:fwrite("MongoEventHandler - unknown msg!~n", []),
    {ok, State}.

% Handle calls
handle_call({insert, Collection, Document}, State) ->
    io:fwrite("MongoEventHandler - call, insert!~n", []),
    mongo_worker:insert(State, Collection, Document),
    {ok, ok, State};

handle_call({get_and_delete, Collection, Query}, State) ->
    Result = mongo_worker:get_and_delete(State, Collection, Query),
    {ok, Result, State};

handle_call({find_one, Collection, Query}, State) ->
    Result = mongo_worker:get_one(State, Collection, Query),
    {ok, Result, State};

handle_call({find, Collection, Query}, State) ->
    Result = mongo_worker:find(State, Collection, Query),
    {ok, Result, State};

handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
