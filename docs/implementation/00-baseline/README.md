# Phase 00 — Verify the boilerplate

## Entry validation

There is no preceding implementation phase. Read [the research review](../research-review.md),
[architecture decisions](../architecture.md), [workflow](../workflow.md), and
the repository AGENTS. Inspect the actual tree against baseline `f46f5bd`;
preserve any changes made since that revision.

## Outcome and scope

A working Phoenix/Elixir starting point whose actual configuration and checks
are recorded for the next agent. Existing authentication is boilerplate, not a
reason to regenerate the application. Do not create game contexts, stub Zone
modules, placeholder schemas, or install the research's proposed dependencies.

Relevant sources: both research introductions; extended report §2/7/11;
`mix.exs`, `.tool-versions`, `config/`, `lib/genesis/application.ex`, router,
`test/support/`, migrations, and `.github/workflows/ci.yml`.

## Work sequence

1. Verify the pinned BEAM tools and dependency lockfile. Run setup only for
   missing prerequisites after reading its alias: `mix setup` creates/migrates
   a development database and builds assets. Never reset an existing database.
2. Confirm Repo, PubSub, endpoint, and Oban are configured; users and Oban are
   the only migrations. Verify Oban Basic, `default: 10`, migration v14, manual
   tests, and available DataCase/ConnCase fixtures.
3. Inspect account registration/login/settings routes and generated tests.
   Confirm that no game routes, worlds, rulesets, NPCs, or stories already exist.
4. Run the repository's `mix precommit` alias. Record its actual result, runtime
   versions, and test count. Inspect formatter and usage-rule output. Resolve
   any baseline defect with the smallest relevant regression test; do not
   manufacture tests for a documentation-only inventory.
5. Record local prerequisites and separate CI-only checks. If the environment
   cannot run a check, name the blocker and leave that gate unverified.

## Handoff criteria

- [x] Existing bootstrap, authentication, database and job configuration have
  been inspected; the next agent can reproduce the environment.
- [x] `mix precommit` passes, with resulting generated changes reviewed.
- [x] No game implementation or new dependencies were introduced in this phase.
- [x] [handoff.md](handoff.md) records evidence and the next entry commands.

Do not infer deployed readiness from the local gate. Phase 01 begins by checking
this baseline and then introduces the first game behavior.
