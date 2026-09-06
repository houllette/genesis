defmodule GenesisWeb.TimeLive do
  use GenesisWeb, :live_view
  alias Genesis.Core.LocalTime
  alias Genesis.Engine.Runtime
  alias Genesis.TimeReview

  @impl true
  def mount(%{"world_id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> id)

    {:ok,
     socket
     |> assign(
       world_id: id,
       review: nil,
       pending: nil,
       decisions: %{},
       request: Ecto.UUID.generate(),
       plan_form: to_form(%{"reason" => "", "downtime_seconds" => "0"}, as: :plan),
       decision_form:
         to_form(%{"mode" => "include", "reason" => "", "elapsed_seconds" => ""}, as: :decision)
     )
     |> load()}
  end

  @impl true
  def handle_event("decision", %{"decision" => attrs}, socket) when is_map(attrs) do
    with id when is_binary(id) <- attrs["experience_id"],
         true <- Enum.any?(socket.assigns.experience_options, &(elem(&1, 1) == id)),
         {:ok, total} <- integer(attrs["elapsed_seconds"]),
         true <-
           attrs["mode"] in ["include", "exclude"] and
             LocalTime.reason?(attrs["reason"]) do
      decision = Map.take(attrs, ~w(mode reason)) |> Map.put("elapsed_seconds", total)

      {:noreply,
       socket |> assign(decisions: Map.put(socket.assigns.decisions, id, decision)) |> load()}
    else
      _ -> failure(socket, :invalid_time_decision)
    end
  end

  def handle_event("prepare", %{"plan" => attrs}, socket) when is_map(attrs) do
    with {:ok, downtime} <- integer(attrs["downtime_seconds"]),
         input = %{
           "decisions" => socket.assigns.decisions,
           "downtime_seconds" => downtime,
           "reason" => attrs["reason"]
         },
         {:ok, _} <- command(socket, {:prepare_time, input, socket.assigns.request}) do
      {:noreply, socket |> assign(request: Ecto.UUID.generate()) |> load()}
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event(
        "schedule",
        %{"schedule" => attrs, "zone" => zone, "revision" => revision, "request" => request},
        socket
      )
      when is_map(attrs) do
    with {:ok, revision} <- integer(revision),
         {:ok, result} <-
           Genesis.Schedules.create(
             socket.assigns.current_scope,
             socket.assigns.world_id,
             zone,
             revision,
             attrs,
             request
           ) do
      {:noreply,
       socket
       |> assign(request: Ecto.UUID.generate())
       |> load()
       |> put_flash(
         :info,
         "Schedule saved as #{result["status"]}. It runs only toward an explicit fictional target."
       )}
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("preview", _params, %{assigns: %{review: %{candidate: %{id: id}}}} = socket) do
    case command(socket, {:preview_time, id}) do
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
         |> assign(pending: nil, decisions: %{})
         |> load()
         |> put_flash(:info, "The reviewed window is published. The world advanced once.")}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  def handle_event(
        "cancel",
        %{"cancel" => %{"reason" => reason}},
        %{assigns: %{review: %{candidate: candidate}}} = socket
      )
      when not is_nil(candidate) do
    case command(socket, {:cancel_time, candidate.id, candidate.digest, reason}) do
      {:ok, _} -> {:noreply, socket |> assign(pending: nil, decisions: %{}) |> load()}
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event(_event, _params, socket), do: failure(socket, :invalid_preparation)

  @impl true
  def handle_info({:world_changed, id, _cursor}, %{assigns: %{world_id: id}} = socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp command(socket, command) do
    Runtime.call(socket.assigns.current_scope, socket.assigns.world_id, command)
  catch
    :exit, _ -> {:error, :publication_interrupted}
  end

  defp load(socket) do
    case TimeReview.view(socket.assigns.current_scope, socket.assigns.world_id) do
      {:ok, review} ->
        experiences =
          Enum.map(review.experiences, &Map.put(&1, :decision, socket.assigns.decisions[&1.id]))

        impacts = if review.candidate, do: review.candidate.places, else: []

        socket
        |> assign(
          review: Map.drop(review, [:experiences, :places]),
          experience_options: Enum.map(experiences, &{&1.name, &1.id})
        )
        |> stream(:experiences, experiences, reset: true)
        |> stream(:impacts, impacts, reset: true)
        |> stream(:schedule_places, review.places, reset: true)

      {:error, reason} when reason in [:publication_busy, :transfer_busy] ->
        put_flash(socket, :info, "The saved result is being installed. Refresh shortly.")

      _ ->
        socket
        |> assign(review: nil, pending: nil, decisions: %{})
        |> stream(:experiences, [], reset: true)
        |> stream(:impacts, [], reset: true)
        |> stream(:schedule_places, [], reset: true)
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 0..31_622_400 -> {:ok, n}
      _ -> {:error, :invalid_time_decision}
    end
  end

  defp integer(_), do: {:error, :invalid_time_decision}

  defp failure(socket, reason), do: {:noreply, put_flash(socket, :error, message(reason))}

  defp message(:unsealed_experience),
    do: "Finish each admitted adventure before preparing this window."

  defp message(:window_not_ready),
    do: "Review every adventure in this window. Each needs an include or exclude decision."

  defp message(:invalid_time_decision),
    do: "Supply a reason and a total duration that covers the recorded play."

  defp message(:invalid_schedule),
    do:
      "Check the future occurrence, action, local NPC and target. Recurrence must be positive or blank for one occurrence."

  defp message(:publication_interrupted),
    do: "The connection was interrupted. Retry the same confirmation to recover its saved result."

  defp message(_),
    do:
      "This plan is unavailable or has changed. Refresh and review it again; no confirmation is silently updated."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="workspace-shell space-y-6">
        <.link navigate={~p"/worlds/#{@world_id}"} class="text-link">← World workspace</.link>
        <p :if={is_nil(@review)} id="time-unavailable" class="notice">
          Window review requires current steward and GM access to every admitted adventure.
        </p>
        <section :if={@review} id="time-review" class="space-y-6">
          <header class="workspace-panel">
            <p class="eyebrow">World time · {@review.world.name}</p>
            <h1 class="page-title">Review the next chapter</h1>
            <p id="published-time">Published coordinate: {@review.world.fictional_time} seconds</p>
            <p>
              Gatherings and real-world waiting never move this clock. Parallel adventures use the latest end, not their summed durations.
            </p>
            <button id="refresh-time" class="secondary-button mt-3" phx-click="refresh">Refresh preparation</button>
          </header>
          <details id="schedule-tools" class="workspace-panel">
            <summary class="text-link">Dated routines and place conditions</summary>
            <p>
              Schedules use existing local rules and actual stock. Closed conditions stop production and travel; harsh conditions halve production capacity. While a window is open, edits remain drafts for a later world revision.
            </p>
            <div id="schedule-places" phx-update="stream" class="space-y-4">
              <section :for={{id, place} <- @streams.schedule_places} id={id}>
                <h3 class="section-heading">{place.name}</h3>
                <p :for={{_id, schedule} <- place.schedules}>
                  {schedule["name"]}: {schedule["action"]} · first at {schedule["first_at"]}s
                </p>
                <.form
                  :let={f}
                  for={
                    to_form(
                      %{
                        "quantity" => "1",
                        "every_value" => "",
                        "first_at" => to_string(@review.world.fictional_time + 86_400)
                      },
                      as: :schedule
                    )
                  }
                  id={"schedule-form-#{place.id}"}
                  phx-submit="schedule"
                >
                  <input type="hidden" name="zone" value={place.id} />
                  <input type="hidden" name="revision" value={place.revision} />
                  <input type="hidden" name="request" value={@request <> "-schedule-" <> place.id} />
                  <.input field={f[:name]} label="Schedule name" required />
                  <.input
                    field={f[:action]}
                    type="select"
                    label="Action"
                    options={[
                      {"Produce", "produce"},
                      {"Consume supplies and rest", "rest"},
                      {"Record supply loss", "disrupt"},
                      {"Fulfil an obligation", "offer"},
                      {"Institutional review", "adjudicate"},
                      {"Change place conditions", "condition"}
                    ]}
                  />
                  <.input
                    field={f[:actor_id]}
                    type="select"
                    label="Local NPC (unused for conditions)"
                    options={Enum.map(place.actors, &{&1.name, &1.id})}
                    prompt="Select an NPC"
                  />
                  <.input
                    field={f[:target_id]}
                    label="Target ID (recipe, recipient, or resting NPC; unused for conditions)"
                  />
                  <.input
                    field={f[:quantity]}
                    type="number"
                    min="1"
                    max="100"
                    label="Quantity, when applicable"
                  />
                  <.input
                    field={f[:condition]}
                    type="select"
                    label="Place condition, for a condition change"
                    options={~w(normal harsh closed)}
                  />
                  <.input
                    field={f[:first_at]}
                    type="number"
                    label="First occurrence (absolute fictional seconds)"
                    required
                  />
                  <.input
                    field={f[:every_value]}
                    type="number"
                    min="0"
                    label="Repeat every (blank or zero for one occurrence)"
                  />
                  <.input
                    field={f[:every_unit]}
                    type="select"
                    label="Recurrence unit"
                    options={~w(second minute hour day month year)}
                  />
                  <button
                    id={"save-schedule-#{place.id}"}
                    class="secondary-button"
                    phx-disable-with="Saving…"
                  >Save schedule</button>
                </.form>
              </section>
            </div>
          </details>
          <div id="window-experiences" phx-update="stream" class="space-y-3">
            <article :for={{id, exp} <- @streams.experiences} id={id} class="workspace-panel">
              <.link
                class="text-link"
                navigate={~p"/worlds/#{@world_id}/experiences/#{exp.id}/review"}
              >{exp.name}</.link>
              <p>
                {exp.status} · starts +{exp.start_offset}s · declared {exp.completion[
                  "elapsed_seconds"
                ] || 0}s
              </p>
              <p :if={exp.decision}>
                Decision: {exp.decision["mode"]}, {exp.decision["elapsed_seconds"]}s — {exp.decision[
                  "reason"
                ]}
              </p>
              <p :if={is_nil(exp.decision)}>No window decision saved yet.</p>
            </article>
          </div>
          <section :if={is_nil(@review.candidate)} class="workspace-panel space-y-4">
            <h2 class="section-heading">Review each outcome</h2>
            <p>
              Exclusion keeps original play records and quarantines its rewards. A corrected duration does not rewrite choices or refund paid time.
            </p>
            <.form
              :if={@experience_options != []}
              for={@decision_form}
              id="time-decision-form"
              phx-submit="decision"
            >
              <.input
                field={@decision_form[:experience_id]}
                type="select"
                label="Adventure"
                options={@experience_options}
              />
              <.input
                field={@decision_form[:mode]}
                type="select"
                label="Outcome decision"
                options={[{"Include", "include"}, {"Exclude from shared history", "exclude"}]}
              />
              <.input
                field={@decision_form[:elapsed_seconds]}
                type="number"
                min="0"
                max="31622400"
                label="Reviewed total, including recorded play (seconds)"
                required
              />
              <.input
                field={@decision_form[:reason]}
                type="textarea"
                label="Reason for this decision"
                maxlength="2048"
                required
              />
              <button id="save-time-decision" class="secondary-button">Save decision for this plan</button>
            </.form>
            <.form for={@plan_form} id="prepare-time-form" phx-submit="prepare">
              <.input
                field={@plan_form[:downtime_seconds]}
                type="number"
                min="0"
                max="31622400"
                label="Additional downtime after all included adventures (seconds)"
                required
              />
              <.input
                field={@plan_form[:reason]}
                type="textarea"
                label="Window review explanation"
                maxlength="2048"
                required
              />
              <p>No included adventures and zero downtime means no time advance.</p>
              <button id="prepare-time" class="primary-button" phx-disable-with="Preparing…">Seal window and prepare changes</button>
            </.form>
          </section>
          <section :if={@review.candidate} id="time-candidate" class="workspace-panel space-y-4">
            <h2 class="section-heading">Candidate: {@review.candidate.status}</h2>
            <p id="candidate-target">
              Proposed coordinate: {@review.candidate.target}s · {@review.candidate.processed} transitions checked
            </p>
            <p :if={@review.candidate.status == "preparing"}>
              Bounded background work is saved after each batch. Nothing is published yet.
            </p>
            <div :if={@review.candidate.status == "needs_review"} id="time-conflicts">
              <p>
                A dated consequence conflicts with recorded play. Cancel this candidate, then explicitly exclude the conflicting adventure or adjust an unrecorded duration. Original choices remain unchanged.
              </p>
              <p :for={conflict <- @review.candidate.conflicts}>
                Place {conflict["zone"]} at {conflict["at"]}s: {conflict["reason"]}
              </p>
            </div>
            <button
              :if={@review.candidate.status == "ready"}
              id="preview-time"
              class="primary-button"
              phx-click="preview"
            >Review publication confirmation</button>
            <.form
              for={to_form(%{"reason" => ""}, as: :cancel)}
              id="cancel-time-form"
              phx-submit="cancel"
            >
              <.input
                name="cancel[reason]"
                value=""
                label="Reason to cancel and revise this candidate"
                required
                maxlength="2048"
              />
              <button id="cancel-time" class="secondary-button">Cancel candidate and reopen review</button>
            </.form>
          </section>
          <div id="time-impacts" phx-update="stream" class="space-y-3">
            <article :for={{id, place} <- @streams.impacts} id={id} class="workspace-panel">
              <h3 class="section-heading">{place.name}</h3>
              <p>Conditions: {place.condition_before} → {place.condition_after}</p>
              <p :if={place.changes == []}>No people, resource or knowledge changes.</p>
              <p :for={change <- place.changes}>
                {change.label}: {change.published} → {change.working}
              </p>
            </article>
          </div>
          <section :if={@pending} id="time-confirmation" class="workspace-panel space-y-4">
            <p>
              Publish {@pending.preview.source_events} source-linked records across {length(
                @pending.preview.zone_ids
              )} places at coordinate {@pending.preview.target}s? This confirmation binds the reviewed candidate, target and world revision.
            </p>
            <button
              id="publish-time"
              phx-click="publish"
              class="primary-button"
              phx-disable-with="Publishing…"
              data-confirm="Publish this reviewed window and close its adventures?"
            >Publish reviewed window</button>
          </section>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
