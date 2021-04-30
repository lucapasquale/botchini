defmodule Botchini.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Botchini.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Botchini.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Botchini.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Botchini.Repo, {:shared, self()})
    end

    :ok
  end
end
