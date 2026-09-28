defmodule BotchiniDiscord.Screens.Interactions.Screen do
  @moduledoc """
  Handles /stream slash command
  """

  alias Nostrum.Constants.{ApplicationCommandOptionType, InteractionCallbackType}
  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.Screens
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}
  alias BotchiniDiscord.Screens.Responses.Components

  @behaviour InteractionBehaviour

  # Only the user who ran the command sees the message
  @ephemeral 64

  @impl InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "stream",
      description: "Share your screen with the server",
      options: [
        %{
          name: "start",
          description: "Get a private link to start sharing your screen",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "stop",
          description: "Stop sharing your screen",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "obs",
          description: "Get a stream key to share your screen from OBS",
          type: ApplicationCommandOptionType.sub_command()
        },
        %{
          name: "watch",
          description: "Watch the screens being shared in this server",
          type: ApplicationCommandOptionType.sub_command()
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.member) do
    reply("Can only be used inside a server!")
  end

  def handle_interaction(interaction, options) do
    cond do
      Helpers.get_option(options, "start") -> handle_start(interaction)
      Helpers.get_option(options, "stop") -> handle_stop(interaction)
      Helpers.get_option(options, "obs") -> handle_obs(interaction)
      Helpers.get_option(options, "watch") -> handle_watch(interaction)
      true -> reply("Invalid command")
    end
  end

  defp handle_start(interaction) do
    owner_name = owner_name(interaction)

    {:ok, room} =
      Screens.start_room(%{
        title: "#{owner_name}'s screen",
        guild_id: Integer.to_string(interaction.guild_id),
        channel_id: Integer.to_string(interaction.channel_id),
        owner_id: Integer.to_string(interaction.user.id),
        owner_name: owner_name
      })

    reply(
      """
      Your screen share **#{Helpers.escape_markdown(room.title)}** is ready! Open **Start sharing** and pick a screen or window.
      Keep that link to yourself, anyone with it can share as you. \
      I'll post the watch link here once you're live.
      """,
      components: [Components.broadcast_screen(room)]
    )
  end

  defp handle_stop(interaction) do
    guild_id = Integer.to_string(interaction.guild_id)

    case Screens.find_owner_room(guild_id, Integer.to_string(interaction.user.id)) do
      nil ->
        reply("You're not sharing your screen")

      room ->
        Screens.stop_room(room)
        reply("Stopped sharing **#{Helpers.escape_markdown(room.title)}**")
    end
  end

  defp handle_obs(interaction) do
    {:ok, key} =
      Screens.create_stream_key(%{
        guild_id: Integer.to_string(interaction.guild_id),
        owner_id: Integer.to_string(interaction.user.id),
        channel_id: Integer.to_string(interaction.channel_id),
        owner_name: owner_name(interaction)
      })

    reply("""
    In OBS, open **Settings → Stream** and set:
    - **Service:** WHIP
    - **Server:** `#{Components.whip_url()}`
    - **Bearer Token:** ||`#{key}`||

    In **Settings → Output**, pick an **H.264** encoder.
    Then **Start Streaming**, and I'll post the watch link here.

    For game audio without Discord, turn on **Capture audio** in Game Capture or add an \
    **Application Audio Capture** source. Keep the token to yourself, running this again replaces it.
    """)
  end

  defp handle_watch(interaction) do
    guild_id = Integer.to_string(interaction.guild_id)
    watch_all = Components.watch_all_screens(guild_id)

    case guild_id |> Screens.list_rooms() |> Enum.filter(& &1.live?) do
      [] ->
        reply(
          "Nobody is sharing their screen right now, open **Watch all** to see screens as they go live",
          components: [watch_all]
        )

      rooms ->
        content =
          Enum.map_join(rooms, "\n", fn room ->
            "🔴 **#{Helpers.escape_markdown(room.title)}** by <@#{room.owner_id}> (#{viewers(room.viewer_count)})"
          end)

        reply(content, components: [watch_all])
    end
  end

  defp viewers(1), do: "1 viewer"
  defp viewers(count), do: "#{count} viewers"

  defp owner_name(interaction) do
    interaction.member.nick || interaction.user.global_name || interaction.user.username
  end

  defp reply(content, data \\ []) do
    %{
      type: InteractionCallbackType.channel_message_with_source(),
      data: Map.merge(%{content: content, flags: @ephemeral}, Map.new(data))
    }
  end
end
