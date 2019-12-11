defmodule Siegfried.Strategy.Cache do
  use Ecto.Schema
  import Ecto.Changeset

  schema "caches" do
    field :key, :string
    field :value, :string

    timestamps()
  end

  @required_fields ~w(key value)a
  @optional_fields ~w()a

  @doc false
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:key)
  end
end
