defmodule Botchini.LokiLogger do
  @moduledoc false
  use GenServer

  @flush_interval :timer.seconds(5)
  @max_buffer_size 100

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def push(entry) do
    GenServer.cast(__MODULE__, {:log, entry})
  catch
    :exit, _ -> :ok
  end

  # Erlang :logger handler callback
  @doc false
  def log(log_event, handler_config) do
    %{level: level, meta: meta} = log_event

    {fmt_mod, fmt_config} = handler_config.formatter

    message =
      fmt_mod.format(log_event, fmt_config)
      |> IO.iodata_to_binary()
      |> String.trim_trailing()

    timestamp_ns =
      case meta do
        %{time: time} -> time * 1_000
        _ -> System.system_time(:nanosecond)
      end

    push({to_string(level), timestamp_ns, message})
  rescue
    _ -> :ok
  end

  # -- GenServer callbacks --

  @impl true
  def init(_) do
    case Application.get_env(:botchini, __MODULE__) do
      nil ->
        :ignore

      opts ->
        :logger.add_handler(:loki, __MODULE__, %{
          level: :all,
          formatter: {LoggerJSON.Formatters.Basic, [metadata: :all]}
        })

        schedule_flush()

        {:ok,
         %{
           endpoint: Keyword.fetch!(opts, :endpoint),
           headers: Keyword.get(opts, :headers, []),
           labels: Keyword.get(opts, :labels, %{}),
           buffer: [],
           buffer_size: 0
         }}
    end
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    buffer = [entry | state.buffer]
    size = state.buffer_size + 1

    if size >= @max_buffer_size do
      flush_buffer(buffer, state)
      {:noreply, %{state | buffer: [], buffer_size: 0}}
    else
      {:noreply, %{state | buffer: buffer, buffer_size: size}}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    flush_buffer(state.buffer, state)
    schedule_flush()
    {:noreply, %{state | buffer: [], buffer_size: 0}}
  end

  @impl true
  def terminate(_reason, state) do
    :logger.remove_handler(:loki)
    flush_buffer(state.buffer, state)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp flush_buffer([], _state), do: :ok

  defp flush_buffer(buffer, state) do
    streams =
      buffer
      |> Enum.reverse()
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {level, entries} ->
        %{
          "stream" => Map.merge(state.labels, %{"level" => level}),
          "values" =>
            Enum.map(entries, fn {_level, ts, msg} ->
              [Integer.to_string(ts), msg]
            end)
        }
      end)

    Req.post("#{state.endpoint}/loki/api/v1/push",
      headers: [{"content-type", "application/json"} | state.headers],
      body: Jason.encode!(%{"streams" => streams}),
      retry: false,
      receive_timeout: 5_000
    )
  rescue
    _ -> :ok
  end
end
