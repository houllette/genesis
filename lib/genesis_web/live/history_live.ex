defmodule GenesisWeb.HistoryLive do
  use GenesisWeb, :live_view
  alias Genesis.Experiences
  alias Genesis.Persistence.Access
  alias Genesis.Persistence.History
  alias Genesis.Worlds
  alias Genesis.WorldStandings

  @impl true
  def mount(%{"world_id" => world}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)

    {:ok,
     assign(socket,
       world_id: world,
       params: %{},
       selected: nil,
       ready: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, socket |> assign(:params, params) |> load()}

  @impl true
  def handle_event("report", %{"id" => id}, socket) do
    request = Worlds.named_id(["recognize-contribution", id])

    result =
      WorldStandings.report(
        socket.assigns.current_scope,
        socket.assigns.world_id,
        socket.assigns.params["experience_id"],
        id,
        request
      )

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :info,
           "Contribution recognized once in this Experience. Shared standing changes only after publication."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :error,
           "Report unavailable. It requires an accepted contribution, a registered institution and an active Experience."
         )}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, load(socket)}
  @impl true
  def handle_info({:world_changed, world, _}, %{assigns: %{world_id: world}} = socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    %{current_scope: scope, world_id: world, params: params} = socket.assigns
    opts = if params["experience_id"], do: [experience_id: params["experience_id"]], else: []
    opts = Keyword.put(opts, :after, cursor(params["after"]))

    with {:ok, record} <- Worlds.get_world(scope, world),
         {:ok, page} <- History.page(scope, world, opts),
         {:ok, standings} <- WorldStandings.view(scope, world, params["experience_id"]) do
      selected = selected(scope, world, params, opts)

      can_report =
        match?(
          {:ok, %{status: "active"}},
          Experiences.get(scope, world, params["experience_id"], ["gm"])
        )

      socket
      |> assign(
        ready: true,
        world: record,
        selected: selected,
        next_cursor: page.next_cursor,
        can_report: can_report,
        can_build: Access.world(scope, world, ["steward", "builder"]) == :ok
      )
      |> stream(:events, page.events, reset: true)
      |> stream(:standings, standings, reset: true)
      |> stream(:sources, if(selected, do: selected.sources, else: []), reset: true)
    else
      _ ->
        socket
        |> assign(ready: false, selected: nil)
        |> put_flash(:error, "History unavailable or your access changed.")
    end
  end

  defp selected(scope, world, %{"event" => id}, _opts), do: result(History.get(scope, world, id))

  defp selected(scope, world, %{"source" => id}, opts),
    do: result(History.source(scope, world, id, opts))

  defp selected(_scope, _world, _params, _opts), do: nil
  defp result({:ok, value}), do: value
  defp result(_), do: nil

  defp cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end

  defp cursor(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={@ready} class="space-y-6">
        <.link navigate={~p"/worlds/#{@world_id}"} class="text-link">← {@world.name}</.link>
        <header>
          <p class="eyebrow">
            {if @params["experience_id"], do: "Experience outcomes", else: "Published history"}
          </p><h1 class="display-title">History & recognition</h1>
        </header>
        <p class="helper-text">
          Accepted events are records, not instructions to run again. A source link grants no access to another campaign's secrets.
        </p>
        <p
          :if={(@params["event"] || @params["source"]) && !@selected}
          id="source-unavailable"
          class="notice"
        >
          No accepted event is available for this reference. Authored baseline references may have no action event; hidden sources stay hidden.
        </p>
        <section :if={@selected} id="history-detail" class="workspace-panel">
          <h2 class="section-heading">{@selected.type}</h2>
          <p id="history-outcome">{Map.get(@selected.result, "outcome", "Accepted occurrence")}</p>
          <p class="helper-text">
            {@selected.scope_kind} · commit {@selected.cursor} · fictional coordinate {@selected.occurred_at}
          </p>
          <h3 class="mt-4 font-medium">Authorized source events</h3>
          <div id="history-sources" phx-update="stream">
            <p id="history-no-sources" class="hidden only:block helper-text">
              No accessible source events.
            </p>
            <div :for={{id, event} <- @streams.sources} id={id}>
              <.link
                class="text-link"
                patch={
                  ~p"/worlds/#{@world_id}/history?#{%{event: event.id, experience_id: @params["experience_id"]}}"
                }
              >{event.type} · {event.cursor}</.link>
            </div>
          </div>
        </section>
        <section>
          <h2 class="section-heading">Institution recognition</h2>
          <p class="helper-text mb-3">
            One institution's sourced standing and relief-supported flag. This does not grant membership, aid, remote inventory rights or universal reputation.
          </p>
          <div id="world-standings" phx-update="stream" class="space-y-3">
            <p id="no-standings" class="hidden only:block helper-text">
              No visible recognition in this scope.
            </p>
            <article :for={{id, standing} <- @streams.standings} id={id} class="workspace-card">
              <p>
                {standing.status} · {standing.actor_id}: standing {standing.standing} · relief supported: {to_string(
                  standing.relief_supported
                )}
              </p>
              <.link
                :for={source <- standing.source_ids}
                class="text-link mr-3"
                patch={
                  ~p"/worlds/#{@world_id}/history?#{%{source: source, experience_id: @params["experience_id"]}}"
                }
              >View contribution</.link>
            </article>
          </div>
        </section>
        <section>
          <h2 class="section-heading mb-3">Accepted timeline</h2>
          <div id="history-events" phx-update="stream" class="space-y-3">
            <p id="history-no-events" class="hidden only:block helper-text">
              No further authorized events.
            </p>
            <article :for={{id, event} <- @streams.events} id={id} class="workspace-card">
              <.link
                class="text-link"
                patch={
                  ~p"/worlds/#{@world_id}/history?#{%{event: event.id, experience_id: @params["experience_id"]}}"
                }
              >{event.type} · commit {event.cursor}</.link>
              <p>{Map.get(event.result, "outcome", "Recorded")}</p>
              <button
                :if={@can_report && event.type == "offer"}
                id={"recognize-#{event.id}"}
                class="secondary-button mt-3"
                phx-click="report"
                phx-value-id={event.id}
                phx-disable-with="Recording…"
              >Recognize contribution (+1 Working standing)</button>
            </article>
          </div>
          <.link
            id="history-next"
            class="text-link mt-4 inline-block"
            patch={
              ~p"/worlds/#{@world_id}/history?#{%{after: @next_cursor, experience_id: @params["experience_id"]}}"
            }
          >Continue after commit {@next_cursor}</.link>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
