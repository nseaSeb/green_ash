defmodule Buis.Repo do
  use AshPostgres.Repo, otp_app: :buis

  # Extensions installed by Ash's Postgres data layer.
  def installed_extensions do
    ["ash-functions"]
  end

  # The Docker Postgres is v15.
  def min_pg_version do
    %Version{major: 15, minor: 0, patch: 0}
  end
end
