defmodule Botchini.Discord.CheckMemberTest do
  use ExUnit.Case, async: false

  use Patch, alias: [patch: :patch_function]

  @moduletag :capture_log

  alias Nostrum.Api.Guild, as: GuildApi
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Error.ApiError
  alias Nostrum.Struct.Guild
  alias Nostrum.Struct.Guild.{Member, Role}

  alias Botchini.Discord

  # Manage Server is the 6th permission bit, and Administrator the 4th
  @manage_guild 0x20
  @administrator 0x8

  defp patch_member(roles, guild_roles, owner_id \\ 99) do
    patch_function(GuildApi, :member, {:ok, %Member{user_id: 10, roles: roles}})
    patch_function(GuildCache, :get, {:ok, %Guild{id: 1, owner_id: owner_id, roles: guild_roles}})
  end

  test "finds members" do
    patch_member([], %{})

    assert Discord.check_member("1", "10") == :member
    assert_called(GuildApi.member(1, 10))
  end

  test "finds admins by their roles' permissions" do
    patch_member([5], %{5 => %Role{id: 5, permissions: @manage_guild}})
    assert Discord.check_member("1", "10") == :admin

    patch_member([6], %{6 => %Role{id: 6, permissions: @administrator}})
    assert Discord.check_member("1", "10") == :admin
  end

  test "finds admins by the permissions of everyone" do
    patch_member([], %{1 => %Role{id: 1, permissions: @manage_guild}})

    assert Discord.check_member("1", "10") == :admin
  end

  test "the owner is an admin" do
    patch_member([], %{}, 10)

    assert Discord.check_member("1", "10") == :admin
  end

  test "members without the permission aren't admins" do
    patch_member([5], %{5 => %Role{id: 5, permissions: 0x400}})

    assert Discord.check_member("1", "10") == :member
  end

  test "members aren't admins when the guild isn't cached" do
    patch_member([5], %{})
    patch_function(GuildCache, :get, {:error, :not_found})

    assert Discord.check_member("1", "10") == :member
  end

  test "finds who isn't in the guild" do
    patch_function(
      GuildApi,
      :member,
      {:error, %ApiError{status_code: 404, response: %{code: 10_007}}}
    )

    assert Discord.check_member("1", "10") == :not_member
  end

  test "finds nobody in guilds the bot isn't in" do
    patch_function(
      GuildApi,
      :member,
      {:error, %ApiError{status_code: 403, response: %{code: 50_001}}}
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
