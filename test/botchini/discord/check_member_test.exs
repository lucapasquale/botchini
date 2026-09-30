defmodule Botchini.Discord.CheckMemberTest do
  use ExUnit.Case, async: false

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Nostrum.Api.Guild, as: GuildApi
  alias Nostrum.Error.ApiError

  alias Botchini.Discord

  test "finds members" do
    patch_function(GuildApi, :member, {:ok, %Nostrum.Struct.Guild.Member{}})

    assert Discord.check_member("1", "10") == :member
    assert_called(GuildApi.member(1, 10))
  end

  test "finds who isn't in the guild" do
    patch_function(
      GuildApi,
      :member,
      {:error, %ApiError{status_code: 404, response: %{code: 10_007}}}
    )

    assert Discord.check_member("1", "10") == :not_member
  end

  test "doesn't take other errors for people who left" do
    patch_function(GuildApi, :member, {:error, %ApiError{status_code: 500, response: %{}}})
    assert Discord.check_member("1", "10") == :error

    patch_function(GuildApi, :member, {:error, :timeout})
    assert Discord.check_member("1", "10") == :error
  end
end
