# Tycoon Capitalist — reviewer rulebook

This repo is built by Claude and reviewed by Codex. This file is the review contract.
The builder's rulebook is `CLAUDE.md`; the two must not contradict each other.

Design reference: `docs/RESEARCH-advcap.md`. Phase plan: `docs/ROADMAP.md`.

## What this project is

**AdVenture Capitalist's exact economy inside a low-poly walkable Roblox tycoon.**

Ten businesses stand on a plot as buildings that grow with their unit count. Tap to collect, buy
units, hit a milestone and the cycle time halves, hire a manager and it goes passive, reset for
Angel Investors when growth flattens.

The economy is a copy and must be exact. The 3D plot, art direction and social layer are new.

## Review priorities, in order

**1. Number overflow and precision.**
This is the highest-value thing to catch in this project. Prices in the source game reach ~2^1024;
a Luau `number` is a float64 that goes `inf` just past that and loses precision far earlier. Any
money value — cash, cost, revenue, lifetime earnings, a compounding multiplier — that is held or
combined as a raw Luau number instead of a `BigNumber` is a **blocking** finding, every time,
including in test code and UI formatting. Flag mixed arithmetic too: a `BigNumber` multiplied by a
raw number without going through the module's API.

**2. Economy fidelity to the source game.**
Check the implementation against the tables in `docs/RESEARCH-advcap.md`:

- `unitCost(n) = initialCost * coefficient^(n-1)` — note the `n-1`; an off-by-one here is silent
- Bulk cost is the geometric series `initialCost * c^N * (c^k - 1) / (c - 1)` and gives **no
  discount** versus k single buys
- Revenue scales **linearly** with units, cost **geometrically**. If revenue compounds anywhere,
  the entire difficulty curve is wrong
- Cycle halving at 25/50/100/200/300/400 per business, **and again** for every business each time
  all ten cross one of those marks; twelve halvings maximum, floor of 1/4096
- Angels: `floor(sqrt(lifetime/divisor) - sqrt(previous/divisor))`, `divisor = 400e9/9`
- Each angel is **+2% additive**, not multiplicative
- Angel upgrades and accountants are **lost on reset**; the angels spent are gone permanently

A wrong constant or a wrong exponent is blocking. These are copied values with a known-correct
answer, so there is no judgement call to make.

**3. Exploitability.**
An idle game is pure currency, so it is pure exploit surface. Flag any path where a client can
influence cash, unit counts, collection timing, manager state, upgrades, angels, lifetime earnings
or offline accrual. Remotes validate type, range and ownership on every argument. A client that
reports its own collection, elapsed time or cash total is blocking.

Offline earnings deserve specific attention: elapsed time must come from a server-trusted
timestamp, never from the client, and must be clamped.

**4. Purity of the economy and config layers.**
`src/shared/Economy` and `src/shared/Config` must not require a Roblox service, touch an instance,
hold mutable state or read the clock. Config modules are pure data, `table.freeze`d, no functions.
A service require in there is blocking — it destroys testability, which is the only reason the
fidelity claims above are checkable at all.

**5. Singleton state.**
Progression must live on a per-player plot record. A module-level `currentPlot`, a global cash
variable or a single player reference is blocking even though shared plots are Phase 8.

**6. Save-schema safety.**
Any change to persisted data needs a version bump and a migration path. In an idle game the save
file *is* the player's entire investment, so an unmigrated schema change is blocking. Also check
session locking — two servers writing one profile loses progress.

**7. Performance under load.**
Ten businesses times hundreds of units, ticking. Flag per-frame allocations, per-unit instances
where one instance with a count would do, unbounded instance creation, uncleaned connections, and
anything that scales with unit count rather than business count.

**8. Device tiering.**
Hard-coded poly counts, particle counts, draw distances or shadow settings that ignore the
resolved device tier. The brief requires this to run well on phones.

**9. Correctness and clarity.**
Normal code review.

## Conventions to enforce

- `--!strict` on every Luau file
- `game:GetService()` at file top
- `PascalCase` modules and types, `camelCase` locals and functions
- `task.*`, never `wait` / `spawn` / `delay`
- Every `:Connect` has a disconnect path
- Balance values in `src/shared/Config`, not inline
- StyLua and Selene are CI-enforced, so do not spend review on formatting

## What not to flag

- Formatting. CI handles it.
- Missing art, audio or VFX before Phase 7. Grey boxes are intentional until then.
- Missing social, ranked or shared-plot features before Phase 8.
- Missing Moon and Mars business tiers, and the seasonal events. Earth only, by design.
- Missing content ahead of its phase. Check the PR's phase label against `docs/ROADMAP.md`
  before calling something incomplete.

## Review format

Leave findings as inline PR comments. Mark each one **blocking** or **non-blocking**. For blocking
findings, state the concrete failure: the input, the state, and the wrong outcome. For an economy
fidelity finding, quote the expected value from `docs/RESEARCH-advcap.md`.
