defmodule MafiaEngine.PubSub do

	def sub(game_id, ref), do:
		Registry.register(Registry.GamePubSub, game_id, ref)

	def sub_player(game_id, name, ref) do
		sub(game_id, name)
		unsub(game_id, ref)
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

	def pub_roles(game_id, players) do
		#Tell everyone their role
		for p <- players do
			pub_player(game_id, p.name, {:game_update, :role, {p.name, p.role}})
		end
		#Tell the mafia their allies roles
		mafiosos = Enum.filter(players, fn p -> p.role == :mafioso end)
		Enum.map(mafiosos,
				fn p ->
					for ally <- mafiosos do
						pub_player(game_id, p.name, {:game_update, :role, {ally.name, p.role}})
					end
				end)
	end

end