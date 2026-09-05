defmodule GenesisWeb.ReviewLive do
  use GenesisWeb, :live_view
  alias Genesis.Engine.Runtime
  alias Genesis.Workspace
  alias Genesis.WorldStandings

  @impl true
  def mount(%{"world_id" => world, "experience_id" => exp}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)

    {:ok,
     socket
     |> assign(
       world_id: world,
       experience_id: exp,
       review: nil,
       pending: nil,
       seal_request: Ecto.UUID.generate()
     )
     |> load()}
  end

  @impl true
  def handle_event("seal", %{"revision" => revision}, %{assigns: %{review: review}} = socket)
      when not is_nil(review) and is_binary(revision) do
    # The captured revision is never silently refreshed to make a stale confirmation succeed.
    with true <- review.eligible,
         {revision, ""} <- Integer.parse(revision),
         {:ok, _} <-
           command(
             socket,
             {:status, socket.assigns.experience_id, :ready, revision,
              socket.assigns.seal_request}
           ) do
      {:noreply,
       socket
       |> load()
       |> put_flash(
         :info,
         "All visited places are sealed. Claims remain held until publication."
       )}
    else
      {:error, reason} -> failure(socket, reason)
      _ -> failure(socket, :unavailable)
    end
  end

  def handle_event("preview", _params, socket) do
    case command(socket, {:preview_incorporation, socket.assigns.experience_id}) do
      {:ok, preview} ->
        {:noreply, assign(socket, pending: %{preview: preview, request: Ecto.UUID.generate()})}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  def handle_event("publish", _params, %{assigns: %{pending: pending}} = socket)
      when not is_nil(pending) do
    case command(socket, {:incorporate, pending.preview.id, pending.request}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(pending: nil)
         |> load()
         |> put_flash(
           :info,
           "All reviewed places were published together. Shared fictional time is unchanged."
         )}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, pending: nil)}
  def handle_event(_event, _params, socket), do: failure(socket, :unavailable)

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world_id: world}} = socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp command(socket, command) do
    Runtime.call(socket.assigns.current_scope, socket.assigns.world_id, command)
  catch
    :exit, _reason -> {:error, :publication_interrupted}
  end

  defp load(socket) do
    case Workspace.experience_review(
           socket.assigns.current_scope,
           socket.assigns.world_id,
           socket.assigns.experience_id
         ) do
      {:ok, review} ->
        {:ok, standings} =
          WorldStandings.view(
            socket.assigns.current_scope,
            socket.assigns.world_id,
            socket.assigns.experience_id
          )

        socket
        |> assign(review: Map.delete(review, :places))
        |> stream(:places, review.places, reset: true)
        |> stream(:standings, standings, reset: true)

      {:error, reason} when reason in [:publication_busy, :transfer_busy] ->
        put_flash(socket, :info, "The saved state is being installed. Please retry shortly.")

      _ ->
        socket
        |> assign(review: nil, pending: nil)
        |> stream(:places, [], reset: true)
        |> put_flash(:error, "Review is unavailable or your GM permission changed.")
    end
  end

  defp failure(socket, reason) do
    socket =
      if reason in [:publication_busy, :publication_interrupted],
        do: socket,
        else: assign(socket, pending: nil)

    {:noreply, put_flash(socket, :error, message(reason))}
  end

  defp message(:publication_interrupted),
    do:
      "The reply was interrupted. Retry this exact confirmation to recover its result; do not start another publication."

  defp message(:publication_busy),
    do: "Publication is installing the saved state. Wait, then retry this confirmation."

  defp message(:sealed_footprint_changed),
    do:
      "The saved state no longer matches its sealed manifest. Nothing was published; the steward must investigate."

  defp message(:unauthorized),
    do: "Publication requires current world stewardship and campaign GM access."

  defp message(_),
    do:
      "This review cannot be applied. Reload and review the saved state; no confirmation is silently rebased."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="mx-auto max-w-5xl px-4 py-10 sm:px-6">
        <.link class="text-link" navigate={~p"/worlds/#{@world_id}/experiences/#{@experience_id}"}>← Back to Experience</.link>
        <section :if={@review} class="mt-6 space-y-6">
          <header>
            <p class="eyebrow">Completion review · {@review.experience.status}</p>
            <h1 id="review-title" class="display-title">{@review.experience.name}</h1>
          </header>
          <aside id="review-boundary" class="notice">
            Review every visited place below. This batch supports one Experience, up to eight places, with no elapsed fictional time. Time reconciliation and multi-Experience review come later. Sealing stops play and keeps claims held; it does not publish anything and cannot currently be undone.
          </aside>
          <p :if={!@review.eligible} id="review-ineligible" class="notice">
            This window needs time or multi-Experience reconciliation. Its outcomes remain saved locally; publication is unavailable here.
          </p>
          <section class="workspace-panel">
            <h2 class="section-heading">World-level changes</h2>
            <p class="helper-text">
              These sourced institution standings are sealed and published with the visited places. Local memberships and holdings retain their existing owners.
            </p>
            <div id="review-standings" phx-update="stream" class="mt-3 space-y-3">
              <p id="review-no-standings" class="hidden only:block helper-text">
                No global standing changes in this Experience.
              </p>
              <div :for={{id, standing} <- @streams.standings} id={id}>
                <p>
                  {standing.actor_id} · standing {standing.standing} · relief supported: {to_string(
                    standing.relief_supported
                  )}
                </p>
              </div>
            </div>
            <.link
              id="review-history"
              class="text-link mt-3 inline-block"
              navigate={~p"/worlds/#{@world_id}/history?#{%{experience_id: @experience_id}}"}
            >Inspect accepted sources</.link>
          </section>
          <div id="review-places" phx-update="stream" class="space-y-4">
            <article :for={{id, place} <- @streams.places} id={id} class="workspace-panel">
              <h2 class="section-heading">{place.name || place.zone_id}</h2>
              <p class="helper-text">
                Elapsed: {place.elapsed}s · {length(place.actors)} people · {length(place.items)} item records
              </p>
              <.link
                class="text-link text-sm"
                navigate={~p"/worlds/#{@world_id}/places/#{place.zone_id}"}
              >Inspect published place</.link>
              <p :if={place.changes == []} class="helper-text mt-4">
                No visible record changes from this place's starting checkpoint.
              </p>
              <div
                :for={change <- place.changes}
                id={"#{id}-#{change.id}"}
                class="mt-4 border-t border-stone-200 pt-4"
              >
                <h3 class="font-semibold">{change.label}</h3>
                <dl class="mt-2 grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <dt class="eyebrow">Starting checkpoint</dt><dd class="break-words">
                      {change.published}
                    </dd>
                  </div>
                  <div>
                    <dt class="eyebrow">Saved outcome</dt><dd class="break-words">
                      {change.working}
                    </dd>
                  </div>
                </dl>
              </div>
            </article>
          </div>
          <div class="flex flex-wrap gap-3">
            <button
              :if={@review.eligible && @review.experience.status in ["active", "paused"]}
              id="seal-review"
              class="secondary-button"
              phx-click="seal"
              phx-value-revision={@review.origin_revision}
              phx-disable-with="Sealing…"
              data-confirm="Seal all visited places? This stops play and cannot currently be undone."
            >Seal all outcomes</button>
            <button
              :if={
                @review.eligible && @review.experience.status == "ready" && @review.can_publish &&
                  is_nil(@pending)
              }
              id="preview-publication"
              class="primary-button"
              phx-click="preview"
              phx-disable-with="Checking…"
            >Review publication</button>
          </div>
          <p
            :if={@review.experience.status == "ready" && !@review.can_publish}
            id="steward-required"
            class="notice"
          >
            The outcomes are sealed. A world steward who can manage this campaign must approve publication.
          </p>
          <p
            :if={@review.experience.status == "incorporated"}
            id="publication-complete"
            class="notice"
          >
            Published together. Claims are released; these saved outcomes remain available for inspection.
          </p>
          <section :if={@pending} id="publication-preview" class="workspace-panel space-y-4">
            <h2 class="section-heading">Publish this reviewed footprint?</h2>
            <p>
              {@pending.preview.source_events} source-linked events across {length(
                @pending.preview.zone_ids
              )} places. Shared fictional time stays unchanged. Nothing publishes until you confirm.
            </p>
            <button
              id="confirm-publication"
              class="primary-button"
              phx-click="publish"
              phx-disable-with="Publishing…"
            >Confirm publication</button>
            <button id="cancel-publication" class="secondary-button" phx-click="cancel">Cancel preview</button>
          </section>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
