defmodule GenesisWeb.WorkspaceComponents do
  @moduledoc "Native GM workbench sections. Forms carry revisions and stable request IDs, never authority grants."
  use GenesisWeb, :html

  def world_overview(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-[1fr_24rem]">
      <div class="space-y-10">
        <section>
          <h2 class="section-heading">People & places</h2>
          <div id="zones" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
            <p id="empty-section-1" class="empty-state hidden only:block sm:col-span-2">
              Start with one place. Give it two people, an object worth noticing, and a question for your next gathering.
            </p>
            <article :for={{id, place} <- @streams.zones} id={id} class="workspace-card">
              <.icon name="hero-map-pin" class="size-6 text-emerald-700" /><span class="badge-published ml-2">Published</span>
              <h3 class="mt-4 text-xl font-semibold">
                <.link navigate={~p"/worlds/#{@world.id}/places/#{place.id}"} class="text-link">{place.name}</.link>
              </h3>
              <p class="mt-2 text-sm leading-relaxed text-stone-600">{place.description}</p>
            </article>
          </div>
        </section>
        <section>
          <h2 class="section-heading">Campaigns</h2>
          <div id="campaigns" phx-update="stream" class="space-y-3">
            <p id="empty-section-2" class="empty-state hidden only:block">
              A campaign organizes your roster and Experiences. Its GM role does not grant world stewardship.
            </p>
            <article
              :for={{id, campaign} <- @streams.campaigns}
              id={id}
              class="workspace-card flex items-center justify-between gap-4"
            >
              <.link
                navigate={~p"/worlds/#{@world.id}/campaigns/#{campaign.id}"}
                class="text-link font-semibold"
              >{campaign.name}</.link>
              <span class="status-label">{if campaign.archived, do: "Archived", else: "Open"}</span>
            </article>
          </div>
        </section>
      </div>
      <div :if={@can_build} class="space-y-6">
        <section class="workspace-panel">
          <p class="eyebrow">Set the scene</p><h2 class="section-heading">Create a place</h2>
          <.form for={@zone_form} id="new-zone-form" phx-submit="create-zone" class="space-y-4">
            <input type="hidden" name="request_id" value={@request_id <> "-zone"} />
            <.input field={@zone_form[:name]} label="Place name" required maxlength="160" />
            <.input
              field={@zone_form[:description]}
              type="textarea"
              label="Public description"
              maxlength="4000"
              rows="3"
            />
            <button id="create-zone" class="primary-button" phx-disable-with="Saving…">{if @window_open,
              do: "Save place draft",
              else: "Create place"}</button>
          </.form>
        </section>
        <section class="workspace-panel">
          <h2 class="section-heading">Create a campaign</h2>
          <.form
            for={@campaign_form}
            id="new-campaign-form"
            phx-submit="create-campaign"
            class="space-y-4"
          >
            <input type="hidden" name="request_id" value={@request_id <> "-campaign"} />
            <.input field={@campaign_form[:name]} label="Campaign name" required maxlength="160" />
            <button id="create-campaign" class="secondary-button" phx-disable-with="Creating…">Create campaign</button>
          </.form>
        </section>
      </div>
    </div>
    """
  end

  def place_editor(assigns) do
    ~H"""
    <section>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="eyebrow">People & places · instantiated records</p><h2
            id="place-title"
            class="section-heading"
          >
            {@zone.name}
          </h2><p class="max-w-2xl text-stone-600">{@zone.description}</p>
        </div>
        <div :if={@can_build} class="flex flex-wrap gap-2">
          <button
            id="preview-player"
            class="secondary-button"
            phx-click="preview"
            aria-pressed={to_string(@preview)}
          >{if @preview, do: "Return to GM view", else: "Preview public view"}</button>
          <button
            :if={!@preview}
            id="edit-place"
            class="secondary-button"
            phx-click="edit-record"
            phx-value-id={@zone.zone_id}
            phx-value-kind="zone"
          >Edit place</button>
        </div>
      </header>
      <aside :if={@preview} id="preview-notice" class="notice mb-6">
        Public preview only. This grants no player access and shows no actor-specific whispers, private persona or GM notes.
      </aside>
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_24rem]">
        <div class="space-y-8">
          <section>
            <h3 class="section-heading">People</h3>
            <div id="actors" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
              <p id="empty-section-3" class="empty-state hidden only:block sm:col-span-2">
                Who belongs here? Add two people with different hopes for this place.
              </p>
              <article :for={{id, actor} <- @streams.actors} id={id} class="workspace-card">
                <span class="status-label">{if actor.kind == :npc, do: "NPC", else: "Player character"}</span>
                <h4 class="mt-2 text-xl font-semibold">{actor.name}</h4>
                <div
                  :if={Map.get(actor, :persona, %{}) != %{}}
                  class="mt-3 space-y-2 text-sm text-stone-600"
                >
                  <p><strong>Temperament:</strong> {actor.persona["temperament"]}</p><p>
                    <strong>Wants:</strong> {actor.persona["goal"]}
                  </p><p>Agency: dormant · no AI process</p>
                </div>
                <p :if={Map.get(actor, :audience) == :gm} class="mt-3 text-sm text-amber-800">
                  Private · GM only
                </p>
                <button
                  :if={@can_build && !@preview}
                  id={"edit-actor-#{actor.id}"}
                  class="text-link mt-4 text-sm"
                  phx-click="edit-record"
                  phx-value-id={actor.id}
                  phx-value-kind={actor.kind}
                >Edit {actor.name}</button>
              </article>
            </div>
          </section>
          <section>
            <h3 class="section-heading">Objects</h3>
            <div id="items" phx-update="stream" class="space-y-3">
              <p id="empty-section-4" class="helper-text hidden only:block">
                No objects yet. An item has one engine-validated owner, not a second inventory field.
              </p>
              <article
                :for={{id, item} <- @streams.items}
                id={id}
                class="workspace-card flex flex-wrap items-center justify-between gap-3"
              >
                <div>
                  <h4 class="font-semibold">{item.name}</h4><p class="helper-text">
                    Quantity {item.quantity} · {if elem(item.owner, 0) == :zone,
                      do: "at this place",
                      else: "carried by a character"}
                  </p>
                </div><button
                  :if={@can_build && !@preview}
                  id={"edit-item-#{item.id}"}
                  class="text-link text-sm"
                  phx-click="edit-record"
                  phx-value-id={item.id}
                  phx-value-kind="item"
                >Edit</button>
              </article>
            </div>
          </section>
          <section>
            <h3 class="section-heading">Linked notes & intentions</h3>
            <p class="helper-text mb-4">
              A note, plan or belief is authored context—not an established engine fact. Private notes belong only to their author.
            </p>
            <div id="notes" phx-update="stream" class="space-y-4">
              <p id="empty-section-5" class="helper-text hidden only:block">
                No notes visible to you.
              </p>
              <article :for={{id, note} <- @streams.notes} id={id} class="workspace-card">
                <span class="status-label">{note.visibility} · {note.kind}</span><h4 class="mt-2 text-lg font-semibold">
                  {note.title}
                </h4><p class="mt-3 whitespace-pre-wrap break-words text-sm leading-relaxed">
                  {note.body}
                </p><button
                  :if={@can_build && !@preview && note.author_id == @current_scope.user.id}
                  id={"edit-note-#{note.id}"}
                  class="text-link mt-4 text-sm"
                  phx-click="edit-note"
                  phx-value-id={note.id}
                >Edit note</button>
              </article>
            </div>
          </section>
        </div>
        <div :if={@can_build && !@preview} class="space-y-6">
          <section class="workspace-panel">
            <div class="flex items-center justify-between gap-3">
              <h3 class="section-heading">
                {if @record_id == "", do: "Add a record", else: "Edit record"}
              </h3><button :if={@record_id != ""} class="text-link text-sm" phx-click="new-record">New record</button>
            </div>
            <.form
              for={@record_form}
              id="record-form"
              phx-submit="save-record"
              phx-change="record-change"
              class="space-y-4"
            >
              <input type="hidden" name="request_id" value={@request_id <> "-record"} /><input
                type="hidden"
                name="record_id"
                value={@record_id}
              /><input type="hidden" name="revision" value={@record_revision} />
              <.input
                :if={@record_id == ""}
                field={@record_form[:kind]}
                type="select"
                label="Record type"
                options={[{"NPC", "npc"}, {"Player character", "pc"}, {"Item", "item"}]}
              />
              <input
                :if={@record_id != ""}
                type="hidden"
                name="record[kind]"
                value={@record_form[:kind].value}
              />
              <.input field={@record_form[:name]} label="Name" required maxlength="160" />
              <.input
                :if={@record_form[:kind].value == "zone"}
                field={@record_form[:description]}
                type="textarea"
                label="Public description"
                maxlength="4000"
              />
              <.input
                :if={@record_form[:kind].value == "npc"}
                field={@record_form[:temperament]}
                label="Temperament"
                required
                maxlength="160"
              />
              <.input
                :if={@record_form[:kind].value == "npc"}
                field={@record_form[:goal]}
                label="What do they want?"
                required
                maxlength="160"
              />
              <.input
                :if={@record_form[:kind].value == "item"}
                field={@record_form[:quantity]}
                type="number"
                label="Quantity"
                min="1"
                max="1000000"
                required
              />
              <.input
                :if={@record_form[:kind].value in ["npc", "item"]}
                field={@record_form[:visibility]}
                type="select"
                label="Visibility"
                options={[{"Public", "public"}, {"GM only", "private"}]}
              />
              <p class="helper-text">
                {if @record_form[:kind].value == "pc",
                  do:
                    "Uses the selected ruleset's validated starting character defaults. Assign this character to the roster in a campaign.",
                  else:
                    "These are real scoped records, not prototypes. NPC agency remains dormant; AI authoring comes later."}
              </p>
              <button id="save-record" class="primary-button" phx-disable-with="Saving…">{if @window_open,
                do: "Save as Draft",
                else: "Save to Published"}</button>
            </.form>
          </section>
          <section class="workspace-panel">
            <h3 class="section-heading">
              {if @note_id == "", do: "Add a linked note", else: "Edit note"}
            </h3>
            <.form for={@note_form} id="note-form" phx-submit="save-note" class="space-y-4">
              <input type="hidden" name="request_id" value={@request_id <> "-note"} /><input
                type="hidden"
                name="note_id"
                value={@note_id}
              /><input type="hidden" name="revision" value={@note_revision} />
              <.input
                field={@note_form[:entity_id]}
                type="select"
                label="Linked record"
                options={@entity_options}
                required
              />
              <.input field={@note_form[:title]} label="Title" required maxlength="160" />
              <.input
                field={@note_form[:body]}
                type="textarea"
                label="Note"
                required
                maxlength="10000"
                rows="4"
              />
              <div class="grid grid-cols-2 gap-3">
                <.input
                  field={@note_form[:kind]}
                  type="select"
                  label="Meaning"
                  options={[{"Note", "note"}, {"Plan", "plan"}, {"Belief", "belief"}]}
                /><.input
                  field={@note_form[:visibility]}
                  type="select"
                  label="Visibility"
                  options={[{"Private to me", "private"}, {"Public", "public"}]}
                />
              </div>
              <button id="save-note" class="secondary-button" phx-disable-with="Saving…">Save note</button>
            </.form>
          </section>
        </div>
      </div>
    </section>
    """
  end

  def campaign_editor(assigns) do
    ~H"""
    <section>
      <header class="mb-6">
        <p class="eyebrow">Campaign</p><h2 id="campaign-title" class="section-heading">
          {@campaign.name}
        </h2><p class="helper-text">
          {if @campaign.archived,
            do: "Archived · history and world assets are retained",
            else: "Your roster, role delegation and shared adventures"}
        </p>
      </header>
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_24rem]">
        <div class="space-y-8">
          <section>
            <h3 class="section-heading">Roster</h3><div
              id="roster"
              phx-update="stream"
              class="space-y-3"
            >
              <p id="empty-section-6" class="helper-text hidden only:block">
                Roster management is visible to this campaign's GM.
              </p>
              <article
                :for={{id, member} <- @streams.roster}
                id={id}
                class="workspace-card flex flex-wrap items-center justify-between gap-3"
              >
                <div class="min-w-0">
                  <p class="break-all font-medium">{member.email}</p><span class="status-label">{member.role}</span>
                </div><button
                  :if={@can_manage && member.id != @current_scope.user.id}
                  class="text-link text-sm"
                  phx-click="revoke-member"
                  phx-value-id={member.id}
                  phx-value-request={@request_id <> "-revoke-" <> member.id}
                  data-confirm="Revoke this person's campaign access? Their history and character remain saved."
                >Revoke access</button>
              </article>
            </div>
          </section>
          <section>
            <h3 class="section-heading">Assigned characters</h3><div
              id="bindings"
              phx-update="stream"
              class="space-y-3"
            >
              <p id="empty-section-7" class="helper-text hidden only:block">
                Create a player character in a place, then assign it to a roster member. GM-only play needs no player character.
              </p><article :for={{id, binding} <- @streams.bindings} id={id} class="workspace-card">
                <strong>{binding.name}</strong><p class="helper-text">
                  Assigned to {member_label(@member_options, binding.user_id)}
                </p>
              </article>
            </div>
          </section>
          <section :if={@can_manage} class="workspace-panel">
            <h3 class="section-heading">Prepare an Experience</h3>
            <.form
              for={@experience_form}
              id="experience-form"
              phx-submit="create-experience"
              class="space-y-4"
            >
              <input type="hidden" name="request_id" value={@request_id <> "-experience"} />
              <.input
                field={@experience_form[:name]}
                label="Experience name"
                required
                maxlength="160"
              />
              <.input
                field={@experience_form[:zone_id]}
                type="select"
                label="Starting place and scope"
                options={@zone_options}
                required
                prompt="Choose a published place"
              />
              <.input
                field={@experience_form[:participants]}
                type="select"
                multiple
                label="Participating characters (optional)"
                options={@actor_options}
              />
              <p class="helper-text">
                A draft holds no claims. Starting pins the published checkpoint and claims this place, its people and items. No wall time becomes fictional time.
              </p>
              <button id="prepare-experience" class="primary-button" phx-disable-with="Preparing…">Prepare Experience</button>
            </.form>
          </section>
        </div>
        <div :if={@can_manage} class="space-y-6">
          <section class="workspace-panel">
            <h3 class="section-heading">Invite someone</h3>
            <.form for={@invitation_form} id="invitation-form" phx-submit="invite" class="space-y-4">
              <input type="hidden" name="request_id" value={@request_id <> "-invite"} /><.input
                field={@invitation_form[:email]}
                type="email"
                label="Their account email"
                required
              /><.input
                field={@invitation_form[:role]}
                type="select"
                label="Campaign role"
                options={[{"Player", "player"}, {"Spectator", "spectator"}, {"GM", "gm"}]}
              /><button id="create-invitation" class="secondary-button" phx-disable-with="Creating…">Create private invite link</button>
            </.form>
            <div :if={@invitation_url} class="mt-4">
              <label for="invitation-link" class="text-sm font-medium">Share privately · valid for seven days</label><input
                id="invitation-link"
                class="workspace-input mt-2"
                value={@invitation_url}
                readonly
              /><p class="helper-text mt-2">
                No email has been sent. Only the named account can accept.
              </p>
            </div>
          </section>
          <section class="workspace-panel">
            <h3 class="section-heading">Assign a character</h3>
            <.form for={@binding_form} id="binding-form" phx-submit="bind" class="space-y-4">
              <input type="hidden" name="request_id" value={@request_id <> "-binding"} />
              <.input
                field={@binding_form[:user_id]}
                type="select"
                label="Roster member"
                options={@member_options}
                required
              /><.input
                field={@binding_form[:actor_id]}
                type="select"
                label="Player character"
                options={@actor_options}
                required
                prompt="Choose an unclaimed character"
              /><button id="bind-character" class="secondary-button" phx-disable-with="Saving…">Assign character</button>
            </.form>
          </section>
          <details class="workspace-panel">
            <summary class="cursor-pointer font-medium">Roles & campaign settings</summary>
            <.form
              for={@member_form}
              id="member-role-form"
              phx-submit="set-role"
              class="mt-5 space-y-4"
            >
              <input type="hidden" name="request_id" value={@request_id <> "-campaign-role"} />
              <.input
                field={@member_form[:user_id]}
                type="select"
                label="Roster member"
                options={@member_options}
                required
              /><.input
                field={@member_form[:role]}
                type="select"
                label="Campaign role"
                options={[{"Player", "player"}, {"Spectator", "spectator"}, {"GM", "gm"}]}
              /><button class="secondary-button">Update campaign role</button>
            </.form>
            <.form
              :if={@steward}
              for={@delegation_form}
              id="world-role-form"
              phx-submit="world-role"
              class="mt-6 space-y-4 border-t border-stone-200 pt-5"
            >
              <input type="hidden" name="request_id" value={@request_id <> "-world-role"} />
              <.input
                field={@delegation_form[:user_id]}
                type="select"
                label="World member"
                options={@member_options}
                required
              /><.input
                field={@delegation_form[:role]}
                type="select"
                label="World authority (separate from campaign)"
                options={[{"Viewer", "viewer"}, {"Builder", "builder"}, {"Steward", "steward"}]}
              /><p class="helper-text">
                Builders curate published records. Stewards additionally manage world authority. The creating steward cannot be demoted.
              </p><button class="secondary-button">Update world authority</button>
            </.form>
            <button
              id="archive-campaign"
              class="text-link mt-6 text-sm"
              phx-click="archive"
              phx-value-revision={@campaign.revision}
              data-confirm="Archive this campaign? World assets and history remain saved."
            >Archive campaign</button>
          </details>
        </div>
      </div>
    </section>
    """
  end

  def experience_editor(assigns) do
    ~H"""
    <section>
      <header class="mb-6">
        <p class="eyebrow">Experience · {@experience.status}</p><h2
          id="experience-title"
          class="section-heading"
        >
          {@experience.name}
        </h2>
      </header>
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_24rem]">
        <div class="space-y-6">
          <section id="experience-state" class="workspace-panel">
            <span class="badge-working">{if @experience.status == "draft",
              do: "Prepared · not started",
              else: "Working · local to this Experience"}</span>
            <div :if={@working} class="mt-5 grid gap-5 sm:grid-cols-2">
              <div>
                <p class="eyebrow">Experience fictional time</p><p
                  id="working-time"
                  class="text-2xl font-semibold"
                >
                  {@working.time.value}s
                </p><p class="helper-text">Elapsed in play: {@working.elapsed}s</p>
              </div><div>
                <p class="eyebrow">Published world time</p><p class="text-2xl font-semibold">
                  {@world.fictional_time}s
                </p><p class="helper-text">Unchanged until approved incorporation</p>
              </div>
            </div>
            <p :if={!@working && @experience.status == "draft"} class="mt-5 text-sm text-stone-600">
              Starting selects the current published checkpoint, claims this place and its contents, and opens a local working state. No players need to be online.
            </p>
            <p
              :if={!@working && @experience.status != "draft"}
              id="unavailable-working-state"
              class="notice mt-5"
            >
              The saved state or starting checkpoint could not be verified. Controls are disabled; ask the steward to review recovery errors.
            </p>
            <.link
              navigate={~p"/worlds/#{@world.id}/places/#{@experience.zone_id}"}
              class="text-link mt-5 inline-block text-sm"
            >Inspect the published place →</.link>
            <p
              :if={@experience.status in ["active", "paused", "ready"]}
              id="claims-held"
              class="notice mt-5"
            >
              Claims held for this place, its people and items. Pausing preserves those claims and fictional time across gatherings.
            </p>
            <div :if={@can_manage} class="mt-6 flex flex-wrap gap-3">
              <button
                :if={@experience.status == "draft"}
                id="start-experience"
                class="primary-button"
                phx-click="start"
                phx-value-revision={@experience.revision}
                phx-disable-with="Starting…"
              >Start Experience</button>
              <button
                :if={@experience.status == "active" && @working}
                id="pause-experience"
                class="primary-button"
                phx-click="status"
                phx-value-action="pause"
                phx-value-revision={@working.revision}
                phx-value-request={@request_id <> "-pause"}
              >Pause & save</button>
              <button
                :if={@experience.status == "paused" && @working}
                id="resume-experience"
                class="primary-button"
                phx-click="status"
                phx-value-action="resume"
                phx-value-revision={@working.revision}
                phx-value-request={@request_id <> "-resume"}
              >Resume Experience</button>
            </div>
          </section>
          <section :if={@working} aria-labelledby="working-changes-heading">
            <h3 id="working-changes-heading" class="section-heading">Local outcomes</h3>
            <p class="helper-text mb-4">
              Changes since this Experience's published checkpoint. Only information visible to you is included; none of these rows publish a change.
            </p>
            <div id="working-changes" phx-update="stream" class="space-y-3">
              <p id="no-working-changes" class="empty-state hidden only:block">
                No visible record changes since the starting checkpoint.
              </p>
              <article :for={{id, change} <- @streams.working_changes} id={id} class="workspace-card">
                <h4 class="font-semibold">{change.label}</h4>
                <div class="mt-3 grid gap-4 sm:grid-cols-2">
                  <div>
                    <span class="badge-published">Starting checkpoint</span><p class="mt-2 break-words text-sm">
                      {change.published}
                    </p>
                  </div><div>
                    <span class="badge-working">Working outcome</span><p class="mt-2 break-words text-sm">
                      {change.working}
                    </p>
                  </div>
                </div>
              </article>
            </div>
          </section>
          <section id="incorporation-limit" class="notice">
            <h3 class="font-semibold">Time reconciliation is not available yet</h3><p class="mt-2 text-sm leading-relaxed">
              Your Experience is saved locally. Multi-Experience review, declared elapsed time and world advancement arrive in phase 08. The zero-duration storage proof is not a full completion workflow; there is no publish shortcut here.
            </p>
          </section>
          <section>
            <h3 class="section-heading">Gatherings</h3><p class="helper-text mb-4">
              Real meeting dates, separate from the story clock. One Experience can span several gatherings.
            </p>
            <div id="gatherings" phx-update="stream" class="space-y-3">
              <p id="empty-section-8" class="empty-state hidden only:block">
                No gathering scheduled. Add your first date, or return to play whenever you choose.
              </p><article
                :for={{id, gathering} <- @streams.gatherings}
                id={id}
                class="workspace-card"
              >
                <h4 class="font-semibold">{gathering.title}</h4><time class="mt-2 block text-sm text-stone-600">{Calendar.strftime(
                  gathering.starts_at,
                  "%b %d, %Y · %H:%M UTC"
                )}</time><a
                  :if={gathering.meeting_url not in [nil, ""]}
                  href={gathering.meeting_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-link mt-3 inline-block text-sm"
                >Open meeting link ↗</a>
              </article>
            </div>
          </section>
        </div>
        <section :if={@can_manage} class="workspace-panel">
          <h3 class="section-heading">Add a gathering</h3>
          <.form for={@gathering_form} id="gathering-form" phx-submit="gather" class="space-y-4">
            <input type="hidden" name="request_id" value={@request_id <> "-gather"} /><.input
              field={@gathering_form[:title]}
              label="Gathering name"
              required
              maxlength="160"
            /><.input
              field={@gathering_form[:starts_at]}
              type="datetime-local"
              label="Real meeting date & time (UTC)"
              required
            /><.input
              field={@gathering_form[:meeting_url]}
              type="url"
              label="Meeting link (optional)"
              placeholder="https://…"
            /><p class="helper-text">
              Dates are entered and displayed in UTC. Adding a gathering does not start or advance the Experience.
            </p><button id="save-gathering" class="secondary-button" phx-disable-with="Saving…">Save gathering</button>
          </.form>
        </section>
      </div>
    </section>
    """
  end

  defp member_label(options, id),
    do:
      Enum.find_value(options, "a roster member", fn {label, value} ->
        if value == id, do: label
      end)
end
