%% CSCI182E - Distributed Systems
%% Harvey Mudd College
%% Dynamic Dining Philosophers
%% @author Tum Chaturapruek, Patrick Lu, Cory Pruce
%% @doc Think, hungry, and eat.
-module(philosopher).

%% ====================================================================
%%                             Public API
%% ====================================================================
-export([main/1]).

%% ====================================================================
%%                             Constants
%% ====================================================================
-define(TIMEOUT, 10000).


%% ====================================================================
%%                            Main Function
%% ====================================================================
% The main/1 function.
main(Params) ->
    try 
        % The first parameter is destination node name
        %  It is a lowercase ASCII string with no periods or @ signs in it.
        NodeName = list_to_atom(hd(Params)),

        % 0 or more additional parameters, each of which is the Erlang node
        % name of a neighbor of the philosopher.
        Neighbors = tl(Params),

        %% IMPORTANT: Start the empd daemon!
        os:cmd("epmd -daemon"),

        % format microseconds of timestamp to get an 
        % effectively-unique node name
        {_, _, Micro} = os:timestamp(),
        net_kernel:start([list_to_atom("diningphisolophers" ++
            integer_to_list(Micro)), shortnames]),

        register(philosopher, self()),

        Ref = make_ref(), % make a ref so I know I got a valid response back
        philosophize(Ref, joining, NodeName, Neighbors)

        % PROTOCOL

        % {ref, eating} - sent by a philosopher
        % {ref, gone} - sent by a philosopher

        % {pid, ref, become_hungry} - sent by a controller to a philosopher
        % {pid, ref, stop_eating} - sent by a controller to a philosopher.
        % {pid, ref, leave} - sent by a controller to a philosopher.
    catch
        _:_ -> print("Error parsing command line parameters or resolving node name.~n")
    end,
    halt().

%% im pretty sure that the message passing should be the other way around since 
%%we are only writing the philosophers' code and not the external controller's. 
%%Was the infinite_loop intended to be a test controller? Also, should we keep using NewRef or just use NewRef for eating?

philosophize(Ref, joining, Node, Neighbors)->
	print("joining"),
	%philosophize(Ref, thinking, Node, Neighbors);
    requestJoin(Ref, Node, Neighbors),
    philosophize(Ref, thinking, Node, Neighbors).

%requests each neighbor to join the network, one at a time,
%when joining there shouldn't be any other requests for forks or leaving going on
requestJoin(_,_,[])-> ok;
requestJoin(Ref, Node, Neighbors)->
    try
        io:format("Process ~p at node ~p sending request to ~n~s", 
            [self(), Node, hd(Neighbors)]),
        io:format("After~n"),
        {list_to_atom(hd(Neighbors)), Node} ! {self(), Ref, requestJoin},
        receive
            {Ref, ok} -> 
                io:format("Got reply (from ~p): ok!", 
                          [Ref);
            Reply -> 
                io:format("Got unexpected message: ~p~n", [Reply])
        after ?TIMEOUT -> io:format("Timed out waiting for reply!")
        end,
        requestJoin(Ref, Node, tl(Neighbors))
    catch
        _:_ -> io:format("Error getting joining permission.~n")
    end.

philosophize(Ref, thinking, Node, Neighbors, ForksList)->
	receive
	   {self(), NewRef, leave} ->
           print("leaving"),
           philosophize(NewRef, leaving, Node, Neighbors);
	   {self(), NewRef, become_hungry} ->
		   print("becoming hungry"),
		   philosophize(NewRef, hungry, Node, Neighbors)
	after ?TIMEOUT -> print("Timed out waiting for reply!")
	end;
philosophize(Ref, hungry, Node, Neighbors)->
	receive
	    {self(), NewRef, leave} ->
		    print("leaving"),
		    philosophize(NewRef, leaving, Node, Neighbors);	
	%   {self(), NewRef, Fork} ->  AND/OR CHECK IF ALL NEIGHBORS ARE NOT EATING?
		%print("got fork"),
		% check if has all forks
		% continue with philosophize(NewRef, 
	    
	%end;

	% want to receive all forks and then start eating
	{controller, Node} ! {NewRef, eating},
	print("eating"),
	philosophize(Ref, eating, Node, Neighbors)
	end;
philosophize(Ref, eating, Node, Neighbors)->
	receive
	   {self(), NewRef, stop_eating} ->
		% handle forks and hygenity if doing that
		print("stopping eating"),
		philosophize(NewRef, thinking, Node, Neighbors);
	   {self(), NewRef, leave} ->
		print("stopping eating and leaving"),
		%get rid of forks
		philosophize(NewRef, leaving, Node, Neighbors)
   	after ?TIMEOUT -> print("Timed out waiting for reply!")
	end; 
philosophize(Ref, leaving, Node, Neighbors)->
	{controller, Node} ! {Ref, gone}.

%infinite_loop(Ref, Nodel, Neighbors) ->
%    {spelling, Node} ! {self(), Ref, become_hungry},
    % {spelling, Node} ! {self(), Ref, stop_eating},
    % {spelling, Node} ! {self(), Ref, leave},
%    receive
%        {Ref, eating} ->
%        print("~p is eating.~n", [Ref]);
%        {Ref, gone} ->
%        print("~p is gone.~n", [Ref]);
%        Reply ->
%        print("Got unexpected message: ~p~n", [Reply])
%        after ?TIMEOUT -> print("Timed out waiting for reply!")
%    end,
%    infinite_loop(Ref, Nodel, Neighbors)
%end.

%% ====================================================================
%%                        Utility Functions
%% ====================================================================
% Below are helper functions for timestamp handling and printing with
% timestamp.
get_two_digit_list(Number) ->
    if Number < 10 ->
           ["0"] ++ integer_to_list(Number);
       true ->
           integer_to_list(Number)
    end.

get_three_digit_list(Number) ->
    if Number < 10 ->
           ["00"] ++ integer_to_list(Number);
       Number < 100 ->
           ["0"] ++ integer_to_list(Number);
       true ->
           integer_to_list(Number)
    end.

get_formatted_time() ->
    {MegaSecs, Secs, MicroSecs} = now(),
    {{Year, Month, Date},{Hour, Minute, Second}} =
        calendar:now_to_local_time({MegaSecs, Secs, MicroSecs}),
    integer_to_list(Year) ++ ["-"] ++
    get_two_digit_list(Month) ++ ["-"] ++
    get_two_digit_list(Date) ++ [" "] ++
    get_two_digit_list(Hour) ++ [":"] ++
    get_two_digit_list(Minute) ++ [":"] ++
    get_two_digit_list(Second) ++ ["."] ++
    get_three_digit_list(MicroSecs div 1000).

% print/1
% includes system time.
print(To_Print) ->
    io:format(get_formatted_time() ++ ": " ++ To_Print ++ "~n").

% print/2
print(To_Print, Options) ->
    io:format(get_formatted_time() ++ ": " ++ To_Print, Options ++ "~n").
    
