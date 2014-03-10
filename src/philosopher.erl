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
    % try 
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
        net_kernel:start([list_to_atom(NodeNames), shortnames]),

        register(philosopher, self()),

        %joining
        philosophize(joining, NodeName, Neighbors, dict:new()),

        % PROTOCOL

        % {ref, eating} - sent by a philosopher
        % {ref, gone} - sent by a philosopher

        % {pid, ref, become_hungry} - sent by a controller to a philosopher
        % {pid, ref, stop_eating} - sent by a controller to a philosopher.
        % {pid, ref, leave} - sent by a controller to a philosopher.
    % catch
    %     _:_ -> print("Error parsing command line parameters or resolving node name.~n")
    % end,
    halt().

%requests each neighbor to join the network, one at a time,
%when joining there shouldn't be any other requests for forks or leaving going on
%If another process requests to join during the joining phase, hold onto it until
%successfully joined and return it
requestJoin([])-> ok;
requestJoin(Neighbors)->
    try
        io:format("Process ~p at node ~p sending request to ~n~s", 
            [self(), node(), hd(Neighbors)]),
        io:format("After~n"),
        {list_to_atom(hd(Neighbors)), Node} ! {node(), requestJoin},
        receive
            {Node, ok} -> 
                io:format("Got reply (from ~p): ok!", 
                          [Pid]),
                %{philosopher, Node} ! {ok},
                        requestJoin(Node, tl(Neighbors), Joiner);
        end,
    catch
        _:_ -> io:format("Error getting joining permission.~n")
    end.

%% im pretty sure that the message passing should be the other way around since 
%%we are only writing the philosophers' code and not the external controller's. 
%%Was the infinite_loop intended to be a test controller? Also, should we keep using NewRef or just use NewRef for eating?
requestForks([],ForksList) -> ForksList;
requestForks(Neighbors, ForksList)->
    try
        io:format("Checking for neighbor ~n"),
        %See if we have the fork from this edge
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork
            {ok, [0,_]} -> {philosopher, list_to_atom(hd(Neighbors))} ! {node(), requestFork},
            {ok, [1,_]} -> io:format("Already Have Fork"),
        end,
        requestJoin(Ref, Node, tl(Neighbors), ForksList); 
    catch
        _:_ -> io:format("Error getting joining permission.~n")
    end.

createForks([],ForkList,_) -> ForkList;
createForks(JoinRequests,ForkList,Ref) ->
    %create the fork and hold it
    dict:append(list_to_atom(hd(JoinRequests)), [1, "DIRTY"], ForkList),
    %tell the process that it has joined the network successfully
    {list_to_atom(hd(JoinRequests)), Ref} ! {self(), Ref, ok},
    createForks(tl(JoinRequests),ForkList, Ref).

philosophize(joining, Node, Neighbors, ForkList)->
	io:format("joining~n"),
	%philosophize(Ref, thinking, Node, Neighbors);
    requestJoin(Ref, Node, Neighbors, []),
    io:fomat("Requested to join everybody~n"),
    %create forks for people who requested join earlier
    NewForkList = createForks(JoinRequests, ForkList, Ref),
    %now we start thinking
    philosophize(Ref, thinking, Node, Neighbors, NewForkList);


%When thinking, we can be told to leave, to become hungry,
%or get request for a fork
philosophize(thinking, Node, Neighbors, ForksList)->
	io:format("Thinking~n"),
    receive
	   {Pid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(NewRef, leaving, Node, Neighbors, ForksList);
	   {Pid, NewRef, become_hungry} ->
           io:format("becoming hungry"),
           philosophize(NewRef, hungry, Node, Neighbors, ForksList);
       {Pid, NewRef, requestJoin} ->
           io:format("~p Requested to Join, accepting",[Pid]),
           dict:append(list_to_atom(Pid), [1, "DIRTY"], ForkList),
           philosophize(Ref, thinking, Node, Neighbors, ForksList);
           %%%
       {Pid, NewRef, requestFork} ->
           io:format("sending fork"),
           %delete the fork from the list send message
           dict:erase(list_to_atom(Pid), ForksList),
           dict:append(list_to_atom(Pid), [0, "DIRTY"], ForksList),

           {Pid, NewRef} ! {self(), Ref, fork}
	end,
    philosophize(Ref, thinking, Node, Neighbors, ForksList).

philosophize(Ref, hungry, Node, Neighbors, ForksList)->
    NewForksList = requestForks(Ref, Node, Neighbors, ForksList),
    receive
    %Get the fork from the other process
        {Node, fork} -> 
            dict:erase(Node, ForksList),
            dict:append(Node, [1, "CLEAN"], ForksList),
            requestForks(Node, tl(Neighbors), ForksList);
        {Node, requestJoin} ->
            %if we get a join request, just create the fork and give acknowledgement
            dict:erase(Node, ForksList),
            dict:append(Node, [1, "DIRTY"], ForksList),
            {philosopher, Node} ! {node(), ok};
            % if someone requests a fork
            end,
        requestJoin(Ref, Node, tl(Neighbors), ForksList);
    philosophize(Ref, eating, Node, Neighbors, ForksList);

philosophize(Ref, eating, Node, Neighbors, ForksList)->
    receive
       {pid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(NewRef, leaving, Node, Neighbors, ForksList);
       {pid, NewRef, stop_eating} ->
           io:format("sending fork"),
           %delete the fork from the list send message
           dict:erase(pid, ForksList),
           dict:append(pid, [0, "DIRTY"], ForksList),
           {pid, NewRef} ! {self(), Ref, fork};
    {pid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(NewRef, leaving, Node, Neighbors, ForksList)
    end.

	% want to receive all forks and then start eating
	%{controller, Node} ! {NewRef, eating},
	%print("eating"),
	%philosophize(Ref, eating, Node, Neighbors)
	%end;
%philosophize(Ref, eating, Node, Neighbors, ForksList)->
%	receive
%	   {self(), NewRef, stop_eating} ->
%		% handle forks and hygenity if doing that
%		print("stopping eating"),
%		philosophize(NewRef, thinking, Node, Neighbors);
%	   {self(), NewRef, leave} ->
%		print("stopping eating and leaving"),
%		%get rid of forks
%		philosophize(NewRef, leaving, Node, Neighbors)
%  	after ?TIMEOUT -> print("Timed out waiting for reply!")
%	end; 
%philosophize(Ref, leaving, Node, Neighbors, ForksList)->
%	{controller, Node} ! {Ref, gone}.

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
    
