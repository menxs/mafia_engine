defmodule MafiaEngine.Players do
	alias MafiaEngine.Player

	def new(), do: %{}

	def add(players, name) when is_binary(name) do
		if name in Map.keys(players) do
			{:error, :name_already_taken}
		else
			{:ok, Map.put(players, name, Player.new())}
		end
	end

	def remove(players, name) do
		{:ok, Map.delete(players, name)}
	end

	def set_roles(players, role_list) do
		updated_players =
			role_list
			|> Enum.shuffle()
			|> Enum.zip(players)
			|> Enum.map(fn {role, {name, player}} ->
									{name, Player.set_role(player, role)} end)
			|> Map.new()
		{:ok, updated_players}
	end
end