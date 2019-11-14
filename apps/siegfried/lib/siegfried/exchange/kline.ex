defmodule Siegfried.Exchange.Kline do
  use Ecto.Schema
  import Ecto.Changeset

  schema "klines" do
    field :exchange, :string
    field :symbol, :string
    field :period, :string
    field :datetime, :string
    field :timestamp, :integer
    field :open, :float
    field :close, :float
    field :low, :float
    field :high, :float

    timestamps()
  end

  @required_fields ~w(exchange symbol period timestamp open close low high)a
  @optional_fields ~w(datetime)a

  @doc false
  def changeset(kline, attrs) do
    kline
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> set_datetime()
  end

  defp set_datetime(%Ecto.Changeset{valid?: false} = changeset), do: changeset
  defp set_datetime(changeset) do
    timestamp = get_field(changeset, :timestamp)
    put_change(changeset, :datetime, transform_timestamp(timestamp))
  end

  defp transform_timestamp(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.Timezone.convert("Asia/Shanghai")
    |> DateTime.to_string()
  end
end
