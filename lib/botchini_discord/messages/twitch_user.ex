defmodule BotchiniDiscord.Messages.TwitchUser do
  @moduledoc """
  Embed message on Discord with Twitch user information
  """

  alias Nostrum.Struct.Embed
  import Nostrum.Struct.Embed

  alias Botchini.Twitch.API.Structs.User

  @spec generate_embed(User.t()) :: Embed.t()
  def generate_embed(user) do
    stream_url = "https://www.twitch.tv/" <> user.login

    %Embed{}
    |> put_author(user.display_name, stream_url, user.profile_image_url)
    |> put_title(user.display_name)
    |> put_description(user.description)
    |> put_url(stream_url)
    |> put_thumbnail(user.profile_image_url)
    |> put_color(6_570_404)
    |> put_footer("Since")
    |> put_timestamp(user.created_at)
  end
end
