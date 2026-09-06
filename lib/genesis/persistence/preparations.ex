defmodule Genesis.Persistence.Preparations do
  @moduledoc "World-owned durable timeline preparation. Jobs resume only a stored explicit target and generation."
  import Ecto.Query
  alias Genesis.Core.{LocalTime, Scope, Timeline}

  alias Genesis.Persistence.{
    Access,
    Actions,
    Codec,
    Preparation,
    PreparationInputs,
    PrepareTimeline,
    Tx,
    Window
  }

  alias Genesis.{Repo, Worlds}

  @spec start(scope :: term(), world :: String.t(), attrs :: term(), request :: String.t()) ::
          term()
  def start(scope, world, attrs, request) do
    Tx.run(world, fn world ->
      with :ok <- Access.world(scope, world.id, ["steward"]),
           {:ok, user} <- Access.user_id(scope),
           true <- Scope.id?(request) and PreparationInputs.valid_attrs?(attrs) do
        restore_or_start(scope, world, user, attrs, request)
      else
        false -> {:error, :invalid_preparation}
        error -> error
      end
    end)
  end

  defp restore_or_start(scope, world, user, attrs, request) do
    case Repo.get_by(Preparation, world_id: world.id, principal_id: user, request_id: request) do
      nil ->
        start_new(scope, world, user, attrs, request)

      %{input: ^attrs} = row ->
        with {:ok, _} <- authorized(scope, world.id, row.id),
             do: {:ok, %{"preparation_id" => row.id}}

      _ ->
        {:error, :request_conflict}
    end
  end

  defp start_new(scope, world, user, attrs, request) do
    window =
      Repo.one(from w in Window, where: w.world_id == ^world.id and w.status != "closed") ||
        Tx.insert!(Window, %{
          world_id: world.id,
          generation: world.generation,
          base_revision: world.revision
        })

    with true <- window.status == "open",
         {:ok, inputs} <- PreparationInputs.validate(scope, world, window, attrs),
         id = Worlds.named_id([world.id, world.generation, "time", user, request]),
         {:ok, work} <-
           Timeline.new(
             inputs.states,
             inputs.records,
             inputs.manifest["target"],
             world.calendar,
             id
           ),
         {:ok, encoded} <- Codec.dump(work) do
      row =
        Tx.insert!(Preparation, %{
          id: id,
          world_id: world.id,
          window_id: window.id,
          principal_id: user,
          generation: world.generation,
          base_revision: world.revision,
          request_id: request,
          status: "preparing",
          input: attrs,
          manifest: inputs.manifest,
          work: encoded,
          digest: Codec.digest(work)
        })

      Tx.update!(window, %{status: "sealed"})
      enqueue!(row)

      Tx.metadata!(world, scope, "timeline_preparation_requested", %{
        "preparation_id" => id,
        "reason" => attrs["reason"],
        "decisions" => attrs["decisions"],
        "target" => inputs.manifest["target"]
      })

      {:ok, %{"preparation_id" => id}}
    else
      false -> {:error, :window_sealed}
      {:error, :invalid_format} -> {:error, :timeline_capacity}
      error -> error
    end
  end

  @spec step(
          scope :: term(),
          world :: String.t(),
          id :: String.t(),
          generation :: integer(),
          opts :: keyword()
        ) :: term()
  def step(scope, world, id, generation, opts \\ []) do
    Tx.run(world, fn world ->
      with {:ok, row} <- authorized(scope, world.id, id),
           true <- row.generation == world.generation and generation == world.generation,
           true <- row.status in ["cancelled", "published"] or row.base_revision == world.revision,
           {:ok, work} <- Codec.load(row.work),
           true <- row.digest == Codec.digest(work) do
        advance(scope, world, row, work, opts)
      else
        false -> {:error, :stale_preparation}
        error -> error
      end
    end)
  end

  defp advance(scope, world, %{status: "preparing"} = row, work, opts) do
    window = Repo.get!(Window, row.window_id)

    with {:ok, inputs} <- PreparationInputs.validate(scope, world, window, row.input),
         true <- inputs.manifest == row.manifest and window.status == "sealed",
         true <- work["target"] == row.manifest["target"] and work["calendar"] == world.calendar,
         {:ok, next} <- Timeline.batch(work, Keyword.get(opts, :batch_size, 32)),
         {:ok, encoded} <- Codec.dump(next) do
      row = Tx.update!(row, %{status: next["status"], work: encoded, digest: Codec.digest(next)})
      if row.status == "preparing", do: enqueue!(row)

      Tx.metadata!(world, scope, "timeline_batch_saved", %{
        "preparation_id" => row.id,
        "status" => row.status,
        "processed" => next["processed"]
      })

      Actions.fault(opts, :preparation_before_commit)
      {:ok, %{"status" => row.status}}
    else
      false -> {:error, :stale_preparation}
      error -> error
    end
  end

  defp advance(_scope, _world, row, _work, _opts)
       when row.status in ["ready", "needs_review", "cancelled", "published"],
       do: {:ok, %{"status" => row.status}}

  @spec authorized(scope :: term(), world :: String.t(), id :: String.t()) :: term()
  def authorized(scope, world, id) do
    with :ok <- Access.world(scope, world, ["steward"]),
         true <- Access.uuid?(id),
         %Preparation{} = row <- Repo.get_by(Preparation, id: id, world_id: world),
         true <- is_list(row.manifest["experiences"]),
         true <-
           Enum.all?(
             row.manifest["experiences"],
             &match?({:ok, _}, Genesis.Experiences.get(scope, world, &1["id"], ["gm"]))
           ) do
      {:ok, row}
    else
      _ -> {:error, :unavailable}
    end
  end

  @spec cancel(
          scope :: term(),
          world :: String.t(),
          id :: String.t(),
          digest :: String.t(),
          reason :: String.t()
        ) :: term()
  def cancel(scope, world, id, digest, reason) do
    Tx.run(world, fn world ->
      with {:ok, row} <- authorized(scope, world.id, id),
           true <- row.generation == world.generation and row.base_revision == world.revision,
           true <-
             row.digest == digest and row.status in ["preparing", "ready", "needs_review"] and
               LocalTime.reason?(reason) do
        Tx.update!(row, %{status: "cancelled"})
        Tx.update!(Repo.get!(Window, row.window_id), %{status: "open"})

        Tx.metadata!(world, scope, "timeline_preparation_cancelled", %{
          "preparation_id" => row.id,
          "reason" => reason
        })

        {:ok, %{"status" => "cancelled"}}
      else
        false -> {:error, :stale_preparation}
        error -> error
      end
    end)
  end

  defp enqueue!(row),
    do:
      %{"preparation_id" => row.id, "world_id" => row.world_id, "generation" => row.generation}
      |> PrepareTimeline.new()
      |> Oban.insert!()
end
