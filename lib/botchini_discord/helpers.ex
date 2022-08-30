defmodule BotchiniDiscord.Helpers do
  @moduledoc """
  Helpers for handling the interaction and options
  """

  alias Nostrum.Struct.ApplicationCommandInteractionData

  alias Botchini.Creators.Schema.Creator
  alias BotchiniDiscord.InteractionBehaviour

  @spec parse_interaction_data(ApplicationCommandInteractionData.t()) ::
          InteractionBehaviour.interaction_input()

  def parse_interaction_data(interaction_data) when is_binary(interaction_data.custom_id) do
    IO.inspect(interaction_data, label: "nope")
    [name, options_string] = String.split(interaction_data.custom_id, "|")

    options =
      String.split(options_string, ":")
      |> Enum.chunk_every(2)
      |> Enum.reduce([], fn [name, value], acc ->
        acc ++ [%{name: name, value: value, focused: false}]
      end)

    {name, options}
  end

  def parse_interaction_data(interaction_data) do
    IO.inspect(interaction_data, label: "data")

    options =
      Map.get(interaction_data, :options, [])
      |> Enum.flat_map(fn opt ->
        if opt.type == 3 do
          %{name: opt.name, value: opt.value, focused: Map.get(opt, :focused, false)}
        else
          parse_interaction_data(opt)
        end
      end)

    {interaction_data.name, options}
  end

  @spec get_service(InteractionBehaviour.interaction_options()) :: Creator.services()
  def get_service(options) do
    {service, _autocomplete} = get_option(options, "service")
    map_service(service)
  end

  @spec get_term(InteractionBehaviour.interaction_options()) :: {String.t(), boolean()}
  def get_term(options) do
    {code, autocomplete} = get_option(options, "term")
    {cleanup_stream_code(code), autocomplete}
  end

  @spec get_option(InteractionBehaviour.interaction_options(), String.t()) ::
          {String.t(), boolean()}
  def get_option(options, name) do
    case Enum.find(options, fn opt -> opt.name == name end) do
      nil ->
        raise("Invalid option received")

      option ->
        {option.value, option.focused}
    end
  end

  defp map_service(service) do
    case String.downcase(service) do
      "twitch" -> :twitch
      "youtube" -> :youtube
      _ -> raise("Invalid service received")
    end
  end

  defp cleanup_stream_code(code) do
    code
    |> String.trim()
    |> String.downcase()
  end
end
