defmodule GenesisWeb.WorldLibraryLive do
  use GenesisWeb, :live_view
  alias Genesis.Worlds

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Your worlds")
     |> fresh_form()
     |> stream(:worlds, Worlds.list_worlds(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("create", %{"world" => attrs, "request_id" => request}, socket) do
    case Worlds.create_world(socket.assigns.current_scope, calendar_attrs(attrs), request) do
      {:ok, world} ->
        {:noreply, push_navigate(socket, to: ~p"/worlds/#{world.id}")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:form, to_form(attrs, as: :world))
         |> put_flash(
           :error,
           "Add a name and choose a supported ruleset, profile and valid calendar epoch."
         )}
    end
  end

  defp fresh_form(socket),
    do:
      assign(socket,
        form:
          to_form(
            %{
              "name" => "Ashfall",
              "ruleset" => "fantasy_local",
              "profile" => "village",
              "calendar_kind" => "ordinal",
              "epoch_year" => "1",
              "epoch_month" => "1",
              "epoch_day" => "1"
            },
            as: :world
          ),
        request_id: Ecto.UUID.generate()
      )

  defp calendar_attrs(attrs) do
    {options, attrs} = Map.split(attrs, ~w(calendar_kind epoch_year epoch_month epoch_day))

    if Map.get(options, "calendar_kind", "ordinal") == "ordinal" do
      attrs
    else
      epoch = Map.new(~w(year month day), &{&1, integer(options["epoch_" <> &1])})

      Map.put(attrs, "calendar", %{
        "format" => 1,
        "id" => "world-calendar",
        "version" => 1,
        "implementation" => options["calendar_kind"],
        "epoch" => epoch
      })
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <section class="workspace-hero">
        <p class="eyebrow">A place for worlds worth returning to</p>
        <h1 class="display-title">Your worlds</h1>
        <p class="lede">
          Give a place its people. Bring a story to the table. Decide together what becomes history.
        </p>
      </section>
      <div class="grid gap-8 lg:grid-cols-[1fr_24rem]">
        <section aria-labelledby="library-heading">
          <h2 id="library-heading" class="section-heading">The world library</h2>
          <div id="worlds" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
            <div id="empty-library-1" class="empty-state hidden only:block sm:col-span-2">
              Your first world begins with a name. No players or setup scripts needed.
            </div>
            <article :for={{id, world} <- @streams.worlds} id={id} class="workspace-card group">
              <.icon name="hero-globe-alt" class="size-7 text-emerald-700" />
              <h3 class="mt-5 text-2xl font-semibold">
                <.link navigate={~p"/worlds/#{world.id}"} class="stretched-link">{world.name}</.link>
              </h3>
              <p class="mt-2 text-sm text-stone-600">
                {String.capitalize(world.profile)} · Published revision {world.revision}
              </p>
              <p class="mt-6 text-sm font-medium text-emerald-800">
                Open workspace <span aria-hidden="true">→</span>
              </p>
            </article>
          </div>
        </section>
        <section class="workspace-panel" aria-labelledby="create-heading">
          <p class="eyebrow">Begin something</p>
          <h2 id="create-heading" class="section-heading">Create a world</h2>
          <.form for={@form} id="new-world-form" phx-submit="create" class="space-y-5">
            <input type="hidden" name="request_id" value={@request_id} />
            <.input field={@form[:name]} label="World name" required maxlength="160" />
            <.input
              field={@form[:ruleset]}
              type="select"
              label="Ruleset"
              options={[
                {"Fantasy · settlement mechanics", "fantasy_local"},
                {"Cyberpunk · settlement mechanics", "cyberpunk_local"},
                {"Fantasy · original demo", "fantasy_demo"},
                {"Cyberpunk · original demo", "cyberpunk_demo"}
              ]}
            />
            <.input
              field={@form[:profile]}
              type="select"
              label="World profile"
              options={[
                {"Village · a close-knit place", "village"},
                {"Frontier · an unsettled edge", "frontier"}
              ]}
            />
            <p class="helper-text">
              Profiles set the starting scale, not an automated simulation. World time only moves through an approved advancement.
            </p>
            <details id="world-calendar-options" class="space-y-3">
              <summary class="cursor-pointer text-sm font-semibold">Calendar (optional)</summary>
              <p class="helper-text">
                Keep ordinal seconds, or pin a supported calendar. The epoch below is fictional coordinate zero, not today's date. This cannot be changed after creation.
              </p>
              <.input
                field={@form[:calendar_kind]}
                type="select"
                label="Calendar structure"
                options={[
                  {"Ordinal seconds", "ordinal"},
                  {"Gregorian", "gregorian"},
                  {"Coptic · 13 months", "coptic"}
                ]}
              />
              <.input field={@form[:epoch_year]} type="number" label="Epoch year" min="1" max="9999" />
              <.input field={@form[:epoch_month]} type="number" label="Epoch month" min="1" max="13" />
              <.input field={@form[:epoch_day]} type="number" label="Epoch day" min="1" max="31" />
            </details>
            <button id="create-world" class="primary-button w-full" phx-disable-with="Creating…">Create world
            <.icon name="hero-arrow-right" class="size-4" /></button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
