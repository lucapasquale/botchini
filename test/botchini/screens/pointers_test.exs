defmodule BotchiniTest.Screens.PointersTest do
  use ExUnit.Case, async: true

  alias Botchini.Screens.Pointers

  @move %{
    "a" => %{"k" => "s", "i" => "room-1"},
    "p" => [[0.5, 0.25, 1_000, 0], [0.52, 0.3, 1_016, 1]],
    "c" => 3,
    "st" => "neon",
    "w" => 10
  }

  describe "parse_move" do
    test "takes positions over a stream" do
      assert {:ok, move} = Pointers.parse_move(@move)
      assert move.a == %{k: "s", i: "room-1"}
      assert move.p == [[0.5, 0.25, 1_000, 0], [0.52, 0.3, 1_016, 1]]
      assert %{c: 3, st: "neon", w: 10} = move
    end

    test "takes positions far down the page" do
      move = %{@move | "a" => %{"k" => "p", "i" => "guild:1"}, "p" => [[0.5, 12.5, 1_000, 0]]}

      assert {:ok, %{a: %{k: "p", i: "guild:1"}}} = Pointers.parse_move(move)
    end

    test "refuses unknown looks" do
      assert Pointers.parse_move(%{@move | "st" => "blink"}) == :error
      assert Pointers.parse_move(%{@move | "c" => 10}) == :error
      assert Pointers.parse_move(%{@move | "w" => 3}) == :error
      assert Pointers.parse_move(%{@move | "w" => 25}) == :error
    end

    test "refuses positions far from the stream or page" do
      assert Pointers.parse_move(%{@move | "p" => [[3.0, 0.5, 1_000, 0]]}) == :error
      assert Pointers.parse_move(%{@move | "p" => [[0.5, 2.5, 1_000, 0]]}) == :error

      page = %{"k" => "p", "i" => "guild:1"}
      assert Pointers.parse_move(%{@move | "a" => page, "p" => [[0.5, 51, 1_000, 0]]}) == :error
    end

    test "refuses malformed positions" do
      assert Pointers.parse_move(%{@move | "p" => []}) == :error
      assert Pointers.parse_move(%{@move | "p" => [[0.5, 0.5, 1_000]]}) == :error
      assert Pointers.parse_move(%{@move | "p" => [[0.5, 0.5, 1_000, 2]]}) == :error
      assert Pointers.parse_move(%{@move | "p" => [[0.5, 0.5, 1.5, 0]]}) == :error
      assert Pointers.parse_move(%{@move | "p" => [["0.5", 0.5, 1_000, 0]]}) == :error
    end

    test "refuses too many positions at once" do
      points = List.duplicate([0.5, 0.5, 1_000, 0], 41)

      assert Pointers.parse_move(%{@move | "p" => points}) == :error
    end

    test "refuses unknown anchors" do
      assert Pointers.parse_move(%{@move | "a" => %{"k" => "x", "i" => "1"}}) == :error
      assert Pointers.parse_move(%{@move | "a" => %{"k" => "s", "i" => ""}}) == :error

      long_id = String.duplicate("a", 101)
      assert Pointers.parse_move(%{@move | "a" => %{"k" => "s", "i" => long_id}}) == :error
    end

    test "refuses missing fields" do
      assert Pointers.parse_move(Map.delete(@move, "st")) == :error
    end
  end

  describe "parse_effect" do
    @effect %{"e" => "lightning", "a" => %{"k" => "s", "i" => "room-1"}, "x" => 0.4, "y" => 0.6}

    test "knows every shape's effect" do
      assert Enum.sort(Pointers.effects()) ==
               ~w(circle eggplant heart infinity lightning spiral star target)
    end

    test "takes known effects" do
      for effect <- Pointers.effects() do
        assert {:ok, %{e: ^effect, x: 0.4, y: 0.6}} =
                 Pointers.parse_effect(%{@effect | "e" => effect})
      end
    end

    test "refuses unknown effects and positions off the stream" do
      assert Pointers.parse_effect(%{@effect | "e" => "nuke"}) == :error
      assert Pointers.parse_effect(%{@effect | "x" => 5}) == :error
      assert Pointers.parse_effect(Map.delete(@effect, "y")) == :error
    end
  end

  describe "hit_move" do
    test "allows 40 batches a second" do
      limiter =
        Enum.reduce(1..40, Pointers.new_limiter(), fn i, limiter ->
          assert {:ok, limiter} = Pointers.hit_move(limiter, 5_000 + i)
          limiter
        end)

      assert Pointers.hit_move(limiter, 5_999) == :limited
      assert {:ok, _limiter} = Pointers.hit_move(limiter, 6_000)
    end
  end

  describe "hit_effect" do
    test "allows one effect every 1.5 seconds" do
      assert {:ok, limiter} = Pointers.hit_effect(Pointers.new_limiter(), 10_000)
      assert Pointers.hit_effect(limiter, 11_499) == :limited
      assert {:ok, _limiter} = Pointers.hit_effect(limiter, 11_500)
    end
  end
end
