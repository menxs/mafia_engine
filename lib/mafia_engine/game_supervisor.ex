defmodule MafiaEngine.GameSupervisor do
  use DynamicSupervisor

  alias MafiaEngine.Game

  def start_link(_options), do:
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  def start_game(game_id) do
    DynamicSupervisor.start_child(__MODULE__, {Game, game_id})
  end

  def stop_game(game_id) do
    :ets.delete(:game_state, game_id)
    DynamicSupervisor.terminate_child(__MODULE__, pid_from_game_id(game_id))
  end

  @impl true
  def init(:ok), do:
    DynamicSupervisor.init(strategy: :one_for_one)

  defp pid_from_game_id(game_id) do
    [{pid, _}] = Registry.lookup(Registry.Game, game_id)
    pid
  end
end
