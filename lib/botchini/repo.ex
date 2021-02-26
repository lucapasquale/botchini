defmodule Botchini.Repo do
  use Ecto.Repo,
    otp_app: :botchini,
    adapter: Ecto.Adapters.Postgres
end
