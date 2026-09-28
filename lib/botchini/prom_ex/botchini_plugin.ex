defmodule Botchini.PromEx.BotchiniPlugin do
  @moduledoc """
  Metrics for Discord interactions, external API calls, music playback and screen sharing
  """

  use PromEx.Plugin

  @duration_buckets [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

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
        )
      ])
    ]
  end
end
