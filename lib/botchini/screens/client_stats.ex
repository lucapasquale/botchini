defmodule Botchini.Screens.ClientStats do
  @moduledoc """
  What the browsers watching and sharing screens say about their connection,
  from WebRTC's stats, as metrics. Pages report every few seconds, and as it's
  the browser's word, only numbers in sensible ranges are kept and a page reports
  at most once every 5 seconds per screen.

  Viewers report what they receive, telling apart the screens' sources and, for
  audio, whether it's in stereo. Broadcasters report what they send, and why
  their browser is holding back quality, if it is.
  """

  @min_interval_ms 5_000

  @sources ~w(screen window tab obs)
  @quality_limitations ~w(none cpu bandwidth other)

  # Field => highest sensible value, read from the browser's JSON by name
  @video_fields %{
    kbps: 200_000,
    fps: 240,
    height: 4_320,
    frames_dropped_percent: 100,
    freezes: 100,
    frozen_percent: 100,
    # Reports are meant to take 10s; a much longer gap is not a report interval
    elapsed_ms: 600_000,
    packet_loss_percent: 100,
    jitter_ms: 10_000,
    jitter_buffer_ms: 10_000
  }
  @audio_fields %{
    kbps: 1_000,
    packet_loss_percent: 100,
    concealed_percent: 100,
    jitter_ms: 10_000
  }
  @broadcast_video_fields %{
    kbps: 200_000,
    fps: 240,
    height: 4_320,
    packet_loss_percent: 100,
    rtt_ms: 10_000
  }
  @broadcast_audio_fields %{kbps: 1_000}

  @doc """
  Whether a page can report about `key` again, and when it last did if so. Pages
  keep the map of when they reported
  """
  @spec due(%{optional(term()) => integer()}, term(), integer()) ::
          {:ok, %{optional(term()) => integer()}} | :too_soon
  def due(reported_at, key, now_ms) do
    case reported_at do
      %{^key => last} when now_ms - last < @min_interval_ms -> :too_soon
      _first_or_due -> {:ok, Map.put(reported_at, key, now_ms)}
    end
  end

  @doc """
  What a viewer receives of a screen whose room has `source`
  """
  @spec viewer(atom() | nil, map()) :: :ok
  def viewer(source, params) do
    source = source_tag(source)

    emit([:botchini, :screens, :viewer, :video], params["video"], @video_fields, %{source: source})

    emit([:botchini, :screens, :viewer, :audio], params["audio"], @audio_fields, %{
      source: source,
      stereo: to_string(match?(%{"stereo" => true}, params["audio"]))
    })
  end

  @doc """
  What a broadcaster sends from a screen whose room has `source`
  """
  @spec broadcaster(atom() | nil, map()) :: :ok
  def broadcaster(source, params) do
    source = source_tag(source)

    limitation =
      if params["quality_limitation"] in @quality_limitations,
        do: params["quality_limitation"],
        else: "other"

    emit([:botchini, :screens, :broadcaster, :video], params["video"], @broadcast_video_fields, %{
      source: source,
      quality_limitation: limitation
    })

    emit([:botchini, :screens, :broadcaster, :audio], params["audio"], @broadcast_audio_fields, %{
      source: source
    })
  end

  defp source_tag(source) when is_atom(source) and source != nil do
    source = Atom.to_string(source)
    if source in @sources, do: source, else: "other"
  end

  defp source_tag(_unknown), do: "unknown"

  defp emit(event, values, fields, metadata) when is_map(values) do
    measurements =
      for {field, max} <- fields,
          value = values[Atom.to_string(field)],
          is_number(value) and value >= 0 and value <= max,
          into: %{},
          do: {field, value}

    if measurements != %{}, do: :telemetry.execute(event, measurements, metadata)
    :ok
  end

  defp emit(_event, _not_a_map, _fields, _metadata), do: :ok
end
