defmodule BotchiniTest.Screens.SoundsTest do
  use ExUnit.Case, async: true

  alias Botchini.Screens.Sounds

  describe "all" do
    test "every sound has a file in priv/static/sounds" do
      for sound <- Sounds.all() do
        assert File.exists?(Path.join([:code.priv_dir(:botchini), "static/sounds", sound.file]))
      end
    end
  end

  describe "hit" do
    defp hits(times) do
      Enum.reduce(times, {Sounds.new_limiter(), []}, fn now, {limiter, results} ->
        case Sounds.hit(limiter, now) do
          {:ok, limiter} -> {limiter, results ++ [:ok]}
          {:cooldown, left_ms} -> {limiter, results ++ [{:cooldown, left_ms}]}
        end
      end)
      |> elem(1)
    end

    test "starts a cooldown after three sounds within three seconds" do
      assert hits([0, 1_000, 2_900, 3_000, 7_899, 7_900]) ==
               [:ok, :ok, :ok, {:cooldown, 4_900}, {:cooldown, 1}, :ok]
    end

    test "allows any number of sounds spread out over time" do
      assert hits([0, 1_500, 3_000, 4_500, 6_000, 7_500]) == List.duplicate(:ok, 6)
    end

    test "starts counting again after the cooldown" do
      assert hits([0, 100, 200, 5_200, 5_300, 5_400, 5_500]) ==
               [:ok, :ok, :ok, :ok, :ok, :ok, {:cooldown, 4_900}]
    end
  end

  describe "cooldown_left" do
    test "is zero when not cooling down" do
      assert Sounds.cooldown_left(Sounds.new_limiter(), 1_000) == 0
    end
  end
end
