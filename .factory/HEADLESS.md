# Headless Agent Dispatch Protocol

**Purpose:** Operational rules for running `agy headless` on a remote VM (e.g. Muse,
Oracle Cloud ARM, or any persistent Linux/macOS agent) to advance the Dérivée roadmap
while Walsh is away.

> [!CAUTION]
> Trailing 7d evidence (2026-10-04): 79% of tokens burned on failed/killed waves.
> Unattended agents amplify this. Every rule below exists to prevent spiral burns.

---

## 1. Environment Classification & Platform Division of Labor

> [!IMPORTANT]
> **Core Division of Labor:**
> - **Headless VM (Linux/Cloud VM / Muse):** Exclusively for the **PWA** ([`DeriveeWeb/`](../DeriveeWeb)), the Go Observer ([`observer/`](../observer)), GIS/pack compiler scripts ([`scripts/`](../scripts)), and documentation/schemas. All code must be verified with headless terminal commands (`tsc`, `vitest`, `go test`, `pytest`).
> - **Local Mac (Apple Silicon macOS):** Exclusively for **Native iOS** ([`DeriveeNative/`](../DeriveeNative)), Xcode builds, iOS Simulator ergonomics tests (`verify-ux.sh`), Metal shaders, and direct-to-main development.

| Environment | Platform | Can Build iOS? | Can Run Simulator? | Target Subsystems | Allowed Scope Tier |
|---|---|---|---|---|---|
| `local-mac` | Apple Silicon Mac | ✅ | ✅ | **Native iOS** (`DeriveeNative/`, `DeriveeCore/`), Metal, Simulator | `mechanically-computable` or `visual-sensory` |
| `headless-vm` | Linux VM / Cloud | ❌ | ❌ | **PWA** (`DeriveeWeb/`), Go Observer (`observer/`), GIS (`scripts/`) | `mechanically-computable` only |

**Headless VMs are strictly restricted to `mechanically-computable` scope tier.** This means:
- ✅ **The PWA** (`DeriveeWeb/`): TypeScript (`tsc --noEmit`), unit & worker tests (`vitest run`), Vite bundling, Service Worker, OPFS pipelines, and WASM bindings
- ✅ **Go Observer** (`observer/`): `go build`, `go test`, `go vet`
- ✅ **GIS pipeline & pack compiler scripts** (`scripts/`): Python tests, pack compiler (`pack_builder`), data generation
- ✅ **Documentation, schemas, `.factory/` contracts**
- ❌ **Native iOS** (`DeriveeNative/`): SwiftUI screens, sheets, navigation, or map interactions (requires Xcode/macOS)
- ❌ **Metal shaders, MapLibre custom layers, fog engine** (requires Metal/macOS)
- ❌ **iOS Simulator tests** (`DeriveeSnapshotTests`, `verify-ux.sh`) (requires macOS Simulator runtime)
- ❌ **C++20 Swift interop** (`DeriveeCore/`) — requires Xcode/Apple Clang toolchain

---

## 2. Branch Isolation (Mandatory for Headless)

Headless agents **never push directly to `main`**. Two delivery modes:

### 2a. `wave-branch` (preferred)
```bash
git checkout -b wave/<wave_id>
# ... agent works ...
git push origin wave/<wave_id>
```
Walsh reviews and merges (or cherry-picks) when back at the Mac.

### 2b. `patch-only` (minimal footprint)
```bash
git diff > .factory/diffs/<wave_id>.patch
```
No commits, no pushes. Walsh applies the patch manually:
```bash
git apply .factory/diffs/<wave_id>.patch
```

### Direct-to-main
Only permitted when `environment: local-mac` **and** Walsh is present and has
explicitly named the wave. This is the existing "vibe coding" workflow.

---

## 3. Circuit Breaker Rules

These carry forward from `80H-PROVING-PLAN.md` and are **non-negotiable**:

1. **Max 3 code-modifying attempts per problem.** After the 3rd failure: halt, emit
   receipt with `kill_reason: "attempt-limit"`, write diagnostic.
2. **Recon passes don't count as attempts.** Read-only exploration is free and
   encouraged — burn recon tokens, not execution tokens.
3. **Kill mispriced contracts immediately.** If a wave produces zero code within 25%
   of its budget, halt with `kill_reason: "budget-exceeded"`. Never retry an identical
   contract — re-scope first.
