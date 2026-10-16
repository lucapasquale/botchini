defmodule Botchini.PromEx.BotchiniPlugin do
  @moduledoc """
  Metrics for Discord interactions, external API calls, music playback, screen
  sharing, and how screens come through to the browsers watching and sharing them
  """

  use PromEx.Plugin

  @duration_buckets [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
  @percent_buckets [0.1, 0.5, 1, 2, 5, 10, 25, 50]
  @jitter_buckets [5, 10, 20, 30, 50, 100, 200, 500]
  @video_kbps_buckets [250, 500, 1_000, 2_000, 3_000, 4_000, 8_000, 15_000, 25_000]
  @audio_kbps_buckets [16, 32, 48, 64, 96, 128, 160, 256]
  @fps_buckets [5, 10, 15, 20, 24, 28, 30, 45, 55, 60]
  @height_buckets [240, 360, 480, 720, 1_080, 1_440, 2_160]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:botchini_discord_interaction_metrics, [
        counter([:botchini, :discord, :interaction, :count],
          event_name: [:botchini, :discord, :interaction, :stop],
          description: "Discord interactions handled, by command and result",
          tags: [:command, :subcommand, :kind, :status]
        ),
        distribution([:botchini, :discord, :interaction, :duration, :milliseconds],
          event_name: [:botchini, :discord, :interaction, :stop],
          measurement: :duration,
          description: "Time to handle a Discord interaction and send its response",
          reporter_options: [buckets: @duration_buckets],
          tags: [:command, :kind],
          unit: {:native, :millisecond}
        )
      ]),
      Event.build(:botchini_http_metrics, [
        counter([:botchini, :http, :request, :count],
          event_name: [:botchini, :http, :request, :stop],
          description: "External API requests, by service and response status",
          tags: [:service, :endpoint, :status, :result]
        ),
        distribution([:botchini, :http, :request, :duration, :milliseconds],
          event_name: [:botchini, :http, :request, :stop],
          measurement: :duration,
          description: "External API request duration",
          reporter_options: [buckets: @duration_buckets],
          tags: [:service],
          unit: {:native, :millisecond}
        )
      ]),
      Event.build(:botchini_music_metrics, [
        counter([:botchini, :music, :track, :start, :count],
          event_name: [:botchini, :music, :track, :start],
          description: "Tracks that started playing",
          tags: [:play_type]
        ),
        counter([:botchini, :music, :track, :failure, :count],
          event_name: [:botchini, :music, :track, :failure],
          description: "Tracks that couldn't be played, by failure reason",
          tags: [:play_type, :reason]
        )
      ]),
      Event.build(:botchini_screens_metrics, [
        counter([:botchini, :screens, :room, :start, :count],
          event_name: [:botchini, :screens, :room, :start],
          description: "Screen sharing rooms created"
        ),
        counter([:botchini, :screens, :room, :live, :count],
          event_name: [:botchini, :screens, :room, :live],
          description: "Screen sharing rooms whose broadcaster went live"
        ),
        counter([:botchini, :screens, :room, :stop, :count],
          event_name: [:botchini, :screens, :room, :stop],
          description: "Screen sharing rooms ended, by reason",
          tags: [:reason]
        ),
        distribution([:botchini, :screens, :room, :duration, :seconds],
          event_name: [:botchini, :screens, :room, :stop],
          measurement: :duration,
          description: "How long screen sharing rooms lasted",
          reporter_options: [buckets: [60, 300, 900, 1_800, 3_600, 7_200, 14_400, 28_800]],
          unit: {:native, :second}
        ),
        distribution([:botchini, :screens, :room, :peak_viewers],
          event_name: [:botchini, :screens, :room, :stop],
          measurement: :peak_viewers,
          description: "Most viewers watching a screen sharing room at once",
          reporter_options: [buckets: [0, 1, 2, 3, 5, 8, 13, 20]]
        ),
        counter([:botchini, :screens, :viewer, :join, :count],
          event_name: [:botchini, :screens, :viewer, :join],
          description: "Viewers that connected to a screen sharing room"
        ),
        counter([:botchini, :screens, :viewer, :leave, :count],
          event_name: [:botchini, :screens, :viewer, :leave],
          description: "Viewers that stopped watching a screen sharing room"
        ),
        last_value([:botchini, :screens, :room, :viewers],
          event_name: [:botchini, :screens, :room, :state],
          measurement: :viewers,
          description: "Viewers currently watching a screen sharing room",
          tags: [:screen_owner_name],
          reporter_options: [keep: :all]
        ),
        last_value([:botchini, :screens, :room, :broadcasting],
          event_name: [:botchini, :screens, :room, :state],
          measurement: :broadcasting,
          description: "1 while a screen sharing room is broadcasting, 0 once it ends",
          tags: [:screen_owner_name],
          reporter_options: [keep: :all]
        )
      ]),
      viewer_metrics(),
      broadcaster_metrics()
    ]
  end

  # What viewers' browsers receive, see Botchini.Screens.ClientStats
  defp viewer_metrics do
    video = [:botchini, :screens, :viewer, :video]
    audio = [:botchini, :screens, :viewer, :audio]

    Event.build(:botchini_viewer_metrics, [
      counter(video ++ [:reports, :count],
        event_name: video,
        description: "Reports from viewers' browsers on the video they receive",
        tags: [:source]
      ),
      client_distribution(video, :kbps, "Video bitrate viewers receive", @video_kbps_buckets),
      client_distribution(video, :fps, "Frames per second viewers decode", @fps_buckets),
      client_distribution(video, :height, "Height of the video viewers receive", @height_buckets),
      client_distribution(
        video,
        :frames_dropped_percent,
        "Frames viewers' browsers dropped",
        @percent_buckets
      ),
      client_distribution(video, :freezes, "Video freezes viewers saw", [0, 1, 2, 5, 10]),
      client_distribution(
        video,
        :packet_loss_percent,
        "Video packets lost on the way to viewers",
        @percent_buckets
      ),
      client_distribution(video, :jitter_ms, "Video jitter viewers see", @jitter_buckets),
      client_distribution(
        video,
        :jitter_buffer_ms,
        "How long viewers' browsers hold video before showing it",
        [20, 50, 100, 200, 300, 500, 1_000, 2_000]
      ),
      counter(audio ++ [:reports, :count],
        event_name: audio,
        description:
          "Reports from viewers' browsers on the audio they receive, and if it's stereo",
        tags: [:source, :stereo]
      ),
      client_distribution(audio, :kbps, "Audio bitrate viewers receive", @audio_kbps_buckets, [
        :source,
        :stereo
      ]),
      client_distribution(
        audio,
        :packet_loss_percent,
        "Audio packets lost on the way to viewers",
        @percent_buckets
      ),
      client_distribution(
        audio,
        :concealed_percent,
        "Audio viewers' browsers had to make up for lost or late packets",
        @percent_buckets
      ),
      client_distribution(audio, :jitter_ms, "Audio jitter viewers see", @jitter_buckets)
    ])
  end

  # What sharing browsers send, see Botchini.Screens.ClientStats
  defp broadcaster_metrics do
    video = [:botchini, :screens, :broadcaster, :video]
    audio = [:botchini, :screens, :broadcaster, :audio]
    video_tags = [:source, :quality_limitation]

    Event.build(:botchini_broadcaster_metrics, [
      counter(video ++ [:reports, :count],
        event_name: video,
        description:
          "Reports from sharing browsers, by why they hold back quality: none, cpu, bandwidth or other",
        tags: video_tags
      ),
      client_distribution(
        video,
        :kbps,
        "Video bitrate sharing browsers send",
        @video_kbps_buckets,
        video_tags
      ),
      client_distribution(
        video,
        :fps,
        "Frames per second sharing browsers send",
        @fps_buckets,
        video_tags
      ),
      client_distribution(
        video,
        :height,
        "Height of the video sharing browsers send",
        @height_buckets,
        video_tags
      ),
      client_distribution(
        video,
        :rtt_ms,
        "Round trip between sharing browsers and the server",
        [10, 25, 50, 100, 200, 500, 1_000],
        video_tags
      ),
      client_distribution(
        video,
        :packet_loss_percent,
        "Video packets lost on the way to the server",
        @percent_buckets,
        video_tags
      ),
      client_distribution(
        audio,
        :kbps,
        "Audio bitrate sharing browsers send",
        @audio_kbps_buckets
      )
    ])
  end

  defp client_distribution(event, measurement, description, buckets, tags \\ [:source]) do
    distribution(event ++ [measurement],
      event_name: event,
      measurement: measurement,
      description: description,
      reporter_options: [buckets: buckets],
      tags: tags
    )
  end
end
