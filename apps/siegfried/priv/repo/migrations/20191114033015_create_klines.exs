defmodule Siegfried.Repo.Migrations.CreateKlines do
  use Ecto.Migration

  def change do
    create table(:klines) do
      add :exchange, :string
      add :symbol, :string
      add :period, :string
      add :datetime, :string
      add :timestamp, :integer
      add :open, :float
      add :close, :float
      add :low, :float
      add :high, :float

      timestamps()
    end

    create unique_index(:klines, [:exchange, :symbol, :period, :timestamp])
  end
end
