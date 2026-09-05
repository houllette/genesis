defmodule GenesisWeb.SettlementLive do
  use GenesisWeb, :live_view
  import GenesisWeb.SettlementComponents
  alias Genesis.Content
  alias Genesis.Core.Audience
  alias Genesis.Core.Companions
  alias Genesis.Core.LocalAction
  alias Genesis.Engine.Runtime
  alias Genesis.Engine.Session
  alias Genesis.Experiences
  alias Genesis.Persistence.Access
  alias Genesis.Persistence.History
  alias Genesis.Workspace
  alias Genesis.Worlds

  @quantity_actions ~w(buy sell barter produce offer disrupt)

  @impl true
  def mount(%{"world_id" => world}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Genesis.PubSub, "world:" <> world)

    {:ok,
     assign(socket,
       attachment: nil,
       attachment_actor: nil,
       attachment_ref: nil,
       pending: nil,
       forms_ready: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, socket |> load(params) |> forms()}

  @impl true
  def handle_event(
        "save-settlement",
        %{
          "settlement" => attrs,
          "revision" => revision,
          "request_id" => request,
          "record_id" => id
        },
        socket
      ) do
    attrs =
      attrs
      |> Map.put("kind", "settlement")
      |> numbers(~w(price scarcity_threshold multiplier capacity quote_ttl))
      |> booleans(~w(accepting_members witnessing enabled))

    save(socket, integer(revision), blank_nil(id), attrs, request)
  end

  def handle_event(
        "save-stock",
        %{"stock" => attrs, "revision" => revision, "request_id" => request, "record_id" => id},
        socket
      ),
      do:
        save(
          socket,
          integer(revision),
          blank_nil(id),
          attrs
          |> Map.put("kind", "stock")
          |> Map.put("name", "Resource lot")
          |> numbers(["quantity"]),
          request
        )

  def handle_event("edit-stock", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.scene.items, &(&1.id == id and not is_nil(&1.commodity))) do
      nil ->
        failure(socket, :unavailable)

      item ->
        {:noreply,
         assign(socket,
           stock_id: id,
           stock_revision: socket.assigns.scene.revision,
           stock_request: Ecto.UUID.generate(),
           stock_form:
             to_form(
               %{
                 "owner_id" => elem(item.owner, 1),
                 "commodity" => item.commodity,
                 "quantity" => item.quantity,
                 "reason" => ""
               },
               as: :stock
             )
         )}
    end
  end

  def handle_event("reopen-editors", _params, socket),
    do:
      {:noreply, socket |> load(socket.assigns.params) |> assign(:forms_ready, false) |> forms()}

  def handle_event("command-change", %{"command" => attrs}, socket),
    do:
      {:noreply,
       assign(socket,
         command_form: to_form(attrs, as: :command),
         violation_options: violations(socket.assigns.scene, attrs["actor_id"])
       )}

  def handle_event("quote", %{"command" => attrs}, socket) do
    with {:ok, actor, intent} <- command(attrs),
         socket = cancel_pending(socket),
         {:ok, socket} <- attach(socket, actor) do
      propose(socket, actor, intent)
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("confirm", _params, %{assigns: %{pending: pending}} = socket)
      when not is_nil(pending) do
    case attach(socket, pending.actor) do
      {:ok, socket} -> confirm_pending(socket, pending)
      {:error, reason} -> failure(socket, reason)
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, cancel_pending(socket)}
  def handle_event(_event, _params, socket), do: failure(socket, :invalid_request)

  @impl true
  def handle_info({:world_changed, world, _cursor}, %{assigns: %{world: %{id: world}}} = socket),
    do: {:noreply, load(socket, socket.assigns.params)}

  def handle_info({:genesis_changed, pid}, %{assigns: %{attachment: pid}} = socket),
    do: {:noreply, load(socket, socket.assigns.params)}

  def handle_info({:genesis_revoked, pid}, %{assigns: %{attachment: pid}} = socket),
    do: {:noreply, socket |> assign(attachment: nil, pending: nil) |> load(socket.assigns.params)}

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{attachment_ref: ref}} = socket
      ),
      do: {:noreply, assign(socket, attachment: nil, attachment_ref: nil)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp propose(socket, actor, intent) do
    id = Ecto.UUID.generate()

    case safely(fn -> Session.propose(socket.assigns.attachment, id, intent) end) do
      {:ok, quote} ->
        {:noreply,
         assign(socket, pending: %{quote: quote, actor: actor, request: Ecto.UUID.generate()})}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp confirm_pending(socket, pending) do
    case safely(fn ->
           Session.confirm(socket.assigns.attachment, pending.request, pending.quote.id)
         end) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:pending, nil)
         |> load(socket.assigns.params)
         |> put_flash(
           :info,
           "Saved once in this Experience. Published holdings are unchanged until incorporation."
         )}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp save(%{assigns: %{live_action: :edit}} = socket, revision, id, attrs, request) do
    case Content.curate(
           socket.assigns.current_scope,
           socket.assigns.world.id,
           socket.assigns.scene.zone_id,
           revision,
           id,
           attrs,
           request
         ) do
      {:ok, result} ->
        message =
          if result["status"] == "draft",
            do: "Saved as a Draft. Published and Working holdings are unchanged.",
            else: "Saved with an audit record."

        {:noreply,
         socket
         |> load(socket.assigns.params)
         |> assign(:forms_ready, false)
         |> forms()
         |> put_flash(:info, message)}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp save(socket, _revision, _id, _attrs, _request), do: failure(socket, :unauthorized)

  defp attach(
         %{assigns: %{live_action: :run, attachment: pid, attachment_actor: actor}} = socket,
         actor
       )
       when is_pid(pid), do: {:ok, socket}

  defp attach(%{assigns: %{live_action: :run}} = socket, actor) do
    if socket.assigns.attachment, do: safely(fn -> Session.detach(socket.assigns.attachment) end)

    with {:ok, pid} <-
           safely(fn ->
             Runtime.attach(
               socket.assigns.current_scope,
               socket.assigns.world.id,
               socket.assigns.experience.id,
               actor
             )
           end) do
      {:ok,
       assign(socket,
         attachment: pid,
         attachment_actor: actor,
         attachment_ref: Process.monitor(pid)
       )}
    end
  end

  defp attach(_socket, _actor), do: {:error, :unauthorized}

  defp cancel_pending(%{assigns: %{pending: nil}} = socket), do: socket

  defp cancel_pending(socket) do
    if socket.assigns.attachment,
      do:
        safely(fn ->
          Session.cancel(socket.assigns.attachment, socket.assigns.pending.quote.id)
        end)

    assign(socket, :pending, nil)
  end

  # Transport loss is an unknown outcome, not permission to issue a fresh command.
  # The pending request ID survives so the explicit retry can find its durable receipt.
  defp safely(fun) do
    fun.()
  catch
    :exit, _reason -> {:error, :connection_lost}
  end

  defp command(attrs) when is_map(attrs) do
    if Map.keys(attrs) -- ~w(actor_id type target_id quantity record_id) == [] do
      intent = %{type: attrs["type"], target_id: attrs["target_id"]}

      intent =
        if Map.has_key?(attrs, "quantity"),
          do: Map.put(intent, :quantity, integer(attrs["quantity"])),
          else: intent

      intent =
        if Map.has_key?(attrs, "record_id"),
          do: Map.put(intent, :record_id, attrs["record_id"]),
          else: intent

      if LocalAction.valid_intent?(intent) or
           (map_size(intent) == 2 and Companions.handles?(intent.type)),
         do: {:ok, attrs["actor_id"], intent},
         else: {:error, :invalid_request}
    else
      {:error, :invalid_request}
    end
  end

  defp load(socket, params) do
    scope = socket.assigns.current_scope

    with {:ok, world} <- Worlds.get_world(scope, params["world_id"]),
         {:ok, selected} <- selection(scope, world.id, params) do
      scene = selected.scene

      bindings =
        if selected.experience,
          do: Workspace.bindings(scope, world.id, selected.experience.campaign_id),
          else: []

      controlled =
        Enum.filter(scene.actors, fn actor ->
          actor.kind == :npc or
            Enum.any?(bindings, &(&1.actor_id == actor.id and &1.user_id == scope.user.id))
        end)

      {:ok, page} =
        History.page(
          scope,
          world.id,
          if(selected.experience, do: [experience_id: selected.experience.id], else: [])
        )

      socket
      |> assign(selected)
      |> assign(
        world: world,
        params: params,
        page_title: "Resources & institutions",
        local_rules: world.bundle["local"],
        window_open: Content.window_open?(scope, world.id),
        actor_options: Enum.map(scene.actors, &{&1.name, &1.id}),
        npc_options: Enum.filter(scene.actors, &(&1.kind == :npc)) |> Enum.map(&{&1.name, &1.id}),
        controlled_options: Enum.map(controlled, &{&1.name, &1.id}),
        quantity_actions: @quantity_actions,
        violation_options: violations(scene, socket.assigns[:attachment_actor])
      )
      |> stream(:holdings, holdings(scene), reset: true)
      |> stream(
        :local_records,
        local_records(scene),
        reset: true
      )
      |> stream(:history, page.events, reset: true)
    else
      _ ->
        socket
        |> assign(pending: nil, forms_ready: false)
        |> put_flash(:error, "This resource workspace is unavailable or your permission changed.")
        |> push_navigate(to: ~p"/worlds")
    end
  end

  defp selection(scope, world, %{"zone_id" => zone}) do
    with :ok <- Access.world(scope, world, ["steward", "builder"]),
         {:ok, scene} <- Content.view(scope, world, zone),
         do: {:ok, %{scene: scene, experience: nil}}
  end

  defp selection(scope, world, %{"experience_id" => exp} = params) do
    with {:ok, experience} <- Experiences.get(scope, world, exp, ["gm"]),
         {:ok, scene} <- Workspace.experience_view(scope, world, exp, params["zone"]),
         do: {:ok, %{scene: scene, experience: experience}}
  end

  defp holdings(scene),
    do:
      scene.items
      |> Enum.filter(&(not is_nil(&1.commodity)))
      |> Enum.map(fn item ->
        Map.put(item, :owner_name, actor_name(scene, elem(item.owner, 1)))
      end)

  defp actor_name(scene, id),
    do:
      Enum.find_value(scene.actors, "Unknown actor", fn actor ->
        if actor.id == id, do: actor.name
      end)

  defp local_records(scene),
    do:
      scene.knowledge
      |> Enum.filter(&String.starts_with?(&1.predicate, "local:"))
      |> Enum.map(fn record ->
        Map.merge(record, %{
          subject_name: actor_name(scene, record.subject_id),
          object_name: actor_name(scene, record.object_id)
        })
      end)

  defp violations(scene, actor),
    do:
      scene.knowledge
      |> Enum.filter(fn record ->
        record.kind == :fact and record.predicate == "local:trespass" and
          Audience.permits?(record.audience, %{actor_id: actor})
      end)
      |> Enum.map(
        &{"#{actor_name(scene, &1.subject_id)} · store entry at #{&1.occurred_at}s", &1.id}
      )

  defp forms(%{assigns: %{forms_ready: true}} = socket), do: socket

  defp forms(%{assigns: %{scene: scene}} = socket) do
    settlement = scene.settlement

    attrs =
      if settlement,
        do:
          Map.drop(settlement, ~w(id version site_id rules available_grain))
          |> Map.put("profile", settlement["profile"]["id"]),
        else: defaults()

    assign(socket,
      forms_ready: true,
      settlement_form: to_form(attrs, as: :settlement),
      settlement_id: if(settlement, do: settlement["id"], else: ""),
      settlement_revision: scene.revision,
      settlement_request: Ecto.UUID.generate(),
      stock_form:
        to_form(%{"commodity" => "grain", "quantity" => 1, "reason" => "Opening holdings"},
          as: :stock
        ),
      stock_id: "",
      stock_revision: scene.revision,
      stock_request: Ecto.UUID.generate(),
      command_form: to_form(%{"type" => "buy", "quantity" => 1}, as: :command)
    )
  end

  defp forms(socket), do: socket

  defp defaults,
    do: %{
      "name" => "The relief market",
      "profile" => "temple_market",
      "tradition" => "Keep a place at the table",
      "claim" => "",
      "price" => 10,
      "scarcity_threshold" => 5,
      "multiplier" => 2,
      "capacity" => 10,
      "quote_ttl" => 300,
      "accepting_members" => true,
      "witnessing" => true,
      "enabled" => true
    }

  defp numbers(attrs, keys),
    do:
      Enum.reduce(keys, attrs, fn key, acc ->
        if Map.has_key?(acc, key), do: Map.update!(acc, key, &integer/1), else: acc
      end)

  defp booleans(attrs, keys),
    do:
      Enum.reduce(keys, attrs, fn key, acc ->
        if Map.has_key?(acc, key), do: Map.update!(acc, key, &boolean/1), else: acc
      end)

  defp boolean(value) when value in [true, "true"], do: true
  defp boolean(value) when value in [false, "false"], do: false
  defp boolean(_value), do: :invalid

  defp integer(n) when is_integer(n), do: n

  defp integer(n) when is_binary(n) do
    case Integer.parse(n) do
      {value, ""} -> value
      _ -> -1
    end
  end

  defp integer(_n), do: -1
  defp blank_nil(""), do: nil
  defp blank_nil(id), do: id

  defp failure(socket, reason),
    do: {:noreply, socket |> load(socket.assigns.params) |> put_flash(:error, message(reason))}

  defp message(reason) when reason in [:stale_revision, :stale_snapshot],
    do:
      "This record changed. Reopen the editors to review current values; your old form was not silently rebased."

  defp message(:stale_proposal),
    do:
      "The stock, price, resources or eligibility changed. Nothing was spent. Request and confirm a fresh preview."

  defp message(:quote_expired),
    do: "This quote expired in fictional time. Request a fresh preview; no payment was made."

  defp message(:migration_required),
    do:
      "Live holdings or institutional obligations prevent this change. Keep the existing profile until an explicit migration is available."

  defp message(:connection_lost),
    do:
      "Connection interrupted; the outcome may already be saved. Retry this same confirmation to recover its receipt."

  defp message(:paused),
    do: "Resume the Experience before making a new action. Paused time does not expire quotes."

  defp message(:currency_disabled),
    do: "This is a barter community. Use the declared barter exchange instead of currency."

  defp message(:institution_refused),
    do: "The institution is not accepting affiliations. No resources or convictions changed."

  defp message(:aid_unavailable),
    do:
      "Aid is unavailable under the institution's current obligations, access policy or resources."

  defp message(reason) when reason in [:insufficient_stock_or_capacity, :production_capacity],
    do: "The required stock, funds or capacity are unavailable. Nothing was spent."

  defp message(_reason),
    do:
      "This action is unavailable. Check the selected actor, target, quantities and permissions. No new action was accepted."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div :if={assigns[:world] && @forms_ready}>
        <nav aria-label="Breadcrumb" class="mb-7 flex flex-wrap gap-3 text-sm">
          <.link navigate={~p"/worlds/#{@world.id}"} class="text-link">{@world.name}</.link>
          <.link
            :if={!@experience}
            navigate={~p"/worlds/#{@world.id}/places/#{@scene.zone_id}"}
            class="text-link"
          >{@scene.name}</.link>
          <.link
            :if={@experience}
            navigate={~p"/worlds/#{@world.id}/experiences/#{@experience.id}"}
            class="text-link"
          >{@experience.name}</.link>
          <.link
            :if={@experience}
            id="resource-travel"
            navigate={~p"/worlds/#{@world.id}/experiences/#{@experience.id}/travel"}
            class="text-link"
          >Travel & visited places</.link>
        </nav>
        <header class="mb-8">
          <p class="eyebrow">Finite resources · lasting obligations</p><h1 class="display-title">
            Resources & institutions
          </h1>
          <p id="resource-scope" class="lede mt-4">
            {if @experience, do: "Working · #{@experience.status}", else: "Published"} · {@scene.name} · fictional coordinate {@scene.time.value}s
          </p>
        </header>
        <p :if={!@local_rules} id="local-unavailable" class="notice">
          This world's pinned ruleset does not enable settlement mechanics. Existing worlds are not upgraded silently. Create a settlement-enabled world; migration of existing holdings is not yet available.
        </p>
        <div :if={@local_rules} class="space-y-8">
          <aside :if={@window_open && !@experience} id="resource-draft-notice" class="notice">
            An advancement window is open. Authoring saves are Drafts, not changes to Published or Working resources.
          </aside>
          <.settlement_summary :if={@scene.settlement} {assigns} />
          <.settlement_editor :if={@live_action == :edit} {assigns} />
          <.settlement_records {assigns} />
        </div>
        <.settlement_actions :if={@live_action == :run} {assigns} />
      </div>
    </Layouts.app>
    """
  end
end
