defmodule PingPong do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def stop() do
    GenServer.stop(__MODULE__)
  end

  def ping() do
    IO.puts("Ping Pong")
  end

  def pong() do
    IO.puts("Pong Ping")
  end

  def init(_) do
    {:ok, :nostate}
  end

  def handle_call(_call, _from, state), do: {:noreply, state}

  def handle_cast(_cast, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}
end

defmodule PingPongTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM


  property "stateful property", [:verbose] do
    forall cmds <- commands(__MODULE__) do
      PingPong.start_link()
      {history, state, result} = run_commands(__MODULE__, cmds)
      PingPong.stop()

      (result == :ok)
      |> aggregate(command_names(cmds))
      |> when_fail(
        IO.puts("""
        History: #{inspect(history)}
        State: #{inspect(state)}
        Result: #{inspect(result)}
        """)
      )
    end
  end

  def initial_state(), do: true

  def command(true), do: {:call, PingPong, :ping, []}
  def command(false), do: {:call, PingPong, :pong, []}

  def precondition(true, {:call, PingPong, :ping, []}), do: true
  def precondition(true, {:call, PingPong, :pong, []}), do: false
  def precondition(false, {:call, PingPong, :ping, []}), do: false
  def precondition(false, {:call, PingPong, :pong, []}), do: true

  def postcondition(state, {:call, PingPong, :ping, []}, _res) do
    state == true
  end

  def postcondition(state, {:call, PingPong, :pong, []}, _res) do
    state == false
  end

  def next_state(state, _res, {:call, _mod, _fun, _args}) do
    not state
  end

end