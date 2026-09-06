defmodule Genesis.Persistence.PrepareTimeline do
  @moduledoc "Resume one bounded approved preparation batch; fictional targets are never UTC scheduled_at values."
  use Oban.Worker, queue: :default, max_attempts: 5
  alias Genesis.Accounts.{Scope, User}
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.{Access, Preparation}
  alias Genesis.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"preparation_id" => id, "world_id" => world, "generation" => generation}
      }) do
    with true <- Access.uuid?(id) and Access.uuid?(world),
         %Preparation{world_id: ^world, generation: ^generation} = row <-
           Repo.get(Preparation, id),
         %User{} = user <- Repo.get(User, row.principal_id),
         {:ok, _} <-
           Runtime.call(Scope.for_user(user), world, {:step_time, id, generation}) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:cancel, :stale_preparation}
    end
  end

  def perform(_job), do: {:cancel, :invalid_preparation}
end
