defmodule Botchini.Services.Twitch.AuthMiddleware do
  @moduledoc """
  Middleware to generate accessToken for Twitch API
  """

  use Agent

  def start_link(_initial_value) do
    Agent.start_link(fn -> %{exp: nil, access_token: ""} end, name: __MODULE__)
  end

  def get_token do
    %{exp: exp, access_token: access_token} = Agent.get(__MODULE__, & &1)

    if NaiveDateTime.compare(NaiveDateTime.utc_now(), exp) == :gt do
      access_token
    else
      auth_resp =
        Req.post!("https://id.twitch.tv/oauth2/token",
          params: [
            grant_type: "client_credentials",
            client_id: Application.fetch_env!(:botchini, :twitch_client_id),
            client_secret: Application.fetch_env!(:botchini, :twitch_client_secret)
          ]
        ).body

      Agent.update(__MODULE__, fn _ ->
        %{
          access_token: auth_resp["access_token"],
          exp: NaiveDateTime.add(NaiveDateTime.utc_now(), auth_resp["expires_in"])
        }
      end)

      auth_resp["access_token"]
    end
  end
end
