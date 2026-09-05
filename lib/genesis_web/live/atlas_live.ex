defmodule GenesisWeb.AtlasLive do
  use GenesisWeb, :live_view
  alias Genesis.{Campaigns, Content, Worlds}
  alias Genesis.Content.Atlas
  alias Genesis.Core.AtlasRecord
  alias Genesis.Persistence.Access

  @impl true
  def mount(%{"world_id" => world}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)

    {:ok,
     assign(socket,
       world_id: world,
       query: "",
       preview: false,
       selected: nil,
       editor: nil,
       archived: false
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world_id: world}} = socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket)
      when is_binary(query) and byte_size(query) <= 100,
      do: {:noreply, socket |> assign(:query, query) |> load()}

  def handle_event("search", _params, socket),
    do: {:noreply, socket |> load() |> put_flash(:error, "Search is limited to 100 bytes.")}

  def handle_event("preview", _params, socket),
    do:
      {:noreply,
       socket |> assign(preview: not socket.assigns.preview, selected: nil, editor: nil) |> load()}

  def handle_event("archives", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(archived: not socket.assigns.archived, selected: nil, editor: nil)
       |> load()}

  def handle_event("show", %{"ref" => ref}, socket),
    do: {:noreply, socket |> assign(selected: %{id: ref}, editor: nil) |> load()}

  def handle_event("new", _params, socket) do
    socket = load(socket)

    if socket.assigns.can_edit do
      attrs = %{
        "kind" => "article",
        "name" => "",
        "body" => "",
        "visibility" => "gm",
        "tags" => ""
      }

      {:noreply, edit(socket, nil, 0, attrs)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit", _params, socket) do
    socket = load(socket)

    case socket.assigns.selected do
      %{editable: true} = record when socket.assigns.can_edit ->
        {:noreply, edit(socket, record.record_id, record.revision, edit_attrs(record))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :editor, nil)}

  def handle_event(
        "change",
        %{"record" => attrs, "editor_request" => request},
        %{assigns: %{editor: %{request: request}}} = socket
      ),
      do: {:noreply, assign(socket, :record_form, to_form(attrs, as: :record))}

  def handle_event(
        "save",
        %{"record" => attrs, "editor_request" => request},
        %{assigns: %{editor: %{request: request}}} = socket
      ) do
    %{current_scope: scope, world_id: world, editor: editor} = socket.assigns

    result =
      Atlas.save(
        scope,
        world,
        editor.id,
        editor.revision,
        normalize(attrs, editor.fields),
        editor.request
      )

    case result do
      {:ok, result} ->
        message =
          if result["status"] == "draft",
            do: "Saved as a Draft. Published and Working state are unchanged.",
            else: "Atlas record saved."

        {:noreply, socket |> assign(editor: nil) |> load() |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, socket |> load() |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("save", _params, socket),
    do:
      {:noreply,
       socket
       |> load()
       |> put_flash(:error, "That editor is no longer current. Reopen the record before saving.")}

  def handle_event(_event, _params, socket), do: {:noreply, load(socket)}

  defp edit(socket, id, revision, attrs) do
    fields = if socket.assigns.selected && id, do: socket.assigns.selected.fields, else: %{}

    assign(socket,
      editor: %{id: id, revision: revision, request: Ecto.UUID.generate(), fields: fields},
      record_form: to_form(Map.put(attrs, "annotations", annotation_values(fields)), as: :record)
    )
    |> load()
  end

  defp edit_attrs(record) do
    attrs =
      Map.new(
        [
          :kind,
          :name,
          :body,
          :visibility,
          :campaign_id,
          :parent,
          :source,
          :target,
          :relation,
          :archived
        ],
        &{Atom.to_string(&1), Map.get(record, &1)}
      )

    attrs |> Map.put("tags", Enum.join(record.tags, ", ")) |> Map.merge(record.fields)
  end

  defp normalize(attrs, saved_fields) do
    kind = attrs["kind"]

    fields = custom_fields(kind, attrs, saved_fields)

    attrs
    |> Map.take(~w(kind name body visibility))
    |> Map.merge(%{
      "tags" =>
        String.split(Map.get(attrs, "tags", ""), ",", trim: true) |> Enum.map(&String.trim/1),
      "campaign_id" => if(attrs["visibility"] == "party", do: blank(attrs["campaign_id"])),
      "parent" => if(kind in ~w(region location), do: blank(attrs["parent"])),
      "source" => if(kind in ~w(route relationship), do: blank(attrs["source"])),
      "target" => if(kind in ~w(route relationship), do: blank(attrs["target"])),
      "relation" => if(kind == "relationship", do: attrs["relation"]),
      "fields" => fields,
      "archived" => attrs["archived"] in [true, "true"]
    })
  end

  defp custom_fields("route", attrs, _saved),
    do: %{"condition" => attrs["condition"], "capacity" => integer(attrs["capacity"])}

  defp custom_fields("resource_site", attrs, _saved), do: %{"resource" => attrs["resource"]}
  defp custom_fields(_kind, %{"annotations" => rows}, _saved), do: annotations(rows)
  defp custom_fields(_kind, _attrs, saved), do: saved

  defp annotation_values(fields) do
    fields
    |> Enum.sort()
    |> Enum.with_index()
    |> Map.new(fn {{key, value}, index} ->
      type =
        cond do
          is_boolean(value) -> "boolean"
          is_integer(value) -> "integer"
          true -> "text"
        end

      {Integer.to_string(index),
       %{
         "key" => String.replace_prefix(key, "note:", ""),
         "type" => type,
         "value" => to_string(value)
       }}
    end)
  end

  defp annotations(rows) when is_map(rows) and map_size(rows) <= 8 do
    pairs =
      for {_index, %{"key" => key, "type" => type, "value" => value}} <- rows,
          is_binary(key) and is_binary(type) and is_binary(value),
          key != "",
          do: {"note:" <> key, annotation_value(type, value)}

    if Enum.all?(rows, &annotation_row?/1) and
         length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))),
       do: Map.new(pairs),
       else: %{"invalid" => true}
  end

  defp annotations(_rows), do: %{"invalid" => true}

  defp annotation_row?({_index, %{"key" => key, "type" => type, "value" => value}}),
    do: is_binary(key) and is_binary(type) and is_binary(value)

  defp annotation_row?(_row), do: false

  defp annotation_value("integer", value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp annotation_value("boolean", "true"), do: true
  defp annotation_value("boolean", "false"), do: false
  defp annotation_value("text", value), do: value
  defp annotation_value(_type, _value), do: nil

  defp annotation(form, index, key),
    do: get_in(form.params, ["annotations", to_string(index), key]) || ""

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> -1
    end
  end

  defp integer(_value), do: -1

  defp load(socket) do
    %{current_scope: scope, world_id: world, query: query} = socket.assigns
    opts = [public: socket.assigns.preview, archived: socket.assigns.archived]

    with {:ok, record} <- Worlds.get_world(scope, world),
         {:ok, page} <- Atlas.search(scope, world, query, opts) do
      can_edit =
        not socket.assigns.preview and Access.world(scope, world, ["steward", "builder"]) == :ok

      {selected, links} = selection(scope, world, socket.assigns.selected, opts)

      editor =
        if can_edit and editor_visible?(scope, world, socket.assigns.editor, opts),
          do: socket.assigns.editor

      choices = reference_choices(socket, page.records, opts)

      socket
      |> assign(
        world: record,
        can_edit: can_edit,
        can_build: Access.world(scope, world, ["steward", "builder"]) == :ok,
        selected: selected,
        editor: editor,
        count: page.count,
        more: page.more,
        window_open: Content.window_open?(scope, world),
        search_form: to_form(%{"query" => query}, as: :search),
        choices: Enum.map(choices, &{&1.name <> " · " <> &1.kind, &1.id}),
        places:
          Enum.filter(choices, &(&1.kind in ~w(region location zone)))
          |> Enum.map(&{&1.name, &1.id}),
        campaigns: Campaigns.list_campaigns(scope, world) |> Enum.map(&{&1.name, &1.id})
      )
      |> stream(:records, page.records, reset: true)
      |> stream(:links, links, reset: true)
    else
      {:error, :invalid_query} ->
        put_flash(socket, :error, "Search is limited to 100 bytes.")

      _ ->
        socket
        |> assign(editor: nil, selected: nil)
        |> put_flash(:error, "This world is unavailable or your access changed.")
        |> push_navigate(to: ~p"/worlds")
    end
  end

  defp reference_choices(socket, records, opts) do
    refs =
      if socket.assigns.editor do
        Enum.map([:parent, :source, :target], &socket.assigns.record_form[&1].value)
      else
        []
      end

    current =
      refs
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn ref ->
        case Atlas.get(socket.assigns.current_scope, socket.assigns.world_id, ref, opts) do
          {:ok, %{record: record}} -> [record]
          _ -> []
        end
      end)

    (current ++ records)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&(&1.archived or &1.kind in ~w(route relationship)))
  end

  defp selection(_scope, _world, nil, _opts), do: {nil, []}

  defp selection(scope, world, selected, opts) do
    case Atlas.get(scope, world, selected.id, opts) do
      {:ok, result} -> {result.record, result.links}
      _ -> {nil, []}
    end
  end

  defp editor_visible?(_scope, _world, nil, _opts), do: false
  defp editor_visible?(_scope, _world, %{id: nil}, _opts), do: true

  defp editor_visible?(scope, world, editor, opts),
    do: match?({:ok, _}, Atlas.get(scope, world, "record:" <> editor.id, opts))

  defp error_message(:stale_revision),
    do: "This record changed. Reopen its editor before saving; your edit was not applied."

  defp error_message(:location_cycle),
    do: "A place cannot contain itself or one of its ancestors."

  defp error_message(:invalid_reference),
    do: "A linked record is unavailable, archived or the wrong type. Choose an available record."

  defp error_message(:capacity_limit),
    do:
      "This world's bounded atlas is full. Archiving preserves identities and does not free this limit."

  defp error_message(_reason),
    do: "Not saved. Check the fields, linked records and your current permissions."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={assigns[:world]}>
        <.link navigate={~p"/worlds/#{@world.id}"} class="text-link">← {@world.name}</.link>
        <header class="my-6 flex flex-wrap items-center justify-between gap-4">
          <div>
            <p class="eyebrow">Published world · linked records</p><h1 class="display-title">
              Atlas
            </h1>
          </div>
          <div class="flex flex-wrap gap-2">
            <button :if={@can_build} id="atlas-preview" class="secondary-button" phx-click="preview">{if @preview,
              do: "Return to GM view",
              else: "Preview public view"}</button>
            <button :if={@can_edit} id="atlas-new" class="primary-button" phx-click="new">Add a record</button>
          </div>
        </header>
        <p :if={@preview} id="atlas-preview-notice" class="notice mb-4">
          Public preview only; no private persona, campaign records or hidden links.
        </p>
        <p :if={@window_open} id="atlas-window" class="notice mb-4">
          An advancement window is open. Edits save as Drafts; they do not change the current world or any Experience.
        </p>
        <.form
          for={@search_form}
          id="atlas-search"
          phx-submit="search"
          class="flex flex-wrap items-end gap-3"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@search_form[:query]}
              label="Find a person, place or subject"
              maxlength="100"
            />
          </div>
          <button class="secondary-button mb-2" phx-disable-with="Searching…">Search</button>
        </.form>
        <p id="atlas-count" class="helper-text mb-5">
          {@count} visible results{if @more, do: " · first 50 shown; narrow your search"}
        </p>
        <div class="grid items-start gap-6 lg:grid-cols-2">
          <section>
            <div id="atlas-records" phx-update="stream" class="space-y-3">
              <p id="atlas-empty" class="empty-state hidden only:block">
                No matching records. Try a name or a tag.
              </p>
              <article
                :for={{id, record} <- @streams.records}
                id={id}
                data-kind={record.kind}
                class="workspace-card"
              >
                <span class="status-label">{String.replace(record.kind, "_", " ")}{if record.archived,
                  do: " · archived"}</span>
                <h2 class="mt-2 font-semibold">
                  <button class="text-link text-left" phx-click="show" phx-value-ref={record.id}>{record.name}</button>
                </h2>
                <p class="mt-2 break-words text-sm text-stone-600">
                  {String.slice(record.body, 0, 180)}
                </p>
              </article>
            </div>
            <button
              :if={@can_edit}
              id="atlas-archives"
              class="text-link mt-5 text-sm"
              phx-click="archives"
            >{if @archived, do: "Hide archived records", else: "Include archived records"}</button>
          </section>
          <div class="space-y-5">
            <section :if={@selected && !@editor} id="atlas-detail" class="workspace-panel">
              <h2 class="section-heading">{@selected.name}</h2>
              <p class="helper-text">
                {if @selected.editable,
                  do: "Authored reference · not an engine-established fact or prototype",
                  else: "Live world identity · fields come from its owning place"}
              </p>
              <p class="mt-4 whitespace-pre-wrap break-words">{@selected.body}</p>
              <.link
                :for={source <- @selected.source_ids}
                class="text-link mr-3"
                navigate={~p"/worlds/#{@world.id}/history?#{%{source: source}}"}
              >View accepted source</.link>
              <dl :if={@selected.fields != %{}} class="mt-4 text-sm">
                <div :for={{key, value} <- Enum.sort(@selected.fields)}>
                  <dt class="font-medium">{key}</dt><dd>{to_string(value)}</dd>
                </div>
              </dl>
              <div class="mt-4 flex flex-wrap gap-3">
                <.link
                  :if={@selected.zone_id}
                  id="atlas-owner"
                  class="text-link"
                  navigate={~p"/worlds/#{@world.id}/places/#{@selected.zone_id}"}
                >Open owning place</.link>
                <button
                  :if={@selected.editable && @can_edit}
                  id="atlas-edit"
                  class="secondary-button"
                  phx-click="edit"
                >Open editor</button>
                <button
                  :for={
                    ref <-
                      Enum.reject([@selected.parent, @selected.source, @selected.target], &is_nil/1)
                  }
                  class="text-link"
                  phx-click="show"
                  phx-value-ref={ref}
                >Follow {if ref == @selected.parent,
                  do: "parent",
                  else: if(ref == @selected.source, do: "source", else: "target")}</button>
              </div>
              <h3 class="mt-6 font-medium">Linked from</h3>
              <div id="atlas-links" phx-update="stream" class="mt-3 space-y-2">
                <p id="atlas-no-links" class="helper-text hidden only:block">No visible backlinks.</p>
                <div :for={{id, record} <- @streams.links} id={id}>
                  <button class="text-link" phx-click="show" phx-value-ref={record.id}>{record.name}</button>
                </div>
              </div>
            </section>
            <section :if={@editor && @can_edit} class="workspace-panel">
              <h2 class="section-heading">
                {if @editor.id, do: "Edit atlas record", else: "Add an atlas record"}
              </h2>
              <p class="helper-text mb-4">
                Link existing people, objects and institutions. Edit their live fields at their owning place. Described routes are notes; Connections controls actual travel.
              </p>
              <.form
                for={@record_form}
                id="atlas-form"
                phx-submit="save"
                phx-change="change"
                class="space-y-4"
              >
                <input type="hidden" name="editor_request" value={@editor.request} />
                <.input
                  :if={!@editor.id}
                  field={@record_form[:kind]}
                  type="select"
                  label="Record type"
                  options={Enum.map(AtlasRecord.kinds(), &{String.replace(&1, "_", " "), &1})}
                />
                <input
                  :if={@editor.id}
                  type="hidden"
                  name="record[kind]"
                  value={@record_form[:kind].value}
                />
                <.input field={@record_form[:name]} label="Name" required maxlength="128" />
                <.input
                  field={@record_form[:body]}
                  type="textarea"
                  label="Description or authored claim"
                  maxlength="10000"
                  rows="4"
                />
                <.input
                  field={@record_form[:visibility]}
                  type="select"
                  label="Who can read this?"
                  options={[{"GM only", "gm"}, {"World members", "public"}, {"One campaign", "party"}]}
                />
                <.input
                  :if={@record_form[:visibility].value == "party"}
                  field={@record_form[:campaign_id]}
                  type="select"
                  label="Campaign"
                  prompt="Choose a campaign you manage"
                  options={@campaigns}
                />
                <.input
                  :if={@record_form[:kind].value in ~w(region location)}
                  field={@record_form[:parent]}
                  type="select"
                  label="Within"
                  prompt="No parent"
                  options={@places}
                />
                <div :if={@record_form[:kind].value in ~w(route relationship)} class="space-y-3">
                  <p class="helper-text">
                    Choices follow the search results. Search first to narrow a large atlas.
                  </p>
                  <.input
                    field={@record_form[:source]}
                    type="select"
                    label="From"
                    prompt="Choose source"
                    options={if @record_form[:kind].value == "route", do: @places, else: @choices}
                  />
                  <.input
                    field={@record_form[:target]}
                    type="select"
                    label="To"
                    prompt="Choose target"
                    options={if @record_form[:kind].value == "route", do: @places, else: @choices}
                  />
                  <.input
                    :if={@record_form[:kind].value == "relationship"}
                    field={@record_form[:relation]}
                    type="select"
                    label="Connection"
                    options={AtlasRecord.relations()}
                  />
                </div>
                <div :if={@record_form[:kind].value == "route"} class="space-y-3">
                  <.input
                    field={@record_form[:condition]}
                    type="select"
                    label="Described condition"
                    options={~w(open damaged closed)}
                  />
                  <.input
                    field={@record_form[:capacity]}
                    type="number"
                    label="Described capacity (record only)"
                    min="1"
                    max="1000"
                    required
                  />
                </div>
                <.input
                  :if={@record_form[:kind].value == "resource_site"}
                  field={@record_form[:resource]}
                  label="Resource description (not stock)"
                  required
                  maxlength="128"
                />
                <details class="rounded-lg border border-stone-200 p-3">
                  <summary class="cursor-pointer text-sm font-medium">Tags & archive</summary>
                  <div class="mt-3 space-y-3">
                    <.input field={@record_form[:tags]} label="Tags, separated by commas" />
                    <.input
                      field={@record_form[:archived]}
                      type="checkbox"
                      label="Archive (retain identity and history)"
                    />
                  </div>
                </details>
                <details
                  :if={@record_form[:kind].value not in ~w(route resource_site)}
                  id="atlas-annotations"
                  class="rounded-lg border border-stone-200 p-3"
                >
                  <summary class="cursor-pointer text-sm font-medium">Custom annotations</summary>
                  <p class="helper-text my-3">
                    Up to eight descriptive fields. These never grant items, abilities or facts. Clear a name to remove it.
                  </p>
                  <div :for={index <- 0..7} class="grid gap-2 sm:grid-cols-3">
                    <.input
                      id={"annotation-key-#{index}"}
                      name={"record[annotations][#{index}][key]"}
                      value={annotation(@record_form, index, "key")}
                      label={"Field #{index + 1}"}
                      maxlength="120"
                    />
                    <.input
                      id={"annotation-type-#{index}"}
                      name={"record[annotations][#{index}][type]"}
                      value={annotation(@record_form, index, "type")}
                      type="select"
                      label="Type"
                      options={~w(text integer boolean)}
                    />
                    <.input
                      id={"annotation-value-#{index}"}
                      name={"record[annotations][#{index}][value]"}
                      value={annotation(@record_form, index, "value")}
                      label="Value (true/false for boolean)"
                      maxlength="512"
                    />
                  </div>
                </details>
                <div class="flex flex-wrap gap-3">
                  <button id="atlas-save" class="primary-button" phx-disable-with="Saving…">{if @window_open,
                    do: "Save draft",
                    else: "Save record"}</button><button
                    type="button"
                    class="secondary-button"
                    phx-click="cancel"
                  >Cancel</button>
                </div>
              </.form>
            </section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
