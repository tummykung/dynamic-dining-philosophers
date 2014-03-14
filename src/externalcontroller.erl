%% CSCI182E - Distributed Systems
%% Harvey Mudd College
%% Dynamic Dining Philosophers
%% @author Tum Chaturapruek, Patrick Lu, Cory Pruce
%% @doc Think, hungry, and eat.
-module(externalcontroller).
      
%% ====================================================================
%%                             Public API
%% ====================================================================
-export([main/1]).
    
%% ====================================================================
%%                             Constants
%% ====================================================================

%% ====================================================================
%%                            Main Function
%% ====================================================================


main(Nodes) ->
	Philosophers = lists:map(fun(Node) -> list_to_atom(Node) end,
		Nodes),
	%% IMPORTANT: Start the empd daemon!
	os:cmd("epmd -daemon"),
	% format microseconds of timestamp to get an 
	% effectively-unique node name
	net_kernel:start([externalcontroller, shortnames]),
	register(externalcontroller, self()),
	control_loop(Philosophers),
	halt().

%control_loop([]) -> maybe handle a request to join?
control_loop(Philosophers) ->
