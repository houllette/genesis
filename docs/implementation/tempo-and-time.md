# Tempo and the three time domains

Tempo is selected for Genesis's testable system-clock boundary and calendar/
interval operations. It does not decide when fiction advances. The
[experience-time contract](experience-time.md) remains authoritative: local
actions, completed experiences and approved downtime supply fictional time.
Phase 03 has installed and qualified the clock boundary. Calendar/interval
integration below remains planned for phase 08, not implied by installation.

## Verified fit and adoption

Source inspected on 2026-09-04: upstream revision
`e8a074ed1efed6a0f78b87d900fc4cb0c4156278`. Its
[Mix project](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/mix.exs)
declares package **`:ex_tempo`**, version 1.6.4, Elixir `~> 1.17` and OTP 27+.
Genesis's current toolchain pins meet those declared floors. The initial review
was source inspection; phase 03 subsequently built the released Hex 1.6.4 package
successfully in dev and test. Floating HexDocs served
an older version during review, so do not mix its examples with a newer checkout.

Phase 03 pins `{:ex_tempo, "== 1.6.4"}`. Its
[handoff](03-zone-sessions/handoff.md) records the exact tested APIs, new required
transitives (astro, calendrical, localize and geo), build impact and audit evidence.
Keep this release qualification procedure for future upgrades:
The user's selection covers Tempo, not unrelated optional calendar-import or
timezone packages. Check the actual release's APIs, dependency audits, compile
cost and existing quality gates. If the required release cannot be qualified,
record the blocker instead of silently using an unpinned Git main dependency.
Do not install speculative dependencies in phase 00 or rewrite generated auth
timestamps just to make every timestamp pass through Tempo.

## Responsibility map

| Time domain | Representation and tool | Authority and limits |
| --- | --- | --- |
| Real-world recording and calendar spans | UTC `DateTime` at persistence/job boundaries; Tempo clock and interval operations where needed | Audit/gathering dates describe real time, never game progression |
| Runtime elapsed time | Explicit-unit `System.monotonic_time/1`, through an injectable shell boundary | Provider/call timeouts, elapsed latency and in-process cooldowns; never persisted as a world date or durable deadline |
| Fictional world and Experience time | Versioned world-scoped integer coordinates and durations; Tempo-backed calendar/interval conversion where supported | Zone/World validates supplied local or approved targets; no call to any `now` function chooses them |

Tempo's own [usage guidance](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/guides/when-to-use-tempo.md)
keeps instant-valued database timestamps and monotonic timing in the standard
library. It supplies span comparison, calendar arithmetic and recurrence tools;
it is not a durable job runner. Oban remains the execution/retry mechanism.

## Runtime clock and deterministic tests — phase 03

The implemented shell boundary is `Genesis.Time.Clock`, with explicit UTC
and monotonic operations. Reuse
[Tempo.Clock](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/lib/tempo/clock.ex)
instead of inventing a competing wall-clock behaviour. The production default
uses Tempo.Clock.System. For interval-shaped current-date queries use
`Tempo.utc_now/0` or `Tempo.now/1`; the UTC timestamp adapter may use
`Tempo.Clock.utc_now/0` to retain its `DateTime` and microseconds. The inspected
[current-time implementation](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/lib/tempo.ex)
truncates `Tempo.utc_now/0` to seconds. Do not round-trip audit timestamps through
that API or assume all interval operations support subsecond precision.

Read clocks in the shell and supply values to pure reducers; Core never calls
Tempo's clock, `DateTime.utc_now/0` or `System` time functions. Pure interval
operations with explicit inputs are fine. Keep dependency-specific types inside
the small adapter where practical, without wrapping every upstream function.

[Tempo.Clock.Test](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/lib/tempo/clock/test.ex)
pins/advances time in the calling process. Tests must select that clock as well
as pin it; `put/1` alone does not change the default clock. A test process's
dictionary is **not inherited** by a spawned Zone, Task or Oban worker. Pass a
test-local clock dependency to supervised children or initialize their clock
explicitly; prove they read the intended value. Avoid per-test global application
environment changes and a global test clock that breaks unconfigured children.
Inject monotonic readings separately: freezing wall time does not freeze OTP timers.

Test two concurrent callers with distinct pins, a supervised child, missing-pin
failure, microsecond timestamp preservation, and a backward wall-clock jump while
monotonic elapsed time increases. No sleeps or real clock adjustments are needed.

