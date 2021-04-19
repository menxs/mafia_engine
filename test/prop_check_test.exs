defmodule PropCheckTest do
  use ExUnit.Case
  use PropCheck

  property "Unique player names" do
    forall p <- players() do 
      not repeated?(p)
    end
  end

  def players(n \\ 30) do
    1..:rand.uniform(n)
    |> Enum.map(&Integer.to_string/1)
  end

  def repeated?([]), do: false
  def repeated?([h | t]), do:
    Enum.member?(t, h) || repeated?(t)

end