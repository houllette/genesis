defmodule GenesisWeb.NetworkLive do
  use GenesisWeb, :live_view
  alias Genesis.{WorldNetwork, Worlds}

  @impl true
  def mount(%{"world_id" => world}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)
    {:ok, assign(socket, world_id: world, editor: nil, preview: false, assessment: nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world_id: world}} = socket),
    do: {:noreply, socket |> assign(:assessment, nil) |> load()}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new", _params, socket) do
    socket = load(socket)

    if socket.assigns.can_edit do
      {:noreply,
       editor(
         socket,
         "connection",
         %{
           "from" => "",
           "to" => "",
           "condition" => "open",
           "capacity" => 4,
           "visibility" => "gm"
         },
         false
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-connection", %{"from" => from, "to" => to}, socket) do
    socket = load(socket)
    edge = Enum.find(socket.assigns.edges, &(&1["from"] == from and &1["to"] == to))

    if socket.assigns.can_edit and edge,
      do: {:noreply, editor(socket, "connection", edge, true)},
      else: {:noreply, socket}
  end

  def handle_event("jurisdiction", %{"id" => id}, socket) do
    socket = load(socket)
    institution = Enum.find(socket.assigns.sites, &(&1.id == id))

    if socket.assigns.can_edit and institution do
      attrs = %{
        "institution_id" => id,
        "zones" => institution.zones,
        "visibility" => institution.visibility
      }

      {:noreply, editor(socket, "jurisdiction", attrs, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :editor, nil)}

  def handle_event("preview", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(preview: not socket.assigns.preview, editor: nil, assessment: nil)
       |> load()}

  def handle_event(
        "save",
        %{"record" => attrs, "editor_request" => request},
        %{assigns: %{editor: %{request: request} = editor}} = socket
      )
      when is_map(attrs) do
    result =
      with {:ok, command} <- command(attrs, editor) do
        WorldNetwork.save(
          socket.assigns.current_scope,
          socket.assigns.world_id,
          editor.expected,
          command,
          request
        )
      end

    case result do
      {:ok, result} ->
        message =
          if result["status"] == "draft",
            do: "Saved as a Draft. Published connections and active Experiences are unchanged.",
            else: "Published world connections updated. No actors or resources moved."

        {:noreply,
         socket |> assign(editor: nil, assessment: nil) |> load() |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, socket |> load() |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("save", _params, socket),
    do:
      {:noreply,
       socket
       |> load()
       |> put_flash(:error, "That editor is no longer current. Reopen it before saving.")}

  def handle_event("assess", %{"check" => params}, socket) when is_map(params) do
    socket = load(socket)

    result =
      if socket.assigns.world do
        WorldNetwork.assess(
          socket.assigns.current_scope,
          socket.assigns.world_id,
          params["from"],
          params["to"],
          integer(params["size"])
        )
      else
        {:error, :unavailable}
      end

    {:noreply,
     assign(socket, assessment: assessment(result), check_form: to_form(params, as: :check))}
  end

  def handle_event(_event, _params, socket), do: {:noreply, load(socket)}

  defp editor(socket, type, attrs, existing) do
    expected = %{generation: socket.assigns.generation, revision: socket.assigns.revision}

    assign(socket,
      editor: %{
        type: type,
        attrs: attrs,
        existing: existing,
        expected: expected,
        request: Ecto.UUID.generate()
      },
      record_form: to_form(attrs, as: :record),
      editor_stale: false
    )
  end

  defp command(attrs, %{type: "connection"} = editor) do
    if Map.keys(attrs) -- ~w(from to condition capacity visibility) == [] do
      attrs = Map.put(attrs, "capacity", integer(attrs["capacity"]))

      attrs =
        if editor.existing, do: Map.merge(attrs, Map.take(editor.attrs, ~w(from to))), else: attrs

      {:ok, Map.put(attrs, "type", "connection")}
    else
      {:error, :invalid_connection}
    end
  end

  defp command(attrs, %{type: "jurisdiction", attrs: original}) do
    if Map.keys(attrs) -- ~w(zones visibility) == [] do
      zones = attrs["zones"]
      zones = if is_list(zones), do: Enum.reject(zones, &(&1 == "")), else: zones

      {:ok,
       %{
         "type" => "jurisdiction",
         "institution_id" => original["institution_id"],
         "zones" => zones,
         "visibility" => attrs["visibility"]
       }}
    else
      {:error, :invalid_jurisdiction}
    end
  end

  defp load(socket) do
    case WorldNetwork.view(socket.assigns.current_scope, socket.assigns.world_id,
           public: socket.assigns.preview
         ) do
      {:ok, view} ->
        editor = if view.can_edit, do: socket.assigns.editor

        stale =
          not is_nil(editor) and
            editor.expected != %{generation: view.generation, revision: view.revision}

        edges =
          Enum.map(
            view.connections,
            &Map.put(
              &1,
              "id",
              Worlds.named_id([view.world.id, "connection", &1["from"], &1["to"]])
            )
          )

        socket
        |> assign(
          world: view.world,
          revision: view.revision,
          generation: view.generation,
          can_edit: view.can_edit,
          window_open: view.window_open,
          editor: editor,
          editor_stale: stale,
          edges: view.connections,
          sites: view.institutions,
          zone_names: Map.new(view.zones, &{&1.id, &1.name}),
          zone_options: Enum.map(view.zones, &{&1.name, &1.id})
        )
        |> assign_new(:check_form, fn ->
          to_form(%{"from" => "", "to" => "", "size" => 1}, as: :check)
        end)
        |> stream(:connections, Enum.map(edges, &%{id: &1["id"], data: &1}), reset: true)
        |> stream(:institutions, view.institutions, reset: true)

      {:error, _reason} ->
        socket
        |> assign(
          world: nil,
          editor: nil,
          can_edit: false,
          edges: [],
          sites: [],
          assessment: nil,
          zone_names: %{},
          zone_options: []
        )
        |> stream(:connections, [], reset: true)
        |> stream(:institutions, [], reset: true)
        |> put_flash(:error, "This world's connections are unavailable.")
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(value) when is_integer(value), do: value
  defp integer(_value), do: nil

  defp error_message(reason) when reason in [:stale_revision, :stale_generation],
    do:
      "The published network changed. Reopen the editor and review the current values before saving."

  defp error_message(:invalid_network),
    do: "Not saved. Check available places, the institution's home, and the network limits."

  defp error_message(_reason),
    do: "Not saved. Check the fields, current permissions, and selected places."

  defp assessment(:ok),
    do:
      "This connection fits the group. This check is not travel: nobody has moved or reserved a destination."

  defp assessment({:error, :capacity_exceeded}),
    do: "This group exceeds the connection's capacity."

  defp assessment({:error, :route_unavailable}),
    do: "No open visible connection in that direction. Damaged and closed links block passage."

  defp assessment(_result), do: "Choose a group size from 1 to 1,000 and available places."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={@world}>
        <.link navigate={~p"/worlds/#{@world.id}"} class="text-link">← {@world.name}</.link>
        <header class="my-6 flex flex-wrap items-center justify-between gap-4">
          <div>
            <p class="eyebrow">Published world · geography & institutions</p><h1 class="display-title">
              World connections
            </h1>
          </div>
          <div class="flex gap-2">
            <button
              :if={@can_edit or @preview}
              id="network-preview"
              phx-click="preview"
              class="secondary-button"
            >{if @preview, do: "Return to GM view", else: "Preview public view"}</button>
            <button :if={@can_edit} id="network-new" phx-click="new" class="primary-button">Connect places</button>
          </div>
        </header>
        <p id="network-boundary" class="mb-4 text-sm text-stone-600">
          Connections have one direction. Add the return direction separately. Atlas lore routes are descriptive records, not these links. Actor travel uses the separate Experience travel screen; remote deliveries are not enabled yet.
        </p>
        <p :if={@window_open} id="network-window" class="notice mb-4">
          An advancement window is open. Saves create Drafts; Published and Working state stay unchanged.
        </p>
        <div class="grid items-start gap-8 lg:grid-cols-2">
          <section>
            <h2 class="section-heading">Connections</h2>
            <div id="network-connections" phx-update="stream" class="space-y-3">
              <p id="network-empty" class="empty-state hidden only:block">
                No visible connections yet.
              </p>
              <article :for={{id, edge} <- @streams.connections} id={id} class="workspace-card">
                <h3 class="font-semibold">
                  {@zone_names[edge.data["from"]]} → {@zone_names[edge.data["to"]]}
                </h3>
                <p class="mt-2 text-sm">
                  {String.capitalize(edge.data["condition"])} · capacity {edge.data["capacity"]} · {if edge.data[
                                                                                                         "visibility"
                                                                                                       ] ==
                                                                                                         "gm",
                                                                                                       do:
                                                                                                         "GM only",
                                                                                                       else:
                                                                                                         "Public"}
                </p>
                <button
                  :if={@can_edit}
                  id={"edit-" <> edge.id}
                  phx-click="edit-connection"
                  phx-value-from={edge.data["from"]}
                  phx-value-to={edge.data["to"]}
                  class="text-link mt-3"
                >Edit connection</button>
              </article>
            </div>
          </section>
          <section>
            <h2 class="section-heading">Institution reach</h2>
            <p class="mb-4 text-sm text-stone-600">
              Declared jurisdictions do not grant membership, spread private knowledge, or enforce laws elsewhere. Local stock, affiliations and policy stay with the home place.
            </p>
            <div id="network-institutions" phx-update="stream" class="space-y-3">
              <p id="network-no-institutions" class="empty-state hidden only:block">
                No visible registered institutions.
              </p>
              <article :for={{id, site} <- @streams.institutions} id={id} class="workspace-card">
                <h3 class="font-semibold">{site.name}</h3>
                <p class="mt-2 text-sm">
                  {if site.registered, do: "Registered", else: "Local only"} · Home: {@zone_names[
                    site.home_zone
                  ]}
                </p>
                <p :if={site.registered} class="mt-2 text-sm">
                  Declared reach: {Enum.map_join(site.zones, ", ", &@zone_names[&1])}
                </p>
                <div class="mt-3 flex gap-4">
                  <.link
                    id={"institution-home-" <> site.id}
                    navigate={~p"/worlds/#{@world.id}/places/#{site.home_zone}/resources"}
                    class="text-link"
                  >Inspect home</.link>
                  <button
                    :if={@can_edit}
                    id={"jurisdiction-" <> site.id}
                    phx-click="jurisdiction"
                    phx-value-id={site.id}
                    class="text-link"
                  >{if site.registered, do: "Edit reach", else: "Register reach"}</button>
                </div>
              </article>
            </div>
          </section>
        </div>
        <section :if={@editor} class="workspace-panel mt-8 max-w-2xl">
          <h2 class="section-heading">
            {if @editor.type == "connection", do: "Connection", else: "Institution reach"}
          </h2>
          <p :if={@editor_stale} id="network-stale" class="notice mb-4">
            The network changed while you were editing. Cancel and reopen this editor to review the new values.
          </p>
          <.form for={@record_form} id="network-form" phx-submit="save" class="space-y-4">
            <input type="hidden" name="editor_request" value={@editor.request} />
            <div :if={@editor.type == "connection"}>
              <div :if={not @editor.existing} class="grid gap-3 sm:grid-cols-2">
                <.input
                  field={@record_form[:from]}
                  type="select"
                  label="From"
                  prompt="Choose a place"
                  options={@zone_options}
                  required
                />
                <.input
                  field={@record_form[:to]}
                  type="select"
                  label="To"
                  prompt="Choose a place"
                  options={@zone_options}
                  required
                />
              </div>
              <p :if={@editor.existing} class="mb-3">
                {@zone_names[@editor.attrs["from"]]} → {@zone_names[@editor.attrs["to"]]}
              </p>
              <.input
                field={@record_form[:condition]}
                type="select"
                label="Condition"
                options={[
                  {"Open", "open"},
                  {"Damaged — passage blocked", "damaged"},
                  {"Closed", "closed"}
                ]}
              />
              <.input
                field={@record_form[:capacity]}
                type="number"
                label="Maximum group size"
                min="1"
                max="1000"
                required
              />
            </div>
            <div :if={@editor.type == "jurisdiction"}>
              <p class="mb-3 text-sm">
                Include the institution's home. This preserves its existing identity and local records.
              </p>
              <.input
                field={@record_form[:zones]}
                type="select"
                multiple
                label="Declared places"
                options={@zone_options}
                required
              />
            </div>
            <.input
              field={@record_form[:visibility]}
              type="select"
              label="Visibility"
              options={[{"GM only", "gm"}, {"Public world members", "public"}]}
            />
            <div class="flex gap-3">
              <button
                id="network-save"
                class="primary-button"
                disabled={@editor_stale}
                phx-disable-with="Saving…"
              >{if @window_open, do: "Save draft", else: "Save published changes"}</button>
              <button id="network-cancel" type="button" phx-click="cancel" class="secondary-button">Cancel</button>
            </div>
          </.form>
        </section>
        <details class="workspace-panel mt-8 max-w-2xl">
          <summary class="cursor-pointer font-semibold">Check a connection's capacity</summary>
          <.form for={@check_form} id="network-check" phx-submit="assess" class="mt-4 space-y-3">
            <.input
              field={@check_form[:from]}
              type="select"
              label="From"
              prompt="Choose a place"
              options={@zone_options}
              required
            />
            <.input
              field={@check_form[:to]}
              type="select"
              label="To"
              prompt="Choose a place"
              options={@zone_options}
              required
            />
            <.input
              field={@check_form[:size]}
              type="number"
              label="Group size"
              min="1"
              max="1000"
              required
            />
            <button id="network-assess" class="secondary-button">Check only</button>
          </.form>
          <p :if={@assessment} id="network-assessment" role="status" class="mt-4 text-sm">
            {@assessment}
          </p>
        </details>
      </div>
    </Layouts.app>
    """
  end
end