## Durable representation — phases 01–04

- Introduce explicit fictional coordinate/unit values in 01–02. Start with
  integer fictional seconds and a versioned epoch/calendar definition; do not
  hard-code an Earth epoch. Keep world ID, calendar version and StateScope with
  coordinates. Reject comparisons across unrelated worlds/calendars without an
  explicit validated conversion. A zero-duration event remains an event at a
  coordinate, not a Tempo interval silently widened to one second.
- Phase 04 keeps audit timestamps as UTC `DateTime`/`:utc_datetime_usec` and
  fictional occurrence/learned coordinates separate from commit-order cursors.
  Neither wall nor monotonic timestamps establish durable commit order.
- Persist only used, versioned temporal data: coordinate/unit, calendar identity,
  explicit interval bounds/resolution and recurrence policy. Reconstruct Tempo
  values through validated adapters; do not store opaque library structs or
  decode user-supplied calendar module names into atoms. Later interval features
  add their fields when used, not speculative schema in 04.
- Monotonic readings are local to a VM lifetime. Recover real deadlines from
  durable UTC deadline/policy or explicitly saved remaining duration, not a saved
  monotonic counter. Paused decision deadlines retain their remainder; provider
  timeout/retry does not advance the fictional cursor. Test restart in 04 and
  complete pause/deadline semantics in 08.

## Calendars, consequences and history — phases 08 and 14

Phase 08 uses a small pure Tempo-backed calendar adapter for supported calendar
arithmetic and interval predicates: observance/market-day windows, seasonal
modifiers, production/travel spans and the GM's timeline preview. Resolve authored
months/years from the pinned calendar and start coordinate; a month is not a
fixed number of seconds. Persist the resolved result and policy for replay.

Temporal availability uses explicit half-open intervals `[start, end)` so adjacent
windows do not overlap. Point-like due events have a separate catch-up convention:
`cursor < due_at <= target`, with stable occurrence IDs across batches and local/
incorporation processing. Test both endpoints, zero duration, adjacent intervals,
calendar rollover and chunk equivalence. Calendar non-overlap never bypasses the
MVP's conservative actor/zone claims.

Expand recurrences only to an admitted local/approved world target, with event
count and work caps plus a persisted continuation cursor. Tempo's
[scheduling guide](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/guides/scheduling.md)
requires bounded materialization; a bounded 2,000-year interval can still produce
too much work. Genesis must enforce its own caps and stable event identities.
Do not turn fictional recurrences into Oban cron or UTC `scheduled_at` dates.
Oban jobs carry scope, generation and authorized fictional target separately
from when the worker may run in real time.

Custom calendars use reviewed, allowlisted implementations and versioned world
data. Tempo's [calendar guide](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/guides/custom-calendars.md)
demonstrates Calendrical integration but also names unsupported calendar shapes.
Do not claim arbitrary fantasy calendars, moons or variable-length days work
without fixtures. Qualify one supported non-Gregorian mapping in 08; unsupported
definitions get a clear capability error, never silent Gregorian substitution.
Ordinal fictional time remains usable without enabling unsupported calendar
features. No dynamic module creation from GM input or Earth astronomy defaults
for fictional seasons. Real-world meeting availability/import is optional future
GM tooling, not a new MVP scheduling product or a driver of game time.

Phase 14 reuses these representations for eras, reigns, wars and memorial
anniversaries. A source may know an approximate date or broad period; store that
precision/uncertainty separately from the engine's exact occurrence coordinate
where known. A legend's uncertain date cannot reschedule an event or become
omniscient NPC knowledge. Test pre-epoch dates, long-history bounds, calendar
version replay and remembrance without re-executing the original event.

## Evidence carried between fresh agents

03 hands 04 the exact clock dependency/API, child-process test strategy and
wall-versus-monotonic regressions. 04 hands 05 the serialization/precision and
deadline-recovery evidence. 08 hands 09 supported calendar fixtures, interval/
recurrence bounds and the day-100 collision test with independently advanced real
clocks. 14 hands 15 long-history/uncertainty/version evidence. Each handoff names
real commands and unqualified capabilities. No source inspection or empty adapter
counts as delivered support. Phases 01–03 have executable evidence; 04 and later
must still supply their own persistence, calendar and history proofs.
