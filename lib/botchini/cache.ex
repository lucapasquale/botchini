defmodule Botchini.Cache do
  @moduledoc """
  ETS caches with TTL functionality
  """

  use GenServer

  @name __MODULE__
  @table :cache

  # 30 minutes
  @default_ttl 30 * 60 * 1_000

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid}
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: @name)

  @spec init(any()) :: {:ok, nil}
  def init(_) do
    :ets.new(@table, [:set, :named_table])
    {:ok, nil}
  end

  @spec get_value(String.t(), pos_integer(), (-> any())) :: {:ok, any()}
  def get_value(key, ttl \\ @default_ttl, resolver) when is_function(resolver) do
    case GenServer.call(@name, {:get, key}) do
      nil ->
        with result <- resolver.() do
          GenServer.call(@name, {:insert, {key, result, ttl}})
          {:ok, result}
        end

      cached_value ->
        {:ok, cached_value}
    end
  end

  def handle_call({:get, key}, _ref, state) do
    case :ets.lookup(@table, key) do
      [{^key, value, deleted_at}] ->
        if timestamp() <= deleted_at do
          {:reply, value, state}
        else
          true = :ets.delete(@table, key)
          {:reply, nil, state}
        end

      _else ->
        {:reply, nil, state}
    end
  end

  def handle_call({:insert, {key, value, ttl}}, _ref, state) do
    deleted_at = timestamp() + ttl

    true = :ets.insert(@table, {key, value, deleted_at})
    {:reply, value, state}
  end

  defp timestamp, do: System.os_time(:millisecond)
end
