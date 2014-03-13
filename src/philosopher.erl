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
    io:format("~p Sending the fork to ~p~n",[now(), hd(Requests)]),
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
            {ok, [{0,_}]} -> io:format("~p Don't have all forks~n", [now()]),
                          false;
            {ok, [{1,_}]} -> haveAllForks(tl(Neighbors), ForksList)
        end.

%requests each neighbor to join the network, one at a time,
%when joining there shouldn't be any other requests for forks or leaving going on
%If another process requests to join during the joining phase, hold onto it until
%successfully joined and then handle it using the erlang mailbox.
requestJoin([], ForksList)-> ForksList;
requestJoin(Neighbors, ForksList)->
        io:format("~p Process ~p at node ~p sending request to ~s~n", 
            [now(), self(), node(), hd(Neighbors)]),
        {philosopher, hd(Neighbors)} ! {node(), requestJoin},
        receive
            {Node, ok} -> 
                io:format("!~p Got reply (from ~p): ok!~n", [now(), Node]),
                ForkList = dict:append(Node, {0, "SPAGHETTI SAUCE"}, ForksList),
                requestJoin(tl(Neighbors), ForkList)
        end.

%% im pretty sure that the message passing should be the other way around since 
%%we are only writing the philosophers' code and not the external controller's. 
%%Was the infinite_loop intended to be a test controller? Also, should we keep using NewRef or just use NewRef for eating?
requestForks([],_) -> io:format("~p No more neighbors to request ~n", [now()]);
requestForks(Neighbors, ForksList)->
        %See if we have the fork from this edge
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork if 0
            {ok,[{0,_}]} -> io:format("~p Requesting fork~n", [now()]),
                          {philosopher, hd(Neighbors)} ! {node(), requestFork};
            {ok,[{1,_}]} -> ok
        end,
        requestForks(tl(Neighbors), ForksList).

% This is the joining state, initially the process will try to join
% by getting acknowledgement from all its neighors. Only when it has
% acknowledgement can it transition to thinking
philosophize(joining, Neighbors, ForkList)->
  io:format("~p Joining~n", [now()]),
  %philosophize(Ref, thinking, Neighbors);
    ForksList = requestJoin(Neighbors, ForkList),
    io:format("~p Requested to join everybody~n", [now()]),
    %now we start thinking
    philosophize(thinking, Neighbors, ForksList);


