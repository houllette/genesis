defmodule Genesis.Repo.Migrations.AddDurableWorldWorkspace do
  use Ecto.Migration

  def change do
    create table(:worlds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :generation, :bigint, null: false, default: 0
      add :revision, :bigint, null: false, default: 0
      add :cursor, :bigint, null: false, default: 0
      add :bundle, :map, null: false
      add :profile, :string, null: false, default: "village"
      add :calendar_id, :string, null: false, default: "ordinal"
      add :calendar_version, :integer, null: false, default: 1
      add :fictional_time, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:world_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :role, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :revision, :bigint, null: false, default: 0
      add :archived, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:campaign_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :role, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:advancement_windows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :generation, :bigint, null: false
      add :base_revision, :bigint, null: false
      add :status, :string, null: false, default: "open"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:experiences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict),
        null: false

      add :window_id, references(:advancement_windows, type: :binary_id, on_delete: :restrict)
      add :zone_id, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :revision, :bigint, null: false, default: 0
      add :participants, {:array, :string}, null: false, default: []
      add :base_checkpoint_id, :binary_id
      add :deadline, :map, null: false, default: %{}
      add :completion, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create table(:zone_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :generation, :bigint, null: false
      add :scope_key, :string, null: false
      add :scope_kind, :string, null: false
      add :experience_id, references(:experiences, type: :binary_id, on_delete: :restrict)
      add :zone_id, :string, null: false
      add :revision, :bigint, null: false
      add :state, :map, null: false
      add :digest, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:zone_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :snapshot_id, references(:zone_snapshots, type: :binary_id, on_delete: :restrict),
        null: false

      add :cursor, :bigint, null: false
      add :state, :map, null: false
      add :digest, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:world_entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :entity_id, :string, null: false
      add :zone_id, :string, null: false
      add :owner_kind, :string
      add :owner_id, :string
      add :actor_kind, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:character_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :actor_id, :string, null: false
      add :entity_kind, :string, null: false, default: "actor"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:experience_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :generation, :bigint, null: false
      add :resource_kind, :string, null: false
      add :resource_id, :string, null: false

      add :experience_id, references(:experiences, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:world_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :cursor, :bigint, null: false
      add :snapshot_id, references(:zone_snapshots, type: :binary_id, on_delete: :restrict)
      add :scope_key, :string, null: false
      add :kind, :string, null: false
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict)
      add :experience_id, references(:experiences, type: :binary_id, on_delete: :restrict)
      add :principal_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :actor_id, :string
      add :core_event_id, :string, null: false
      add :event, :map, null: false
      add :transition, :map, null: false, default: %{}
      add :audience_users, {:array, :binary_id}, null: false, default: []
      add :source_event_id, references(:world_events, type: :binary_id, on_delete: :restrict)
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:request_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :scope_key, :string, null: false
      add :principal_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :request_id, :string, null: false
      add :payload, :map, null: false
      add :result, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:event_outbox, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :event_id, references(:world_events, type: :binary_id, on_delete: :restrict),
        null: false

      add :cursor, :bigint, null: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create table(:content_drafts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :zone_id, :string, null: false
      add :entity_id, :string, null: false
      add :kind, :string, null: false
      add :attrs, :map, null: false
      add :base_revision, :bigint, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:workspace_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict)
      add :entity_id, :string, null: false
      add :title, :string, null: false
      add :body, :string, null: false
      add :kind, :string, null: false, default: "note"
      add :visibility, :string, null: false, default: "private"
      add :author_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :revision, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:experience_gatherings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false

      add :experience_id, references(:experiences, type: :binary_id, on_delete: :restrict),
        null: false

      add :request_id, :string, null: false
      add :title, :string, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :meeting_url, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:workspace_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world_id, references(:worlds, type: :binary_id, on_delete: :restrict), null: false
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :restrict)
      add :email, :string, null: false
      add :role, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :inviter_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:world_memberships, [:world_id, :user_id])
    create unique_index(:campaigns, [:id, :world_id])
    create unique_index(:campaign_memberships, [:campaign_id, :user_id])
    create unique_index(:experiences, [:id, :world_id])
    create unique_index(:zone_snapshots, [:world_id, :scope_key, :zone_id])
    create unique_index(:zone_snapshots, [:experience_id, :zone_id])
    create unique_index(:world_entities, [:world_id, :kind, :entity_id])
    create unique_index(:character_bindings, [:world_id, :actor_id])

    create unique_index(:experience_claims, [:world_id, :generation, :resource_kind, :resource_id])

    create unique_index(:world_events, [:world_id, :cursor])
    create unique_index(:world_events, [:source_event_id])
    create unique_index(:world_events, [:world_id, :scope_key, :core_event_id])
    create unique_index(:request_receipts, [:world_id, :scope_key, :principal_id, :request_id])
    create unique_index(:event_outbox, [:event_id])
    create unique_index(:experience_gatherings, [:experience_id, :request_id])
    create unique_index(:workspace_invitations, [:token_hash])

    create unique_index(:advancement_windows, [:world_id],
             where: "status = 'open'",
             name: :one_open_window_per_world
           )

    execute "ALTER TABLE campaign_memberships ADD CONSTRAINT campaign_world FOREIGN KEY (campaign_id, world_id) REFERENCES campaigns(id, world_id)",
            "ALTER TABLE campaign_memberships DROP CONSTRAINT campaign_world"

    execute "ALTER TABLE campaign_memberships ADD CONSTRAINT campaign_world_member FOREIGN KEY (world_id, user_id) REFERENCES world_memberships(world_id, user_id)",
            "ALTER TABLE campaign_memberships DROP CONSTRAINT campaign_world_member"

    execute "ALTER TABLE experiences ADD CONSTRAINT experience_campaign_world FOREIGN KEY (campaign_id, world_id) REFERENCES campaigns(id, world_id)",
            "ALTER TABLE experiences DROP CONSTRAINT experience_campaign_world"

    execute "ALTER TABLE character_bindings ADD CONSTRAINT binding_campaign_world FOREIGN KEY (campaign_id, world_id) REFERENCES campaigns(id, world_id)",
            "ALTER TABLE character_bindings DROP CONSTRAINT binding_campaign_world"

    execute "ALTER TABLE character_bindings ADD CONSTRAINT binding_member FOREIGN KEY (campaign_id, user_id) REFERENCES campaign_memberships(campaign_id, user_id)",
            "ALTER TABLE character_bindings DROP CONSTRAINT binding_member"

    execute "ALTER TABLE character_bindings ADD CONSTRAINT binding_character FOREIGN KEY (world_id, entity_kind, actor_id) REFERENCES world_entities(world_id, kind, entity_id)",
            "ALTER TABLE character_bindings DROP CONSTRAINT binding_character"

    execute "ALTER TABLE experience_claims ADD CONSTRAINT claim_experience_world FOREIGN KEY (experience_id, world_id) REFERENCES experiences(id, world_id)",
            "ALTER TABLE experience_claims DROP CONSTRAINT claim_experience_world"

    execute "ALTER TABLE experience_claims ADD CONSTRAINT claim_entity FOREIGN KEY (world_id, resource_kind, resource_id) REFERENCES world_entities(world_id, kind, entity_id)",
            "ALTER TABLE experience_claims DROP CONSTRAINT claim_entity"

    execute "ALTER TABLE zone_snapshots ADD CONSTRAINT snapshot_experience_world FOREIGN KEY (experience_id, world_id) REFERENCES experiences(id, world_id)",
            "ALTER TABLE zone_snapshots DROP CONSTRAINT snapshot_experience_world"

    execute "ALTER TABLE experiences ADD CONSTRAINT experience_checkpoint FOREIGN KEY (base_checkpoint_id) REFERENCES zone_checkpoints(id)",
            "ALTER TABLE experiences DROP CONSTRAINT experience_checkpoint"

    execute "ALTER TABLE workspace_notes ADD CONSTRAINT note_campaign_world FOREIGN KEY (campaign_id, world_id) REFERENCES campaigns(id, world_id)",
            "ALTER TABLE workspace_notes DROP CONSTRAINT note_campaign_world"

    execute "ALTER TABLE experience_gatherings ADD CONSTRAINT gathering_experience_world FOREIGN KEY (experience_id, world_id) REFERENCES experiences(id, world_id)",
            "ALTER TABLE experience_gatherings DROP CONSTRAINT gathering_experience_world"

    execute "ALTER TABLE workspace_invitations ADD CONSTRAINT invitation_campaign_world FOREIGN KEY (campaign_id, world_id) REFERENCES campaigns(id, world_id)",
            "ALTER TABLE workspace_invitations DROP CONSTRAINT invitation_campaign_world"

    create constraint(:world_memberships, :world_role,
             check: "role IN ('steward', 'builder', 'viewer')"
           )

    create constraint(:campaign_memberships, :campaign_role,
             check: "role IN ('gm', 'player', 'spectator')"
           )

    create constraint(:character_bindings, :binding_actor_only, check: "entity_kind = 'actor'")

    create constraint(:experiences, :experience_status,
             check:
               "status IN ('draft', 'active', 'paused', 'ready', 'incorporated', 'needs_review', 'closed_without_publication')"
           )

    create constraint(:worlds, :world_nonnegative,
             check: "generation >= 0 AND revision >= 0 AND cursor >= 0"
           )
  end
end
