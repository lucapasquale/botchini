defmodule BotchiniTest do
  use ExUnit.Case
  doctest Botchini

  test "greets the world" do
    assert Botchini.hello() == :world
  end
end
