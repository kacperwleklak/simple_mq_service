-module(erlmq_utils).
-author("kacper").

%% API
-export([to_bin/1]).

to_bin(T) when is_tuple(T) ->
    list_to_tuple(lists:map(fun to_bin/1, tuple_to_list(T)));
to_bin([H | _] = L) when is_tuple(H) ->
    lists:map(fun to_bin/1, L);
to_bin(L) when is_list(L) ->
    list_to_binary(L);
to_bin(B) -> B.
