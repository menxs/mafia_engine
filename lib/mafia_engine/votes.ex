defmodule MafiaEngine.Votes do
	@moduledoc """
	This module defines the type for votes and functions to handle them.

	## Examples

		iex> v = MafiaEngine.Votes.new("Annie")
		...> jeff = MafiaEngine.Player.new("Jeff")
		...> abed = MafiaEngine.Player.new("Abed")
		...> {:ok, v} = MafiaEngine.Votes.vote(v, :guilty, jeff)
		...> {:ok, v} = MafiaEngine.Votes.vote(v, :innocent, abed)
		...> v.guilty
		#MapSet<["Jeff"]>
		iex> v.innocent
		#MapSet<["Abed"]>
		iex> MafiaEngine.Votes.result(v)
		:innocent
		iex> v = MafiaEngine.Votes.remove_vote(v, "Abed")
		...> v.innocent
		#MapSet<[]>
		iex> MafiaEngine.Votes.result(v)
		:guilty

	"""

	alias __MODULE__
	alias MafiaEngine.Player

	@enforce_keys [:innocent, :guilty, :accused]
	defstruct [:innocent, :guilty, :accused]

	@type t :: %Votes{innocent: MapSet.t(String.t), guilty: MapSet.t(String.t), accused: String.t}

	@type vote :: :innocent | :guilty

	@doc """
	Creates votes data type with `accused` as the accused.
	"""

	@spec new(String.t) :: t
	def new(accused) do
		%Votes{innocent: MapSet.new(), guilty: MapSet.new(), accused: accused}
	end

	@doc """
	Adds the `vote` of `voter`.

	Returns an error if the `voter` is the accused or is not alive.

	##Examples

		iex> v = MafiaEngine.Votes.new("Annie")
		...> annie = MafiaEngine.Player.new("Annie")
		...> pierce = MafiaEngine.Player.new("Pierce")
		...> pierce = MafiaEngine.Player.kill(pierce)
		...> MafiaEngine.Votes.vote(v, :guilty, pierce)
		{:error, :cannot_vote_while_dead}
		iex> MafiaEngine.Votes.vote(v, :innocent, annie)
		{:error, :accused_player_cannot_vote}

	"""

	@spec vote(t, vote, MafiaEngine.Player.t) :: {:ok, t}
	| {:error, :cannot_vote_while_dead | :accused_player_cannot_vote}
	def vote(_votes, _vote, %Player{alive: false}) do
		{:error, :cannot_vote_while_dead}
	end

	def vote(%Votes{accused: accused}, _vote, %Player{name: accused}) do
		{:error, :accused_player_cannot_vote}
	end
		
	def vote(%Votes{} = votes, :innocent, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.delete(&1, voter.name)))
			|> Map.update!(:innocent, &(MapSet.put(&1, voter.name)))
		{:ok, updated_votes}
	end

	def vote(%Votes{} = votes, :guilty, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.put(&1, voter.name)))
			|> Map.update!(:innocent, &(MapSet.delete(&1, voter.name)))
		{:ok, updated_votes}
	end

	@doc """
	Removes the vote from the given `voter` if exists.
	"""

	@spec remove_vote(t, String.t) :: t
	def remove_vote(%Votes{} = votes, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.delete(&1, voter)))
			|> Map.update!(:innocent, &(MapSet.delete(&1, voter)))
		updated_votes
	end

	@doc """
	Returns `:guilty` if there is more guilty votes and `:innocent` otherwise.
	"""

	@spec result(t) :: vote
	def result(%Votes{} = votes) do
		if MapSet.size(votes.guilty) > MapSet.size(votes.innocent) do
			:guilty
		else
			:innocent
		end
	end
end