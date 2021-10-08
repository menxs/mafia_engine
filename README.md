# MafiaEngine

MafiaEngine implements the basic logic of the [Mafia party game](https://en.wikipedia.org/wiki/Mafia_(party_game)). With the posiblity of handling multiple games at the same time.

## Installation

The package can be installed
by adding `mafia_engine` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mafia_engine, "~> 0.1.1"}
  ]
end
```

## Usage



```elixir
Alias MafiaEngine

# Create a new game
game_id = GameSupervisor.start_game()

# Add players
{:ok, _players} = Game.add_player(game_id, "Jeff")
{:ok, _players} = Game.add_player(game_id, "Abed")
{:ok, _players} = Game.add_player(game_id, "Britta")
{:ok, _players} = Game.add_player(game_id, "Troy")

# Subscribe for game update messages of a player
PubSub.sub_player(game_id, "Abed", self())

# Start game
Game.start_game(game_id)

# Transition to next phase
Game.next_phase(game_id)

# Input player actions
Game.accuse(game_id, "Jeff", "Abed")
Game.vote_innocent(game_id, "Britta")
Game.select(game_id, "Troy", "Abed")
```

## Architecture
[MafiaEngine Architechture](/doc/diagrams/SComponentEngine.png)