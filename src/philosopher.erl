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

%% ====================================================================
%%                            Main Function
%% ====================================================================
% The main/1 function.
main(Params) ->
    % try 
        % The first parameter is destination node name
        %  It is a lowercase ASCII string with no periods or @ signs in it.
        NodeName = hd(Params),

        % 0 or more additional parameters, each of which is the Erlang node
        % name of a neighbor of the philosopher.
        NeighborsList = tl(Params),
        Neighbors = lists:map(fun(Node) -> list_to_atom(Node) end, 
          NeighborsList), 
        %% IMPORTANT: Start the empd daemon!
        os:cmd("epmd -daemon"),

        % format microseconds of timestamp to get an 
        % effectively-unique node name
        net_kernel:start([list_to_atom(NodeName), shortnames]),

        register(philosopher, self()),

        %joining
        philosophize(joining, Neighbors, dict:new()),

    halt().


% This is a helper function to that sends forks to all
% processes in a list.
sendForks([], ForksList) -> ForksList;
sendForks(Requests, ForksList) ->
    print("Sending the fork to ~p~n", [hd(Requests)]),
    ForkList = dict:erase(hd(Requests), ForksList),
    NewForkList = dict:append(hd(Requests), {0, "SPAGHETTI"}, ForkList),
    {philosopher, hd(Requests)} ! {node(), fork},
    sendForks(tl(Requests), NewForkList).

% Check to see if a process has all the forks
% it needs to eat
haveAllForks([],_) -> true;
haveAllForks(Neighbors, ForksList) ->
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork
            {ok, [{0,_}]} -> print("Don't have all forks~n"),
                          false;
            {ok, [{1,_}]} -> haveAllForks(tl(Neighbors), ForksList)
        end.

% Constantly query neighbor philosophers to make sure that they are still
% there. If one is gone, delete fork to that philosopher and remove from 
% neighbors list, sufficiently removing the edge. Otherwise, keep
% philosophizing. 
% Code modified from http://stackoverflow.com/questions/9772357/monitoring-a-gen-server

check_neighbors([], _)-> ok;
check_neighbors([X|XS], ParentPid) ->
        io:format("dsgsgs~n"),
        spawn(?MODULE, monitor, [ParentPid, X]),
        io:format("hi~n"),
        check_neighbors(XS, ParentPid).

monitor(ParentPid, Philosopher) ->
    io:format("kkkkkk~n"),
    erlang:monitor(process,self()),
    io:format("ssssss~n"),
    receive
		{'DOWN', _Ref, process, _Pid,  normal} -> 
			ParentPid ! {self(), check, Philosopher};
		{'DOWN', _Ref, process, _Pid,  _Reason} ->
			ParentPid ! {self(), missing, Philosopher}
	end.


%check_neighbors([], Acc)-> Acc; 
%check_neighbors([X|Neighbors], Acc)->
%	io:format("~p Checking to see if Process ~p at node ~p is still philosohizing~n", [now(), node(), X]), 
%        {philosopher, X} ! {node(), stillAwake},
%	receive
%		{Node, ok} ->
%			io:format("~p Received reply from ~p~n", [now(), Node]),
%			check_neighbors(Neighbors, Acc++X)
%	after 5000 ->
%	        io:format("~p is no longer in the group~n", [X]),
%		check_neighbors(Neighbors, Acc)
%	end.

				
%requests each neighbor to join the network, one at a time,
%when joining there shouldn't be any other requests for forks or leaving going on
%If another process requests to join during the joining phase, hold onto it until
%successfully joined and then handle it using the erlang mailbox.
requestJoin([], ForksList)-> ForksList;
requestJoin(Neighbors, ForksList)->
        print("Process ~p at node ~p sending request to ~s~n", 
            [self(), node(), hd(Neighbors)]),
        {philosopher, hd(Neighbors)} ! {node(), requestJoin},
        receive
            {Node, ok} -> 
                print("!Got reply (from ~p): ok!~n", [Node]),
                ForkList = dict:append(Node, {0, "SPAGHETTI SAUCE"}, ForksList),
                requestJoin(tl(Neighbors), ForkList)
        end.

%% im pretty sure that the message passing should be the other way around since 
%%we are only writing the philosophers' code and not the external controller's. 
%%Was the infinite_loop intended to be a test controller? Also, should we keep using NewRef or just use NewRef for eating?
requestForks([],_) -> print("No more neighbors to request ~n");
requestForks(Neighbors, ForksList)->
        %See if we have the fork from this edge
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork if 0
            {ok,[{0,_}]} -> print("Requesting fork~n"),
                          {philosopher, hd(Neighbors)} ! {node(), requestFork};
            {ok,[{1,_}]} -> ok
        end,
        requestForks(tl(Neighbors), ForksList).

