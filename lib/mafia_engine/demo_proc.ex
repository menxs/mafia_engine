defmodule MafiaEngine.DemoProc do
	def init(game_id) do
		{:ok, _} = Registry.register(Registry.GamePubSub, game_id, [])
		loop(game_id)
	end
  def loop(game_id) do
    receive do
      message -> IO.puts "#{game_id} got a message:\n#{inspect(message)}"
    end
    loop(game_id)
  end
end
