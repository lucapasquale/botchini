defmodule Botchini.Services.Twitch.AuthMiddleware do
  @moduledoc """
  Middleware to generate accessToken for Twitch API
  """

  use Agent

  alias Botchini.Services.Telemetry

  def start_link(_initial_value) do
    Agent.start_link(fn -> %{exp: nil, access_token: ""} end, name: __MODULE__)
  end

  def get_token do
    %{exp: exp, access_token: access_token} = Agent.get(__MODULE__, & &1)

    if exp != nil and DateTime.before?(DateTime.utc_now(), exp) do
      access_token
    else
      auth_resp =
        Req.new(url: "https://id.twitch.tv/oauth2/token")
        |> Telemetry.attach(:twitch_auth)
        |> Req.post!(
          params: [
            grant_type: "client_credentials",
            client_id: Application.fetch_env!(:botchini, :twitch_client_id),
            client_secret: Application.fetch_env!(:botchini, :twitch_client_secret)
          ]
        ).body

      Agent.update(__MODULE__, fn _ ->
        %{
          access_token: auth_resp["access_token"],
          exp: DateTime.add(DateTime.utc_now(), auth_resp["expires_in"])
        }
      end)

      auth_resp["access_token"]
    end
  end
end
