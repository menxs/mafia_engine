defmodule MafiaEngine.Game do
	use GenStateMachine, callback_mode: [:state_functions, :state_enter], restart: :transient

	alias MafiaEngine.{Player, Players, Settings, Accusations, Votes, NightActions, PubSub}

	@afk_timeout_action  {{:timeout, :afk}, 45 * 60 * 1000, :exterminate}

	#============================================================================#
	# Client Functions                                                           #
	#============================================================================#

	def start_link(game_id), do:
		GenStateMachine.start_link(__MODULE__, game_id, name: via_tuple(game_id))

	def via_tuple(game_id), do: {:via, Registry, {Registry.Game, game_id}}

	#----------------------------------------------------------------------------- Afterinterface

	def next_phase(game), do:
		GenStateMachine.cast(via_tuple(game), :next_phase)

	def started?(game), do:
		GenStateMachine.call(via_tuple(game), :started?)

	#----------------------------------------------------------------------------- Afterinterface

	def add_player(game, name), do:
		GenStateMachine.call(via_tuple(game), {:add_player, name})

	def remove_player(game, name), do:
		GenStateMachine.cast(via_tuple(game), {:remove_player, name})

	def increase_role(game, role), do:
		GenStateMachine.cast(via_tuple(game), {:change_role, :inc, role})

	def decrease_role(game, role), do:
		GenStateMachine.cast(via_tuple(game), {:change_role, :dec, role})

	def increase_timer(game, phase), do:
		GenStateMachine.cast(via_tuple(game), {:change_timer, :inc, phase})

	def decrease_timer(game, phase), do:
		GenStateMachine.cast(via_tuple(game), {:change_timer, :dec, phase})

	def start_game(game), do:
		GenStateMachine.cast(via_tuple(game), :start_game)

	def talk_to(game, author), do:
		GenStateMachine.call(via_tuple(game), {:talk_to, author})

	def accuse(game, accuser, accused), do:
		GenStateMachine.cast(via_tuple(game), {:accuse, accuser, accused})

	def withdraw(game, accuser), do:
		GenStateMachine.cast(via_tuple(game), {:withdraw, accuser})

	def vote_innocent(game, voter), do:
		GenStateMachine.cast(via_tuple(game), {:vote, :innocent, voter})

	def vote_guilty(game, voter), do:
		GenStateMachine.cast(via_tuple(game), {:vote, :guilty, voter})

	def remove_vote(game, voter), do:
		GenStateMachine.cast(via_tuple(game), {:remove_vote, voter})

	def select(game, actor, target), do:
		GenStateMachine.cast(via_tuple(game), {:select, actor, target})

	def unselect(game, actor), do:
		GenStateMachine.cast(via_tuple(game), {:unselect, actor})

	#============================================================================#
	# Server Callbacks                                                           #
	#============================================================================#

	@impl true
	def init(game_id) do
		{:ok, :initializing, fresh_data(game_id),
			[{:next_event, :internal, {:set_state, game_id}}]}
	end

	@impl true
	def terminate({:shutdown, _reason}, _state, data) do
		IO.puts("Deleting everything")
		PubSub.pub(data.game_id, {:game_update, :state, :shutdown})
		PubSub.unsub_all(data.game_id)
		:ets.delete(:game_state, data.game_id)
		:ok
	end

	@impl true
	def terminate(:normal, _state, data) do
		PubSub.pub(data.game_id, {:game_update, :state, :shutdown})
		PubSub.unsub_all(data.game_id)
		:ets.delete(:game_state, data.game_id)
		:ok
	end

	@impl true
	def terminate(_reason, _state, _data) do
		:ok
	end

	#----------------------------------------------------------------------------#
	# Initializing state                                                         #
	#----------------------------------------------------------------------------#

	def initializing(:enter, :initializing, _data), do: :keep_state_and_data

	def initializing(:internal, {:set_state, game_id}, data) do
		case :ets.lookup(:game_state, game_id) do
			[] ->
				{:next_state, :initialized, data}
			[{_key, {state, data}}] ->
				{:next_state, state, data}
		end
	end

	def initializing(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Initialized state                                                          #
	#----------------------------------------------------------------------------#

	def initialized(:enter, _old_state, _data), do: :keep_state_and_data

	def initialized({:call, from}, {:add_player, name}, data) do
		with {:ok, players} <- Players.add(data.players, name)
		do
			updated_data = 
				data
				|> update_players(players)
				|> update_settings(Settings.player_added(data.settings, length(players)))
			success(:keep_state, :initialized, updated_data,
							[{:reply, from, {:ok, players}}])
		else
			{:error, reason} -> reply_error(from, {:error, reason})
		end
	end

	def initialized(:cast, {:remove_player, name}, data) do
		players = Players.remove(data.players, name)
		if length(players) > 0 do
			updated_data =
				data
				|> update_players(players)
				|> update_settings(Settings.player_left(data.settings, length(players)))
			success(:keep_state, :initialized, updated_data)
		else
			{:stop, {:shutdown, :zero_players}}
		end
	end

	def initialized(:cast, {:change_role, inc_or_dec, role}, data) do
		settings = Settings.change_role(data.settings, inc_or_dec, role, length(data.players))
		updated_data = update_settings(data, settings)
		success(:keep_state, :initialized, updated_data)
	end

	def initialized(:cast, {:change_timer, inc_or_dec, phase}, data) do
		settings = Settings.change_timer(data.settings, inc_or_dec, phase)
		updated_data = update_settings(data, settings)
		success(:keep_state, :initialized, updated_data)
	end

	def initialized({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, false}]}

	def initialized(:cast, :start_game, data) do
		roles = roles(length(data.players), data.settings.roles)
		players = Players.set_roles(data.players, roles)
		updated_data = update_players(data, players)
		PubSub.pub_roles(data.game_id, players)
		PubSub.pub(data.game_id, {:game_update, :state, :playing})
		success(:next_state, :afternoon, updated_data)
	end

	def initialized({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def initialized(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Morning state                                                              #
	#----------------------------------------------------------------------------#

	def morning(:enter, _old_state, data), do:
		success(:keep_state_and_data, :morning, data,
						[{:state_timeout, data.settings.timer.morning, :go_next}])

	def morning({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def morning({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {author.alive, :everyone}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def morning(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def morning(:state_timeout, :go_next, data), do:
		success(:next_state, :accusation, data)

	def morning({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def morning(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Accusation state                                                           #
	#----------------------------------------------------------------------------#

	def accusation(:enter, :initializing, data), do:
		success(:keep_state_and_data, :accusation, data,
						[{:state_timeout, data.settings.timer.accusation, :go_next}])

	def accusation(:enter, _old_state, data) do
		required =
      data.players
      |> Enum.filter(&(&1.alive))
      |> length()
			|> div(2)
			|> (& &1 + 1).()
		updated_data = update_accusations(data, Accusations.new(required))
		success(:keep_state, :accusation, updated_data,
						[{:state_timeout, data.settings.timer.accusation, :go_next}])
	end

	def accusation({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def accusation(:cast, {:accuse, accuser_name, accused_name}, data) do
		with  %Player{} = accuser <- Players.get(data.players, accuser_name),
					true 									<- accuser.alive,
		 		 	%Player{} = accused <- Players.get(data.players, accused_name),
		 		 	true 									<- accused.alive,
		 	   	{:ok, accusations} 		<- Accusations.accuse(data.accusations,
		 	   												accuser, accused)
		do
			updated_data = update_accusations(data, accusations)
			success(:keep_state, :accusation, updated_data)
		else
			{:accused, accused, accusations} ->
				updated_data =
			  	data
					|> update_accusations(accusations)
					|> update_votes(Votes.new(accused))
				PubSub.pub(data.game_id, {:game_update, :accused, accused})
				success(:next_state, :defense, updated_data)
			:none ->
				error(data.game_id, accuser_name, {:error, :unknown_accuser_or_accused})
			false ->
				error(data.game_id, accuser_name, {:error, :accuser_or_accused_dead})
			{:error, reason} ->
				error(data.game_id, accuser_name, {:error, reason})
		end
	end

	def accusation(:cast, {:withdraw, accuser}, data) do
		accusations = Accusations.withdraw(data.accusations, accuser)
		updated_data = update_accusations(data, accusations)
		success(:keep_state, :accusation, updated_data)
	end

	def accusation({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {author.alive, :everyone}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def accusation(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def accusation(:state_timeout, :go_next, data), do:
		success(:next_state, :afternoon, data)

	def accusation({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def accusation(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Defense state                                                              #
	#----------------------------------------------------------------------------#

	def defense(:enter, _old_state, data) do
		success(:keep_state_and_data, :defense, data,
						[{:state_timeout, data.settings.timer.defense, :go_next}])
	end

	def defense({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def defense({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {name == data.votes.accused, :everyone}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def defense(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def defense(:state_timeout, :go_next, data), do:
		success(:next_state, :judgement, data)

	def defense({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def defense(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Judgement state                                                            #
	#----------------------------------------------------------------------------#

	def judgement(:enter, _old_state, data), do:
		success(:keep_state_and_data, :judgement, data,
						[{:state_timeout, data.settings.timer.judgement, :go_next}])

	def judgement({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def judgement(:cast, {:vote, vote, voter_name}, data) do
		with  %Player{} = voter <- Players.get(data.players, voter_name),
					true 								<- voter.alive,
					{:ok, votes} 				<- Votes.vote(data.votes, vote, voter)
		do
			updated_data = update_votes(data, votes)
			success(:keep_state, :judgement, updated_data)
		else
			:none ->           error(data.game_id, voter_name, {:error, :unknown_voter})
			false ->            error(data.game_id, voter_name, {:error, :voter_dead})
			{:error, reason} -> error(data.game_id, voter_name, {:error, reason})
		end
	end

	def judgement(:cast, {:remove_vote, voter}, data) do
		votes = Votes.remove_vote(data.votes, voter)
		updated_data = update_votes(data, votes)
		success(:keep_state, :judgement, updated_data)
	end

	def judgement({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {author.alive, :everyone}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def judgement(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def judgement(:state_timeout, :go_next, data) do
		accused = data.votes.accused
		updated_data =
			case Votes.result(data.votes) do
				:guilty ->
					updated_players = Players.kill(data.players, accused)
					PubSub.pub(data.game_id, {:game_update, :role, {accused, Players.get(data.players, accused).role}})
					update_players(data, updated_players)
				:innocent ->
					data
			end
		check_win(:afternoon, updated_data)
	end

	def judgement({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def judgement(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Afternoon state                                                            #
	#----------------------------------------------------------------------------#

	def afternoon(:enter, _old_state, data), do:
		success(:keep_state_and_data, :afternoon, data,
						[{:state_timeout, data.settings.timer.afternoon, :go_next}])

	def afternoon({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def afternoon({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {author.alive, :everyone}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def afternoon(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def afternoon(:state_timeout, :go_next, data), do:
		success(:next_state, :night, data)

	def afternoon({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}

	def afternoon(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Night state                                                                #
	#----------------------------------------------------------------------------#

	def night(:enter, :initializing, data), do:
		success(:keep_state_and_data, :night, data,
						[{:state_timeout, data.settings.timer.night, :go_next}])

	def night(:enter, _old_state, data) do
		updated_data = update_night_actions(data, NightActions.new())
		success(:keep_state, :night, updated_data,
						[{:state_timeout, data.settings.timer.night, :go_next}])
	end

	def night({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def night(:cast, {:select, actor_name, target_name}, data) do
		with  %Player{} = actor  <- Players.get(data.players, actor_name),
					%Player{} = target <- Players.get(data.players, target_name),
					{:ok, night_actions} <- NightActions.select(data.night_actions, actor, target)
		do
			updated_data = update_night_actions(data, night_actions)
			success(:keep_state, :night, updated_data)
		else
			:none ->           error(data.game_id, actor_name, {:error, :unknown_actor_or_target})
			{:error, reason} -> error(data.game_id, actor_name, {:error, reason})
		end
	end

	def night(:cast, {:unselect, actor}, data) do
		night_actions = NightActions.unselect(data.night_actions, actor)
		updated_data = update_night_actions(data, night_actions)
		success(:keep_state, :night, updated_data)
	end

	def night({:call, from}, {:talk_to, name}, data) do
		with  %Player{} = author <- Players.get(data.players, name) do
			{:keep_state_and_data, [{:reply, from, {author.alive and author.role == :mafioso, :mafioso}}]}
		else
			:none -> reply_error(from, {:error, :unknown_author})
		end
	end

	def night(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :go_next}]}

	def night(:state_timeout, :go_next, data) do
		events = NightActions.execute(data.night_actions)
		updated_players = process_events(data.players, events, data.game_id)
		updated_data = update_players(data, updated_players)
		check_win(:morning, updated_data)
	end

	def night({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}
	
	def night(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Game Over state                                                            #
	#----------------------------------------------------------------------------#

	def game_over(:enter, _old_state, data) do
		PubSub.pub(data.game_id, {:game_update, :players, data.players})
		PubSub.pub(data.game_id, {:game_update, :winner, data.winner})
		success(:keep_state_and_data, :game_over, data,
						[{:state_timeout, data.settings.timer.game_over, :exterminate}])
	end

	def game_over({:call, from}, :started?, _), do: {:keep_state_and_data, [{:reply, from, true}]}

	def game_over({:call, from}, {:talk_to, _name}, _data), do:
		{:keep_state_and_data, [{:reply, from, {true, :everyone}}]}

	def game_over(:cast, :next_phase, _data), do:
		{:keep_state_and_data, [{:state_timeout, 0, :exterminate}]}

	def game_over(:state_timeout, :exterminate, _data), do:
		{:stop, {:shutdown, :game_ended}}

	def game_over(_, _, _), do: :keep_state_and_data

	#============================================================================#
	# Private Functions                                                          #
	#============================================================================#

	defp fresh_data(game_id) do
		%{
			game_id: game_id,
			settings: Settings.new(),
			players: Players.new(),
			accusations: nil,
			votes: nil,
			night_actions: nil
		}
	end

	defp roles(n) do
		villagers = (round (n/2)) |> replicate(:townie)
		mafia =  (round (n/4)) |> replicate(:mafioso)
		doctors =   (floor (n/8)) |> replicate(:doctor)
		sheriffs =  (round (n/8)) |> replicate(:sheriff)
		Enum.concat([villagers, mafia, doctors, sheriffs])
	end

	defp roles(n, roles) do
		roles
		|> Enum.reduce([], fn {role, amount}, acc -> [replicate(amount, role) | acc] end)
		|> Enum.concat()
		|> (& replicate(n - length(&1), :townie) ++ &1).()
	end

	defp replicate(0, _), do: []
	defp replicate(n, x) do
		for _ <- 1..n do x end
	end

	defp update_players(data, players) do
		players_without_role = Enum.map(players, &Player.set_role(&1, :unknown))
		PubSub.pub(data.game_id, {:game_update, :players, players_without_role})
		%{data | players: players}
	end

	defp update_settings(data, settings) do
		PubSub.pub(data.game_id, {:game_update, :settings, settings})
		%{data | settings: settings}
	end

	defp update_accusations(data, accusations) do
		PubSub.pub(data.game_id, {:game_update, :accusations, accusations})
		%{data | accusations: accusations}
	end

	defp update_votes(data, votes), do:
		%{data | votes: votes}

	defp update_night_actions(data, night_actions), do:
		%{data | night_actions: night_actions}

	defp process_events(players, events, game_id) do
		process_fun =
			fn
				{_actor, :kill, target}, acc_players ->
					PubSub.pub(game_id, {:game_update, :role, {target, Players.get(acc_players, target).role}})
					Players.kill(acc_players, target)
				{actor, :investigate, target}, acc_players ->
					PubSub.pub_player(game_id, actor, {:game_update, :role, {target, Players.get(acc_players, target).role}})
					acc_players
				_event, acc_players ->
					acc_players
			end
		Enum.reduce(events, players, process_fun)
	end

	defp check_win(next_state, data) do
		case is_win?(data) do
			:no_win -> 
				success(:next_state, next_state, data)
			{:win, winner} ->
				success(:next_state, :game_over, Map.put(data, :winner, winner))
		end
	end

	defp is_win?(data) do
    alive_players =
      data.players
      |> Enum.filter(&(&1.alive))

    players_count = length(alive_players)
    mafia_count = Enum.count(alive_players, &(&1.role == :mafioso))

    cond do
      mafia_count == 0 ->
        {:win, :town}
      2 * mafia_count >= players_count ->
        {:win, :mafia}
      true ->
        :no_win
    end
	end

	defp save_data(state, data) do
		:ets.insert(:game_state, {data.game_id, {state, data}})
	end

	defp success(type, state, data, actions \\ [])

	defp success(:keep_state_and_data, state, data, actions) do
		save_data(state, data)
		{:keep_state_and_data, [@afk_timeout_action | actions]}
	end

	defp success(:keep_state, state, data, actions) do
		save_data(state, data)
		{:keep_state, data, [@afk_timeout_action | actions]}
	end

	defp success(:next_state, next_state, data, actions) do
		PubSub.pub(data.game_id, {:game_update, :phase, next_state})
		PubSub.pub(data.game_id, {:game_update, :timer, data.settings.timer[next_state]})
		{:next_state, next_state, data, [@afk_timeout_action | actions]}
	end

	# defp error(game_id, error) do
	# 	PubSub.pub(game_id, {:game_error, error})
	# 	:keep_state_and_data
	# end

	defp error(_game_id, _name, _error) do
		#PubSub.pub_player(game_id, name, {:game_error, error})
		:keep_state_and_data
	end

	defp reply_error(from, response), do:
		{:keep_state_and_data, [{:reply, from, response}]}
end