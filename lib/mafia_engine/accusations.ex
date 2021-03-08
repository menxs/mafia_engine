defmodule MafiaEngine.Accusations do
	@moduledoc """
  This module defines the type for accusations and functions to handle them.

  ## Examples

		iex> a = MafiaEngine.Accusations.new(2)
		%MafiaEngine.Accusations{ballots: %{}, required: 2}
		iex> abed = MafiaEngine.Player.new("Abed")
		...> jeff = MafiaEngine.Player.new("Jeff")
		...> {:ok, a} = MafiaEngine.Accusations.accuse(a, abed, jeff)
		{:ok, %MafiaEngine.Accusations{ballots: %{"Abed" => "Jeff"}, required: 2}}
		iex> a = MafiaEngine.Accusations.withdraw(a, abed)
		%MafiaEngine.Accusations{ballots: %{}, required: 2}
		iex> {:ok, a} = MafiaEngine.Accusations.accuse(a, jeff, abed)
		...> MafiaEngine.Accusations.accuse(a, abed, abed)
		{:accused, "Abed",
		 %MafiaEngine.Accusations{
		   ballots: %{"Abed" => "Abed", "Jeff" => "Abed"},
		   required: 2
		 }}

  """

	alias __MODULE__
	alias MafiaEngine.Player

	@enforce_keys [:ballots, :required]
	defstruct [:ballots, :required]

	@type t :: %Accusations{ballots: %{optional(String.t) => String.t}, required: pos_integer}

	@doc """
	Creates a new accusations with `required` as the number of accusations required to cause a player to be accused.
	"""

	@spec new(pos_integer) :: t
	def new(required) do
		%Accusations{ballots: Map.new(), required: required}
	end

	@doc """
	Removes the accusation from `accuser` if exists.
	"""

	@spec withdraw(t, String.t) :: t
	def withdraw(%Accusations{} = accusations, accuser) do
			accusations
			|> Map.update!(:ballots, &(Map.delete(&1, accuser)))
	end

	@doc """
	Adds the accusation from `accuser` to `accused`.
	It also checks if accused has the required accusations to be accused.

	Returns an error if either `accuser` or `accused` is not alive.

	## Examples 

		iex> a = MafiaEngine.Accusations.new(2)
		...> jeff = MafiaEngine.Player.new("Jeff")
		...> pierce = MafiaEngine.Player.new("Pierce")
		...> pierce = MafiaEngine.Player.kill(pierce)
		...> MafiaEngine.Accusations.accuse(a, pierce, jeff)
		{:error, :cannot_accuse_while_dead}
		iex> MafiaEngine.Accusations.accuse(a, jeff, pierce)
		{:error, :cannot_accuse_dead_players}

	"""

	@spec accuse(t, MafiaEngine.Player.t, MafiaEngine.Player.t) ::
		{:ok, t}
		| {:accused, String.t, t}
		| {:error, :cannot_accuse_while_dead | :cannot_accuse_dead_players}

	def accuse(_accusations, %Player{alive: false}, _accused) do
		{:error, :cannot_accuse_while_dead}
	end

	def accuse(_accusations, _accuser, %Player{alive: false}) do
		{:error, :cannot_accuse_dead_players}
	end

	def accuse(%Accusations{} = accusations, accuser, accused) do
		accusations
		|> Map.update!(:ballots, &(Map.put(&1, accuser.name, accused.name)))
		|> check_accusations(accused.name)
	end

	@spec check_accusations(t, String.t) :: {:ok, t} | {:accused, String.t, t}
	defp check_accusations(accusations, accused) do
		if enough?(accusations, accused) do
			{:accused, accused, accusations}
		else
			{:ok, accusations}
		end
	end

	@spec enough?(t, String.t) :: boolean
	defp enough?(%{ballots: ballots, required: required}, accused) do
		ballots
		|> Map.values()
		|> Enum.filter(&(&1 == accused))
		|> Enum.count()
		|> (& &1 >= required).()
	end
end