defmodule MafiaEngine.PubSub do

	def sub(game_id, ref), do:
		Registry.register(Registry.GamePubSub, game_id, ref)

	def sub_player(game_id, name, ref) do
		unsub(game_id, ref)
		sub(game_id, name)
	end

	def unsub(game_id, ref), do:
		Registry.unregister_match(Registry.GamePubSub, game_id, ref)

	def unsub_player(game_id, name), do:
		unsub(game_id, name)

	def unsub_all(game_id), do:
		Registry.unregister(Registry.GamePubSub, game_id)

	def pub(game_id, message), do:
		Registry.dispatch(Registry.GamePubSub, game_id, fn entries ->
			for {pid, _} <- entries, do: send(pid, message)
		end)

	def pub_player(game_id, name, message), do:
		Registry.dispatch(Registry.GamePubSub, game_id, fn entries ->
			for {pid, ref} <- entries do
				if ref == name, do: send(pid, message)
			end
		end)

	def pub_state(game_id, state), do:
		pub(game_id, {:game_update, :state, {:playing, state}})

	def pub_players(game_id, players) do
		public_players =
			players
			|> Enum.map(fn {name, info} ->
										{name, Map.drop(info, [:role, :__struct__])}
									end)
			|> Map.new()
		pub(game_id, {:game_update, :players, public_players})
	end

	def pub_roles(game_id, players) do
		for {name, info} <- players do
			pub_player(game_id, name, {:player_update, :role, info.role})
		end
	end

	def pub_accusations(game_id, accusations) do
		pub(game_id, {:game_update, :accusations, accusations})
	end

end