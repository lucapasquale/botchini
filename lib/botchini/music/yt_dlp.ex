defmodule Botchini.Music.YtDlp do
  @moduledoc """
  Looks songs up on YouTube and downloads their audio with yt-dlp, the same one
  the bot plays music with on Discord. Only YouTube links and searches are
  taken, so members can't have the server fetch any address they like
  """

  alias Botchini.Music.PlaybackFailure

  @youtube_hosts [
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be"
  ]

  @max_filesize "100M"

  @type video :: %{
          id: String.t(),
          title: String.t(),
          url: String.t(),
          thumbnail: String.t(),
          duration_ms: pos_integer() | nil,
          channel: String.t() | nil
        }

  @type reason :: PlaybackFailure.reason() | :not_found | :too_big

  @doc """
  Finds the video a YouTube link points to, or the first one a search finds.
  Only what's listed is read, without resolving the video's formats, which is
  much faster. Live streams have no duration
  """
  @spec lookup(String.t()) :: {:ok, video()} | {:error, reason()}
  def lookup(term) do
    with {:ok, target} <- target(term),
         {:ok, output} <-
           run([
             "--flat-playlist",
             "--no-playlist",
             "--playlist-items",
             "1",
             "--print",
             "%(.{id,title,duration,channel})j",
             "--",
             target
           ]) do
      output
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "{"))
      |> parse_video()
    end
  end

  @doc """
  Downloads the video's audio to `dir`, named `name` with the format's extension,
  and returns where it is. m4a is preferred, as every browser plays it
  """
  @spec download(String.t(), Path.t(), String.t()) :: {:ok, Path.t()} | {:error, reason()}
  def download(url, dir, name) do
    args = [
      "--no-playlist",
      "--no-progress",
      "--format",
      "bestaudio[ext=m4a]/bestaudio",
      "--max-filesize",
      @max_filesize,
      "--output",
      Path.join(dir, "#{name}.%(ext)s"),
      "--print",
      "after_move:filepath",
      "--",
      url
    ]

    # A file over the size limit is skipped without an error, so nothing is printed
    with {:ok, output} <- run(args) do
      path = output |> String.split("\n", trim: true) |> List.last()
      if path && File.regular?(path), do: {:ok, path}, else: {:error, :too_big}
    end
  end

  @spec youtube_url?(String.t()) :: boolean()
  def youtube_url?(term), do: URI.parse(term).host in @youtube_hosts

  defp target(term) do
    cond do
      youtube_url?(term) -> {:ok, term}
      String.match?(term, ~r/^https?:/i) -> {:error, :unsupported_url}
      true -> {:ok, "ytsearch1:#{term}"}
    end
  end

  defp parse_video(nil), do: {:error, :not_found}

  defp parse_video(line) do
    with {:ok, %{"id" => id, "title" => title} = video} when is_binary(title) <-
           Jason.decode(line),
         true <- is_binary(id) and String.match?(id, ~r/^[\w-]{11}$/) do
      {:ok,
       %{
         id: id,
         title: title,
         url: "https://www.youtube.com/watch?v=#{id}",
         thumbnail: "https://i.ytimg.com/vi/#{id}/mqdefault.jpg",
         duration_ms: duration_ms(video["duration"]),
         channel: video["channel"]
       }}
    else
      _not_a_video -> {:error, :not_found}
    end
  end

  defp duration_ms(seconds) when is_number(seconds) and seconds > 0, do: round(seconds * 1_000)
  defp duration_ms(_live_or_unknown), do: nil

  defp run(args) do
    executable = Application.get_env(:nostrum, :youtubedl, "yt-dlp")

    case System.cmd(executable, ["--no-warnings", "--socket-timeout", "15" | args],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, _exit_status} -> {:error, output |> PlaybackFailure.classify() |> elem(0)}
    end
  rescue
    # System.cmd raises when the executable can't be found
    _error in ErlangError -> {:error, :executable_missing}
  end
end
