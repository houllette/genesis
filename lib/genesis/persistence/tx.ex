defmodule Genesis.Persistence.Tx do
  @moduledoc "Short world-row transactions allocate commit-ordered cursors; no callbacks to live authority."
  import Ecto.Query
  alias Genesis.Core.Scope
  alias Genesis.Persistence.{Access, Codec, DeliverEvent, Event, Outbox, Receipt, World}
  alias Genesis.Repo
  alias Genesis.Time.Clock

  @spec run(world_id :: String.t(), fun :: (World.t() -> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def run(world_id, fun) do
    if Access.uuid?(world_id) do
      Repo.transact(fn -> locked(world_id, fun) end)
    else
      {:error, :unavailable}
    end
  end

  defp locked(world_id, fun) do
    case Repo.one(from w in World, where: w.id == ^world_id, lock: "FOR UPDATE") do
      nil -> {:error, :unavailable}
      world -> fun.(world)
    end
  end

  @doc "Receipt wrapper for authorized workspace commands. Omitted IDs denote new trusted calls, never network retries."
  @spec record_command(
          world :: String.t(),
          user :: String.t(),
          key :: String.t(),
          request :: String.t() | nil,
          payload :: term(),
          schema :: module(),
          fun :: (-> term())
        ) :: term()
  def record_command(world, user, key, request, payload, schema, fun) do
    request = request || Ecto.UUID.generate()

    if Scope.id?(request),
      do: recorded_command(world, user, key, request, payload, schema, fun),
      else: {:error, :invalid_request}
  end

  defp recorded_command(world, user, key, request, payload, schema, fun) do
    case receipt(world, key, user, request, payload) do
      :new ->
        remember_record(world, user, key, request, payload, schema, fun)

      {:ok, fields} ->
        attrs =
          Enum.map(schema.__schema__(:fields), &{&1, Map.fetch!(fields, Atom.to_string(&1))})

        {:ok, schema |> struct(attrs) |> Ecto.put_meta(state: :loaded)}

      error ->
        error
    end
  end

  defp remember_record(world, user, key, request, payload, schema, fun) do
    with {:ok, record} <- fun.() do
      fields = Map.new(schema.__schema__(:fields), &{Atom.to_string(&1), Map.fetch!(record, &1)})
      remember!(world, key, user, request, payload, fields)
      {:ok, record}
    end
  end

  @spec insert!(schema :: module(), attrs :: map()) :: struct()
  def insert!(schema, attrs),
    do: schema |> struct() |> Ecto.Changeset.change(attrs) |> Repo.insert!()

  @spec update!(record :: struct(), attrs :: map()) :: struct()
  def update!(record, attrs), do: record |> Ecto.Changeset.change(attrs) |> Repo.update!()

  @spec receipt(
          world_id :: String.t(),
          scope_key :: String.t(),
          user :: String.t(),
          id :: String.t(),
          payload :: term()
        ) :: {:ok, map()} | :new | {:error, atom()}
  def receipt(world_id, key, user, id, payload) do
    encoded = Codec.dump!(payload)

    case Repo.get_by(Receipt,
           world_id: world_id,
           scope_key: key,
           principal_id: user,
           request_id: id
         ) do
      nil -> :new
      %{payload: ^encoded, result: result} -> Codec.load(result)
      _ -> {:error, :request_conflict}
    end
  end

  @spec remember!(
          world_id :: String.t(),
          scope_key :: String.t(),
          user :: String.t(),
          id :: String.t(),
          payload :: term(),
          result :: term()
        ) :: struct()
  def remember!(world_id, key, user, id, payload, result),
    do:
      insert!(Receipt, %{
        world_id: world_id,
        scope_key: key,
        principal_id: user,
        request_id: id,
        payload: Codec.dump!(payload),
        result: Codec.dump!(result)
      })

  @spec event!(world :: World.t(), attrs :: map(), clock :: Clock.t()) :: Event.t()
  def event!(world, attrs, clock \\ Clock.system()) do
    # Lock is held until commit; another transaction cannot reserve and publish
    # a later cursor while this transaction is still uncommitted.
    current = Repo.get!(World, world.id)
    world = update!(current, %{cursor: current.cursor + 1})

    event =
      insert!(
        Event,
        Map.merge(
          %{
            world_id: world.id,
            cursor: world.cursor,
            recorded_at: Clock.read(clock).utc,
            core_event_id: Ecto.UUID.generate()
          },
          attrs
        )
      )

    outbox = insert!(Outbox, %{world_id: world.id, event_id: event.id, cursor: event.cursor})
    %{"outbox_id" => outbox.id} |> DeliverEvent.new() |> Oban.insert!()
    event
  end

  @doc "Audit non-fictional workspace mutations in the same transaction and invalidate read models."
  @spec metadata!(
          world :: World.t(),
          scope :: term(),
          type :: String.t(),
          result :: map(),
          campaign :: String.t() | nil
        ) :: Event.t()
  def metadata!(world, scope, type, result, campaign \\ nil) do
    {:ok, user} = Access.user_id(scope)

    event!(world, %{
      scope_key: "workspace",
      kind: "world",
      principal_id: user,
      campaign_id: campaign,
      audience_users: [user],
      event: Codec.dump!(%{type: type, result: result})
    })
  end
end
