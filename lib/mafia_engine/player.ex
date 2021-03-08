defmodule MafiaEngine.Player do
	@moduledoc """
	This module defines the player type and functions to handle it.

	## Examples

		iex> abed = MafiaEngine.Player.new("Abed")
		%MafiaEngine.Player{alive: true, name: "Abed", role: :unknown}
		iex> abed = MafiaEngine.Player.set_role(abed, :townie)
		%MafiaEngine.Player{alive: true, name: "Abed", role: :townie}
		iex> abed = MafiaEngine.Player.kill(abed)
		%MafiaEngine.Player{alive: false, name: "Abed", role: :townie}
		iex> abed.alive
		false

	"""

	alias __MODULE__

	defstruct [:name, role: :unknown, alive: true]

	@typedoc """
	Type that represents a player in the game.
	"""

	@type t :: %Player{name: String.t, role: MafiaEngine.Role.t(), alive: boolean}

	@doc """
	Creates a new player with the given `name`.
	"""

	@spec new(String.t) :: Player.t()
	def new(name) do
		%Player{name: name}
	end

	@doc """
	Changes the `player` role the given `role`.
	"""

	@spec set_role(Player.t(), MafiaEngine.Role.t()) :: Player.t()
	def set_role(%Player{} = player, role) do
		%{player | role: role}
	end

	@doc """
	Sets the `player` alive field to `false`.
	"""

	@spec kill(Player.t()) :: Player.t()
	def kill(%Player{} = player) do
		%{player | alive: false}
	end
end