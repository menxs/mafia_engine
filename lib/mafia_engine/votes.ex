defmodule MafiaEngine.Votes do
	alias __MODULE__

	@enforce_keys [:innocent, :guilty, :accused]
	defstruct [:innocent, :guilty, :accused]

	def new(accused) do
		%Votes{innocent: MapSet.new(), guilty: MapSet.new(), accused: accused}
	end

	def vote(%Votes{} = votes, _vote, voter) when voter == votes.accused, do:
		{:error, :accused_player_cannot_vote}
		
	def vote(%Votes{} = votes, :innocent, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.delete(&1, voter)))
			|> Map.update!(:innocent, &(MapSet.put(&1, voter)))
		{:ok, updated_votes}
	end

	def vote(%Votes{} = votes, :guilty, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.put(&1, voter)))
			|> Map.update!(:innocent, &(MapSet.delete(&1, voter)))
		{:ok, updated_votes}
	end

	def remove_vote(%Votes{} = votes, voter) do
		updated_votes =
			votes
			|> Map.update!(:guilty, &(MapSet.delete(&1, voter)))
			|> Map.update!(:innocent, &(MapSet.delete(&1, voter)))
		{:ok, updated_votes}
	end

	def result(%Votes{} = votes) do
		if MapSet.size(votes.guilty) > MapSet.size(votes.innocent) do
			:guilty
		else
			:innocent
		end
	end
end