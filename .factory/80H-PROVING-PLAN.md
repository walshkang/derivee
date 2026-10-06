# 80-Hour Proving Plan

**Window:** 2026-10-04 21:30 EDT → 2026-10-08 ~05:30 EDT
**Budget:** 25% of weekly remaining (~12M tokens estimated — correct if the limit differs)

## Why this exists

Trailing 7d: 13.9M tokens burned on failed/killed waves vs 3.7M on success
(79% failure burn, 32 killed vs 12 green). The factory is a prototype, not a
machine. These 80 hours prove whether the design works under rationing — or
the design itself needs rethinking.

## 1. Circuit breaker (the core rule)

- Max **3 attempts per problem**. After the 3rd failure/kill: mandatory stop.
- An **attempt** is any dispatch where code modification is in scope.
  Read-only recon waves and orchestrator CLI runs do **not** increment the
  counter — reconnaissance is never rationed, only execution is.
- Stop means no retry, no resume. Run recon (`loops/templates/recon-brief.md`),
  re-scope, re-price.
- Kill, don't retry, a mispriced contract: after a zero-code budget-exceeded
  attempt, the next dispatch must be a rescope/reprice or a kill — never an
  identical retry of the same contract. (The 3-attempt retry presumes resumed
  partial work; with zero code written there is nothing to resume.)
- A new dispatch on the same problem requires the recon output **and** Walsh's
  explicit word naming the wave.

## 2. Budget rationing

- **Operational target: ≤1.5M tokens for the entire 80h window.** The active
  scope is one Gate 4 plus batched device acceptance — if convergence burns
  anywhere near the ceiling, the factory has failed the test early.
- **Emergency ceiling: ~12M tokens.** Hard cap; every dispatch is logged
  against it. If device feedback surfaces more than 2 batched waves, stop and
  triage rather than burning the ceiling down.
- Empirical priors per wave: surgical 150–250k, cross-cutting 500k–1M,
  read-only recon ≤50k, free orchestrator CLI recon first.
- `--budget` is mandatory (launcher refuses without it). No priced contract =
  no dispatch. No exceptions.
- Check the rolling burn before sizing a wave: `bin/agy-window.py`
  (trailing 1h/5h/24h) — local estimation against the 5-hour rate limit.

## 3. Allowed work — convergence only

1. **Gate 4 on the realtime stopid fix** (commit `55d4d4f`): `tsc --noEmit`,
   targeted tests, harness Live-badge assertion (❌→✅ — must assert the badge
   positively, missing `gtfs_id` degrades silently to Scheduled), ledger regen,
   deploy + served-bundle verification.
2. **Device acceptance:** 11 ledger scenarios are harness-green / device-pending.
   Batch the checks into one round, one acceptance ask per round with named
   evidence.
3. Nothing else dispatches without Walsh explicitly naming it.

## 4. Deferred — no waves for 80h

- OPFS: recon only. Zero fix waves into the tar pit.
- New features / roadmap surface: none.
- leg-detail v2-resume chain: paused. Recon + re-scope before any redispatch.

## 5. Device feedback batching

- Device notes are collected and triaged together.
- One wave per batch — never one wave per screenshot.
- Never ask for a retest without a new build or new diagnostic.

## 6. Dispatch checklist (orchestrator, every wave — no dispatch without all)

- [ ] Contract priced: one theme, named files/dirs, explicit budget, kill conditions
- [ ] Mode selected: cold (`agy-run`) for fresh waves/recon; warm (`agy-warm`)
      ONLY for immediate red→green iteration on active work
- [ ] Recon verified: Phase 1 CLI blast radius complete; Phase 2 recon wave only
      if symbols/paths remain unknown (recon never counts as an attempt)
- [ ] Attempt count on this problem < 3 (code-modifying waves only)
- [ ] Budget check: fits operational target (≤1.5M convergence) and emergency
      ceiling (12M); rolling burn checked via `bin/agy-window.py`
- [ ] Invariant check: test spec requires positive state assertion — assert the
      target state (e.g. Live badge with real-time ETA text), never merely the
      presence of a container or absence of an error (silent fallbacks fail this)
- [ ] Approval check: Walsh named the wave, or it is explicitly listed
      convergence work (§3)

## 7. Success criteria (judged at end of window)

- Failure burn < 30% of period total (vs 79% trailing 7d)
- Zero 4+ attempt chains
- Stopid fix device-accepted; ledger device-pending count reduced

## 8. If the budget breaks early

Factory halts. No waves until the weekly reset. Free work (recon, planning,
brief-writing) continues. The halt itself is a finding: the design failed the
proving period.
