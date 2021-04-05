defmodule Botchini.Release do
  @moduledoc """
  Migrations to be run before deploying prod application
  """

  def migrate do
    {:ok, _} = Application.ensure_all_started(:botchini)

    path = Application.app_dir(:botchini, "priv/repo/migrations")
    Ecto.Migrator.run(Botchini.Repo, path, :up, all: true)

    :init.stop()
  end
end
