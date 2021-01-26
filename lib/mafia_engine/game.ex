defmodule MafiaEngine.Game do
	use GenStateMachine, callback_mode: [:state_functions, :state_enter], restart: :transient

	alias MafiaEngine.{Player, Players, Accusations, Votes, NightActions, PubSub}

	@afk_timeout_action  {{:timeout, :afk}, 24 * 60 * 60 * 1000, :exterminate}
	@timeout 5 * 1000

	#============================================================================#
	# Client Functions                                                           #
	#============================================================================#

	def start_link(game_id), do:
		GenStateMachine.start_link(__MODULE__, game_id, name: via_tuple(game_id))

	def via_tuple(game_id), do: {:via, Registry, {Registry.Game, game_id}}

	def get_players(game), do:
		GenStateMachine.cast(via_tuple(game), :get_players)

	def add_player(game, name), do:
		GenStateMachine.call(via_tuple(game), {:add_player, name})

	def remove_player(game, name), do:
		GenStateMachine.cast(via_tuple(game), {:remove_player, name})

	def start_game(game), do:
		GenStateMachine.cast(via_tuple(game), :start_game)

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

	def initialized(:cast, :get_players, data) do
		PubSub.pub_players(data.game_id, data.players)
		:keep_state_and_data
	end

	def initialized({:call, from}, {:add_player, name}, data) do
		with {:ok, players} <- Players.add(data.players, name)
		do
			updated_data = update_players(data, players)
			success(:keep_state, :initialized, updated_data,
							[{:reply, from, {:ok, players}}])
		else
			{:error, reason} -> reply_error(from, {:error, reason})
		end
	end

	def initialized(:cast, {:remove_player, name}, data) do
		{:ok, players} = Players.remove(data.players, name)
		if map_size(players) > 0 do
			updated_data = update_players(data, players)
			success(:keep_state, :initialized, updated_data)
		else
			{:stop, {:shutdown, :zero_players}}
		end
	end

	def initialized(:cast, :start_game, data) do
		roles = roles(map_size(data.players))
		{:ok, players} = Players.set_roles(data.players, roles)
		updated_data = update_players_secrets(data, players)
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
						[{:state_timeout, @timeout, :go_next}])

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
						[{:state_timeout, @timeout, :go_next}])

	def accusation(:enter, _old_state, data) do
		required =
      data.players
      |> Map.values()
      |> Enum.filter(&(&1.alive))
      |> length()
			|> div(2)
			|> (& &1 + 1).()
		updated_data = update_accusations(data, Accusations.new(required))
		success(:keep_state, :accusation, updated_data,
						[{:state_timeout, @timeout, :go_next}])
	end

	def accusation(:cast, {:accuse, accuser, accused}, data) do
		with  {:ok, accuser_player} <- Map.fetch(data.players, accuser),
					true 									<- accuser_player.alive,
		 		 	{:ok, accused_player} <- Map.fetch(data.players, accused),
		 		 	true 									<- accused_player.alive,
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
			:error ->
				error(data.game_id, accuser, {:error, :unknown_accuser_or_accused})
			false ->
				error(data.game_id, accuser, {:error, :accuser_or_accused_dead})
		end
	end

	def accusation(:cast, {:withdraw, accuser}, data) do
		{:ok, accusations} = Accusations.withdraw(data.accusations, accuser)
		updated_data = update_accusations(data, accusations)
		success(:keep_state, :accusation, updated_data)
	end

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
						[{:state_timeout, @timeout, :go_next}])
	end

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
						[{:state_timeout, @timeout, :go_next}])

	def judgement(:cast, {:vote, vote, voter}, data) do
		with  {:ok, voter_player} <- Map.fetch(data.players, voter),
					true 								<- voter_player.alive,
					{:ok, votes} 				<- Votes.vote(data.votes, vote, voter)
		do
			updated_data = update_votes(data, votes)
			success(:keep_state, :judgement, updated_data)
		else
			:error ->           error(data.game_id, voter, {:error, :unknown_voter})
			false ->            error(data.game_id, voter, {:error, :voter_dead})
			{:error, reason} -> error(data.game_id, voter, {:error, reason})
		end
	end

	def judgement(:cast, {:remove_vote, voter}, data) do
		{:ok, votes} = Votes.remove_vote(data.votes, voter)
		updated_data = update_votes(data, votes)
		success(:keep_state, :judgement, updated_data)
	end

	def judgement(:state_timeout, :go_next, data) do
		updated_data =
			case Votes.result(data.votes) do
				:guilty ->
					updated_players = update_in(data.players, [data.votes.accused], &Player.kill/1)
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
						[{:state_timeout, @timeout, :go_next}])

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
						[{:state_timeout, @timeout, :go_next}])

	def night(:enter, _old_state, data) do
		updated_data = update_night_actions(data, NightActions.new())
		success(:keep_state, :night, updated_data,
						[{:state_timeout, @timeout, :go_next}])
	end

	def night(:cast, {:select, actor, target}, data) do
		with  {:ok, actor_player}  <- Map.fetch(data.players, actor),
					{:ok, target_player} <- Map.fetch(data.players, target),
					{:ok, night_actions} <- NightActions.select(data.night_actions, 
																		actor, actor_player, target, target_player)
		do
			updated_data = update_night_actions(data, night_actions)
			success(:keep_state, :night, updated_data)
		else
			:error ->           error(data.game_id, actor, {:error, :unknown_actor_or_target})
			{:error, reason} -> error(data.game_id, actor, {:error, reason})
		end
	end

	def night(:cast, {:unselect, actor}, data) do
		{:ok, night_actions} = NightActions.unselect(data.night_actions, actor)
		updated_data = update_night_actions(data, night_actions)
		success(:keep_state, :night, updated_data)
	end

	def night(:state_timeout, :go_next, data) do
		{:ok, events} = NightActions.execute(data.night_actions)
		updated_players = process_events(data.players, events)
		updated_data = update_players(data, updated_players)
		check_win(:morning, updated_data)
	end

	def night({:timeout, :afk}, :exterminate, _data), do:
		{:stop, {:shutdown, :timeout}}
	
	def night(_, _, _), do: :keep_state_and_data

	#----------------------------------------------------------------------------#
	# Game Over state                                                            #
	#----------------------------------------------------------------------------#

	def game_over(:enter, _old_state, data), do:
		success(:keep_state_and_data, :game_over, data,
						[{:state_timeout, @timeout, :exterminate}])

	def game_over(:state_timeout, :exterminate, _data), do:
		{:stop, {:shutdown, :game_ended}}

	def game_over(_, _, _), do: :keep_state_and_data

	#============================================================================#
	# Private Functions                                                          #
	#============================================================================#

	defp fresh_data(game_id) do
		%{
			game_id: game_id,
			players: Players.new(),
			accusations: nil,
			votes: nil,
			night_actions: nil
		}
	end

	defp roles(n) do
		villagers = (round (n/2)) |> replicate(:townie)
		mafiosos =  (round (n/4)) |> replicate(:mafioso)
		doctors =   (floor (n/8)) |> replicate(:doctor)
		sheriffs =  (round (n/8)) |> replicate(:sheriff)
		Enum.concat([villagers, mafiosos, doctors, sheriffs])
	end

	defp replicate(0, _), do: []
	defp replicate(n, x) do
		for _ <- 1..n do x end
	end

	defp update_players(data, players) do
		PubSub.pub_players(data.game_id, players)
		%{data | players: players}
	end

	defp update_players_secrets(data, players) do
		PubSub.pub_roles(data.game_id, players)
		%{data | players: players}
	end

	defp update_accusations(data, accusations) do
		PubSub.pub_accusations(data.game_id, accusations)
		%{data | accusations: accusations}
	end

	defp update_votes(data, votes), do:
		%{data | votes: votes}

	defp update_night_actions(data, night_actions), do:
		%{data | night_actions: night_actions}

	defp process_events(players, events) do
		process_fun =
			fn
				{_actor, :kill, target}, acc_players ->
					update_in(acc_players, [target], &Player.kill/1)
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
      |> Map.values()
      |> Enum.filter(&(&1.alive))

    players_count = length(alive_players)
    mafiosos_count = Enum.count(alive_players, &(&1.role == :mafioso))

    cond do
      mafiosos_count == 0 ->
        {:win, :town}
      2 * mafiosos_count >= players_count ->
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
		PubSub.pub_state(data.game_id, next_state)
		{:next_state, next_state, data, [@afk_timeout_action | actions]}
	end

	# defp error(game_id, error) do
	# 	PubSub.pub(game_id, {:game_error, error})
	# 	:keep_state_and_data
	# end

	defp error(game_id, name, error) do
		#PubSub.pub_player(game_id, name, {:game_error, error})
		:keep_state_and_data
	end

	defp reply_error(from, response), do:
		{:keep_state_and_data, [{:reply, from, response}]}
end