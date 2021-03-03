defmodule Botchini.Twitch.AuthMiddleware do
  use Agent
  use Tesla

  def start_link(_initial_value) do
    Agent.start_link(fn -> %{exp: nil, access_token: ""} end, name: __MODULE__)
  end

  @behaviour Tesla.Middleware
  def call(env, next, _) do
    env
    |> Tesla.put_header("authorization", "Bearer " <> get_token())
    |> Tesla.run(next)
  end

  defp get_token do
    %{exp: exp, access_token: access_token} = Agent.get(__MODULE__, & &1)

    if NaiveDateTime.utc_now() < exp do
      access_token
    else
      %{access_token: access_token, expires_at: expires_at} = Botchini.Twitch.API.authenticate()

      Agent.update(__MODULE__, fn _ ->
        %{
          access_token: access_token,
          exp: NaiveDateTime.add(NaiveDateTime.utc_now(), expires_at)
        }
      end)

      access_token
    end
  end
end
