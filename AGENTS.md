# Agent Guidelines

## Project overview

Genesis is a living-world, system-agnostic tabletop RPG engine on Elixir/OTP.
One shared persistent world hosts solo curated stories, GM-less group stories
(sync or async), and live GM sessions; NPCs and narrative beats are partly
LLM-driven behind hard engine validation. Players connect over a terminal UI
(ExRatatui, served over SSH) and over LiveView in the browser — both are
transports onto the same authoritative state.

The full architecture report is `ttrpg-elixir.md`; read it before making
structural decisions. The load-bearing parts:

- **The zone is the consistency boundary.** A `Zone` GenServer is the single
  writer for its slice of the world; NPCs, items and factions live inside it as
  plain data, and an NPC is promoted to its own process only when it goes "hot"
  (active LLM conversation or autonomous agenda). Sessions send intents to the
  authoritative zone; they never mutate world state themselves.
- **Functional core.** Pure reducers `(state, intent) -> {state, effects}` in
  the core namespace, with no processes; OTP modules own the processes and the
  side effects. Keep the split — it is what makes the engine testable.
- **Single node, on purpose.** Process lookup goes through `Registry` and
  `DynamicSupervisor` so Horde can be swapped in later. Do not add libcluster
  or Horde without a decision to revisit §2/§10 of the report.
- **Time is lazy.** A coarse world clock plus zone hibernation and
  catch-up-on-wake. Never tick idle entities.
- **Persistence is snapshot plus an append-only `WorldEvent` log** (audit,
  replay, "what happened while I was gone"), not full event sourcing. Postgres
  with jsonb for system-specific attributes; pgvector for NPC memory.
- **Rulesets are data.** A `GameSystem` behaviour plus declarative bundles;
  fantasy and cyberpunk are two config bundles, not two codebases.
- **The LLM is never the source of truth.** It emits tool calls into engine
  intents that the engine validates against the ruleset and the world. Treat
  all player text as untrusted and structurally isolated from instructions;
  every prompt and response is logged, and cost caps live in the gateway.
- **Per-actor visibility ("fog of knowledge") is enforced at the state layer**,
  not in the UI. Effects carry a visibility set.

## Commands

Everything below is bundled into one alias. **Run `mix precommit` when you
think you're done** — it runs the same checks CI runs, so a green `precommit`
means a green PR.

| Task | Command |
| --- | --- |
| Everything (run this before you're done) | `mix precommit` |
| Install deps | `mix deps.get` |
| Compile (warnings are errors in CI) | `mix compile --warnings-as-errors` |
| Run all tests | `mix test` |
| Run one test file | `mix test test/path/to/file_test.exs` |
| Run one test | `mix test test/path/to/file_test.exs:LINE` |
| Format | `mix format` |
| Lint | `mix credo --strict` |
| Compile-time dependency check | `mix xref graph --label compile-connected --fail-above 0` |
| Type check (slow; runs in CI, not in `precommit`) | `mix dialyzer` |
| Dependency vulnerabilities | `mix deps.audit` |
| Retired packages | `mix hex.audit` |
| Phoenix security scan | `mix sobelow --exit --skip` |
| Refresh AGENTS.md usage rules | `mix usage_rules.sync --yes` |
| Check those rules are current | `mix usage_rules.sync --check` |
| Search dependency docs | `mix usage_rules.search_docs "term" -p package` |

Some of these only exist once the matching dep is installed; the `precommit`
alias in `mix.exs` is the authoritative list for this project.

## Conventions

- **Run `mix precommit` before declaring work finished.** Fix what it reports
  rather than narrowing the check or adding a suppression. If a check is
  genuinely wrong for this project, change the config in a separate commit and
  say why.
- **Format before committing.** CI enforces `mix format --check-formatted`.
- **No compiler warnings.** CI compiles with `--warnings-as-errors`, and tests
  run with `--warnings-as-errors` too — test files are held to the same bar.
- **Test-first when practical.** Add or update an ExUnit test that captures the
  behavior change, watch it fail, then implement. Use `async: true` in test
  modules unless they share global state (named processes, the database outside
  the SQL sandbox, Application env).
- **A test must be able to fail.** No test without an assertion, and no
  assertion that holds regardless of the code under test (`assert x == x`,
  or `assert is_map(result)` where every return value passes). If you can't
  write an assertion that would have failed before the change, the test isn't
  earning its keep.
- **Don't add dependencies to solve small problems.** The standard library
  covers date and time (`Date`, `Time`, `DateTime`, `Calendar`), and every new
  dep is one more thing CI has to audit. Ask before adding one.
- **Pattern match at function heads** rather than with nested `case`/`cond`
  where it reads naturally; use `with` for chains of fallible calls. Never
  write a `case` whose only clauses are `true` and `false` — that's an `if`.
- **Let it crash where appropriate.** Don't defensively rescue exceptions in
  supervised processes; reserve `try/rescue` for genuine boundary concerns.
  Never `rescue` an exception only to log it and continue.
- **Typespecs on public functions** of library-style modules; Dialyzer runs in
  CI when `dialyxir` is installed. Name the arguments in the spec —
  `@spec fetch(user_id :: integer()) :: {:ok, t()} | {:error, term()}`.
- **Keep runtime deps out of compile time.** `mix xref graph --label
  compile-connected --fail-above 0` fails the build when a module edit starts
  triggering wide recompiles. The fix is usually to stop invoking a macro or
  referencing a struct at compile time across a context boundary.
- **Don't edit generated or vendored files** (`deps/`, `_build/`,
  `priv/static/assets/`, migration files that have already shipped).
