defmodule Botchini.Services.Response do
  @moduledoc """
  Builds structs from external API responses
  """

  @doc """
  Builds the struct from the response fields it defines, with either string or
  atom keys. APIs send fields we don't use and add new ones over time (like
  YouTube's `kind` and `etag`, or Twitch's stream `tags`), so those are dropped
  instead of raising
  """
  @spec to_struct(module(), map()) :: struct()
  def to_struct(module, attrs) when is_map(attrs) do
    fields =
      for field <- Map.keys(module.__struct__()) -- [:__struct__],
          {:ok, value} <- [fetch_field(attrs, field)],
          into: %{},
          do: {field, value}

    struct!(module, fields)
  end

  defp fetch_field(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, Atom.to_string(field))
    end
  end
end
