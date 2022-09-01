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
    options =
      Map.get(interaction_data, :options, [])
      |> Enum.flat_map(&parse_data_option(&1))

    {interaction_data.name, options}
  end

  # Sub-command
  defp parse_data_option(option) when option.type == 1 do
    [%{name: option.name, value: "", focused: false}] ++
      Enum.map(option.options, &parse_data_option(&1))
  end

  # Option
  defp parse_data_option(option) do
    %{
      name: option.name,
      value: option.value,
      focused: if(is_nil(option.focused), do: false, else: option.focused)
    }
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

  @spec get_option!(InteractionBehaviour.interaction_options(), String.t()) ::
          {String.t(), boolean()}
  def get_option!(options, name) do
    case get_option(options, name) do
      nil ->
        raise("Invalid option received")

      option ->
        option
    end
  end

  @spec get_option(InteractionBehaviour.interaction_options(), String.t()) ::
          nil | {String.t(), boolean()}
  def get_option(options, name) do
    case Enum.find(options, fn opt -> opt.name == name end) do
      nil ->
        nil

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