- **If this repo has both `.github/workflows/` and `.forgejo/workflows/`,
  they are not copies.** The Forgejo one installs the BEAM by hand, references
  actions by full URL, and reaches services by container name — every
  difference is deliberate and documented in README.md. When you change one
  pipeline, decide consciously whether the other needs the same change; don't
  mirror it mechanically. Note that `actionlint` cannot check the Forgejo file,
  so verify edits there by hand.

## Background jobs

Oban is wired up with a single `default` queue (10 concurrent), the Basic
(Postgres) engine, and its migration at version 14. It is the durable half of
the world: scheduled world events, zone catch-up, the LLM offline content
compiler, and NPC reflection belong here rather than in `Process.send_after`,
because they must survive a restart.

`config/test.exs` sets `testing: :manual`, so **tests do not execute jobs**.
Assert that work was scheduled with `assert_enqueued/1` (available in every
`Genesis.DataCase` via `use Oban.Testing`). When a test genuinely needs the job
to run, wrap it: `Oban.Testing.with_testing_mode(:inline, fn -> ... end)`.

## Framework and library guidelines

Generators — notably `mix phx.new` — ship their own `AGENTS.md`. On bootstrap
its guidance is merged into *this* file rather than left as a competing second
file: framework-specific rules go in a section below the conventions above,
and the machine-generated block goes at the bottom.

### Project guidelines

- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

#### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

#### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

#### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

