# defmodule StateTest do
#   use ExUnit.Case
#   use PropCheck
#   use PropCheck.StateM

#   property "game state machine", [:verbose] do
#     forall cmds <- commands(__MODULE__) do

#       {history, state, result} = run_commands(__MODULE__, cmds)
#       cleanup(state.id)

#       (result == :ok)
#       |> aggregate(command_names(cmds))
#       |> when_fail(
#         IO.puts("""
#         History: #{inspect(history)}
#         State: #{inspect(state)}
#         Result: #{inspect(result)}
#         """)
#       )
#     end
#   end

#   def initial_state() do
#     game_id = MafiaEngine.GameSupervisor.start_game()
#     MafiaEngine.PubSub.sub(s.id, self())
#     %{
#       id: game_id,
#       phase: :initialized,
#       players: [],
#       alive: %{},
#       role: %{},
#       accusation: %{},
#       accusations: %{}, 
#       accused: "",
#       vote: %{}
#     }
#   end

#   def cleanup(id) do
#     MafiaEngine.GameSupervisor.stop_game(id)
#   end

#   def command(s) do
#     possible =
#       case s.phase do
#         :initialized ->
#           [{:call, MafiaEngine.Game, :add_player, [s.id, name()]},
#           {:call, MafiaEngine.Game, :remove_player, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :start_game, [s.id]}]
#         :morning ->
#           [{:call, MafiaEngine.Game, :next_phase, [s.id]}]
#         :accusation ->
#           [{:call, MafiaEngine.Game, :accuse, [s.id, name(s), name(s)]},
#           {:call, MafiaEngine.Game, :withdraw, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :next_phase, [s.id]}]
#         :defense ->
#           [{:call, MafiaEngine.Game, :next_phase, [s.id]}]
#         :judgement ->
#           [{:call, MafiaEngine.Game, :vote_innocent, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :vote_guilty, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :remove_vote, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :next_phase, [s.id]}]
#         :afternoon ->
#           [{:call, MafiaEngine.Game, :next_phase, [s.id]}]
#         :night ->
#           [{:call, MafiaEngine.Game, :select, [s.id, name(s), name(s)]},
#           {:call, MafiaEngine.Game, :unselect, [s.id, name(s)]},
#           {:call, MafiaEngine.Game, :next_phase, [s.id]}]
#       end
#     oneof(possible)
#   end

#   # Preconditions

#   def precondition(s, {:call, _, :add_player, [_, name]}) do
#     not Enum.member?(s.players, name)
#   end

#   def precondition(s, {:call, _, :start_game, _}) do 
#     length(s.players) > 3
#   end

#   def precondition(s, {:call, _, :accuse, [_, accuser, accused]}) do
#     s.alive[accuser] && s.alive[accused] &&  not Map.has_key?(s.accusation, accuser)
#   end

#   def precondition(s, {:call, _, :withdraw, [_, accuser]}) do
#     Map.has_key?(s.accusation, accuser)
#   end

#   def precondition(s, {:call, _, :vote_innocent, [_, voter]}) do
#     s.alive[voter] && voter != s.accused
#   end

#   def precondition(s, {:call, _, :vote_guilty, [_, voter]}) do
#     s.alive[voter] && voter != s.accused
#   end

#   def precondition(s, {:call, _, :remove_vote, [_, voter]}) do
#     Map.has_key?(s.vote, voter)
#   end

#   def precondition(s, {:call, _, :select, [_, actor, target]}) do
#     s.alive[actor]
#     && s.alive[target]
#     && s.role[actor] != :townie
#     && not (s.role[actor] == :mafioso and s.role[target] == :mafioso)
#   end

#   def precondition(s, {:call, _, :unselect, [_, actor]}) do
#     Map.has_key?(s.action, actor)
#   end

#   #No precondition: remove_player, next_phase
#   def precondition(_, _), do: true


#   # Postconditions

#   # def postcondition(s, {:call, _, :add_player, [_, name]}) do
    
#   # end
#   # def postcondition(s, {:call, _, :remove_player, [s.id, name()]})
#   # def postcondition(s, {:call, _, :start_game, [s.id]})
#   # def postcondition(s, {:call, _, :accuse, [s.id, name(), name()]})
#   # def postcondition(s, {:call, _, :withdraw, [s.id, name()]},)
#   # def postcondition(s, {:call, _, :vote_innocent, [s.id, name()]})
#   # def postcondition(s, {:call, _, :vote_guilty, [s.id, name()]})
#   # def postcondition(s, {:call, _, :remove_vote, [s.id, name()]})
#   # def postcondition(s, {:call, _, :select, [s.id, name(), name()]})
#   # def postcondition(s, {:call, _, :unselect, [s.id, name()]})
#   # def postcondition(s, {:call, _, :next_phase, [s.id]})

