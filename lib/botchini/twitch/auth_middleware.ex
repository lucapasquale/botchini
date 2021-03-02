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
      auth_resp = request_twitch_tokens()

      Agent.update(__MODULE__, fn _ ->
        %{
          access_token: auth_resp["access_token"],
          exp: NaiveDateTime.add(NaiveDateTime.utc_now(), auth_resp["expires_in"])
        }
      end)

      auth_resp["access_token"]
    end
  end

  defp request_twitch_tokens do
    Tesla.client([Tesla.Middleware.JSON])
    |> Tesla.post!("https://id.twitch.tv/oauth2/token", "",
      query: [
        grant_type: "client_credentials",
        client_id: Application.fetch_env!(:botchini, :twitch_client_id),
        client_secret: Application.fetch_env!(:botchini, :twitch_client_secret)
      ]
    )
    |> Map.get(:body)
  end
end
