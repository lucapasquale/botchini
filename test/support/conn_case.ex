defmodule BotchiniWeb.ConnCase do
  @moduledoc """
  Case for tests that go through the web endpoint, like controllers and LiveViews
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BotchiniWeb.Endpoint

      use BotchiniWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
