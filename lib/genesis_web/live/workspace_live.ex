defmodule GenesisWeb.WorkspaceLive do
  use GenesisWeb, :live_view
  import GenesisWeb.WorkspaceComponents
  alias Genesis.{Campaigns, Content, Experiences, Invitations, Workspace, Worlds}
  alias Genesis.Core.Persona
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.{Access, History}

  @impl true
  def mount(%{"world_id" => world}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)
    {:ok, assign(socket, preview: false, invitation_url: nil, forms_ready: false)}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, load(socket, params) |> initialize_forms()}

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world: %{id: world}}} = socket),
    do: {:noreply, load(socket, socket.assigns.params)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create-zone", %{"zone" => attrs, "request_id" => request}, socket) do
    case Content.create_zone(
           socket.assigns.current_scope,
           socket.assigns.world.id,
           attrs,
           request
         ) do
      {:ok, %{"status" => "published", "zone_id" => id}} ->
        {:noreply, push_navigate(socket, to: ~p"/worlds/#{socket.assigns.world.id}/places/#{id}")}

      result ->
        finish(socket, result)
    end
  end

  def handle_event("record-change", %{"record" => attrs}, socket),
    do: {:noreply, assign(socket, :record_form, to_form(attrs, as: :record))}

  def handle_event(
        "save-record",
        %{"record" => attrs, "record_id" => id, "revision" => revision, "request_id" => request},
        socket
      ) do
    result =
      Content.curate(
        socket.assigns.current_scope,
        socket.assigns.world.id,
        socket.assigns.zone.zone_id,
        integer(revision),
        blank_nil(id),
        normalize_record(attrs),
        request
      )

    finish(socket, result)
  end

  def handle_event("edit-record", %{"id" => id, "kind" => kind}, socket) do
    case record_attrs(socket.assigns.zone, id, kind) do
      nil ->
        finish(socket, {:error, :unavailable})

      attrs ->
        {:noreply,
         assign(socket,
           record_form: to_form(attrs, as: :record),
           record_id: id,
           record_revision: socket.assigns.zone.revision,
           request_id: Ecto.UUID.generate()
         )}
    end
  end

  def handle_event("new-record", _params, socket), do: {:noreply, record_form(socket)}

  def handle_event("preview", _params, socket),
    do:
      {:noreply,
       socket |> assign(:preview, not socket.assigns.preview) |> load(socket.assigns.params)}

  def handle_event(
        "save-note",
        %{"note" => attrs, "note_id" => id, "revision" => revision, "request_id" => request},
        socket
      ),
      do:
        finish(
          socket,
          Content.save_note(
            socket.assigns.current_scope,
            socket.assigns.world.id,
            blank_nil(id),
            integer(revision),
            attrs,
            request
          )
        )

  def handle_event("edit-note", %{"id" => id}, socket) do
    note =
      Content.list_notes(socket.assigns.current_scope, socket.assigns.world.id)
      |> Enum.find(&(&1.id == id and &1.author_id == socket.assigns.current_scope.user.id))

    if note do
      attrs = %{
        "title" => note.title,
        "body" => note.body,
        "kind" => note.kind,
        "visibility" => note.visibility,
        "entity_id" => note.entity_id
      }

      {:noreply,
       assign(socket,
         note_form: to_form(attrs, as: :note),
         note_id: id,
         note_revision: note.revision,
         request_id: Ecto.UUID.generate()
       )}
    else
      finish(socket, {:error, :unavailable})
    end
  end

  def handle_event("create-campaign", %{"campaign" => attrs, "request_id" => request}, socket) do
    case Campaigns.create_campaign(
           socket.assigns.current_scope,
           socket.assigns.world.id,
           attrs,
           request
         ) do
      {:ok, campaign} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/worlds/#{socket.assigns.world.id}/campaigns/#{campaign.id}"
         )}

      error ->
        finish(socket, error)
    end
  end

  def handle_event("invite", %{"invitation" => attrs, "request_id" => request}, socket) do
    case Invitations.invite(
           socket.assigns.current_scope,
           socket.assigns.world.id,
           socket.assigns.campaign.id,
           attrs,
           request
         ) do
      {:ok, invitation} ->
        {:noreply,
         assign(socket, invitation_url: url(~p"/invitations/#{invitation.token}"))
         |> put_flash(
           :info,
           "Invitation created. Share this link privately with the named person; it expires in seven days."
         )}

      error ->
        finish(socket, error)
    end
  end

  def handle_event(
        "set-role",
        %{"member" => %{"user_id" => user, "role" => role}, "request_id" => request},
        socket
      ),
      do:
        finish(
          socket,
          Campaigns.add_member(
            socket.assigns.current_scope,
            socket.assigns.world.id,
            socket.assigns.campaign.id,
            user,
            role,
            request
          )
        )

  def handle_event(
        "world-role",
        %{"delegation" => %{"user_id" => user, "role" => role}, "request_id" => request},
        socket
      ),
      do:
        finish(
          socket,
          Worlds.set_role(
            socket.assigns.current_scope,
            socket.assigns.world.id,
            user,
            role,
            request
          )
        )

  def handle_event("revoke-member", %{"id" => user, "request" => request}, socket),
    do:
      finish(
        socket,
        Campaigns.revoke_member(
          socket.assigns.current_scope,
          socket.assigns.world.id,
          socket.assigns.campaign.id,
          user,
          request
        )
      )

  def handle_event(
        "bind",
        %{"binding" => %{"user_id" => user, "actor_id" => actor}, "request_id" => request},
        socket
      ),
      do:
        finish(
          socket,
          Campaigns.bind_character(
            socket.assigns.current_scope,
            socket.assigns.world.id,
            socket.assigns.campaign.id,
            user,
            actor,
            request
          )
        )

  def handle_event("create-experience", %{"experience" => attrs, "request_id" => request}, socket) do
    case Experiences.create(
           socket.assigns.current_scope,
           socket.assigns.world.id,
           socket.assigns.campaign.id,
           attrs,
           request
         ) do
      {:ok, exp} ->
        {:noreply,
         push_navigate(socket, to: ~p"/worlds/#{socket.assigns.world.id}/experiences/#{exp.id}")}

      error ->
        finish(socket, error)
    end
  end

  def handle_event("start", %{"revision" => revision}, socket),
    do:
      finish(
        socket,
        Experiences.start(
          socket.assigns.current_scope,
          socket.assigns.world.id,
          socket.assigns.experience.id,
          integer(revision)
        )
      )

  def handle_event(
        "status",
        %{"action" => action, "revision" => revision, "request" => request},
        socket
      )
      when action in ["pause", "resume", "ready"] do
    command = %{"pause" => :pause, "resume" => :resume, "ready" => :ready}[action]

    finish(
      socket,
      Runtime.call(
        socket.assigns.current_scope,
        socket.assigns.world.id,
        {:status, socket.assigns.experience.id, command, integer(revision), request}
      )
    )
  end

  def handle_event("gather", %{"gathering" => attrs, "request_id" => request}, socket) do
    attrs = Map.update(attrs, "starts_at", "", &(&1 <> ":00Z"))

    finish(
      socket,
      Workspace.gather(
        socket.assigns.current_scope,
        socket.assigns.world.id,
        socket.assigns.experience.id,
        attrs,
        request
      )
    )
  end

  def handle_event("archive", %{"revision" => revision}, socket),
    do:
      finish(
        socket,
        Campaigns.archive(
          socket.assigns.current_scope,
          socket.assigns.world.id,
          socket.assigns.campaign.id,
          integer(revision)
        )
      )

  def handle_event(_event, _params, socket), do: finish(socket, {:error, :invalid_request})

  defp finish(socket, {:ok, result}) do
    message =
      if is_map(result) and Map.get(result, "status") == "draft",
        do: "Saved as a Draft. Published history and the active Experience are unchanged.",
        else: "Saved. Your changes are durable."

    {:noreply,
     socket
     |> load(socket.assigns.params)
     |> assign(:forms_ready, false)
     |> initialize_forms()
     |> put_flash(:info, message)}
  end

  defp finish(socket, {:error, reason}),
    do:
      {:noreply,
       socket |> load(socket.assigns.params) |> put_flash(:error, error_message(reason))}

  defp load(socket, %{"world_id" => world_id} = params) do
    scope = socket.assigns.current_scope

    with {:ok, world} <- Worlds.get_world(scope, world_id),
         {:ok, selected} <- selection(scope, world_id, params, socket.assigns.preview) do
      socket
      |> assign(selected)
      |> assign(
        world: world,
        params: params,
        page_title: world.name,
        can_build: Access.world(scope, world_id, ["steward", "builder"]) == :ok,
        steward: Access.world(scope, world_id, ["steward"]) == :ok,
        window_open: Content.window_open?(scope, world_id)
      )
      |> collections()
    else
      _ ->
        socket
        |> put_flash(:error, "This workspace is unavailable or your access has changed.")
        |> push_navigate(to: ~p"/worlds")
    end
  end

  defp selection(scope, world, %{"zone_id" => id}, preview) do
    result =
      if preview, do: Content.preview(scope, world, id), else: Content.view(scope, world, id)

    with {:ok, zone} <- result,
         do: {:ok, %{zone: zone, campaign: nil, experience: nil, working: nil, can_manage: false}}
  end

  defp selection(scope, world, %{"campaign_id" => id}, _preview) do
    with {:ok, campaign} <- Campaigns.get_campaign(scope, world, id),
         do:
           {:ok,
            %{
              zone: nil,
              campaign: campaign,
              experience: nil,
              working: nil,
              can_manage:
                not campaign.archived and
                  match?({:ok, _}, Access.campaign(scope, world, id, ["gm"]))
            }}
  end

  defp selection(scope, world, %{"experience_id" => id}, _preview) do
    with {:ok, exp} <- Experiences.get(scope, world, id),
         {:ok, campaign} <- Campaigns.get_campaign(scope, world, exp.campaign_id) do
      working =
        case Workspace.experience_view(scope, world, id) do
          {:ok, view} -> view
          _ -> nil
        end

      {:ok,
       %{
         zone: nil,
         campaign: campaign,
         experience: exp,
         working: working,
         can_manage:
           not campaign.archived and
             match?({:ok, _}, Access.campaign(scope, world, campaign.id, ["gm"]))
       }}
    end
  end

  defp selection(_scope, _world, _params, _preview),
    do: {:ok, %{zone: nil, campaign: nil, experience: nil, working: nil, can_manage: false}}

  defp collections(socket) do
    %{current_scope: scope, world: world, zone: zone, campaign: campaign, experience: exp} =
      socket.assigns

    zones = Content.list_zones(scope, world.id)

    notes =
      Content.list_notes(scope, world.id,
        public: socket.assigns.preview,
        zone_id: if(zone, do: zone.zone_id)
      )

    roster = if campaign, do: Workspace.roster(scope, world.id, campaign.id), else: []
    bindings = if campaign, do: Workspace.bindings(scope, world.id, campaign.id), else: []
    pcs = published_characters(scope, world.id, zones)
    history = history(scope, world.id, exp)

    socket
    |> assign(
      zone_options: Enum.map(zones, &{&1.name, &1.id}),
      member_options: Enum.map(roster, &{&1.email, &1.id}),
      actor_options: Enum.map(pcs, &{&1.name, &1.id}),
      entity_options: entity_options(zones, zone),
      request_id: Map.get(socket.assigns, :request_id, Ecto.UUID.generate())
    )
    |> stream(:zones, zones, reset: true)
    |> stream(:campaigns, Campaigns.list_campaigns(scope, world.id), reset: true)
    |> stream(:experiences, Experiences.list(scope, world.id), reset: true)
    |> stream(:drafts, Content.list_drafts(scope, world.id), reset: true)
    |> stream(:notes, notes, reset: true)
    |> stream(:actors, if(zone, do: zone.actors, else: []), reset: true)
    |> stream(:items, if(zone, do: zone.items, else: []), reset: true)
    |> stream(:roster, roster, reset: true)
    |> stream(
      :bindings,
      Enum.map(bindings, &Map.put(Map.from_struct(&1), :name, actor_name(pcs, &1.actor_id))),
      reset: true
    )
    |> stream(:gatherings, if(exp, do: Workspace.gatherings(scope, world.id, exp.id), else: []),
      reset: true
    )
    |> stream(:history, history, reset: true)
    |> stream(
      :working_changes,
      if(socket.assigns.working, do: socket.assigns.working.changes, else: []),
      reset: true
    )
  end

  defp published_characters(scope, world, zones) do
    Enum.flat_map(zones, fn zone ->
      case Content.view(scope, world, zone.id) do
        {:ok, view} -> Enum.filter(view.actors, &(&1.kind == :pc))
        _ -> []
      end
    end)
  end

  defp actor_name(pcs, id),
    do: Enum.find_value(pcs, id, fn actor -> if actor.id == id, do: actor.name end)

  defp entity_options(zones, nil), do: Enum.map(zones, &{&1.name <> " · place", &1.id})

  defp entity_options(_zones, zone),
    do:
      [{zone.name <> " · place", zone.zone_id}] ++
        Enum.map(zone.actors ++ zone.items, &{&1.name, &1.id})

  defp history(scope, world, exp) do
    opts = if exp, do: [experience_id: exp.id], else: []

    case History.page(scope, world, opts) do
      {:ok, page} -> page.events
      _ -> []
    end
  end

  defp initialize_forms(%{assigns: %{forms_ready: true}} = socket), do: socket

  defp initialize_forms(%{assigns: %{world: _}} = socket) do
    socket
    |> assign(
      forms_ready: true,
      request_id: Ecto.UUID.generate(),
      note_id: "",
      note_revision: 0,
      zone_form:
        to_form(
          %{
            "name" => "The Lantern Quay",
            "description" => "A weathered landing where river paths meet."
          },
          as: :zone
        ),
      note_form: to_form(%{"kind" => "note", "visibility" => "private"}, as: :note),
      campaign_form: to_form(%{"name" => "The Ashfall chronicles"}, as: :campaign),
      invitation_form: to_form(%{"role" => "player"}, as: :invitation),
      member_form: to_form(%{"role" => "player"}, as: :member),
      delegation_form: to_form(%{"role" => "viewer"}, as: :delegation),
      binding_form: to_form(%{}, as: :binding),
      experience_form:
        to_form(%{"name" => "A light at the quay", "participants" => []}, as: :experience),
      gathering_form: to_form(%{"title" => "An evening in Ashfall"}, as: :gathering)
    )
    |> record_form()
  end

  defp initialize_forms(socket), do: socket

  defp record_form(socket),
    do:
      assign(socket,
        record_id: "",
        record_revision: if(socket.assigns.zone, do: socket.assigns.zone.revision, else: 0),
        record_form:
          to_form(
            %{
              "kind" => "npc",
              "visibility" => "public",
              "temperament" => "Watchful",
              "goal" => "Protect their place in the community",
              "role" => "Resident",
              "culture" => "Unspecified",
              "motivation" => "Maintain belonging and security"
            },
            as: :record
          )
      )

  defp record_attrs(zone, id, "zone") when zone.zone_id == id,
    do: %{"kind" => "zone", "name" => zone.name, "description" => zone.description}

  defp record_attrs(zone, id, kind) when kind in ["npc", "pc"] do
    case Enum.find(zone.actors, &(&1.id == id and Atom.to_string(&1.kind) == kind)) do
      nil ->
        nil

      actor ->
        persona = Persona.materialize(actor.id, Map.get(actor, :persona, %{}))

        Map.merge(Map.take(persona, ~w(temperament goal role culture motivation)), %{
          "kind" => kind,
          "name" => actor.name,
          "visibility" => "unchanged"
        })
    end
  end

  defp record_attrs(zone, id, "item") do
    case Enum.find(zone.items, &(&1.id == id)) do
      nil ->
        nil

      item ->
        %{
          "kind" => "item",
          "name" => item.name,
          "quantity" => item.quantity,
          "visibility" => "unchanged"
        }
    end
  end

  defp record_attrs(_zone, _id, _kind), do: nil

  defp normalize_record(%{"kind" => "item"} = attrs),
    do: Map.update(attrs, "quantity", 1, &integer/1)

  defp normalize_record(attrs), do: attrs
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> -1
    end
  end

  defp integer(_value), do: -1
  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  defp error_message(:claimed),
    do:
      "That place is claimed by an unfinished Experience. Reopen it from Experiences below, or choose another place."

  defp error_message(reason) when reason in [:stale_revision, :stale_experience, :stale_snapshot],
    do:
      "This record changed since you opened it. Reopen its editor to review the latest version before saving."

  defp error_message(:unfinished_experiences),
    do:
      "This campaign still has unfinished Experiences. Pause them or complete their review before archiving."

  defp error_message(reason) when reason in [:unauthorized, :unavailable],
    do:
      "This operation is unavailable or your permission changed. Reopen the workspace or ask its steward."

  defp error_message(_reason),
    do:
      "The change was not saved. Check the fields, selected records and your current permissions."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={assigns[:world]}>
        <nav aria-label="Breadcrumb" class="mb-8 flex flex-wrap gap-2 text-sm text-stone-600">
          <.link navigate={~p"/worlds"} class="text-link">Your worlds</.link><span aria-hidden="true">/</span>
          <.link navigate={~p"/worlds/#{@world.id}"} class="text-link">{@world.name}</.link>
          <span :if={@zone} aria-current="page">/ {@zone.name}</span>
          <.link
            :if={@campaign}
            navigate={~p"/worlds/#{@world.id}/campaigns/#{@campaign.id}"}
            class="text-link"
          >/ {@campaign.name}</.link>
          <span :if={@experience} aria-current="page">/ {@experience.name}</span>
        </nav>
        <header class="mb-8 flex flex-wrap items-end justify-between gap-5">
          <div>
            <p class="eyebrow">The world-building workbench</p><h1
              id="world-title"
              class="display-title"
            >
              {@world.name}
            </h1>
          </div>
          <div id="published-time" class="status-card">
            <span class="badge-published">Published</span><p class="mt-2 text-sm">
              Fictional coordinate {@world.fictional_time}s · revision {@world.revision}
            </p>
          </div>
        </header>
        <aside :if={@window_open} id="open-window" class="notice mb-8">
          <strong>An advancement window is open.</strong>
          Ongoing Experiences work from the published checkpoint. Authoring changes save as Drafts; the shared world stays unchanged.
        </aside>
        <.world_overview :if={@live_action == :world} {assigns} />
        <.place_editor :if={@live_action == :zone} {assigns} />
        <.link
          :if={@zone && @can_build && !@preview}
          id="place-resources"
          class="secondary-button mt-6"
          navigate={~p"/worlds/#{@world.id}/places/#{@zone.zone_id}/resources"}
        >Resources & institutions</.link>
        <.campaign_editor :if={@live_action == :campaign} {assigns} />
        <.experience_editor :if={@live_action == :experience} {assigns} />
        <.link
          :if={@experience && @working && @can_manage}
          id="experience-resources"
          class="secondary-button mt-6"
          navigate={~p"/worlds/#{@world.id}/experiences/#{@experience.id}/resources"}
        >Trade, production & local consequences</.link>
        <section class="mt-12 border-t border-stone-200 pt-8">
          <h2 class="section-heading">Experiences</h2>
          <div id="experiences" phx-update="stream" class="grid gap-4 md:grid-cols-2">
            <p id="empty-workspace-1" class="empty-state hidden only:block md:col-span-2">
              Prepare an Experience from a campaign when the world is ready. You can start without a connected player.
            </p>
            <article :for={{id, exp} <- @streams.experiences} id={id} class="workspace-card">
              <span class="status-label">{String.replace(exp.status, "_", " ")}</span>
              <h3 class="mt-2 text-xl font-semibold">
                <.link navigate={~p"/worlds/#{@world.id}/experiences/#{exp.id}"} class="text-link">{exp.name}</.link>
              </h3>
              <p class="helper-text">
                {if exp.status == "draft",
                  do: "Not started · no claims held",
                  else: "Local outcomes · shared history changes only after review"}
              </p>
            </article>
          </div>
        </section>
        <section :if={@can_build} class="mt-8">
          <h2 class="section-heading">Authoring drafts</h2>
          <div id="drafts" phx-update="stream" class="space-y-3">
            <p id="empty-workspace-2" class="helper-text hidden only:block">
              No pending authoring drafts.
            </p>
            <article :for={{id, draft} <- @streams.drafts} id={id} class="notice">
              <span class="badge-draft">Draft</span> <strong>{draft.attrs["name"]}</strong>
              · {draft.kind}
              <p class="helper-text">
                Saved against published revision {draft.base_revision}. Publication requires the window to close and a fresh conflict review; draft promotion is not yet available.
              </p>
            </article>
          </div>
        </section>
        <details class="mt-10 rounded-xl border border-stone-200 p-5">
          <summary class="cursor-pointer font-medium">
            {if @experience, do: "Experience audit", else: "Published audit"} · your authorized history
          </summary>
          <div id="history" phx-update="stream" class="mt-4 space-y-3">
            <p id="empty-workspace-3" class="helper-text hidden only:block">
              No visible history in this scope.
            </p>
            <article
              :for={{id, event} <- @streams.history}
              id={id}
              class="border-b border-stone-100 pb-3 text-sm"
            >
              <span>{String.replace(event.type, "_", " ")}</span><time class="ml-3 text-stone-500">{Calendar.strftime(
                event.recorded_at,
                "%b %d, %Y · %H:%M UTC"
              )}</time>
            </article>
          </div>
          <p class="helper-text mt-4">
            First 30 visible entries. Timestamps are real audit time, not fictional elapsed time.
          </p>
        </details>
      </div>
    </Layouts.app>
    """
  end
end
