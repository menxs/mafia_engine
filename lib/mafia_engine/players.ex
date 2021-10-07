defmodule MafiaEngine.Players do
  @moduledoc """
  This module defines the type for a player list and functions to handle it.

  ## Examples

  	iex> p = MafiaEngine.Players.new()
  	[]
  	iex> {:ok, p} = MafiaEngine.Players.add(p, "Abed")
  	{:ok, [%MafiaEngine.Player{alive: true, name: "Abed", role: :unknown}]}
  	iex> {:ok, p} = MafiaEngine.Players.add(p, "Jeff")
  	{:ok,
  		[%MafiaEngine.Player{alive: true, name: "Jeff", role: :unknown},
  		%MafiaEngine.Player{alive: true, name: "Abed", role: :unknown}]
  	}
  	iex> MafiaEngine.Players.names(p)
  	["Jeff", "Abed"]
  	iex> p = MafiaEngine.Players.remove(p, "Abed")
  	[%MafiaEngine.Player{alive: true, name: "Jeff", role: :unknown}]
  	iex> MafiaEngine.Players.set_roles(p, [:townie])
  	[%MafiaEngine.Player{alive: true, name: "Jeff", role: :townie}]

  """

  alias MafiaEngine.Player

  @type t :: list(MafiaEngine.Player.t())

  @doc """
  Creates a new player list.
  """

  @spec new() :: t
  def new(), do: []

  @doc """
  Adds a new player with the given `name` unless `name` is taken.

  ## Examples

  	iex> p = MafiaEngine.Players.new()
  	[]
  	iex> {:ok, p} = MafiaEngine.Players.add(p, "Abed")
  	{:ok, [%MafiaEngine.Player{alive: true, name: "Abed", role: :unknown}]}
  	iex> MafiaEngine.Players.add(p, "Abed")
  	{:error, :name_already_taken}

  """

  @spec add(t, String.t()) :: {:ok, t} | {:error, :name_already_taken}
  def add(players, name) when is_binary(name) do
    if name in names(players) do
      {:error, :name_already_taken}
    else
      {:ok, [Player.new(name) | players]}
    end
  end

  @doc """
  Removes the player with the given `name` from the list if exists.
  """

  @spec remove(t, String.t()) :: t
  def remove(players, name) do
    Enum.reject(players, fn p -> p.name == name end)
  end

  @doc """
  Returns the player with the given `name` from the list.

  If the player does not exist it returns none instead.
  """

  @spec get(t, String.t()) :: MafiaEngine.Player.t() | :none
  def get(players, name) do
    Enum.find(players, :none, fn p -> p.name == name end)
  end

  @doc """
  Gives a role from `role_list` at random to each player.

  The `role_list` should have the same lenght as the player list.
  """

  @spec set_roles(t, list(MafiaEngine.Role.t())) :: t
  def set_roles(players, role_list) do
    updated_players =
      role_list
      |> Enum.shuffle()
      |> Enum.zip(players)
      |> Enum.map(fn {role, player} ->
        Player.set_role(player, role)
      end)

    updated_players
  end

  @doc """
  Sets the player with the given `name` role to `role`.
  """

  @spec set_role(t, String.t(), MafiaEngine.Role.t()) :: t
  def set_role(players, name, role) do
    Enum.map(
      players,
      fn
        p when p.name == name -> Player.set_role(p, role)
        p -> p
      end
    )
  end

  @doc """
  Sets the player with the given `name` alive field to `false`.
  """

  @spec kill(t, String.t()) :: t
  def kill(players, name) do
    Enum.map(
      players,
      fn
        p when p.name == name -> Player.kill(p)
        p -> p
      end
    )
  end

  @doc """
  Returns a list with the player names.
  """

  @spec names(t) :: list(String.t())
  def names(players) do
    Enum.map(players, fn p -> p.name end)
  end
end
