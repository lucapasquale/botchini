defmodule Botchini.Twitch.AuthMiddleware do
  use Agent
  use Tesla

  def start_link(_initial_value) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  @behaviour Tesla.Middleware
  def call(env, next, _) do
    env
    |> Tesla.put_header("authorization", "Bearer " <> get_token())
    |> Tesla.run(next)
  end

  defp get_token do
    case Agent.get(__MODULE__, & &1) do
      nil ->
        token = get_access_token()
        Agent.update(__MODULE__, fn _ -> token end)
        token

      token ->
        token
    end
  end

  defp get_access_token do
    Tesla.client([Tesla.Middleware.JSON])
    |> Tesla.post!("https://id.twitch.tv/oauth2/token", "",
      query: [
        grant_type: "client_credentials",
        client_id: Application.fetch_env!(:botchini, :twitch_client_id),
        client_secret: Application.fetch_env!(:botchini, :twitch_client_secret)
      ]
    )
    |> Map.get(:body)
    |> Map.get("access_token")
  end
end
