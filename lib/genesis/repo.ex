defmodule Genesis.Repo do
  use Ecto.Repo,
    otp_app: :genesis,
    adapter: Ecto.Adapters.Postgres
end
