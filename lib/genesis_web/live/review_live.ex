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
       completion_form: nil,
       time_form: to_form(%{"unit" => "minute", "value" => "0", "reason" => ""}, as: :duration),
       time_request: Ecto.UUID.generate(),
       seal_request: Ecto.UUID.generate()
     )
     |> load()}
  end

  @impl true
  def handle_event("finish", %{"completion" => attrs, "revision" => revision}, socket)
      when is_map(attrs) do
    with {revision, ""} <- parse_integer(revision),
         {total, ""} <- parse_integer(Map.get(attrs, "elapsed_seconds", "")),
         attrs = Map.put(attrs, "elapsed_seconds", total),
         attrs =
           Map.update(
             attrs,
             "review_required",
             false,
             &Map.get(%{"true" => true, "false" => false}, &1)
           ),
         {:ok, _} <-
           command(
             socket,
             {:status, socket.assigns.experience_id, {:finish, attrs}, revision,
              socket.assigns.seal_request}
           ) do
      {:noreply,
       socket
       |> load()
       |> put_flash(
         :info,
         "Completion saved. Actual costs remain recorded; the world has not advanced."
       )}
    else
      {:error, reason} -> failure(socket, reason)
      _ -> failure(socket, :invalid_completion)
    end
  end

  def handle_event("elapse", %{"duration" => attrs, "revision" => revision}, socket)
      when is_map(attrs) do
    with {revision, ""} <- parse_integer(revision),
         {value, ""} <- parse_integer(Map.get(attrs, "value", "")),
         attrs = Map.put(attrs, "value", value),
         {:ok, _} <-
           command(
             socket,
             {:status, socket.assigns.experience_id, {:elapse, attrs}, revision,
              socket.assigns.time_request}
           ) do
      {:noreply,
       socket
       |> assign(time_request: Ecto.UUID.generate(), completion_form: nil)
       |> load()
       |> put_flash(:info, "Scene time recorded once. Published time is unchanged.")}
    else
      {:error, reason} -> failure(socket, reason)
      _ -> failure(socket, :invalid_local_time)
    end
  end

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
        |> assign(review: Map.drop(review, [:places, :time_entries]))
        |> completion_form(review)
        |> stream(:places, review.places, reset: true)
        |> stream(:time_entries, review.time_entries, reset: true)
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

  defp completion_form(%{assigns: %{completion_form: nil}} = socket, review),
    do:
      assign(socket,
        completion_form:
          to_form(
            %{
              "elapsed_seconds" => to_string(review.elapsed_seconds),
              "outcome" => "completed",
              "reason" => "",
              "basis" => review.basis
            },
            as: :completion
          )
      )

  defp completion_form(socket, _review), do: socket

  defp parse_integer(value) when is_binary(value), do: Integer.parse(value)
  defp parse_integer(_value), do: :error

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
    do:
      "This action requires current campaign GM access; publication additionally requires world stewardship."

  defp message(:duration_before_recorded_time),
    do: "The total cannot be shorter than the time already recorded in play."

  defp message(:multi_zone_time_unavailable),
    do:
      "Scene time across several visited places requires the next time-coordination slice. No time was added."

  defp message(:unsupported_calendar),
    do:
      "Months and years need a supported, pinned calendar and epoch. Use explicit seconds, minutes, hours or days for an ordinal world."

  defp message(:request_conflict),
    do:
      "This request already has a different saved result. Reload to begin a new reviewed request."

  defp message(:stale_completion),
    do: "The reviewed outcomes changed. Reload and review the new footprint before finishing."

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
            Finish an adventure with its actual outcome and total fictional duration. Completion stops play and keeps claims held; it does not publish anything and cannot currently be undone. Publication still supports only one zero-duration Experience until ordered time reconciliation is implemented.
          </aside>
          <p :if={!@review.eligible} id="review-ineligible" class="notice">
            This window needs time or multi-Experience reconciliation. Its outcomes remain saved locally; publication is unavailable here.
          </p>
          <section id="experience-time-review" class="workspace-panel space-y-4">
            <h2 class="section-heading">Fictional time and completion</h2>
            <p id="recorded-elapsed">Recorded in play: {@review.elapsed_seconds} seconds.</p>
            <p class="helper-text">
              The completion total includes time already paid by actions. Any difference is an end-of-adventure duration for later reconciliation, not another action cost or permission to skip due consequences.
            </p>
            <div id="time-ledger" phx-update="stream" class="space-y-2">
              <p id="time-ledger-empty" class="hidden only:block helper-text">
                No explicit time contributions visible to you. Older events retain their original time data.
              </p>
              <div :for={{id, entry} <- @streams.time_entries} id={id} class="text-sm">
                <span>{entry.type}: +{entry.seconds}s ({entry.from} → {entry.to})</span>
                <span :if={entry.reason}> · {entry.reason}</span>
                <.link
                  class="text-link ml-2"
                  navigate={
                    ~p"/worlds/#{@world_id}/history?#{%{experience_id: @experience_id, event: entry.id}}"
                  }
                >Source</.link>
              </div>
            </div>
            <details :if={@review.experience.status == "active"} id="scene-time-controls">
              <summary class="cursor-pointer text-sm font-semibold">
                Record additional scene time
              </summary>
              <.form for={@time_form} id="scene-time-form" phx-submit="elapse" class="mt-4 space-y-3">
                <input type="hidden" name="revision" value={@review.origin_revision} />
                <.input
                  field={@time_form[:value]}
                  type="number"
                  min="0"
                  max="31622400"
                  label="Additional time"
                  required
                />
                <.input
                  field={@time_form[:unit]}
                  type="select"
                  label="Unit"
                  options={~w(second minute hour day month year)}
                />
                <.input
                  field={@time_form[:reason]}
                  label="What happened during this time?"
                  required
                  maxlength="2048"
                />
                <button id="record-scene-time" class="secondary-button" phx-disable-with="Saving…">Record scene time</button>
              </.form>
            </details>
            <.form
              :if={@review.experience.status in ["active", "paused"]}
              for={@completion_form}
              id="completion-form"
              phx-submit="finish"
              class="space-y-3"
            >
              <.input field={@completion_form[:basis]} type="hidden" />
              <input type="hidden" name="revision" value={@review.origin_revision} />
              <.input
                field={@completion_form[:elapsed_seconds]}
                type="number"
                min={@review.elapsed_seconds}
                max="31622400"
                label="Total fictional duration (seconds, including recorded play)"
                required
              />
              <.input
                field={@completion_form[:outcome]}
                type="select"
                label="Actual outcome"
                options={~w(completed failed abandoned)}
              />
              <.input
                field={@completion_form[:reason]}
                type="textarea"
                label="Completion and duration explanation"
                required
                maxlength="2048"
              />
              <.input
                field={@completion_form[:review_required]}
                type="checkbox"
                label="Keep this sealed outcome in needs review"
              />
              <button
                id="finish-experience"
                class="primary-button"
                phx-disable-with="Finishing…"
                data-confirm="Finish and seal these outcomes? Play stops and claims remain held."
              >Finish Experience</button>
            </.form>
            <div :if={@review.experience.completion["format"] == 3} id="completion-summary">
              <p>Outcome: {@review.experience.completion["declaration"]["outcome"]}</p>
              <p>
                Declared total: {@review.experience.completion["elapsed_seconds"]} seconds. Recorded play: {@review.experience.completion[
                  "recorded_elapsed_seconds"
                ]} seconds.
              </p>
              <p>Completion ID: {@review.experience.completion["completion_id"]}</p>
            </div>
          </section>
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