<!-- phoenix-gen-auth-start -->
### Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A `live_session :current_user` scope - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope - for routes that require authentication, similar to the plug with the same name
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session` as described below**

#### Routes that require authentication

LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{GenesisWeb.UserAuth, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

#### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the __existing__ `:current_user` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{GenesisWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->

Anything between the `<!-- usage-rules-start -->` and `<!-- usage-rules-end -->`
markers at the end of this file is **generated from the installed
dependencies** by `mix usage_rules.sync`. Never hand-edit inside those markers:
the next sync overwrites it, and CI fails when the block is out of date. Put
your own guidance above the markers instead. After changing dependencies, run
`mix usage_rules.sync --yes` and commit the result.

That task prompts for confirmation, so it hangs if you run it bare in a
non-interactive shell. Always pass `--yes` (write the changes) or `--check`
(exit non-zero if stale, without writing).

## Versions

Erlang/Elixir versions are pinned in `.tool-versions` (used by asdf/mise
locally and by `erlef/setup-beam` in CI). Bump versions there, nowhere else.

<!-- usage-rules-start -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied

<!-- phoenix:ecto-end -->
<!-- phoenix:elixir-start -->
## phoenix:elixir usage
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages


<!-- phoenix:elixir-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset

<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

<!-- phoenix:phoenix-end -->
<!-- sobelow-start -->
## sobelow usage
_Security-focused static analysis for Elixir & the Phoenix framework_

# Sobelow usage rules

Sobelow is a security-focused **static** analyser for Elixir and Phoenix. It reads
source code, never runs it, and never contacts a running application.

## Running it

```sh
mix sobelow                 # scan the current project
mix sobelow -r ../my_app    # scan another project root
```

Add it as a dev/test dependency so `mix sobelow` is available:

```elixir
{:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
```

Sobelow scans **one application at a time**. For an umbrella, add an alias to the
root `mix.exs` and give each child app its own config file:

```elixir
defp aliases do
  [sobelow: ["cmd mix sobelow"]]
end
```

## Confidence levels are triage guidance, not severity

Every finding carries High, Medium, or Low confidence. This is Sobelow's confidence
that the code is *reachable with attacker-controlled input* — not how bad the bug
would be.

- **High** — the tainted value traces back to a function parameter or `conn.params`.
- **Medium** — the dangerous call is present but the input source is less certain.
- **Low** — the pattern looks dangerous but Sobelow cannot tell whether it takes
  user input. Often, but not always, a false positive.

Sobelow intentionally over-reports. **A green (low) finding may still be critical.**
Never tell a user their code is safe because findings are low confidence, and never
suppress low-confidence findings wholesale to make a build pass.

Use `--threshold low|medium|high` to filter the report by confidence.

## Suppressing false positives

There are two mechanisms and they are not interchangeable.

**`# sobelow_skip` comments** mark a *specific function* or a *specific Phoenix
router pipeline*. The comment must sit immediately above the `def` or `pipeline`
it applies to.

```elixir
# sobelow_skip ["Traversal.SendFile", "XSS.Raw"]
def download(conn, params) do
  ...
end
```

On a pipeline they suppress the router configuration checks — `Config.CSRF`,
`Config.Headers`, and `Config.CSP`:

```elixir
# sobelow_skip ["Config.CSRF"]
pipeline :api do
  ...
end
```

Listing the parent `Config` module suppresses every Config check on that
pipeline, the same way `-i Config` ignores the whole group.

Spacing does not matter, but the check names must be a list of double-quoted
strings. A comment Sobelow cannot read is reported on stderr with its file and
line rather than being ignored, so a skip that appears to do nothing is worth
checking the warnings for.

They still cannot suppress configuration findings that are not attached to a
function or a pipeline — `Config.Secrets` or `Config.HTTPS`, for instance, which
come from `config/*.exs`. Use `--mark-skip-all` for those.

**`--mark-skip-all`** writes every currently-reported finding to a `.sobelow-skips`
file, and works for *all* finding types including configuration ones. Use it when
adopting Sobelow on an existing codebase.

Either way, the skips only take effect when you pass `--skip`:

```sh
mix sobelow --mark-skip-all   # record the current findings as accepted
mix sobelow --skip            # scan, ignoring those
mix sobelow --clear-skip      # discard the recorded skips
```

Commit `.sobelow-skips` so the whole team and CI share the same baseline. The file
is rewritten in sorted order each time it is regenerated, so re-running
`--mark-skip-all` after fixing or adding a finding produces a small, readable diff
rather than reshuffling the file. Pass `--legacy-skips` if you need the older
append-only behaviour, which never rewrites lines it did not add.

Prefer `# sobelow_skip` with an explicit module list over `--mark-skip-all` when you
have only a handful of false positives — it documents the decision at the code, and
it does not go stale silently when the line moves.

`--ignore` (`-i`) is different again: it disables a whole check for the entire scan.
Reach for it only when a check does not apply to the project at all.

## Configuration file

`--save-config` writes a `.sobelow-conf` at the project root from the flags you
passed:

```sh
mix sobelow -i XSS.Raw,Traversal --verbose --exit Low --save-config
```

Precedence rules:

- `.sobelow-conf` is used automatically when present.
- **CLI switches override the file.**
- `--no-config` ignores the file for that run.

The file holds settings only. `--version`, `--details`, `--all-details`,
`--save-config`, and `--diff` pick what Sobelow does instead of configuring a
scan, and each ends the run before one happens, so they are ignored if they
appear in the file.

Commit `.sobelow-conf`. Paths in it are stored relative to the project root, so it
works on other machines and in CI.

## CI

Sobelow exits 0 by default, *even when it finds things*. To fail a build you must
pass `--exit`:

```sh
mix sobelow --exit medium     # non-zero if any medium or high finding exists
mix sobelow --exit            # bare --exit means low, i.e. fail on anything
```

A reasonable starting point for an existing codebase: baseline with
`--mark-skip-all`, then run `mix sobelow --skip --exit low` in CI so any *new*
finding fails the build.

Machine-readable output for other tooling:

```sh
mix sobelow --format json
mix sobelow --format sarif        # e.g. GitHub code scanning
mix sobelow --format sarif --out results.sarif
```

`--out` implies a machine-readable format; a `txt` format is coerced to `json`.

Other useful flags:

- `--private` — no update check, no network requests, no cache file written.
  Use this in CI and in sandboxed builds.
- `--quiet` — print a one-line count instead of findings.
- `--compact` / `--flycheck` — single-line findings for editors and tooling.
- `--strict` — treat a file Sobelow cannot parse as a hard error (exit 2) instead of
  skipping it. Without it, unparseable files are silently skipped.
- `--no-router` — for a project with no Phoenix router, such as a plain Elixir
  library. Without it Sobelow warns that it cannot find one, on every run. The
  router-dependent checks are skipped either way. Set it in `.sobelow-conf` as
  `router: :none`.

## What it will and will not find

Sobelow flags patterns, not proven exploits. It has no cross-function taint
tracking: it decides confidence from the parameters of the *enclosing* function
only. A value laundered through a helper will usually come back as low confidence
or not at all.

It also does not check dependencies for known CVEs in general — the `Vuln.*` checks
cover a small fixed set of historical advisories by inspecting `deps/`. For real
dependency scanning use `mix hex.audit` (retired packages) alongside a dedicated
tool such as MixAudit.

If Sobelow reports nothing, that is not evidence the application is secure. Say so
plainly rather than reporting a clean scan as a security sign-off.

## Getting details on a finding

```sh
mix sobelow -d Config.CSRF     # explain one check
mix sobelow --all-details      # explain all of them
mix help sobelow               # flags and the full module list
```

<!-- sobelow-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
