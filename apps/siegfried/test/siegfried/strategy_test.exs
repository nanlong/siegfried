defmodule Siegfried.StrategyTest do
  use Siegfried.DataCase

  alias Siegfried.Strategy

  describe "caches" do
    alias Siegfried.Strategy.Cache

    @valid_attrs %{key: "some key", value: "some value"}
    @update_attrs %{key: "some updated key", value: "some updated value"}
    @invalid_attrs %{key: nil, value: nil}

    def cache_fixture(attrs \\ %{}) do
      {:ok, cache} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Strategy.create_cache()

      cache
    end

    test "list_caches/0 returns all caches" do
      cache = cache_fixture()
      assert Strategy.list_caches() == [cache]
    end

    test "get_cache!/1 returns the cache with given id" do
      cache = cache_fixture()
      assert Strategy.get_cache!(cache.id) == cache
    end

    test "create_cache/1 with valid data creates a cache" do
      assert {:ok, %Cache{} = cache} = Strategy.create_cache(@valid_attrs)
      assert cache.key == "some key"
      assert cache.value == "some value"
    end

    test "create_cache/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Strategy.create_cache(@invalid_attrs)
    end

    test "update_cache/2 with valid data updates the cache" do
      cache = cache_fixture()
      assert {:ok, %Cache{} = cache} = Strategy.update_cache(cache, @update_attrs)
      assert cache.key == "some updated key"
      assert cache.value == "some updated value"
    end

    test "update_cache/2 with invalid data returns error changeset" do
      cache = cache_fixture()
      assert {:error, %Ecto.Changeset{}} = Strategy.update_cache(cache, @invalid_attrs)
      assert cache == Strategy.get_cache!(cache.id)
    end

    test "delete_cache/1 deletes the cache" do
      cache = cache_fixture()
      assert {:ok, %Cache{}} = Strategy.delete_cache(cache)
      assert_raise Ecto.NoResultsError, fn -> Strategy.get_cache!(cache.id) end
    end

    test "change_cache/1 returns a cache changeset" do
      cache = cache_fixture()
      assert %Ecto.Changeset{} = Strategy.change_cache(cache)
    end
  end
end