4. **Token budget is a hard wall.** The `budget_tokens` field in the execution brief
   is not advisory. Agent must track consumption and halt before exceeding it.
5. **Timeout is a hard wall.** `timeout_minutes` in the brief triggers immediate
   receipt emission and halt.

---

## 4. Recon-First, Code-Second

Before any code-modifying dispatch, the orchestrator should run a **free recon pass**:

1. Agent reads the codebase, maps the blast radius, identifies symbols.
2. Agent writes `recon_output` into the execution brief:
   - `blast_radius_files`: files that will need modification
   - `symbols_mapped`: key functions/types/modules involved
   - `open_questions`: anything requiring Walsh's judgment call
3. Walsh reviews the brief (30 seconds), greenlights or kills.
4. **Only then** does the code-modifying wave dispatch.

This prevents the #1 burn pattern: agents exploring the codebase on the clock while
simultaneously trying to write code.

---

## 5. Dispatch Checklist (Every Wave)

Before dispatching any wave (headless or local), the orchestrator must verify:

- [ ] `active_brief.json` validates against `schemas/execution_brief.schema.json`
- [ ] `environment` matches the actual execution context
- [ ] `scope.tier` is `mechanically-computable` if `environment` is `headless-vm`
- [ ] `branch_policy` is `wave-branch` or `patch-only` if `environment` is `headless-vm`
- [ ] All `scope.verification_commands` can actually run in the target environment
- [ ] `limits.budget_tokens` is priced from evidence (see 80H-PROVING-PLAN.md §2)
- [ ] `kill_conditions` list is non-empty
- [ ] `approved_by` is set (`walsh-explicit` or `convergence-list`)

---

## 6. Receipt Protocol

Every wave — successful or not — must emit a receipt:

```bash
# Receipt lands at:
.factory/receipt.json           # latest (overwritten each wave)
.factory/diffs/<wave_id>.patch  # if patch-only or wave-branch
```

The receipt **must** validate against `schemas/execution_receipt.schema.json`.
New required fields for headless tracking:
- `environment`: `"headless-vm"` or `"local-mac"`
- `branch_policy`: how the output was delivered
- `branch`: the wave branch name (or null)
- `kill_reason`: structured reason if status is `"killed"`
- `attempts_used`: code-modifying attempts consumed

Use `.factory/bin/emit-receipt.py` to emit receipts, or pass `--validate-only` to verify an existing receipt.

---

## 7. What Good Headless Work Looks Like

### Example: Observer reliability engine improvements
```json
{
  "wave_id": "observer-reliability-smoothing",
  "environment": "headless-vm",
  "scope": {
    "tier": "mechanically-computable",
    "allowed_paths": ["observer/**"],
    "verification_commands": ["go build ./...", "go test ./... -race -count=1"]
  },
  "limits": {
    "budget_tokens": 400000,
    "max_attempts": 1,
    "timeout_minutes": 30
  },
  "branch_policy": "wave-branch",
  "acceptance": [
    "go test passes with zero failures",
    "Reliability smoothing window produces monotonically decreasing variance"
  ],
  "kill_conditions": [
    "Any file outside observer/ is modified",
    "Token burn exceeds 400k",
    "go test fails after first code-modifying attempt"
  ],
  "approved_by": "walsh-explicit"
}
```

### Anti-pattern: What NOT to dispatch headless
```json
{
  "wave_id": "transit-sheet-animation-fix",
  "environment": "headless-vm",
  "scope": {
    "tier": "visual-sensory",
    "allowed_paths": ["DeriveeNative/**"]
  }
}
```
❌ This will fail schema validation: `headless-vm` + `visual-sensory` is prohibited.

### Terminal state: harness green, not device-accepted

A headless wave is done when the **Playwright harness is green** — the harness
drives every shipped user flow against the built bundle and the ledger
regenerates with harness ✅. That is the terminal state for unattended work.

**Device acceptance stays Walsh's explicit gate.** The ledger's device tier
remains `pending` until he accepts on his phone; a headless wave MUST NOT mark
device ✅, and no headless wave is "done done" until he does. The receipt
records the harness outcome; the morning surface reports harness-green waves
as awaiting device acceptance.
