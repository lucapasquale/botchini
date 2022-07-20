defmodule Botchini.Services.Youtube.VideoCache do
  @moduledoc """
  ETS cache for YouTube video_id's posted
  """

  use GenServer

  @name __MODULE__

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid}
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: @name)

  @spec init(any()) :: {:ok, nil}
  def init(_) do
    :ets.new(:video_cache, [:set, :named_table])
    {:ok, nil}
  end

  @spec insert(String.t()) :: {:ok}
  def insert(video_id) do
    GenServer.call(@name, {:insert, {video_id, true}})
  end

  @spec has_video_id(String.t()) :: boolean()
  def has_video_id(video_id) do
    GenServer.call(@name, {:exists, video_id})
  end

  def handle_call({:insert, data}, _ref, state) do
    :ets.insert(:video_cache, data)
    {:reply, :ok, state}
  end

  def handle_call({:exists, video_id}, _ref, state) do
    records = :ets.lookup(:video_cache, video_id)
    {:reply, length(records) > 0, state}
  end
end
