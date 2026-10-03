defmodule BotchiniWeb.MusicController do
  @moduledoc """
  Serves the audio of the songs playing on a guild's page. Like screen shares,
  songs get ids that can't be guessed, which only reach the guild's members.
  Browsers ask for parts of the file to start a song in the middle, so ranges
  are supported
  """

  use BotchiniWeb, :controller

  alias Botchini.Screens.Jukebox

  # yt-dlp prefers m4a, which MIME doesn't know
  @content_types %{
    ".m4a" => "audio/mp4",
    ".webm" => "audio/webm",
    ".opus" => "audio/ogg",
    ".mp3" => "audio/mpeg"
  }

  def show(conn, %{"guild_id" => guild_id, "track_id" => track_id}) do
    with {:ok, path} <- Jukebox.file(guild_id, track_id),
         {:ok, %{size: size}} <- File.stat(path) do
      conn
      |> put_resp_content_type(content_type(path), nil)
      |> put_resp_header("accept-ranges", "bytes")
      # A song's file never changes, and ends with it
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_audio(path, size)
    else
      _missing -> send_resp(conn, 404, "Not found")
    end
  end

  defp send_audio(conn, path, size) do
    case conn |> get_req_header("range") |> parse_range(size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :whole ->
        send_file(conn, 200, path)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  # A single range, as "first-last", "first-" or "-suffix". Several ranges at once
  # get the whole file, which is also an answer the spec allows
  @spec parse_range([String.t()], non_neg_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | :whole | :unsatisfiable
  def parse_range(["bytes=" <> spec], size) do
    if String.contains?(spec, ",") do
      :whole
    else
      case spec |> String.trim() |> String.split("-", parts: 2) |> Enum.map(&Integer.parse/1) do
        [{first, ""}, :error] when first < size ->
          {:ok, first, size - 1}

        [{first, ""}, {last, ""}] when first <= last and first < size ->
          {:ok, first, min(last, size - 1)}

        [:error, {suffix, ""}] when suffix > 0 and size > 0 ->
          {:ok, max(size - suffix, 0), size - 1}

        _invalid ->
          :unsatisfiable
      end
    end
  end

  def parse_range(_no_range, _size), do: :whole

  defp content_type(path),
    do: Map.get_lazy(@content_types, Path.extname(path), fn -> MIME.from_path(path) end)
end
