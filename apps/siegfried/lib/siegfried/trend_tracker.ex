defmodule Siegfried.Strategy do
  @moduledoc """
  The Strategy context.
  """

  import Ecto.Query, warn: false
  alias Siegfried.Repo

  alias Siegfried.Strategy.Cache

  def list_cache do
    Repo.all(Cache)
  end

  def get_cache(key) do
    key = to_string(key)
    data = Repo.get_by(Cache, key: key)

    if data do
      {result, _} = Code.eval_string(data.value)
      result
    end
  end

  def set_cache(key, value) do
    key = to_string(key)
    value = inspect(value)
    case Repo.get_by(Cache, key: key) do
      nil -> Cache.changeset(%Cache{}, %{key: key, value: value})
      cache -> Cache.changeset(cache, %{value: value})
    end
    |> Repo.insert_or_update()
  end

  def delete_cache(key) do
    key = to_string(key)
    case Repo.get_by(Cache, key: key) do
      nil -> {:error, :not_found}
      cache -> Repo.delete(cache)
    end
  end

  def delete_all_cache do
    Repo.delete_all(Cache)
  end
end
