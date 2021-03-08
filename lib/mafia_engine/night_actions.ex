defmodule MafiaEngine.NightActions do
	alias MafiaEngine.Player

	@type t :: %{optional(String.t) => {MafiaEngine.Role.t, String.t}}

	@type action :: {String.t, MafiaEngine.Role.t, String.t}

	@type event :: {String.t, MafiaEngine.Role.outcome, String.t}

	@spec new() :: t
	def new(), do: %{}

	@spec unselect(t, String.t) :: t
	def unselect(night_actions, actor) do
		Map.delete(night_actions, actor)
	end

	@spec select(t, MafiaEngine.Player.t, MafiaEngine.Player.t) :: {:ok, t}
	| {:error, reason :: atom}
	def select(night_actions, %Player{} = actor, %Player{} = target) do
		with :ok <-
			check_action(actor, target)
		do
			{:ok, Map.put(night_actions, actor.name, {actor.role, target.name})}
		else
			{:error, reason} -> {:error, reason}
		end
	end

	@spec execute(t) :: list(event)
	def execute(night_actions) do
			night_actions
			|> actions_to_list()
			|> mafia_attacks()
			|> doctor_heals()
			|> sheriff_investigates()
	end

	@spec actions_to_list(t) :: list(action)
	defp actions_to_list(night_actions) do
		night_actions
		|> Map.to_list()
		|> Enum.map(fn {actor, {role, target}} -> {actor, role, target} end)
	end

	@spec mafia_attacks(list(action | event)) :: list(action | event)
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

	@spec doctor_heals(list(action | event)) :: list(action | event)
	defp doctor_heals(events) do
		with {[_ | _] = doctor_events, events} <-
			Enum.split_with(events, fn {_actor, role, _target} -> role == :doctor end)
		do
			Enum.map(events, &process_doctor_action(&1, doctor_events))
		else
			{[], events} -> events
		end
	end

	@spec process_doctor_action(action | event, list(event)) :: action | event
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


	@spec sheriff_investigates(list(action | event)) :: list(action | event)
	defp sheriff_investigates(events) do
		Enum.map(events, &process_sheriff_action/1)
	end

	@spec process_sheriff_action(action | event) :: action | event
	defp process_sheriff_action({actor, :sheriff, target}), do:
		{actor, :investigate, target}
	defp process_sheriff_action(event), do: event

	@spec check_action(MafiaEngine.Player.t, MafiaEngine.Player.t) :: :ok | {:error, reason :: atom}
	defp check_action(%{alive: false}, _target) do
		{:error, :cannot_act_while_dead}
	end

	defp check_action(_actor, %{alive: false}) do
		{:error, :cannot_target_dead_players}
	end

	defp check_action(%{role: :townie}, _target) do
		{:error, :townie_cannot_target}
	end

	defp check_action(%{role: :mafioso}, %{role: :mafioso}) do
		{:error, :mafioso_cannot_target_mafiosos}
	end

	defp check_action(_actor, _target) do
		:ok
	end
end