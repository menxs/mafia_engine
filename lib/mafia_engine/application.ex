defmodule MafiaEngine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.Game},
      {Registry,
        keys: :duplicate,
        name: Registry.GamePubSub,
        partitions: System.schedulers_online()
      },
      MafiaEngine.GameSupervisor
    ]

    :rand.uniform()
    :ets.new(:game_state, [:public, :named_table])
    opts = [strategy: :one_for_one, name: MafiaEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