% This is the joining state, initially the process will try to join
% by getting acknowledgement from all its neighors. Only when it has
% acknowledgement can it transition to thinking
philosophize(joining, Neighbors, ForkList)->
  print("Joining~n"),
  %philosophize(Ref, thinking, Neighbors);
    ForksList = requestJoin(Neighbors, ForkList),
    print("Requested to join everybody~n"),
    %% spawn processes to monitor neighbors once joined
    check_neighbors(Neighbors, self()),
    %now we start thinking
    philosophize(thinking, Neighbors, ForksList);


%When thinking, we can be told to leave, to become hungry,
%or get request for a fork
philosophize(thinking, Neighbors, ForksList)->
  print("Thinking~n"),
  receive
      % Told by exteranl controller to leave
     {NewNode, leaving} -> 
            print("~p left, removing him from lists", [NewNode]),
            NewNeighbors = lists:delete(NewNode, Neighbors),
            NewForkList = dict:erase(NewNode, ForksList),
            philosophize(thinking, NewNeighbors, NewForkList);
      % Told by another philosopher that he's leaving
     {Pid, NewRef, leave} ->
           print("Leaving~n"),
           philosophize(leaving, Neighbors, ForksList, Pid, NewRef);
     % Told to become hungry
     {Pid, NewRef, become_hungry} ->
           print("becoming hungry~n"),
           %Send fork requests to everyone
           requestForks(Neighbors, ForksList),
           print("Sent requests for forks~n"),
           case (haveAllForks(Neighbors, ForksList)) of
              true -> Pid ! {NewRef, eating},
                    print("Have all forks!~n"),
                    philosophize(eating, Neighbors, ForksList, []);
              false -> print("Don't have all forks :(~n"),
                    philosophize(hungry, Neighbors, ForksList, [], Pid, NewRef)
           end;
      % Another process requests to join
    {NewNode, requestJoin} ->
           print("~p requested to Join, accepting~n",[NewNode]),
           NewNeighbors = lists:append(Neighbors, [NewNode]),
           ForkList = dict:append(NewNode, {1, "DIRTY"}, ForksList),
           {philosopher, NewNode} ! {node(), ok},
           philosophize(thinking, NewNeighbors, ForkList);
    % Another philosopher is checking if this philosopher is still running
    {Pid, missing, Who} ->
           io:format("~p has gone missing!~n",[Who]),
           NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
    % monitor alerting that a leaving philosopher has left
    {Pid, check, Who} ->
	   io:format("~p has left for sure, more SPAGHETTI for me!~n", [Who]),
	   NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
     % We get a request for a fork, which we send since we don't need it       
       {NewNode, requestFork} ->
           print("sending fork to ~p~n",[NewNode]),
           %delete the fork from the list send message
           ForkList = dict:erase(NewNode, ForksList),
           NewForkList = dict:append(NewNode, {0, "DIRTY"}, ForkList),
           {philosopher, NewNode} ! {node(), fork},
           philosophize(thinking, Neighbors, NewForkList)
  end.


