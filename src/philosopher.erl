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
        Neighbors = tl(Params),

        %% IMPORTANT: Start the empd daemon!
        os:cmd("epmd -daemon"),

        % format microseconds of timestamp to get an 
        % effectively-unique node name
        {_, _, Micro} = os:timestamp(),
        net_kernel:start([list_to_atom(NodeName), shortnames]),

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

% Check to see if a process has all the forks
% it needs to eat
haveAllForks([],_) -> io:format("DONE~n"),
                      true;
haveAllForks(Neighbors, ForksList) ->
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork
            {ok, [[0,_]]} -> io:format("Don't have all forks~n"),
                          false;
            {ok, [[1,_]]} -> io:format("Already Have Fork~n"),
                          haveAllForks(tl(Neighbors), ForksList)
        end.

%requests each neighbor to join the network, one at a time,
%when joining there shouldn't be any other requests for forks or leaving going on
%If another process requests to join during the joining phase, hold onto it until
%successfully joined and return it
requestJoin([], ForksList)-> ForksList;
requestJoin(Neighbors, ForksList)->
        io:format("Process ~p at node ~p sending request to ~n~s", 
            [self(), node(), hd(Neighbors)]),
        io:format("After~n"),
        {philosopher, list_to_atom(hd(Neighbors))} ! {node(), requestJoin},
        receive
            {Node, ok} -> 
                io:format("Got reply (from ~p): ok!", [Node]),
                dict:append(Node, [0, "SPAGHETTI SAUCE"], ForksList),
                requestJoin(tl(Neighbors), ForksList)
        end.

%% im pretty sure that the message passing should be the other way around since 
%%we are only writing the philosophers' code and not the external controller's. 
%%Was the infinite_loop intended to be a test controller? Also, should we keep using NewRef or just use NewRef for eating?
requestForks([],_) -> io:format("No more neighbors ~n");
requestForks(Neighbors, ForksList)->
        io:format("Checking for neighbor ~n"),
        %See if we have the fork from this edge
        case (dict:find(hd(Neighbors), ForksList)) of
            %Request the fork
            {ok, [[0,_]]} -> io:format("Requesting fork~n"),
                          {philosopher, list_to_atom(hd(Neighbors))} ! {node(), requestFork};
            {ok, [[1,_]]} -> io:format("Already Have Fork~n")
        end,
        requestForks(tl(Neighbors), ForksList).

philosophize(joining, Node, Neighbors, ForkList)->
  io:format("joining~n"),
  %philosophize(Ref, thinking, Node, Neighbors);
    ForksList = requestJoin(Neighbors, ForkList),
    io:format("Requested to join everybody~n"),
    %now we start thinking
    philosophize(thinking, Node, Neighbors, ForksList);


%When thinking, we can be told to leave, to become hungry,
%or get request for a fork
philosophize(thinking, Node, Neighbors, ForksList)->
  io:format("Thinking~n"),
    receive
     {Pid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(leaving, Node, Neighbors, ForksList),
           Pid ! {NewRef, gone};
     {Pid, NewRef, become_hungry} ->
           io:format("becoming hungry"),
           %Send fork requests to everyone
           requestForks(Neighbors, ForksList),
           io:format("Send requests for forks~n"),
           case (haveAllForks(Neighbors, ForksList)) of
              true -> Pid ! {NewRef, eating},
                    io:format("Have all forks!~n"),
                    philosophize(eating, Node, Neighbors, ForksList, []);
              false -> io:format("Don't have all forks :(~n"),
                    philosophize(hungry, Node, Neighbors, ForksList, [], Pid, NewRef)
           end;
    {NewNode, requestJoin} ->
           io:format("~p requested to Join, accepting~n",[NewNode]),
           NewNeighbors = lists:append(Neighbors, [NewNode]),
           ForkList = dict:append(NewNode, [1, "DIRTY"], ForksList),
           {philosopher, NewNode} ! {Node, ok},
           philosophize(thinking, Node, NewNeighbors, ForkList);
           %%%
       {NewNode, requestFork} ->
           io:format("sending fork"),
           %delete the fork from the list send message
           ForkList = dict:erase(NewNode, ForksList),
           NewForkList = dict:append(NewNode, [0, "DIRTY"], ForkList),
           {philosopher, NewNode} ! {Node, fork},
           philosophize(thinking, Node, Neighbors, NewForkList)
  end.

philosophize(eating, Node, Neighbors, ForksList, Requests)->
    io:format("eating!~n"),
    receive
       {Pid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(leaving, Node, Neighbors, ForksList);
       {Pid, NewRef, stop_eating} ->
           io:format("stopped_eating"),
           %send the forks to the processes that wanted them
           {Pid, NewRef} ! {self(), Node, fork};
       {NewNode, requestJoin} ->
            io:format("~p requested to join~n",[NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            NewRequests = lists:append(Neighbors, [NewNode]),
            ForkList = dict:append(NewNode, [1, "DIRTY"], ForksList),
            {philosopher, NewNode} ! {Node, ok},
            philosophize(eating, Node, Neighbors, ForkList, NewRequests)
    end.



philosophize(hungry, Node, Neighbors, ForksList, RequestList, Pid, Ref)->   
    io:format("Hungry, waiting for forks~n"),
    receive
    %Get the fork from the other process
        {NewPid, NewRef, leave} ->
           io:format("leaving"),
           philosophize(leaving, Node, Neighbors, ForksList, NewPid, NewRef);
        {NewNode, fork} -> 
            io:format("Got fork from ~p~n",[NewNode]),
            dict:erase(NewNode, ForksList),
            dict:append(NewNode, [1, "CLEAN"], ForksList),
            case (haveAllForks(Neighbors, ForksList)) of
              true -> Pid ! {Ref, eating},
                    philosophize(eating, Node, Neighbors, ForksList);
              false -> philosophize(hungry, Node, Neighbors, ForksList)
            end;
        {NewNode, requestJoin} ->
            io:format("~p requested to join~n",[NewNode]),
            %if we get a join request, just create the fork and give acknowledgement
            dict:append(NewNode, [1, "DIRTY"], ForksList),
            {philosopher, NewNode} ! {node(), ok};
            % if someone requests a fork
        {NewNode, requestFork} -> 
            io:format("~p requested the fork~n",[NewNode]),
            case (dict:find(NewNode, ForksList)) of
            %Request the fork
            {ok, [1, "CLEAN"]} -> io:format("My fork!, but I'll remember you wanted it somehow~n"),
                                lists:append(RequestList, [NewNode]);
            {ok, [1, "DIRTY"]} -> io:format("~p Fine, I give it up~n",[NewNode]),
                          dict:erase(NewNode, ForksList),
                          dict:append(NewNode, [0, "CLEAN"], ForksList),
                          {philosopher, NewNode} ! {Node, requestFork}
            end
      end,
    philosophize(hungry, Node, Neighbors, ForksList, RequestList, Pid, Ref).

philosophize(leaving, Node, [], ForksList, Pid, Ref) -> Pid ! {Ref, gone};
philosophize(leaving, Node, Neighbors, ForksList, Pid, Ref) -> 
    {philosopher, list_to_atom(hd(Neighbors))} ! {node(), leaving},
    philosophize(leaving, Node, tl(Neighbors), ForksList, Pid, Ref).
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
    
