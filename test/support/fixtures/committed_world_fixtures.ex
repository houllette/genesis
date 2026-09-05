defmodule Genesis.CommittedWorldFixtures do
  @moduledoc false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox

  alias Genesis.Persistence.{
    Binding,
    Campaign,
    CampaignMember,
    Checkpoint,
    Claim,
    Draft,
    Event,
    Experience,
    Gathering,
    Invitation,
    Note,
    Outbox,
    Receipt,
    Snapshot,
    Window,
    World,
    WorldMember
  }

  alias Genesis.Repo

  def unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  # Only the generated world/user belonging to this fixture are removed. This
  # harness is needed for independent committed connections, not shared-sandbox races.
  def cleanup(ctx) do
    unboxed(fn ->
      ids = Repo.all(from o in Outbox, where: o.world_id == ^ctx.world.id, select: o.id)
      Repo.delete_all(from j in Oban.Job, where: fragment("?->>'outbox_id'", j.args) in ^ids)

      Repo.update_all(from(e in Experience, where: e.world_id == ^ctx.world.id),
        set: [base_checkpoint_id: nil]
      )

      for schema <- [
            Claim,
            Binding,
            Receipt,
            Outbox,
            Gathering,
            Invitation,
            Draft,
            Note,
            Event,
            Checkpoint,
            Snapshot,
            Experience,
            Window,
            CampaignMember,
            Campaign,
            WorldMember
          ] do
        Repo.delete_all(from r in schema, where: r.world_id == ^ctx.world.id)
      end

      Repo.delete_all(from r in Genesis.Persistence.Entity, where: r.world_id == ^ctx.world.id)
      Repo.delete_all(from w in World, where: w.id == ^ctx.world.id)
      Repo.delete_all(from u in Genesis.Accounts.User, where: u.id == ^ctx.owner.user.id)
    end)
  end
end
