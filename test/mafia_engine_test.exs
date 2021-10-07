defmodule MafiaEngineTest do
  use ExUnit.Case
  doctest MafiaEngine

  doctest MafiaEngine.Player
  doctest MafiaEngine.Players
  doctest MafiaEngine.Accusations
  doctest MafiaEngine.Votes
  doctest MafiaEngine.NightActions

  test "greets the world" do
    assert MafiaEngine.hello() == :world
  end
end
