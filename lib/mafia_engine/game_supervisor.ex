defmodule MafiaEngine.GameSupervisor do
  @moduledoc false
  use DynamicSupervisor

  alias MafiaEngine.Game

  def start_link(_options), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  def start_game() do
    game_id = gen_game_id()
    {:ok, _} = DynamicSupervisor.start_child(__MODULE__, {Game, game_id})
    game_id
  end

  def stop_game(game_id) do
    :ets.delete(:game_state, game_id)
    DynamicSupervisor.terminate_child(__MODULE__, pid_from_game_id(game_id))
  end

  def exists_id?(game_id) do
    not (Registry.lookup(Registry.Game, game_id) == [])
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  defp gen_game_id() do
    id =
      :rand.uniform(9999)
      |> Integer.to_string()
      |> String.pad_leading(4, "0")

    if exists_id?(id) do
      gen_game_id()
    else
      id
    end
  end

  defp pid_from_game_id(game_id) do
    [{pid, _}] = Registry.lookup(Registry.Game, game_id)
    pid
  end
end
