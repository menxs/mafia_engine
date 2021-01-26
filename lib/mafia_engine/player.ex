defmodule MafiaEngine.Player do
	alias __MODULE__

	defstruct [:role, alive: true]

	def new() do
		%Player{}
	end

	def set_role(%Player{} = player, role) do
		%{player | role: role}
	end

	def kill(%Player{} = player) do
		%{player | alive: false}
	end
end