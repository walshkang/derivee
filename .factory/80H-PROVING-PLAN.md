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
- Stop means no retry, no resume. Run recon (`loops/templates/recon-brief.md`),
  re-scope, re-price.
- A new dispatch on the same problem requires the recon output **and** Walsh's
  explicit word naming the wave.

## 2. Budget rationing

- Hard cap ~12M tokens for the 80h window. Every dispatch is logged against it.
- Empirical priors per wave: surgical 150–250k, cross-cutting 500k–1M,
  read-only recon ≤50k, free orchestrator CLI recon first.
- `--budget` is mandatory (launcher refuses without it). No priced contract =
  no dispatch. No exceptions.

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

- [ ] Priced contract: one theme, named files/dirs, numeric budget, kill conditions
- [ ] Recon done (template Phase 1; Phase 2 only if blast radius still unknown)
- [ ] Attempt count on this problem < 3, or recon + re-scope complete after a stop
- [ ] Budget fits inside the remaining 80h allocation
- [ ] Walsh named the wave (new surface) or it is convergence work (§3)

## 7. Success criteria (judged at end of window)

- Failure burn < 30% of period total (vs 79% trailing 7d)
- Zero 4+ attempt chains
- Stopid fix device-accepted; ledger device-pending count reduced

## 8. If the budget breaks early

Factory halts. No waves until the weekly reset. Free work (recon, planning,
brief-writing) continues. The halt itself is a finding: the design failed the
proving period.
