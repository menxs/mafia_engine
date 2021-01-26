defmodule MafiaEngine.NightActions do
	alias MafiaEngine.Player

	def new(), do: %{}

	def unselect(night_actions, actor) do
		{:ok, Map.delete(night_actions, actor)}
	end

	def select(night_actions, actor_name, %Player{} = actor_player,
							target_name, %Player{} = target_player) do
		with :ok <-
			check_action(actor_name, actor_player, target_name, target_player)
		do
			{:ok, Map.put(night_actions, actor_name, {actor_player.role, target_name})}
		else
			{:error, reason} -> {:error, reason}
		end
	end

	def execute(night_actions) do
		events =
			night_actions
			|> actions_to_list()
			|> mafia_attacks()
			|> doctor_heals()
			|> sheriff_investigates()
		{:ok, events}
	end

	defp actions_to_list(night_actions) do
		night_actions
		|> Map.to_list()
		|> Enum.map(fn {actor, {role, target}} -> {actor, role, target} end)
	end

	defp mafia_attacks(events) do
		with  {[_ | _] = mafioso_events, events} <-
			Enum.split_with(events, fn {_actor, role, _target} -> role == :mafioso end)
		do
			mafia_target =
				mafioso_events
				|> Enum.map(fn {_actor, _role, target} -> target end)
				|> Enum.frequencies()
				|> Enum.shuffle()
				|> Enum.max_by(fn {_target, freq} -> freq end)
				|> elem(0)

			mafia_actor =
				mafioso_events
				|> Enum.map(fn {actor, _role, _target} -> actor end)
				|> Enum.take_random(1)
				|> List.first()

			[{mafia_actor, :kill, mafia_target} | events]
		else
			{[], events} -> events
		end
	end

	defp doctor_heals(events) do
		with {[_ | _] = doctor_events, events} <-
			Enum.split_with(events, fn {_actor, role, _target} -> role == :doctor end)
		do
			Enum.map(events, &process_doctor_action(&1, doctor_events))
		else
			{[], events} -> events
		end
	end

	defp process_doctor_action({_actor, :kill, target} = event, doctor_events) do
		healed =
			Enum.find(doctor_events, :none,
								fn {_actor, _role, heal_target} ->
									target == heal_target
								end)

		case healed do
			:none -> event
			{actor, :doctor, target} -> {actor, :heal, target}
		end
	end
	defp process_doctor_action(event, _doctor_events), do: event

	defp sheriff_investigates(events) do
		Enum.map(events, &process_sheriff_action/1)
	end

	defp process_sheriff_action({actor, :sheriff, target}), do:
		{actor, :investigate, target}
	defp process_sheriff_action(event), do: event

	defp check_action(_actor_name, %{alive: false}, _target_name, _) do
		{:error, :cannot_act_while_dead}
	end

	defp check_action(_actor_name, _, _target_name, %{alive: false}) do
		{:error, :cannot_target_dead_players}
	end

	defp check_action(_actor_name, %{role: :townie}, _target_name, _) do
		{:error, :townie_cannot_target}
	end

	defp check_action(same_name, %{role: :mafioso}, same_name, _) do
		{:error, :mafioso_cannot_target_himself}
	end

	defp check_action(_actor_name, %{role: :mafioso},
										_target_name, %{role: :mafioso}) do
		{:error, :mafioso_cannot_target_mafiosos}
	end

	#Check the role exists
	defp check_action(_actor_name, _, _target_name, _) do
		:ok
	end
end