#   def next_state(s, _, {:call, _, :add_player, [_, name]}) do
#     MafiaEngine.PubSub.sub(s.id, name)
#     %{s | players: [name | s.players]}
#   end

#   def next_state(s, {:call, _, :remove_player, [_, name]}) do
#     MafiaEngine.PubSub.unsub_player(s.id, name)
#     %{s | players: List.delete(s.players, name)}
#   end

#   def next_state(s, _, {:call, _, :start_game, _}) do
#     role =
#       Enum.reduce(
#         s.players,
#         %{},
#         fn name, role ->
#           receive do
#             {:player_update, :role, {n, role}} when n == name -> Map.put(role, name, role)
#           after
#             1_000 -> raise "No role for #{name} received"
#           end
#         end
#       )
    
#     %{s |
#       role: role
#       alive: Enum.reduce(s.players, %{},&(Map.put(&2, &1, true))),
#       phase: :afternoon
#     }
#   end

#   def next_state(s, _, {:call, _, :accuse, [_, accuser, accused]}) do
#     if accused?(s, accused) do
#       %{s |
#         accused: accused,
#         phase: :defense
#       }
#     else
#       %{s |
#         accusation: Map.put(s.accusation, accuser, accused)
#         accusations: Map.put(s.accusations, accused, s.accusations.accused + 1)
#       }
#     end
#   end

#   def next_state(s, _, {:call, _, :withdraw, [_, accuser]}) do
#     accused = s.accusation[accuser]
#     %{s |
#       accusation: Map.delete(s.accusation, accuser)
#       accusations: Map.put(s.accusations, accused, s.accusations.accused - 1)
#     }
#   end

#   def next_state(s, _, {:call, _, :vote_innocent, [_, voter]}) do
#     %{s |
#       vote: Map.put(s.vote, voter, :innocent)
#     }
#   end

#   def next_state(s, _, {:call, _, :vote_guilty, [_, voter]}) do
#     %{s |
#       vote: Map.put(s.vote, voter, :guilty)
#     }
#   end

#   def next_state(s, _, {:call, _, :remove_vote, [_, name]}) do
#     %{s |
#       vote: Map.delete(s.vote, voter)
#     }
#   end

#   def next_state(s, _, {:call, _, :select, [_, actor, target]}) do
#     %{s |
#       action: Map.put(s.action, actor, target)
#     }
#   end
  
#   def next_state(s, _, {:call, _, :unselect, [_, actor]}) do
#     %{s |
#       action: Map.delete(s.action, actor)
#     }
#   end

#     :morning ->

#     :accusation ->

#     :defense ->

#     :judgement ->

#     :afternoon ->

#     :night ->

#   def next_state(%{phase: :morning} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :accusation,
#       accusation: %{},
#       accusations: %{}, 
#       accused: "",
#     }
#   end

#   def next_state(%{phase: :accusation} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :afternoon,
#     }
#   end    }
#   end

#   def next_state(%{phase: :accusation} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :afternoon,
#     }
#   end

#   def next_state(%{phase: :defense} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :judgement,
#     }
#   end

#   def next_state(%{phase: :judgement} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :afternoon,
#     }
#   end



#   def next_state(%{phase: :defense} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :judgement,
#     }
#   end

#   #def next_state(%{phase: :judgement} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :afternoon,
#     }
#   end

#   def next_state(%{phase: :afternoon} = s, {:call, _, :next_phase, _}) do
#     %{s |
#       phase: :night,
#     }
#   end

#   def accused?(s, accused) do
#     (s.accusations.accused + 1) * 2 > length(s.players)
#   end

#   def name() do
#     elements(
#       ["Jeff",
#       "Britta",
#       "Abed",
#       "Shirley",
#       "Annie",
#       "Troy",
#       "Pierce",
#       "Ben",
#       "Craig",
#       "Magnitude",
#       "Ian Duncan",
#       "Buzz Hickey",
#       "Frankie",
#       "Star-Burns",
#       "Leonard",
#       "Vaughn",
#       "Neil",
#       "Garrett",
#       "Elroy"]
#     )
#   end

# end