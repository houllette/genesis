defmodule GenesisWeb.TravelLive do
  use GenesisWeb, :live_view
  alias Genesis.Content
  alias Genesis.{Experiences, Travel, Workspace, WorldNetwork, Worlds}

  @impl true
  def mount(%{"world_id" => world, "experience_id" => exp}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)

    {:ok,
     socket
     |> assign(
       world_id: world,
       experience_id: exp,
       pending: nil,
       ready: false,
       travel_form: to_form(%{"actor" => "", "destination" => ""}, as: :travel)
     )
     |> load()}
  end

  @impl true
  def handle_event(
        "preview",
        %{"travel" => %{"actor" => actor, "destination" => destination} = attrs},
        socket
      ) do
    with {:ok, _} <- permitted(socket),
         {:ok, preview} <-
           Travel.preview(
             socket.assigns.current_scope,
             socket.assigns.world_id,
             socket.assigns.experience_id,
             actor,
             destination,
             exchange(attrs)
           ) do
      {:noreply, assign(socket, pending: %{preview: preview, request: Ecto.UUID.generate()})}
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("confirm", _params, %{assigns: %{pending: pending}} = socket)
      when not is_nil(pending) do
    with {:ok, _} <- permitted(socket),
         {:ok, _} <-
           move(
             socket.assigns.current_scope,
             socket.assigns.world_id,
             socket.assigns.experience_id,
             pending.preview.actor_id,
             pending.preview.token,
             pending.request
           ) do
      {:noreply,
       socket
       |> assign(:pending, nil)
       |> load()
       |> put_flash(
         :info,
         "Travel saved once in this Experience. Published history and fictional time are unchanged."
       )}
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :pending, nil)}
  def handle_event(_event, _params, socket), do: failure(socket, :unavailable)

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world_id: world}} = socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp permitted(socket),
    do:
      Experiences.get(
        socket.assigns.current_scope,
        socket.assigns.world_id,
        socket.assigns.experience_id,
        ["gm"]
      )

  defp exchange(%{"exchange_type" => type, "quantity" => quantity} = attrs)
       when type in ~w(buy sell barter offer) and is_binary(quantity) do
    quantity =
      case Integer.parse(quantity) do
        {n, ""} -> n
        _ -> 0
      end

    %{"type" => type, "target_id" => attrs["target_id"], "quantity" => quantity}
  end

  defp exchange(%{"exchange_type" => type}) when type not in [nil, ""], do: %{"invalid" => true}
  defp exchange(_attrs), do: nil

  # A lost OTP reply is a genuine transport boundary, not proof of rollback.
  defp move(scope, world, exp, actor, token, request) do
    Travel.move(scope, world, exp, actor, token, request)
  catch
    :exit, _reason -> {:error, :transfer_interrupted}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    world = socket.assigns.world_id

    with {:ok, exp} <- permitted(socket),
         {:ok, record} <- Worlds.get_world(scope, world),
         {:ok, scenes} <- Workspace.experience_footprint(scope, world, exp.id),
         {:ok, network} <- WorldNetwork.view(scope, world) do
      actors =
        Workspace.bindings(scope, world, exp.campaign_id)
        |> Enum.filter(&(&1.user_id == scope.user.id and &1.actor_id in exp.participants))
        |> Enum.map(&{&1.actor_id, &1.actor_id})

      names = Map.new(network.zones, &{&1.id, &1.name})

      recipients = Enum.flat_map(network.zones, &recipients(scope, world, &1))

      places =
        Enum.map(scenes, fn scene ->
          %{
            id: scene.zone_id,
            name: scene.name,
            actors: Enum.map_join(scene.actors, ", ", & &1.name),
            holdings: Enum.map_join(scene.items, ", ", &"#{&1.quantity} × #{&1.name}")
          }
        end)

      socket
      |> assign(
        ready: true,
        world: record,
        experience: exp,
        actor_options: actors,
        destination_options: Enum.map(network.zones, &{&1.name, &1.id}),
        place_names: names,
        recipient_options: recipients
      )
      |> stream(:places, places, reset: true)
    else
      {:error, :transfer_busy} ->
        socket

      _ ->
        socket
        |> assign(ready: false, pending: nil)
        |> stream(:places, [], reset: true)
        |> put_flash(:error, "Travel is unavailable or your permission changed.")
        |> push_navigate(to: ~p"/worlds")
    end
  end

  defp recipients(scope, world, zone) do
    case Content.view(scope, world, zone.id) do
      {:ok, view} ->
        for actor <- view.actors,
            actor.kind == :npc,
            do: {"#{zone.name} · #{actor.name}", actor.id}

      _ ->
        []
    end
  end

  defp failure(socket, reason) do
    # Unknown outcomes keep the exact token and request ID for recovery. Other
    # errors require an explicit new preview; never silently rebase confirmation.
    socket =
      if reason in [:transfer_busy, :transfer_interrupted, :recovery_required],
        do: socket,
        else: assign(socket, :pending, nil)

    {:noreply, put_flash(socket, :error, message(reason))}
  end

  defp message(:cross_zone_dependency),
    do:
      "A market operator or institution representative must remain at their post. Nothing moved."

  defp message(:companion_unavailable),
    do:
      "A follower cannot travel or has no active agreement. Resolve or dismiss that commitment first. Nothing moved."

  defp message(:claimed), do: "Another Experience already holds this destination. Nothing moved."

  defp message(:stale_transfer),
    do: "The places changed after preview. Review a fresh preview; nothing moved."

  defp message(reason) when reason in [:transfer_busy, :transfer_interrupted, :recovery_required],
    do:
      "Travel is busy or was interrupted. The outcome may already be saved. Retry this same confirmation to recover it."

  defp message(:time_reconciliation_unavailable),
    do:
      "Travel currently requires zero elapsed fictional time in every visited place. Time reconciliation comes later."

  defp message(_reason),
    do:
      "Travel is unavailable. Check your bound participant, the directed connection and Experience status."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={@ready} class="space-y-8">
        <.link class="text-link" navigate={~p"/worlds/#{@world.id}/experiences/#{@experience.id}"}>{@experience.name}</.link>
        <header>
          <p class="eyebrow">Working Experience</p><h1 class="display-title">
            Travel & visited places
          </h1>
        </header>
        <aside id="travel-boundary" class="notice">
          Your bound participant and every eligible follower move together with their inventories. A trip consumes one step of each companion's agreement. Relationships remain saved after separation. Fictional time remains unchanged in this phase.
          Adding a visited place keeps it claimed by this Experience, even after returning or interrupted travel. Review all visited places together before publishing; the current review supports one zero-duration Experience per window.
        </aside>
        <.form
          :if={@experience.status == "active"}
          for={@travel_form}
          id="travel-form"
          phx-submit="preview"
          class="space-y-4"
        >
          <.input
            field={@travel_form[:actor]}
            type="select"
            label="Your bound participant"
            options={@actor_options}
            prompt="Choose a character"
            required
          />
          <.input
            field={@travel_form[:destination]}
            type="select"
            label="Destination"
            options={@destination_options}
            prompt="Choose a connected place"
            required
          />
          <button class="secondary-button" id="preview-travel">Review travel</button>
          <details id="delivery-options" class="rounded-lg border p-3">
            <summary class="cursor-pointer">Deliver or exchange supplies on arrival</summary>
            <p class="helper-text my-3">
              Travel and one local exchange commit together. A failed exchange leaves everyone and all goods in place.
            </p>
            <.input
              field={@travel_form[:exchange_type]}
              type="select"
              label="Arrival action"
              options={[
                {"Travel only", ""},
                {"Offer supplies", "offer"},
                {"Sell grain", "sell"},
                {"Buy grain", "buy"},
                {"Barter rations", "barter"}
              ]}
            />
            <.input
              field={@travel_form[:target_id]}
              type="select"
              label="Destination recipient"
              options={@recipient_options}
              prompt="Choose a recipient at the destination"
            />
            <.input field={@travel_form[:quantity]} type="number" label="Units" min="1" max="100" />
          </details>
        </.form>
        <p :if={@experience.status != "active"} id="travel-paused" class="notice">
          Resume this Experience before traveling.
        </p>
        <section :if={@pending} id="travel-preview" class="surface-card space-y-4">
          <h2 class="section-heading">
            {@pending.preview.actor_id}: {@place_names[@pending.preview.from] || @pending.preview.from} → {@place_names[
              @pending.preview.to
            ] || @pending.preview.to}
          </h2>
          <p>
            Preview reserves nothing. Confirmation rechecks both places and acquires the destination's durable claims.
          </p>
          <p id="travel-party-size">Party size: {@pending.preview.party_size}</p>
          <p :if={@pending.preview.exchange_summary} id="delivery-summary">
            {@pending.preview.exchange_summary}
          </p>
          <button
            id="confirm-travel"
            class="primary-button"
            phx-click="confirm"
            phx-disable-with="Saving…"
          >Confirm travel</button>
          <button id="cancel-travel" class="secondary-button" phx-click="cancel">Cancel preview</button>
        </section>
        <section>
          <h2 class="section-heading mb-4">Visited places</h2>
          <div id="travel-places" phx-update="stream" class="grid gap-4 md:grid-cols-2">
            <article :for={{id, place} <- @streams.places} id={id} class="surface-card">
              <h3>{place.name}</h3>
              <p class="mt-2 text-sm">
                Present: {if place.actors == "", do: "Nobody", else: place.actors}
              </p>
              <p class="mt-2 text-sm">
                Items: {if place.holdings == "", do: "None", else: place.holdings}
              </p>
              <.link
                class="text-link"
                navigate={
                  ~p"/worlds/#{@world.id}/experiences/#{@experience.id}/resources?zone=#{place.id}"
                }
              >Inspect working resources</.link>
            </article>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
