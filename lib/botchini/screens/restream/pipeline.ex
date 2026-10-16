defmodule Botchini.Screens.Restream.Pipeline do
  @moduledoc """
  ffmpeg reading a video or live stream from the media links yt-dlp found, and
  turning it into H.264 and Opus in real time, sent as RTP to two local UDP ports.
  Videos can start partway through, which ffmpeg skips to exactly and right away.

  It runs under a small shell script, which like every port's program is the
  leader of a session of its own. When the port closes, even with the BEAM going
  down, the script kills its session, as ffmpeg sending to UDP would never notice
  on its own
  """

  @doc """
  The format whose links to look up: ones ffmpeg decodes cheaply first. Live
  streams on YouTube have separate video and audio too, while Twitch's are always
  together
  """
  @spec format() :: String.t()
  def format, do: "bv*[height<=720][vcodec^=avc1]+ba/bv*[height<=720]+ba/b[height<=720]/b"

  # Viewers decode H.264 Constrained Baseline at level 3.1, up to 1280x720 at
  # 30 fps. Keyframes every 2 seconds stand in for asking the broadcaster for one,
  # and each comes with its SPS and PPS, so viewers can join at any of them.
  # RTCP goes to the same ports, as ffmpeg would otherwise send it to the next
  # ones, which could be anything's.
  #
  # Separate video and audio come as two links, and the audio is in the last one.
  # Live streams can't start partway through
  @script ~S"""
  exec 3<&0
  { cat >/dev/null; kill -TERM 0; } <&3 &
  video_port=$1 audio_port=$2 ffmpeg=$3 start_s=$4
  shift 4
  audio_input=$(($# - 1))

  for link do
    if [ "$start_s" = 0 ]; then
      set -- "$@" -re -reconnect 1 -reconnect_delay_max 5 -i "$link"
    else
      set -- "$@" -ss "$start_s" -re -reconnect 1 -reconnect_delay_max 5 -i "$link"
    fi
    shift
  done

  "$ffmpeg" -hide_banner -loglevel error -nostats -nostdin "$@" \
    -map 0:v:0 -c:v libx264 -preset veryfast -tune zerolatency \
    -profile:v baseline -level:v 3.1 -pix_fmt yuv420p \
    -vf "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,fps=30" \
    -g 60 -b:v 2500k -maxrate 2500k -bufsize 5000k \
    -f rtp "rtp://127.0.0.1:$video_port?pkt_size=1200&rtcpport=$video_port" \
    -map "$audio_input:a:0?" -c:a libopus -ar 48000 -ac 2 -b:a 128k \
    -f rtp "rtp://127.0.0.1:$audio_port?pkt_size=1200&rtcpport=$audio_port" </dev/null >/dev/null &
  pipeline=$!
  trap '' TERM
  wait "$pipeline"
  status=$?
  kill -TERM 0
  exit "$status"
  """

  @doc """
  Starts showing the media, links from `format/0`, sending video to `video_port`
  and audio to `audio_port`. Videos start `start_s` seconds in. The calling
  process gets the port's messages: what ffmpeg prints, and the exit status once
  the video ends or something fails
  """
  @spec open([String.t()], :inet.port_number(), :inet.port_number(), non_neg_integer()) ::
          port()
  def open([_ | _] = media, video_port, audio_port, start_s \\ 0) do
    ffmpeg = Application.get_env(:nostrum, :ffmpeg, "ffmpeg")

    Port.open({:spawn_executable, System.find_executable("sh")}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args:
        [
          "-c",
          @script,
          "restream",
          Integer.to_string(video_port),
          Integer.to_string(audio_port),
          ffmpeg,
          Integer.to_string(start_s)
        ] ++ media
    ])
  end

  @doc """
  Stops ffmpeg, unless it already exited. The script kills it once
  it notices the port closed, this doesn't wait for that
  """
  @spec close(port()) :: :ok
  def close(port) do
    Port.close(port)
    :ok
  rescue
    # It exited already
    ArgumentError -> :ok
  end
end
