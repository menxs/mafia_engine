defmodule GameTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM

  property "game test", [:verbose] do
    forall cmds <- commands(__MODULE__) do

      MafiaEngine.Game.start_link("Testing")
      {history, state, result} = run_commands(__MODULE__, cmds)
      GenStateMachine.stop(game_pid())

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

  def initial_state(), do: %{players: []}

  def command(_), do: {:call, MafiaEngine.Game, :add_player, ["Testing", name()]}

  def precondition(s, {:call, _, :add_player, [_, name]}) do
    IO.inspect("Checking precondition for #{name}")
    IO.inspect(s, label: "S")
    IO.puts("\n")
    not Enum.member?(s.players, name)
  end

  def next_state(%{players: []} = s, _, {:call, _, :add_player, [_, name]}) do
    IO.puts("This should appear only once")
    %{s | players: [name | s.players]}
  end

  def next_state(%{players: _} = s, _, {:call, _, :add_player, [_, name]}) do
    IO.puts("\n\n\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n\n\n")
    IO.inspect(name, label: "Adding ")
    %{s | players: [name | s.players]}
  end

  def postcondition(s, {:call, _, :add_player, [_, name]}, _) do
    IO.inspect("Checking postcondition for #{name}")
    IO.inspect(get_players(), label: "get_players")
    IO.inspect(s.players, label: "s.players")
    get_players() == [name | s.players]
  end

  def name(), do:
    :rand.uniform(9999)
      |> Integer.to_string()
      |> String.pad_leading(4, "0")

  def game_pid(), do:
    Registry.lookup(Registry.Game, "Testing") |> List.first() |> elem(0)

  def get_players(), do:
    game_pid()
    |> :sys.get_state()
    |> elem(1)
    |> Map.fetch!(:players)
    |> Enum.map(fn %{name: n} -> n end)

end