% Eating phase, the philosopher has all the forks it needs from its neighbors,
% eventually exits back to thinking or leaving, requests are handled once told
% to stop eating
philosophize(eating, Neighbors, ForksList, Requests) ->
    print("eating!~n"),
    receive
      % Told by exteranl controller to leave
        {NewNode, leaving} -> 
            print("~p left, removing him from lists~n", [NewNode]),
            NewNeighbors = lists:delete(NewNode, Neighbors),
            NewForkList = dict:erase(NewNode, ForksList),
            philosophize(eating, NewNeighbors, NewForkList, Requests);
       % Told by another philosopher that he's leaving
       {Pid, NewRef, leave} ->
           print("leaving~n"),
           philosophize(leaving,Neighbors, ForksList, Pid, NewRef);
        % Told by external controller to stop eating
       {Pid, NewRef, stop_eating} ->
           print("stopped_eating~n"),
           %send the forks to the processes that wanted them
           ForkList = sendForks(Requests, ForksList),
           Pid ! {NewRef, fork},
           philosophize(thinking, Neighbors, ForkList);
      % Another philosopher is checking if this philosopher is still running
    {_Pid, missing, Who} ->
           io:format("~p has gone missing!~n",[Who]),
           NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
    % monitor alerting that a leaving philosopher has left
    {_Pid, check, Who} ->
	   io:format("~p has left for sure, more SPAGHETTI for me!~n", [Who]),
	   NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
    %Another process requests to join 
       % Handle when another process wants to join us
       {NewNode, requestJoin} ->
            print("~p requested to join~n",[NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            NewRequests = lists:append(Neighbors, [NewNode]),
            ForkList = dict:append(NewNode, {1, "DIRTY"}, ForksList),
            {philosopher, NewNode} ! {node(), ok},
            philosophize(eating, Neighbors, ForkList, NewRequests)
    end.
% Is hungry, already requested all the forks 
philosophize(hungry, Neighbors, ForksList, RequestList, Pid, Ref)->   
    print("Hungry, waiting for forks~n"),
    receive
    %Get the fork from the other process
        {NewPid, NewRef, leave} ->
           print("Leaving~n"),
           philosophize(leaving, Neighbors, ForksList, NewPid, NewRef);
        {NewNode, leaving} -> 
            print("~p left, removing him from lists~n", [NewNode]),
            NewNeighbors = lists:delete(NewNode, Neighbors),
            NewForkList = dict:erase(NewNode, ForksList),
            case (haveAllForks(NewNeighbors, NewForkList)) of
              true -> Pid ! {Ref, eating},
                    philosophize(eating, NewNeighbors, NewForkList, RequestList);
              false -> philosophize(hungry, NewNeighbors, NewForkList, RequestList, Pid, Ref)
            end;
        % Get a fork from a process, add it to the list and see if we have
        % all of them to eat
        {NewNode, fork} -> 
            print("Got fork from ~p~n",[NewNode]),
            ForkList = dict:erase(NewNode, ForksList),
            NewForkList = dict:append(NewNode, {1, "CLEAN"}, ForkList),
            case (haveAllForks(Neighbors, NewForkList)) of
              true -> Pid ! {Ref, eating},
                    philosophize(eating, Neighbors, NewForkList, RequestList);
              false -> philosophize(hungry, Neighbors, NewForkList, RequestList, Pid, Ref)
            end;
        % Another process joins, create the fork and give acknowledgement
        {NewNode, requestJoin} ->
            print("~p requested to join~n",[NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            dict:append(NewNode, [1, "DIRTY"], ForksList),
            {philosopher, NewNode} ! {node(), ok};
            % if someone requests a fork
         % Another philosopher is checking if this philosopher is still running
    	{Pid, missing, Who} ->
           io:format("~p has gone missing!~n",[Who]),
           NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
    % monitor alerting that a leaving philosopher has left
    	{Pid, check, Who} ->
	   io:format("~p has left for sure, more SPAGHETTI for me!~n", [Who]),
	   NewNeighbors = Neighbors -- [Who],
	   ForkList = dict:erase(Who, ForksList),
	   philosophize(thinking, NewNeighbors, ForkList);
 %% Check the priority and give the fork only if they have
        % higher priority
        {NewNode, requestFork} -> 
            print("~p requested the fork~n",[NewNode]),
            case (dict:find(NewNode, ForksList)) of
            %Check status
            {ok, [{1, "CLEAN"}]} -> print("My fork!, but I'll remember you wanted it~n"),
                                RequestsList = lists:append(RequestList, [NewNode]),
                                philosophize(hungry, Neighbors, ForksList, RequestsList, Pid, Ref);
            {ok, [{1, "DIRTY"}]} -> print("~p Fine, I give it up~n",[NewNode]),
                          ForkList = dict:erase(NewNode, ForksList),
                          NewForkList = dict:append(NewNode, [0, "SPAGHETTI SAUCE"], ForkList),
                          {philosopher, NewNode} ! {node(), fork},
                          philosophize(hungry, Neighbors, NewForkList, RequestList, Pid, Ref)
            end
      end,
    philosophize(hungry, Neighbors, ForksList, RequestList, Pid, Ref).


% Before leaving, the philosopher sends messages to all its neighbors
% telling them he's leaving and then leaves. Gone is not really a state,
% just alerts controller that he successfully left
philosophize(leaving, [], _, Pid, Ref) -> Pid ! {Ref, gone},
    print("I'm gone forever!~n"),
    halt();
philosophize(leaving, Neighbors, ForksList, Pid, Ref) -> 
    {philosopher, hd(Neighbors)} ! {node(), leaving},
    philosophize(leaving, tl(Neighbors), ForksList, Pid, Ref).


% Helper functions for timestamp handling.
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
  io:format(get_formatted_time() ++ ": " ++ To_Print).

% print/2
print(To_Print, Options) ->
  io:format(get_formatted_time() ++ ": " ++ To_Print, Options).
