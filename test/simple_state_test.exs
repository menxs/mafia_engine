defmodule StateTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM

  property "game state machine", [:verbose] do
    forall cmds <- commands(__MODULE__, initial_state()) do

      {history, state, result} = run_commands(__MODULE__, cmds)
      (result == :ok)
      |> aggregate(command_names(cmds))
      |> when_fail(
        IO.puts("""
        History: #{inspect(history)}
        State: #{inspect(state)}
        Result: #{inspect(result)}
        """)
      )
    end
  end

  def initial_state() do
    game_id = MafiaEngine.GameSupervisor.start_game()
    %{
      id: game_id,
      phase: :initialized,
      players: [],
      alive: %{},
      role: %{},
      accusation: %{},
      accusations: %{}, 
      accused: "",
      action: %{},
      vote: %{}
    }
  end

  # Command generation

  def command(%{phase: :initialized} = s), do:
    oneof([{:call, MafiaEngine.Game, :add_player, [s.id, name()]},
           {:call, MafiaEngine.Game, :start_game, [s.id]}])

  def command(%{phase: :morning} = s), do:
    {:call, MafiaEngine.Game, :next_phase, [s.id]}

  def command(%{phase: :accusation} = s), do:
    oneof([{:call, MafiaEngine.Game, :accuse, [s.id, name(s), name(s)]},
           {:call, MafiaEngine.Game, :next_phase, [s.id]}])

  def command(%{phase: :defense} = s), do:
    {:call, MafiaEngine.Game, :next_phase, [s.id]}

  def command(%{phase: :judgement} = s), do:
    oneof([{:call, MafiaEngine.Game, :vote_innocent, [s.id, name(s)]},
           {:call, MafiaEngine.Game, :vote_guilty, [s.id, name(s)]},
           {:call, MafiaEngine.Game, :next_phase, [s.id]}])

  def command(%{phase: :afternoon} = s), do:
    {:call, MafiaEngine.Game, :next_phase, [s.id]}

  def command(%{phase: :night} = s), do:
    oneof([{:call, MafiaEngine.Game, :select, [s.id, name(s), name(s)]},
           {:call, MafiaEngine.Game, :next_phase, [s.id]}])


  # Preconditions

  def precondition(s, {:call, _, :add_player, [_, name]}) do
    not Enum.member?(s.players, name)
  end

  def precondition(s, {:call, _, :start_game, _}) do 
    length(s.players) > 3
  end

  def precondition(s, {:call, _, :accuse, [_, accuser, accused]}) do
    not has_accused?(s, accuser)
    && alive?(s, accuser)
    && alive?(s, accused)
  end

  def precondition(s, {:call, _, :vote_innocent, [_, voter]}) do
    not has_voted?(s, voter) && alive?(s, voter) && voter != s.accused
  end

  def precondition(s, {:call, _, :vote_guilty, [_, voter]}) do
    not has_voted?(s, voter) && alive?(s, voter) && voter != s.accused
  end

  def precondition(s, {:call, _, :select, [_, actor, target]}) do
    not has_selected?(s, actor)
    && alive?(s, actor)
    && alive?(s, target)
    && s.role[actor] != :townie
    && not (s.role[actor] == :mafioso and s.role[target] == :mafioso)
  end

  def precondition(_, {:call, _, :next_phase, _}), do: true


  # Postconditions

  def postcondition(s, {:call, _, :add_player, [_, name]}, _) do
    Enum.member?(s.players, name)
  end

  def postcondition(_, _, _) do
    true
  end

  # 
    
  # end
  # def postcondition(s, {:call, _, :remove_player, [s.id, name()]})
  # def postcondition(s, {:call, _, :start_game, [s.id]})
  # def postcondition(s, {:call, _, :accuse, [s.id, name(), name()]})
  # def postcondition(s, {:call, _, :withdraw, [s.id, name()]},)
  # def postcondition(s, {:call, _, :vote_innocent, [s.id, name()]})
  # def postcondition(s, {:call, _, :vote_guilty, [s.id, name()]})
  # def postcondition(s, {:call, _, :remove_vote, [s.id, name()]})
  # def postcondition(s, {:call, _, :select, [s.id, name(), name()]})
  # def postcondition(s, {:call, _, :unselect, [s.id, name()]})
  # def postcondition(s, {:call, _, :next_phase, [s.id]})

  # Next state

  def next_state(s, _, {:call, _, :add_player, [_, name]}) do
    %{s | players: [name | s.players]}
  end

  def next_state(s, _, {:call, _, :start_game, _}) do
    role =
      s.id
      |> game_pid()
      |> :sys.get_state()
      |> elem(1)
      |> Map.fetch!(:players)
      |> Enum.map(fn %{name: n, role: r} -> {n, r} end)
      |> Map.new()
    %{s |
      role: role,
      alive: Enum.reduce(s.players, %{},&(Map.put(&2, &1, true))),
      phase: :afternoon
    }
  end

  def next_state(s, _, {:call, _, :accuse, [_, accuser, accused]}) do
    if accused?(s, accused) do
      %{s | accused: accused, phase: :defense}
    else
      %{s |
        accusation: Map.put(s.accusation, accuser, accused),
        accusations: Map.put(s.accusations, accused, s.accusations.accused + 1)
      }
    end
  end

  def next_state(s, _, {:call, _, :vote_innocent, [_, voter]}) do
    %{s | vote: Map.put(s.vote, voter, :innocent)}
  end

  def next_state(s, _, {:call, _, :vote_guilty, [_, voter]}) do
    %{s | vote: Map.put(s.vote, voter, :guilty)}
  end

  def next_state(s, _, {:call, _, :select, [_, actor, target]}) do
    %{s | action: Map.put(s.action, actor, target)}
  end

  def next_state(%{phase: :morning} = s, _, {:call, _, :next_phase, _}) do
    %{s | phase: :accusation}
  end

  def next_state(%{phase: :accusation} = s, _, {:call, _, :next_phase, _}) do
    %{s | phase: :afternoon}
  end

  def next_state(%{phase: :defense} = s, _, {:call, _, :next_phase, _}) do
    %{s | phase: :judgement}
  end

  def next_state(%{phase: :judgement} = s, _, {:call, _, :next_phase, _}) do
    accused_alive =
      s.id
      |> game_pid()
      |> :sys.get_state()
      |> elem(1)
      |> Map.fetch!(:players)
      |> Enum.find(fn %{name: n} -> n == s.accused end)
      |> Map.fetch!(:alive)
    %{s |
      alive: Map.put(s.alive, s.accused, accused_alive),
      phase: :afternoon
    }
  end

  def next_state(%{phase: :afternoon} = s, _, {:call, _, :next_phase, _}) do
    %{s | phase: :night}
  end

  def next_state(%{phase: :night} = s, _, {:call, _, :next_phase, _}) do
    alive =
      s.id
      |> game_pid()
      |> :sys.get_state()
      |> elem(1)
      |> Map.fetch!(:players)
      |> Enum.map(fn %{name: n, alive: a} -> {n, a} end)
      |> Map.new()
    %{s |
      alive: alive,
      phase: :morning
    }
  end

  # Utils

  def name(s), do: oneof(s.players)
  def name(), do:
    oneof(
      ["Jeff",
      "Britta",
      "Abed",
      "Shirley",
      "Annie",
      "Troy",
      "Pierce",
      "Ben",
      "Craig",
      "Magnitude",
      "Ian Duncan",
      "Buzz Hickey",
      "Frankie",
      "Star-Burns",
      "Leonard",
      "Vaughn",
      "Neil",
      "Garrett",
      "Elroy"]
    )

  def alive?(s, name), do: s.alive[name]

  def has_voted?(s, name), do: Map.has_key?(s.vote, name)

  def has_accused?(s, name), do: Map.has_key?(s.accusation, name)

  def has_selected?(s, name), do: Map.has_key?(s.action, name)

  def accused?(s, accused), do:
    (s.accusations[accused] + 1) * 2 > length(s.players)

  def game_pid(game_id), do:
    Registry.lookup(Registry.Game, game_id) |> List.first() |> elem(0)

end