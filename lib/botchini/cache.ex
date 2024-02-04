defmodule Botchini.Cache do
  @moduledoc """
  ETS caches with TTL functionality
  """

  use GenServer

  @name __MODULE__
  @table :cache

  # 30 minutes
  @default_ttl 1_000 * 60 * 30

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid}
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: @name)

  @spec init(any()) :: {:ok, nil}
  def init(_) do
    :ets.new(@table, [:set, :named_table])
    {:ok, nil}
  end

  @spec get(String.t()) :: {:ok, any() | nil}
  def get(key) do
    {:ok, GenServer.call(@name, {:get, key})}
  end

  @spec set(String.t(), pos_integer(), (-> any())) :: {:ok, any()}
  def set(key, ttl \\ @default_ttl, resolver) when is_function(resolver) do
    with result <- resolver.() do
      GenServer.call(@name, {:insert, {key, result, ttl}})
      {:ok, result}
    end
  end

  @spec get_or_set(String.t(), pos_integer(), (-> any())) :: {:ok, any()}
  def get_or_set(key, ttl \\ @default_ttl, resolver) when is_function(resolver) do
    case get(key) do
      {:ok, nil} -> set(key, ttl, resolver)
      {:ok, value} -> {:ok, value}
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
