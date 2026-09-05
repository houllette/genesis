# Handoff: 00 — Baseline

Status: complete for the inspected boilerplate baseline on 2026-09-04.

Phase brief: [README.md](README.md). Follow the [workflow](../workflow.md).
No engine phase has been implemented. Revalidate this evidence if code or
environment changes before phase 01.

The 2026-09-04 second-pass documentation revision changes future product
contracts, not this baseline's implemented state. Read the current product,
story/canon and Lemieux documents through the plan index; older default-fork
and direct-provider recommendations are superseded. The evidence below records
the original baseline run, not validation of those future features.

The later living-history revision adds phase 08a between 08 and 09. The original
16-folder validation below remains historical evidence; the current index has
17 phase folders. No new game implementation or baseline dependency is implied.
The subsequent TUI/subsystem revision combines browser and SSH in phase 05 and
repurposes phase 06 for local world subsystems; both are still unstarted. Use the
current index/folder names, not the historical browser-then-SSH sequence.

## Entry validation

Current-plan note: the latest GM-first revision renumbers the still-unstarted
phases 01–16. GM workspace is 05, player TUI 11, pilot 12 and long history 14.
Use the current index and experience-time contract; the old ordering statements
and verification counts below/above are historical provenance only.

- No preceding phase. Read both research documents and repository instructions.
- Branch: `main`; origin: `git@github.com:houllette/genesis.git`.
- Inspected code revision: `f46f5bde188c1e82ccfe50b7d45d10f7ab479754`.
- Initial worktree was clean. This run adds `docs/implementation/` and a README
  link; it changes no application code, tests, configuration or dependencies.
- Ran `git status --short`, source/file inventory, `elixir --version`,
  `mix help precommit`, `mix precommit`, `git diff --check`, and a read-only
  Markdown local-link/phase-pair check. No baseline repairs were necessary.

## Delivered behavior and contracts

- Existing application: [application.ex](../../../lib/genesis/application.ex),
  [mix.exs](../../../mix.exs), [router.ex](../../../lib/genesis_web/router.ex).
- Accounts and authentication tests are in `test/genesis/accounts_test.exs`,
  `test/genesis_web/user_auth_test.exs`, and generated controller/LiveView tests.
- `Genesis.Repo`, `Genesis.PubSub`, endpoint and Oban are already wired.
  `Genesis.DataCase` provides SQL Sandbox and `Oban.Testing`; `Genesis.ConnCase`
  provides browser test support. There are no game-domain APIs to preserve yet.
- Existing migrations create users/tokens and install Oban migration v14.
  Oban uses Basic, `default: 10`, and manual test mode. No migrations added.
- Tool pins: Erlang `29.0.6`, Elixir `1.20.4-otp-29`. Runtime reported ERTS
  `17.0.6`, Elixir `1.20.4`, 14 schedulers. Postgres was reachable for the tests.
- Development database: `genesis_dev` on localhost; test database:
  `genesis_test` plus optional `MIX_TEST_PARTITION`. Credentials/configuration
  remain in the existing local config files; no setup or reset was needed.
- Architectural refinements are documented in [the review](../research-review.md)
  and [architecture](../architecture.md); none is yet game implementation.

## Verification evidence

| Check | Exact command or procedure | Actual result and evidence |
| --- | --- | --- |
| Existing suite | Included in `mix precommit` | 112 passed, ExUnit seed 926983, max_cases 28 |
| Relevant red-test evidence | Not applicable | Documentation and baseline inventory; no behavior change |
| Real-service check | Existing Ecto tests within precommit | Local test Postgres and existing migrations worked |
| `mix precommit` | `mix precommit` | Exit 0; audits, compile, format, Credo, rule sync, xref, Sobelow, docs and tests passed |
| Document checks | Local-link/phase-pair inspection and `git diff --check` | All 16 phase folders have briefs/handoffs; local links resolve; no whitespace errors |
| Dialyzer / remote CI | Not run | Outside this documentation-only baseline gate; no publication requested |

Validated application code remains the revision above. Uncommitted authored
changes are only `README.md` and `docs/implementation/`. Precommit produced no
tracked formatter, dependency, or generated-rule changes. Verification date:
2026-09-04 on the local macOS workspace. The final handoff text records these
results after the gate; it does not alter the validated application code.

## Limits and remaining work

- No unmet phase 00 criteria. Browser visual inspection, production asset/
  release builds, real SSH, providers and performance are future-phase gates.
- Local precommit does not include Dialyzer, workflow lint or PR-title checks;
  remote CI was not run or claimed green.
- All game behavior is deliberately unimplemented. Research library versions
  are not dependency approvals. No code, dependency or deployment changes are
  needed before starting phase 01.

## Next agent: validate before changing code

1. Read [phase 01](../01-pure-core/README.md), the architecture and workflow.
2. Run `git status --short`, `git rev-parse HEAD`, and `elixir --version`; account
   for any code/config changes since this revision.
3. Run `mix test test/genesis/accounts_test.exs test/genesis_web/user_auth_test.exs test/genesis_web/controllers/page_controller_test.exs`.
   Expected: the existing account/auth/page behavior passes using generated
   fixtures and the configured SQL Sandbox. These are existing files; the full
   suite containing them passed above. This focused subset was not rerun after
   the successful full gate.
4. Verify `config/test.exs` still uses the intended test database and manual
   Oban mode. Preserve the existing two migrations and account/auth routes.
5. Introduce the first pure scene test from phase 01. Do not create the entire
   proposed namespace tree or install future-phase dependencies in advance.
