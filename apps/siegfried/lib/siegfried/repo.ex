defmodule Siegfried.Repo do
  use Ecto.Repo,
    otp_app: :siegfried,
    adapter: Ecto.Adapters.Postgres
end
