defmodule GameLogicTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM

  property "game logic stateful property", [
    :verbose,
    {:constraint_tries, 500},
    {:numtests, 1000},
    {:max_size, 80}
  ] do
    forall cmds <- commands(__MODULE__, initial_state(12)) do
      game_setup(initial_state(12))
      {history, state, result} = run_commands(__MODULE__, cmds)
      game_cleanup()

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
    %{
      phase: :afternoon,
      players: %{
        "Jeff" => %{alive: true, role: :mafioso},
        "Britta" => %{alive: true, role: :townie},
        "Abed" => %{alive: true, role: :doctor},
        "Shirley" => %{alive: true, role: :sheriff},
        "Annie" => %{alive: true, role: :townie},
        "Troy" => %{alive: true, role: :townie},
        "Pierce" => %{alive: true, role: :mafioso},
        "Craig" => %{alive: true, role: :townie}
      },
      accusations: [],
      accused: "",
      votes: [],
      selections: []
    }
  end

  def initial_state(n) do
    villagers = List.duplicate(:townie, round(n / 2))
    mafiosos = List.duplicate(:mafioso, round(n / 4))
    doctors = List.duplicate(:doctor, floor(n / 8))
    sheriffs = List.duplicate(:sheriff, round(n / 4))
    roles = Enum.concat([villagers, mafiosos, doctors, sheriffs])

    players =
      1..n
      |> Enum.map(&Integer.to_string/1)
      |> Enum.zip(roles)
      |> Enum.map(fn {name, role} -> {name, %{alive: true, role: role}} end)
      |> Map.new()

    %{initial_state() | players: players}
  end

  def game_setup(s) do
    MafiaEngine.Game.start_link("Testing")

    names =
      s.players
      |> Map.keys()
      |> Enum.reverse()

    for name <- names do
      MafiaEngine.Game.add_player("Testing", name)
    end

    MafiaEngine.Game.start_game("Testing")

    role_fun = fn players ->
      Enum.map(
        players,
        fn %{name: name} = p ->
          %{p | role: s.players[name].role}
        end
      )
    end

    state_fun = fn game_state ->
      {:afternoon, update_in(elem(game_state, 1), [:players], role_fun)}
    end

    :sys.replace_state(game_pid(), state_fun)
  end

  def game_cleanup() do
    GenStateMachine.stop(game_pid())
  end

  def command(%{phase: :end}), do: {:call, __MODULE__, :do_nothing, []}

  def command(%{phase: :accusation} = s) do
    frequency([
      {20, {:call, MafiaEngine.Game, :accuse, ["Testing", name(s), name(s)]}},
      {5, {:call, __MODULE__, :all_accuse, [alive_players(s), name(s)]}},
      {1, {:call, MafiaEngine.Game, :next_phase, ["Testing"]}}
    ])
  end

  def command(%{phase: :judgement} = s) do
    frequency([
      {10, {:call, MafiaEngine.Game, :vote_innocent, ["Testing", name(s)]}},
      {10, {:call, MafiaEngine.Game, :vote_guilty, ["Testing", name(s)]}},
      {1, {:call, MafiaEngine.Game, :next_phase, ["Testing"]}}
    ])
  end

  def command(%{phase: :night} = s) do
    frequency([
      {20, {:call, MafiaEngine.Game, :select, ["Testing", name(s), name(s)]}},
      {1, {:call, MafiaEngine.Game, :next_phase, ["Testing"]}}
    ])
  end

  def command(_), do: {:call, MafiaEngine.Game, :next_phase, ["Testing"]}

  # Preconditions

  def precondition(s, {:call, _mod, :accuse, [_, accuser, accused]}) do
    s.phase == :accusation &&
      s.players[accuser].alive &&
      s.players[accused].alive &&
      not has_accused?(s, accuser)
  end

  def precondition(s, {:call, _mod, :all_accuse, [_, accused]}) do
    s.phase == :accusation &&
      s.players[accused].alive
  end

  def precondition(s, {:call, _mod, :vote_innocent, [_, voter]}),
    do:
      s.phase == :judgement &&
        s.players[voter].alive &&
        voter != s.accused &&
        not has_voted?(s, voter)

  def precondition(s, {:call, _mod, :vote_guilty, [_, voter]}),
    do:
      s.phase == :judgement &&
        s.players[voter].alive &&
        voter != s.accused &&
        not has_voted?(s, voter)

  def precondition(s, {:call, _mod, :select, [_, actor, target]}),
    do:
      s.phase == :night &&
        s.players[actor].alive &&
        s.players[target].alive &&
        s.players[actor].role != :townie &&
        not (s.players[actor].role == :mafioso and s.players[target].role == :mafioso) &&
        not has_selected?(s, actor)

  def precondition(_s, {:call, _mod, _fun, _args}), do: true

  # Postconditions

  def postcondition(_s, {:call, _mod, :accuse, [_, accuser, accused]}, _res) do
    Map.get(game_accusations(), :ballots) |> Map.get(accuser) == accused
  end

  def postcondition(_s, {:call, _mod, :all_accuse, [_, accused]}, _res) do
    game_phase() == :defense &&
      Map.get(game_votes(), :accused) == accused
  end

  def postcondition(_s, {:call, _mod, :vote_innocent, [_, voter]}, _res) do
    voter in Map.get(game_votes(), :innocent)
  end

  def postcondition(_s, {:call, _mod, :vote_guilty, [_, voter]}, _res) do
    voter in Map.get(game_votes(), :guilty)
  end

  def postcondition(s, {:call, _mod, :select, [_, actor, target]}, _res) do
    Map.get(game_selections(), actor) == {s.players[actor].role, target}
  end

  def postcondition(%{phase: :morning}, {:call, _mod, :next_state, _args}, _res) do
    game_phase() == :accusation
  end

  def postcondition(%{phase: :accusation}, {:call, _mod, :next_state, _args}, _res) do
    game_phase() == :afternoon
  end

  def postcondition(%{phase: :defense}, {:call, _mod, :next_state, _args}, _res) do
    game_phase() == :judgement
  end

  def postcondition(%{phase: :judgement} = s, {:call, _mod, :next_state, _args}, _res) do
    if guilty?(s) do
      game_player(s.accused).alive == false &&
        (game_phase() == :afternoon or game_phase() == :game_over)
    else
      game_phase() == :afternoon
    end
  end

  def postcondition(%{phase: :afternoon}, {:call, _mod, :next_state, _args}, _res) do
    game_phase() == :night
  end

  def postcondition(%{phase: :night}, {:call, _mod, :next_state, _args}, _res) do
    game_phase() == :morning or game_phase() == :game_over
  end

  def postcondition(%{phase: :end}, {:call, _mod, _fun, _args}, _res) do
    game_phase() == :game_over
  end

  def postcondition(_s, {:call, _mod, _fun, _args}, _res), do: true

  # Next State

  def next_state(s, _res, {:call, _mod, :accuse, [_, accuser, accused]}) do
    %{s | accusations: [{accuser, accused} | s.accusations]} |> check_accusations()
  end

  def next_state(s, _res, {:call, _mod, :all_accuse, [_, accused]}) do
    %{s | accused: accused} |> set_phase(:defense)
  end

  def next_state(s, _res, {:call, _mod, :vote_innocent, [_, voter]}) do
    %{s | votes: [{voter, :inno} | s.votes]}
  end

  def next_state(s, _res, {:call, _mod, :vote_guilty, [_, voter]}) do
    %{s | votes: [{voter, :guilty} | s.votes]}
  end

  def next_state(s, _res, {:call, _mod, :select, [_, actor, target]}) do
    %{s | selections: [{actor, target} | s.selections]}
  end

  def next_state(%{phase: :afternoon} = s, _res, {:call, _mod, :next_phase, _args}) do
    set_phase(s, :night) |> clear_selections()
  end

  def next_state(%{phase: :night} = s, _res, {:call, _mod, :next_phase, _args}) do
    mafia_kill(s) |> set_phase(:morning) |> check_end()
  end

  def next_state(%{phase: :morning} = s, _res, {:call, _mod, :next_phase, _args}) do
    set_phase(s, :accusation) |> clear_accusations() |> clear_votes()
  end

  def next_state(%{phase: :accusation} = s, _res, {:call, _mod, :next_phase, _args}) do
    set_phase(s, :afternoon)
  end

  def next_state(%{phase: :defense} = s, _res, {:call, _mod, :next_phase, _args}) do
    set_phase(s, :judgement)
  end

  def next_state(%{phase: :judgement} = s, _res, {:call, _mod, :next_phase, _args}) do
    if guilty?(s) do
      kill(s, s.accused) |> set_phase(:afternoon) |> check_end()
    else
      set_phase(s, :afternoon)
    end
  end

  def next_state(s, _res, {:call, _mod, _fun, _args}), do: s

  # Utils

  def do_nothing(), do: :ok

  def all_accuse(accusers, accused),
    do: Enum.map(accusers, &MafiaEngine.Game.accuse("Testing", &1, accused))

  def set_phase(s, phase), do: %{s | phase: phase}

  def clear_accusations(s), do: %{s | accusations: []}

  def clear_votes(s), do: %{s | votes: []}

  def clear_selections(s), do: %{s | selections: []}

  def has_accused?(s, name), do: Enum.any?(s.accusations, &(elem(&1, 0) == name))

  def has_voted?(s, name), do: Enum.any?(s.votes, &(elem(&1, 0) == name))

  def has_selected?(s, name), do: Enum.any?(s.selections, &(elem(&1, 0) == name))

  def kill(s, name), do: put_in(s, [:players, name, :alive], false)

  def mafia_kill(s) do
    alive_mafiosos = alive_mafiosos(s)
    alive_doctors = alive_doctors(s)

    targets =
      s.selections
      |> Enum.filter(&(elem(&1, 0) in alive_mafiosos))
      |> Enum.map(fn {_actor, target} -> target end)
      |> Enum.frequencies()

    if targets != %{} do
      mafia_target =
        targets
        |> Enum.max_by(fn {_target, freq} -> freq end)
        |> elem(0)

      healed =
        s.selections
        |> Enum.filter(&(elem(&1, 0) in alive_doctors))
        |> Enum.any?(&(elem(&1, 1) == mafia_target))

      if healed do
        s
      else
        kill(s, mafia_target)
      end
    else
      s
    end
  end

  def alive_doctors(s), do: alive_role_names(s, :doctor)

  def alive_mafiosos(s), do: alive_role_names(s, :mafioso)

  def alive_role_names(s, role) do
    Enum.filter(
      s.players,
      fn
        {_, %{role: r, alive: true}} when r == role -> true
        _ -> false
      end
    )
    |> Enum.map(fn {name, _} -> name end)
  end

  def alive_players(s) do
    Enum.filter(
      s.players,
      fn
        {_, %{alive: true}} -> true
        _ -> false
      end
    )
    |> Enum.map(fn {name, _} -> name end)
  end

  def check_accusations(s) do
    {accused, votes} =
      s.accusations
      |> Enum.map(fn {_accuser, accused} -> accused end)
      |> Enum.frequencies()
      |> Enum.max_by(fn {_accused, freq} -> freq end)

    if votes * 2 > length(alive_players(s)) do
      %{s | accused: accused}
      |> set_phase(:defense)
    else
      s
    end
  end

  def guilty?(s),
    do:
      s.votes
      |> Enum.map(&elem(&1, 1))
      |> Enum.count(&(&1 == :guilty))
      |> (&(&1 * 2 > length(s.votes))).()

  def check_end(s) do
    mf_c = length(alive_mafiosos(s))
    alv_c = length(alive_players(s))

    if mf_c * 2 >= alv_c or mf_c == 0 do
      set_phase(s, :end)
    else
      s
    end
  end

  def name(s), do: oneof(s.players |> Map.keys())

  def game_pid(), do: Registry.lookup(Registry.Game, "Testing") |> List.first() |> elem(0)

  def game_state(), do: game_pid() |> :sys.get_state()

  def game_phase(), do: game_state() |> elem(0)

  def game_accusations(), do: game_state() |> elem(1) |> Map.fetch!(:accusations)

  def game_votes(), do: game_state() |> elem(1) |> Map.fetch!(:votes)

  def game_selections(), do: game_state() |> elem(1) |> Map.fetch!(:night_actions)

  def game_player(name),
    do: game_state() |> elem(1) |> Map.fetch!(:players) |> MafiaEngine.Players.get(name)
end
