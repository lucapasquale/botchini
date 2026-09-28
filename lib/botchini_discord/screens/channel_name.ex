defmodule BotchiniDiscord.Screens.ChannelName do
  @moduledoc """
  Marks a streams channel's name while anyone is sharing their screen. Discord
  only allows renaming a channel twice every 10 minutes, so the name only
  changes when the first screen share goes live or the last one ends
  """

  require Logger

  alias Nostrum.Api.Channel
  alias Nostrum.Error.ApiError

  @live_prefix "🔴-"

  @doc """
  The channel's name with or without the live mark, keeping whatever name it was given
  """
  @spec name(String.t(), boolean()) :: String.t()
  def name(current, live?) do
    base = current |> String.replace_prefix(@live_prefix, "") |> String.replace_prefix("🔴", "")
    if live?, do: @live_prefix <> base, else: base
  end

  @doc """
  Renames the channel if its mark is out of date, telling whether it had to.
  It blocks while Discord's rate limit holds the request, so it's meant to run in a task
  """
  @spec rename(String.t(), boolean()) :: {:ok, boolean()} | :error
  def rename(channel_id, live?) do
    channel_id = String.to_integer(channel_id)

    with {:ok, channel} <- Channel.get(channel_id),
         name when name != channel.name <- name(channel.name, live?),
         {:ok, _channel} <-
           Channel.modify(channel_id, %{name: name}, "Screen shares went live or ended") do
      {:ok, true}
    else
      name when is_binary(name) ->
        {:ok, false}

      {:error, %ApiError{status_code: 403}} ->
        Logger.warning("Can't rename streams channel, missing the Manage Channels permission",
          channel_id: channel_id
        )

        :error

      {:error, error} ->
        Logger.warning("Failed to rename streams channel: #{inspect(error)}",
          channel_id: channel_id
        )

        :error
    end
  end
end