%When thinking, we can be told to leave, to become hungry,
%or get request for a fork
philosophize(thinking, Neighbors, ForksList)->
  io:format("~p Thinking~n", [now()]),
    receive
      % Told by exteranl controller to leave
     {NewNode, leaving} -> 
            io:format("~p ~p left, removing him from lists", [now(), NewNode]),
            NewNeighbors = lists:delete(NewNode, Neighbors),
            NewForkList = dict:erase(NewNode, ForksList),
            philosophize(thinking, NewNeighbors, NewForkList);
      % Told by another philosopher that he's leaving
     {Pid, NewRef, leave} ->
           io:format("~p Leaving~n", [now()]),
           philosophize(leaving, Neighbors, ForksList, Pid, NewRef);
     % Told to become hungry
     {Pid, NewRef, become_hungry} ->
           io:format("~p becoming hungry~n", [now()]),
           %Send fork requests to everyone
           requestForks(Neighbors, ForksList),
           io:format("~p Sent requests for forks~n", [now()]),
           case (haveAllForks(Neighbors, ForksList)) of
              true -> Pid ! {NewRef, eating},
                    io:format("~p Have all forks!~n", [now()]),
                    philosophize(eating, Neighbors, ForksList, []);
              false -> io:format("~p Don't have all forks :(~n", [now()]),
                    philosophize(hungry, Neighbors, ForksList, [], Pid, NewRef)
           end;
      % Another process requests to join
    {NewNode, requestJoin} ->
           io:format("~p~p requested to Join, accepting~n",[now(), NewNode]),
           NewNeighbors = lists:append(Neighbors, [NewNode]),
           ForkList = dict:append(NewNode, {1, "DIRTY"}, ForksList),
           {philosopher, NewNode} ! {node(), ok},
           philosophize(thinking, NewNeighbors, ForkList);
        % We get a request for a fork, which we send since we don't need it       
       {NewNode, requestFork} ->
           io:format("~p sending fork to ~p~n",[now(), NewNode]),
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
    io:format("~p eating!~n", [now()]),
    receive
      % Told by exteranl controller to leave
        {NewNode, leaving} -> 
            io:format("~p ~p left, removing him from lists~n", [now(), NewNode]),
            NewNeighbors = lists:delete(NewNode, Neighbors),
            NewForkList = dict:erase(NewNode, ForksList),
            philosophize(eating, NewNeighbors, NewForkList, Requests);
       % Told by another philosopher that he's leaving
       {Pid, NewRef, leave} ->
           io:format("~p leaving~n", [now()]),
           philosophize(leaving,Neighbors, ForksList, Pid, NewRef);
        % Told by external controller to stop eating
       {Pid, NewRef, stop_eating} ->
           io:format("~p stopped_eating~n", [now()]),
           %send the forks to the processes that wanted them
           ForkList = sendForks(Requests, ForksList),
           Pid ! {NewRef, fork},
           philosophize(thinking, Neighbors, ForkList);
       % Another process requests to join 
       % Handle when another process wants to join us
       {NewNode, requestJoin} ->
            io:format("~p~p requested to join~n",[now(), NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            NewRequests = lists:append(Neighbors, [NewNode]),
            ForkList = dict:append(NewNode, {1, "DIRTY"}, ForksList),
            {philosopher, NewNode} ! {node(), ok},
            philosophize(eating, Neighbors, ForkList, NewRequests)
    end.
% Is hungry, already requested all the forks 
philosophize(hungry, Neighbors, ForksList, RequestList, Pid, Ref)->   
    io:format("~p Hungry, waiting for forks~n", [now()]),
    receive
    %Get the fork from the other process
        {NewPid, NewRef, leave} ->
           io:format("~p Leaving~n", [now()]),
           philosophize(leaving, Neighbors, ForksList, NewPid, NewRef);
        {NewNode, leaving} -> 
            io:format("~p~p left, removing him from lists~n", [now(), NewNode]),
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
            io:format("~p Got fork from ~p~n",[now(), NewNode]),
            ForkList = dict:erase(NewNode, ForksList),
            NewForkList = dict:append(NewNode, {1, "CLEAN"}, ForkList),
            case (haveAllForks(Neighbors, NewForkList)) of
              true -> Pid ! {Ref, eating},
                    philosophize(eating, Neighbors, NewForkList, RequestList);
              false -> philosophize(hungry, Neighbors, NewForkList, RequestList, Pid, Ref)
            end;
        % Another process joins, create the fork and give acknowledgement
        {NewNode, requestJoin} ->
            io:format("~p~p requested to join~n",[now(), NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            dict:append(NewNode, [1, "DIRTY"], ForksList),
            {philosopher, NewNode} ! {node(), ok};
            % if someone requests a fork
        % Check the priority and give the fork only if they have
        % higher priority
        {NewNode, requestFork} -> 
            io:format("~p requested the fork~n",[NewNode]),
            case (dict:find(NewNode, ForksList)) of
            %Check status
            {ok, [{1, "CLEAN"}]} -> io:format("~p My fork!, but I'll remember you wanted it~n", [now()]),
                                RequestsList = lists:append(RequestList, [NewNode]),
                                philosophize(hungry, Neighbors, ForksList, RequestsList, Pid, Ref);
            {ok, [{1, "DIRTY"}]} -> io:format("~p~p Fine, I give it up~n",[now(), NewNode]),
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
    io:format("~p I'm gone forever!~n", [now()]),
    halt();
philosophize(leaving, Neighbors, ForksList, Pid, Ref) -> 
    {philosopher, hd(Neighbors)} ! {node(), leaving},
    philosophize(leaving, tl(Neighbors), ForksList, Pid, Ref).

    
