defmodule Botchini.Music.PlaybackFailure do
  @moduledoc """
  Finds out why a track couldn't be played. Nostrum only reports that no audio was
  produced, so the track is fetched again, without downloading it, to capture the error
  """

  alias Botchini.Music.Schema.Track

  @type reason ::
          :age_restricted
          | :bot_check
          | :forbidden
          | :rate_limited
          | :unavailable
          | :unsupported_url
          | :stream_offline
          | :executable_missing
          | :transient
          | :unknown

  # Checked in order, the first pattern found in the error output wins
  @reason_patterns [
    age_restricted: ["confirm your age", "age-restricted", "inappropriate for some users"],
    bot_check: ["not a bot"],
    forbidden: ["HTTP Error 403"],
    rate_limited: ["HTTP Error 429"],
    unavailable: ["unavailable", "Private video", "removed", "HTTP Error 404"],
    unsupported_url: ["Unsupported URL"],
    stream_offline: ["No playable streams"]
  ]

  @doc """
  Returns the failure reason and, when there is one, the error printed by the tool.
  A track that loads fine this time is reported as `:transient`
  """
  @spec diagnose(Track.t()) :: {reason(), String.t() | nil}
  def diagnose(%Track{play_type: :ytdl, play_url: url}) do
    Application.get_env(:nostrum, :youtubedl, "yt-dlp")
    |> run(["--simulate", "--quiet", "--no-warnings", "--socket-timeout", "15", url])
  end

  def diagnose(%Track{play_type: :stream, play_url: url}) do
    Application.get_env(:nostrum, :streamlink, "streamlink")
    |> run(["--json", url])
  end

  @spec classify(String.t()) :: {reason(), String.t() | nil}
  def classify(output) do
    reason =
      Enum.find_value(@reason_patterns, :unknown, fn {reason, patterns} ->
        if String.contains?(output, patterns), do: reason
      end)

    {reason, error_message(output)}
  end

  defp run(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_output, 0} -> {:transient, nil}
      {output, _exit_status} -> classify(output)
    end
  rescue
    # System.cmd raises when the executable can't be found
    error in ErlangError -> {:executable_missing, Exception.message(error)}
  end

  # yt-dlp prints "ERROR: ..." lines, streamlink --json prints {"error": "..."}
  defp error_message(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.find_value(lines, List.first(lines), fn line ->
      case Regex.run(~r/^ERROR: (.*)$|"error": "(.*)"/, String.trim(line)) do
        nil -> nil
        captures -> captures |> Enum.drop(1) |> Enum.find(&(&1 != ""))
      end
    end)
  end
end
