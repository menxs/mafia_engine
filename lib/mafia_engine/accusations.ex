defmodule MafiaEngine.Accusations do
	alias __MODULE__

	@enforce_keys [:ballots, :required]
	defstruct [:ballots, :required]

	def new(required) do
		%Accusations{ballots: Map.new(), required: required}
	end

	def withdraw(%Accusations{} = accusations, accuser) do
		updated_accusations =
			accusations
			|> Map.update!(:ballots, &(Map.delete(&1, accuser)))
		{:ok, updated_accusations}
	end

	#Should a player be able to accuse himself?
	def accuse(%Accusations{} = accusations, accuser, accused) do
		accusations
		|> Map.update!(:ballots, &(Map.put(&1, accuser, accused)))
		|> check_accusations(accused)
	end

	defp check_accusations(accusations, accused) do
		if enough?(accusations, accused) do
			{:accused, accused, accusations}
		else
			{:ok, accusations}
		end
	end

	defp enough?(%{ballots: ballots, required: required}, accused) do
		ballots
		|> Map.values()
		|> Enum.filter(&(&1 == accused))
		|> Enum.count()
		|> (& &1 >= required).()
	end
end