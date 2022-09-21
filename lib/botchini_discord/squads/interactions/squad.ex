defmodule BotchiniDiscord.Squads.Interactions.Squad do
  @moduledoc """
  Handles /squad slash command
  """

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.{ApplicationCommand, Interaction}

  alias Botchini.{Discord, Squads}
  alias BotchiniDiscord.{Helpers, InteractionBehaviour}

  @behaviour InteractionBehaviour

  @impl BotchiniDiscord.InteractionBehaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "squad",
      description: "Create and join squads",
      options: [
        %{
          name: "add",
          description: "Create a new squad",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              name: "name",
              description: "Name of the squad"
            }
          ]
        },
        %{
          name: "join",
          description: "Join a squad",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              autocomplete: true,
              name: "term",
              description: "Name of the squad"
            }
          ]
        },
        %{
          name: "notify",
          description: "Notify all members of a squad",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              autocomplete: true,
              name: "term",
              description: "Name of the squad"
            }
          ]
        },
        %{
          name: "leave",
          description: "Leave a squad",
          type: 1,
          options: [
            %{
              type: 3,
              required: true,
              autocomplete: true,
              name: "term",
              description: "Name of the squad"
            }
          ]
        }
      ]
    }

  @impl InteractionBehaviour
  @spec handle_interaction(Interaction.t(), InteractionBehaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) when is_nil(interaction.member) do
    %{
      type: 4,
      data: %{content: "Can only be used inside a server!"}
    }
  end

  def handle_interaction(interaction, options) do
    cond do
      Helpers.get_option(options, "add") ->
        handle_add(interaction, options)

      Helpers.get_option(options, "join") ->
        handle_join(interaction, options)

      Helpers.get_option(options, "notify") ->
        handle_notify(interaction, options)

      Helpers.get_option(options, "leave") ->
        handle_leave(interaction, options)

      true ->
        %{
          type: 4,
          data: %{content: "Invalid command"}
        }
    end
  end

  defp handle_add(interaction, options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    {name, _autocomplete} = Helpers.get_option!(options, "name")

    Squads.insert(guild, %{name: name})

    %{
      type: 4,
      data: %{content: "Created squad **#{name}**"}
    }
  end

  defp handle_join(interaction, options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    {term_or_id, autocomplete} = Helpers.get_option!(options, "term")

    if autocomplete do
      search_squads(guild, term_or_id)
    else
      squad = Squads.get_by_id!(guild, term_or_id)
      discord_user_id = Integer.to_string(interaction.member.user.id)

      case Squads.insert_member(squad, %{discord_user_id: discord_user_id}) do
        {:error, _} ->
          %{
            type: 4,
            data: %{content: "Already joined **#{squad.name}**!"}
          }

        {:ok, _member} ->
          %{
            type: 4,
            data: %{content: "Joined squad **#{squad.name}**!"}
          }
      end
    end
  end

  defp handle_notify(interaction, options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    {term_or_id, autocomplete} = Helpers.get_option!(options, "term")

    if autocomplete do
      search_squads(guild, term_or_id)
    else
      squad = Squads.get_by_id!(guild, term_or_id)
      users_in_voice = users_in_caller_voice_channel(interaction)

      members_to_call =
        Squads.all_members(squad)
        |> Enum.filter(fn member -> !Enum.member?(users_in_voice, member.discord_user_id) end)

      if members_to_call == [] do
        %{
          type: 4,
          data: %{
            content: "All members from squad #{squad.name} are already on the voice channel"
          }
        }
      else
        %{
          type: 4,
          data: %{
            content: """
            Calling all members from the #{squad.name} squad!
            #{Enum.map_join(members_to_call, "\n", fn member -> "<@#{member.discord_user_id}>" end)}
            """
          }
        }
      end
    end
  end

  defp handle_leave(interaction, options) do
    {:ok, guild} = Discord.upsert_guild(Integer.to_string(interaction.guild_id))
    {term_or_id, autocomplete} = Helpers.get_option!(options, "term")

    if autocomplete do
      search_squads(guild, term_or_id)
    else
      squad = Squads.get_by_id!(guild, term_or_id)
      discord_user_id = Integer.to_string(interaction.member.user.id)

      case Squads.remove_member(squad, %{discord_user_id: discord_user_id}) do
        {:error, :not_found} ->
          %{
            type: 4,
            data: %{content: "You haven't joined the squad **#{squad.name}**!"}
          }

        {:ok, _member} ->
          %{
            type: 4,
            data: %{content: "Left squad **#{squad.name}**!"}
          }
      end
    end
  end

  defp search_squads(guild, term) do
    choices =
      Squads.search_by_term(guild, term)
      |> Enum.map(fn {id, name} -> %{name: name, value: Integer.to_string(id)} end)

    %{
      type: 8,
      data: %{choices: choices}
    }
  end

  defp users_in_caller_voice_channel(interaction) do
    voice_states = GuildCache.get!(interaction.guild_id) |> Map.get(:voice_states)

    case Enum.find(voice_states, fn vs -> vs.user_id == interaction.user.id end) do
      nil ->
        []

      voice_state ->
        voice_states
        |> Enum.filter(fn vs ->
          vs.channel_id == voice_state.channel_id && vs.self_deaf == false
        end)
        |> Enum.map(fn vs -> Integer.to_string(vs.user_id) end)
    end
  end
end
