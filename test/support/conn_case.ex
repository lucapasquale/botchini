defmodule BotchiniWeb.ConnCase do
  @moduledoc """
  Case for tests that go through the web endpoint, like controllers and LiveViews
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      @endpoint BotchiniWeb.Endpoint

      use BotchiniWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
    end
  end

  # Pages reach the database from their own processes, so tests that aren't
  # async share their connection
  setup tags do
    :ok = Sandbox.checkout(Botchini.Repo)

    unless tags[:async] do
      Sandbox.mode(Botchini.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
