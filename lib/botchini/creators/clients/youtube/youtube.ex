defmodule Botchini.Creators.Clients.Youtube do
  @moduledoc """
  Handles communication with YouTube API
  """

  use Tesla

  alias Botchini.Creators.Clients.Youtube

  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.Logger)
  plug(Tesla.Middleware.BaseUrl, "https://youtube.googleapis.com/youtube/v3")

  plug(Tesla.Middleware.Query, [
    {"key", Application.fetch_env!(:botchini, :youtube_api_key)}
  ])

  @spec get_channel(String.t()) :: Youtube.Structs.Channel.t() | nil
  def get_channel(code) do
    {:ok, %{body: body}} =
      get("/channels",
        query: [
          part: "snippet,statistics",
          forUsername: code
        ]
      )

    case Map.get(body, "items") do
      nil ->
        nil

      items ->
        List.first(items)
        |> Youtube.Structs.Channel.new()
    end
  end
end
