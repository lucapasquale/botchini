defmodule Botchini.Screens.Restream.Pipeline do
  @moduledoc """
  yt-dlp downloading a video or live stream as it plays, piped into ffmpeg,
  which turns it into H.264 and Opus in real time and sends them as RTP to two
  local UDP ports. Videos started partway through are read by ffmpeg itself from
  the media yt-dlp finds instead, which skips there exactly and right away.

  Both run under a small shell script, which like every port's program is the
  leader of a session of its own. When the port closes, even with the BEAM going
  down, the script kills its session, as ffmpeg sending to UDP would never notice
  on its own
  """

  # Formats ffmpeg decodes cheaply come first. Live streams on YouTube have
  # separate video and audio too, while Twitch's are always together
  @format "bv*[height<=720][vcodec^=avc1]+ba/bv*[height<=720]+ba/b[height<=720]/b"

  # Viewers decode H.264 Constrained Baseline at level 3.1, up to 1280x720 at
  # 30 fps. Keyframes every 2 seconds stand in for asking the broadcaster for one,
  # and each comes with its SPS and PPS, so viewers can join at any of them.
  # RTCP goes to the same ports, as ffmpeg would otherwise send it to the next
  # ones, which could be anything's.
  #
  # yt-dlp can start partway through too, but it cuts the video at its next
  # keyframe, seconds after the audio, which ffmpeg then races through. Separate
  # video and audio come as two links, and the audio is in the last one
  @script ~S"""
  exec 3<&0
  { cat >/dev/null; kill -TERM 0; } <&3 &
  url=$1 video_port=$2 audio_port=$3 youtubedl=$4 ffmpeg=$5 format=$6 start_s=$7

  encode() {
    "$ffmpeg" -hide_banner -loglevel error -nostats -nostdin "$@" \
      -map 0:v:0 -c:v libx264 -preset veryfast -tune zerolatency \
      -profile:v baseline -level:v 3.1 -pix_fmt yuv420p \
      -vf "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,fps=30" \
      -g 60 -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -f rtp "rtp://127.0.0.1:$video_port?pkt_size=1200&rtcpport=$video_port" \
      -map "$audio_input:a:0?" -c:a libopus -ar 48000 -ac 2 -b:a 128k \
      -f rtp "rtp://127.0.0.1:$audio_port?pkt_size=1200&rtcpport=$audio_port" >/dev/null
  }

  if [ "$start_s" = 0 ]; then
    audio_input=0
    { "$youtubedl" --no-warnings --quiet --no-playlist --socket-timeout 15 --format "$format" \
        --output - -- "$url" </dev/null | encode -re -i pipe:0; } &
  else
    media=$("$youtubedl" --no-warnings --quiet --no-playlist --socket-timeout 15 \
      --format "$format" --print urls -- "$url" </dev/null) || {
      # The watcher would keep the port from seeing the exit
      status=$?
      trap '' TERM
      kill -TERM 0
      exit "$status"
    }
    # Links have a ? in them, which mustn't match files
    set -f
    set --
    audio_input=-1
    for link in $media; do
      set -- "$@" -ss "$start_s" -re -reconnect 1 -reconnect_delay_max 5 -i "$link"
      audio_input=$((audio_input + 1))
    done
    set +f
    encode "$@" </dev/null &
  fi
  pipeline=$!
  trap '' TERM
  wait "$pipeline"
  status=$?
  kill -TERM 0
  exit "$status"
  """

  @doc """
  Starts showing `url`, sending video to `video_port` and audio to `audio_port`.
  Videos start `start_s` seconds in. The calling process gets the port's
  messages: what yt-dlp and ffmpeg print, and the exit status once the video ends
  or something fails
  """
  @spec open(String.t(), :inet.port_number(), :inet.port_number(), non_neg_integer()) :: port()
  def open(url, video_port, audio_port, start_s \\ 0) do
    youtubedl = Application.get_env(:nostrum, :youtubedl, "yt-dlp")
    ffmpeg = Application.get_env(:nostrum, :ffmpeg, "ffmpeg")

    Port.open({:spawn_executable, System.find_executable("sh")}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: [
        "-c",
        @script,
        "restream",
        url,
        Integer.to_string(video_port),
        Integer.to_string(audio_port),
        youtubedl,
        ffmpeg,
        @format,
        Integer.to_string(start_s)
      ]
    ])
  end

  @doc """
  Stops yt-dlp and ffmpeg, unless they already exited. The script kills them once
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
