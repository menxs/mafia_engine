defmodule MafiaEngine.Settings do

  alias __MODULE__

  @role_ratios %{mafioso: 0.25, sheriff: 0.125, doctor: 0.125}

  defstruct [ roles: %{
                mafioso: 0,
                sheriff: 0,
                doctor: 0},
              timer: %{
                morning:  60 * 1000,
                accusation: 3 * 60 * 1000,
                defense: 60 * 1000,
                judgement: 60 * 1000,
                afternoon: 60 * 1000,
                night: 2 * 60 * 1000,
                game_over: 5 * 60 * 1000}
            ]

  def new() do
    %Settings{}
  end

  def player_left(s, n_players) do
    {role, max_ratio_diff} =
      s.roles
      |> Enum.map(fn {role, n} -> {role, n/n_players} end)
      |> Enum.map(fn{role, n} -> {role, n - @role_ratios[role]} end)
      |> Enum.max_by(fn {_, n} -> n end)
      |> IO.inspect()
    if sum_roles(s.roles) > n_players or max_ratio_diff >= 1/n_players do
      %{s | roles: Map.update!(s.roles, role, &(&1 - 1))}
    else
      s
    end
  end
  def player_added(s, n_players) do
    {role, min_ratio_diff} =
      s.roles
      |> Enum.map(fn {role, n} -> {role, n/n_players} end)
      |> Enum.map(fn{role, n} -> {role, n - @role_ratios[role]} end)
      |> Enum.min_by(fn {_, n} -> n end)
    if min_ratio_diff < 0 do
      %{s | roles: Map.update!(s.roles, role, &(&1 + 1))}
    else
      s
    end
  end

  def change_role(s, inc_or_dec, "mafioso", n_players), do: change_role(s, inc_or_dec, :mafioso, n_players)
  def change_role(s, inc_or_dec, "sheriff", n_players), do: change_role(s, inc_or_dec, :sheriff, n_players)
  def change_role(s, inc_or_dec, "doctor", n_players), do:  change_role(s, inc_or_dec, :doctor, n_players)
  def change_role(s, :inc, role, n_players) when is_atom(role) do
    if sum_roles(s.roles) < n_players do
      %{s | roles: Map.update!(s.roles, role, &(&1 + 1))}
    else
      s
    end
  end
  def change_role(s, :dec, role, _n_players) when is_atom(role) do
    if s.roles[role] > 0 do
      %{s | roles: Map.update!(s.roles, role, &(&1 - 1))}
    else
        s
    end
  end

  def sum_roles(roles), do:
    Enum.reduce(roles, 0, fn {_, n}, acc -> n + acc end)

  def change_timer(s, inc_or_dec, "morning"),    do: change_timer(s, inc_or_dec, :morning)
  def change_timer(s, inc_or_dec, "accusation"), do: change_timer(s, inc_or_dec, :accusation)
  def change_timer(s, inc_or_dec, "defense"),    do: change_timer(s, inc_or_dec, :defense)
  def change_timer(s, inc_or_dec, "judgement"),  do: change_timer(s, inc_or_dec, :judgement)
  def change_timer(s, inc_or_dec, "afternoon"),  do: change_timer(s, inc_or_dec, :afternoon)
  def change_timer(s, inc_or_dec, "night"),      do: change_timer(s, inc_or_dec, :night)
  def change_timer(s, inc_or_dec, "game_over"),  do: change_timer(s, inc_or_dec, :game_over)
  def change_timer(s, :inc, phase) when is_atom(phase), do:
    %{s | timer: Map.update!(s.timer, phase, &inc_step/1)}
  def change_timer(s, :dec, phase) when is_atom(phase), do:
    %{s | timer: Map.update!(s.timer, phase, &dec_step/1)}

  def inc_step(ms) when                              ms <          15 * 1000, do: ms
  def inc_step(ms) when          15 * 1000 <= ms and ms <          60 * 1000, do: ms +      15 * 1000
  def inc_step(ms) when          60 * 1000 <= ms and ms <      5 * 60 * 1000, do: ms +      30 * 1000
  def inc_step(ms) when      5 * 60 * 1000 <= ms and ms <     10 * 60 * 1000, do: ms +      60 * 1000
  def inc_step(ms) when     10 * 60 * 1000 <= ms and ms <     30 * 60 * 1000, do: ms +  5 * 60 * 1000
  def inc_step(ms) when     30 * 60 * 1000 <= ms and ms <     60 * 60 * 1000, do: ms + 10 * 60 * 1000
  def inc_step(ms) when     60 * 60 * 1000 <= ms and ms < 6 * 60 * 60 * 1000, do: ms + 60 * 60 * 1000
  def inc_step(ms) when 6 * 60 * 60 * 1000 <= ms                            , do: ms

  def dec_step(ms) when                             ms <=          15 * 1000, do: ms
  def dec_step(ms) when          15 * 1000 < ms and ms <=          60 * 1000, do: ms -      15 * 1000
  def dec_step(ms) when          60 * 1000 < ms and ms <=      5 * 60 * 1000, do: ms -      30 * 1000
  def dec_step(ms) when      5 * 60 * 1000 < ms and ms <=     10 * 60 * 1000, do: ms -      60 * 1000
  def dec_step(ms) when     10 * 60 * 1000 < ms and ms <=     30 * 60 * 1000, do: ms -  5 * 60 * 1000
  def dec_step(ms) when     30 * 60 * 1000 < ms and ms <=     60 * 60 * 1000, do: ms - 10 * 60 * 1000
  def dec_step(ms) when     60 * 60 * 1000 < ms and ms <= 6 * 60 * 60 * 1000, do: ms - 60 * 60 * 1000
  def dec_step(ms) when 6 * 60 * 60 * 1000 < ms                             , do: ms
end