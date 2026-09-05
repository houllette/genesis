defmodule GenesisWeb.SettlementComponents do
  @moduledoc "Native setup, confirmed actions and scoped resource records for the local settlement slice."
  use GenesisWeb, :html

  def settlement_summary(assigns) do
    ~H"""
    <section id="settlement-summary" class="workspace-panel">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="eyebrow">
            {@scene.settlement["profile"]["tradition_kind"]} · {@scene.settlement["profile"][
              "exchange"
            ]}
          </p>
          <h2 class="section-heading">{@scene.settlement["name"]}</h2>
          <p class="text-sm text-stone-600">{@scene.settlement["tradition"]}</p>
        </div>
        <span class="status-label">{if @scene.settlement["enabled"],
          do: "Enabled · version 1",
          else: "Disabled"}</span>
      </div>
      <p :if={@scene.settlement["claim"] != ""} class="mt-4 rounded-lg bg-stone-50 p-3 text-sm">
        <strong>Tradition's claim, not a confirmed fact:</strong> {@scene.settlement["claim"]}
      </p>
      <div class="mt-5 grid gap-4 sm:grid-cols-3">
        <p>
          <span class="helper-text block">Available market grain</span><span
            id="market-grain"
            class="text-2xl font-semibold"
          >{@scene.settlement["available_grain"]}</span>
        </p>
        <p>
          <span class="helper-text block">Production per batch</span><span class="text-lg font-semibold">Up to {@scene.settlement[
            "capacity"
          ]} conversions</span>
        </p>
        <p>
          <span class="helper-text block">Quote lifetime</span><span class="text-lg font-semibold">{@scene.settlement[
            "quote_ttl"
          ]} fictional seconds</span>
        </p>
      </div>
      <p id="recipe-explanation" class="helper-text mt-5">
        Each conversion consumes {@local_rules["recipe"]["input_units"]} {@local_rules["recipe"][
          "input"
        ]} and creates {@local_rules["recipe"]["output_units"]} {@local_rules["recipe"]["output"]} plus {@local_rules[
          "recipe"
        ]["waste_units"]} {@local_rules["recipe"]["waste"]}. Immediate resolution; no background production.
      </p>
      <p class="helper-text mt-2">
        Affiliation is voluntary and private. Aid requires a fulfilled offering obligation and available supplies; it can be redeemed once. Membership grants no platform permissions.
      </p>
    </section>
    """
  end

  def settlement_editor(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-2">
      <section class="workspace-panel">
        <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h2 class="section-heading mb-0">Market & institution</h2>
          <button id="reopen-resource-editors" class="text-link text-sm" phx-click="reopen-editors">Reopen latest values</button>
        </div>
        <p class="helper-text mb-5">
          Choose two existing NPCs: one operates the market, the other represents the institution. Their inventories are the stock and treasury. Add people in the place editor first.
        </p>
        <.form
          for={@settlement_form}
          id="settlement-form"
          phx-submit="save-settlement"
          class="space-y-4"
        >
          <input type="hidden" name="revision" value={@settlement_revision} /><input
            type="hidden"
            name="request_id"
            value={@settlement_request}
          /><input type="hidden" name="record_id" value={@settlement_id} />
          <.input
            field={@settlement_form[:name]}
            label="Market / institution name"
            required
            maxlength="160"
          />
          <.input
            field={@settlement_form[:profile]}
            type="select"
            label="Society preset"
            options={[
              {"Religious institution · currency market", "temple_market"},
              {"Secular mutual-aid guild · barter", "mutual_aid"}
            ]}
          />
          <.input
            field={@settlement_form[:merchant_id]}
            type="select"
            label="Market operator"
            options={@npc_options}
            prompt="Choose an NPC"
            required
          />
          <.input
            field={@settlement_form[:representative_id]}
            type="select"
            label="Institution representative / local adjudicator"
            options={@npc_options}
            prompt="Choose a different NPC"
            required
          />
          <.input
            field={@settlement_form[:tradition]}
            label="Tradition or shared principle"
            required
            maxlength="160"
          />
          <.input
            field={@settlement_form[:claim]}
            type="textarea"
            rows="2"
            maxlength="2000"
            label="Optional belief / lore claim (not engine fact)"
          />
          <details class="rounded-lg border border-stone-200 p-4">
            <summary class="cursor-pointer font-medium">Prices, capacity & local policy</summary>
            <div class="mt-4 space-y-4">
              <.input
                field={@settlement_form[:price]}
                type="number"
                min="2"
                max="1000"
                label="Base grain price, integer minor units"
              />
              <.input
                field={@settlement_form[:scarcity_threshold]}
                type="number"
                min="1"
                max="1000"
                label="Scarcity begins at this remaining stock"
              />
              <.input
                field={@settlement_form[:multiplier]}
                type="number"
                min="1"
                max="10"
                label="Scarcity buy-price multiplier"
              />
              <p class="helper-text">
                Selling pays half the base price, rounded down. Barter uses the pinned recipe's exchange terms. There is no floating-point money.
              </p>
              <.input
                field={@settlement_form[:capacity]}
                type="number"
                min="1"
                max="100"
                label="Maximum conversions in one batch"
              />
              <.input
                field={@settlement_form[:quote_ttl]}
                type="number"
                min="1"
                max="86400"
                label="Quote lifetime, fictional seconds"
              />
              <.input
                field={@settlement_form[:accepting_members]}
                type="checkbox"
                label="Accept voluntary affiliations"
              />
              <.input
                field={@settlement_form[:witnessing]}
                type="checkbox"
                label="Representative witnesses restricted-store entry"
              />
              <.input
                field={@settlement_form[:enabled]}
                type="checkbox"
                label="Enable local mechanics"
              />
              <p class="helper-text">
                Changing society or disabling mechanics is refused while live holdings or obligations exist. Timed recipes and profile migrations are not yet supported.
              </p>
            </div>
          </details>
          <button id="save-settlement" class="primary-button" phx-disable-with="Saving…">{if @window_open,
            do: "Save definition draft",
            else: "Save definitions"}</button>
        </.form>
      </section>
      <section :if={@scene.settlement} class="workspace-panel">
        <h2 class="section-heading">Stock & treasury</h2>
        <p class="helper-text mb-5">
          Opening or corrected holdings are an explicit GM source/sink, with a reason. Actual trades use the Experience's confirmed actions below, not an authoring edit.
        </p>
        <.form for={@stock_form} id="stock-form" phx-submit="save-stock" class="space-y-4">
          <input type="hidden" name="revision" value={@stock_revision} /><input
            type="hidden"
            name="request_id"
            value={@stock_request}
          /><input type="hidden" name="record_id" value={@stock_id} />
          <.input
            field={@stock_form[:owner_id]}
            type="select"
            label="Inventory owner"
            options={@actor_options}
            prompt="Choose an owner"
            required
          />
          <.input
            field={@stock_form[:commodity]}
            type="select"
            label="Resource / denomination"
            options={
              Enum.sort(Enum.map(@local_rules["commodities"], fn {id, label} -> {label, id} end))
            }
          />
          <.input
            field={@stock_form[:quantity]}
            type="number"
            min="0"
            max="1000000"
            label="Quantity in this lot"
            required
          />
          <.input
            field={@stock_form[:reason]}
            label="Reason for this source or correction"
            required
            maxlength="160"
          />
          <button id="save-stock" class="primary-button" phx-disable-with="Saving…">{if @window_open,
            do: "Save holdings draft",
            else: "Record holdings"}</button>
          <p class="helper-text">
            Reopen the editors to start a new lot. Editing a lot cannot change its owner or commodity. Zero retains its spent identity for replay.
          </p>
        </.form>
      </section>
    </div>
    """
  end

  def settlement_actions(assigns) do
    ~H"""
    <section class="workspace-panel">
      <h2 class="section-heading">Resolve a local action</h2>
      <p class="helper-text mb-5">
        Record an NPC's action, or use a character bound to your account. Every choice is previewed and explicitly confirmed; you cannot take control of another player's character. No player connection is required for NPC actions.
      </p>
      <p :if={@experience.status != "active"} id="actions-paused" class="notice mb-5">
        This Experience is {@experience.status}. Resume from its workspace to accept new actions. Fictional time is preserved.
      </p>
      <.form
        for={@command_form}
        id="local-action-form"
        phx-change="command-change"
        phx-submit="quote"
        class="grid gap-4 sm:grid-cols-2"
      >
        <.input
          field={@command_form[:actor_id]}
          type="select"
          label="Acting character"
          options={@controlled_options}
          prompt="Choose an actor"
          required
        />
        <.input
          field={@command_form[:type]}
          type="select"
          label="Action"
          options={[
            {"Buy grain", "buy"},
            {"Sell grain", "sell"},
            {"Barter rations for grain", "barter"},
            {"Produce rations", "produce"},
            {"Rest using supplies", "rest"},
            {"Voluntarily affiliate", "affiliate"},
            {"Offer supplies", "offer"},
            {"Request one-use aid", "aid"},
            {"Enter a restricted store", "trespass"},
            {"Report a known violation", "report"},
            {"Adjudicate a reported violation", "adjudicate"},
            {"Record operator's supply loss", "disrupt"},
            {"Invite a companion", "recruit"},
            {"Resolve companion's response", "agree"},
            {"Dismiss a companion", "dismiss"}
          ]}
        />
        <.input
          field={@command_form[:target_id]}
          type="select"
          label="Target"
          options={
            @actor_options ++
              if(@local_rules,
                do: [{"Recipe: #{@local_rules["recipe"]["id"]}", @local_rules["recipe"]["id"]}],
                else: []
              )
          }
          prompt="Choose a target"
          required
        />
        <.input
          :if={@command_form[:type].value in @quantity_actions}
          field={@command_form[:quantity]}
          type="number"
          min="1"
          max="100"
          label="Units / recipe batches / barter exchanges"
          required
        />
        <.input
          :if={@command_form[:type].value == "report"}
          field={@command_form[:record_id]}
          type="select"
          label="Violation known to the acting character"
          options={@violation_options}
          prompt="Choose an observed violation"
          required
        />
        <p class="helper-text sm:col-span-2">
          Trade targets the market operator; offers and affiliation target the representative. Production targets the recipe; rest and supply loss target the acting character. Only the representative may adjudicate. A GM knowing a secret does not make the acting NPC know it.
          Companion invitations target an existing NPC. Resolve their response separately: an invitation is not consent. Dismissal preserves their inventory and past relationships.
        </p>
        <button
          id="preview-local-action"
          class="primary-button sm:col-span-2"
          disabled={@experience.status != "active"}
          phx-disable-with="Checking…"
        >Preview consequences</button>
      </.form>
      <div :if={@pending} id="local-quote" role="status" class="notice mt-6">
        <h3 class="font-semibold">Review before committing</h3><p class="mt-2">
          {@pending.quote.terms["summary"]}
        </p>
        <p class="mt-2 text-sm">
          Elapsed fiction: +{@pending.quote.terms["duration"]}s · valid before coordinate {@pending.quote.terms[
            "expires_at"
          ]}s. No stock is reserved.
        </p>
        <p :if={@pending.quote.terms["duration"] > 0} class="mt-3 text-sm">
          This elapsed time will be saved. Publishing positive-duration outcomes waits for phase 08's time reconciliation; it will not be erased.
        </p>
        <div class="mt-4 flex flex-wrap gap-3">
          <button
            id="confirm-local-action"
            class="primary-button"
            phx-click="confirm"
            disabled={@experience.status != "active"}
            phx-disable-with="Saving…"
          >Confirm / retry same action</button>
          <button id="cancel-local-action" class="secondary-button" phx-click="cancel">Decline</button>
        </div>
      </div>
    </section>
    """
  end

  def settlement_records(assigns) do
    ~H"""
    <section>
      <h2 class="section-heading">Owned resource lots</h2><p class="helper-text mb-4">
        Quantities and owners come from the authoritative inventory. These are not editable copies of a shop balance.
      </p>
      <div id="resource-holdings" phx-update="stream" class="grid gap-3 md:grid-cols-2">
        <p id="empty-holdings" class="empty-state hidden only:block md:col-span-2">
          No resource lots have been authored yet.
        </p>
        <article
          :for={{id, item} <- @streams.holdings}
          id={id}
          class="workspace-card flex flex-wrap items-center justify-between gap-3"
        >
          <div>
            <h3 class="font-semibold">
              {item.name} · <span data-quantity={item.quantity}>{item.quantity}</span>
            </h3><p class="helper-text">
              {item.owner_name} · {if item.quantity == 0,
                do: "spent lot retained",
                else: "owned inventory"}
            </p>
          </div>
          <button
            :if={@live_action == :edit}
            id={"edit-stock-#{item.id}"}
            class="text-link text-sm"
            phx-click="edit-stock"
            phx-value-id={item.id}
          >Correct lot</button>
        </article>
      </div>
    </section>
    <section>
      <h2 class="section-heading">Affiliations, obligations & local law</h2>
      <p class="helper-text mb-4">
        GM inspection · private records retain their audiences. A report or affiliation does not create global reputation.
      </p>
      <div id="institution-records" phx-update="stream" class="space-y-3">
        <p id="empty-institution-records" class="helper-text hidden only:block">
          No local obligations or affiliations recorded.
        </p>
        <article :for={{id, record} <- @streams.local_records} id={id} class="workspace-card">
          <p class="status-label">{record.kind}</p><p class="mt-2">
            {record.subject_name} → {record.object_name}: {String.replace(
              record.predicate,
              "local:",
              ""
            )} · {to_string(record.value)}
          </p>
          <details class="mt-3 text-xs text-stone-500">
            <summary>Record identity for reporting</summary><code class="break-all">{record.id}</code>
          </details>
          <.link
            :for={source <- Map.get(record, :source_ids, [])}
            class="text-link mt-2 mr-3 inline-block"
            navigate={
              ~p"/worlds/#{@world.id}/history?#{%{source: source, experience_id: if(@experience, do: @experience.id)}}"
            }
          >View accepted source</.link>
        </article>
      </div>
    </section>
    <details class="rounded-xl border border-stone-200 p-5">
      <summary class="cursor-pointer font-medium">Scoped action history</summary>
      <.link
        id="resource-full-history"
        class="text-link mt-3 inline-block"
        navigate={
          ~p"/worlds/#{@world.id}/history?#{%{experience_id: if(@experience, do: @experience.id)}}"
        }
      >Browse history & recognize a contribution</.link>
      <div id="resource-history" phx-update="stream" class="mt-4 space-y-3">
        <p id="empty-resource-history" class="helper-text hidden only:block">
          No visible actions in this scope.
        </p>
        <article
          :for={{id, event} <- @streams.history}
          id={id}
          class="border-b border-stone-100 pb-3 text-sm"
        >
          <p>{event.type} · {Map.get(event.result, "outcome", "Recorded")}</p>
          <p class="helper-text">
            Commit cursor {event.cursor} · fictional coordinate {event.occurred_at}
          </p>
        </article>
      </div>
      <p class="helper-text mt-4">
        First 30 authorized events. Recorded history is not another execution of an action.
      </p>
    </details>
    """
  end
end
