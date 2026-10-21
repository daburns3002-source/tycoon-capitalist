# Roadmap

Nine phases. Each one ends in something playable or verifiable, and nothing in a later phase is
allowed to be a prerequisite for an earlier one. Playtest gates are marked **PLAYTEST**.

---

## Phase 0 — Infrastructure ✅

Repo, toolchain, CI, branch protection, rulebooks, research teardown. No game code.

**Done when:** CI is green, `main` is protected, Codex can comment on a PR.

---

## Phase 1 — The number system and the economy core

No visuals at all. This phase is pure maths and tests.

- `BigNumber` — mantissa/exponent type with add, sub, mul, div, pow, compare, normalise
- `Format` — short-scale names (K, M, B, T, then quadrillion → uncentillion) matching the source
- `Config/Businesses.luau` — the exact Earth table from `RESEARCH-advcap.md`, frozen
- `Economy/Cost.luau` — `unitCost(n)`, `bulkCost(owned, k)` via the geometric series
- `Economy/Cycle.luau` — milestone halving at 25/50/100/200/300/400, per-business and all-business
- `Economy/Revenue.luau` — linear scaling, upgrade multipliers, angel multiplier
- `Economy/Angels.luau` — `floor(sqrt(lifetime/divisor) - sqrt(previous/divisor))`
- `tests/` — assertions against values read out of the real game

**Done when:** tests prove the 2nd Car Wash costs $829.92, 100 Oil Companies cost
$319,433,276,243,943, $1 quadrillion lifetime yields 150 angels, and 400-of-everything puts the
Oil Company cycle at ~9s. Verified against the Steam build.

---

## Phase 2 — One plot, one building, walkable  **PLAYTEST**

The feel test. Grey boxes only.

- A low-poly plot with a spawn, ground and boundary
- Avatar walks it on desktop, touch and gamepad
- One business building (Lemonade Stand) with a working production cycle
- Tap/click/proximity to collect; a cash counter that ticks
- Buy-one button, unit count visible, building geometry grows at thresholds

**Done when:** it is fun to tap for sixty seconds on a phone and on desktop. If it is not, the
interaction model changes here and not three phases later.

---

## Phase 3 — All ten businesses, managers, upgrades  **PLAYTEST**

- All ten Earth businesses placed on the plot, scaled so walking between them reads well
- x1 / x10 / x100 / max buy modes
- Managers purchasable; a managed business runs itself
- Cash upgrades (the ×3 multipliers)
- Milestone halving with loud feedback — this is the game's best moment and must feel like one

**Done when:** a full solo session reaches the Bank with no visuals missing and no number wrong.

---

## Phase 4 — UI pass, Steal an Egg style  **PLAYTEST**

- Typography, panel shapes, button styling, colour language matched to reference screenshots
- Business panel per building; HUD; buy-mode selector; number pops on collect
- Portrait and landscape layouts, safe-area aware, tested at phone, tablet and desktop sizes
- Controller and keyboard navigation

**Done when:** a screenshot of this game and a screenshot of the reference sit together without
looking like different products.

---

## Phase 5 — Persistence and offline earnings

- DataStore profiles with a version field and a migration path
- Session locking so two servers cannot write one profile
- Offline accrual computed server-side from a trusted timestamp
- Welcome-back panel showing what the managers earned while away

**Done when:** closing the game for an hour and returning pays out correctly, and a schema
change survives a migration test.

---

## Phase 6 — Angel Investors  **PLAYTEST**

- Lifetime-earnings tracking across resets
- Reset flow with a clear preview of what is kept and what is lost
- Angel upgrades, accountants, the EZ upgrader
- The +2%-per-angel multiplier applied everywhere income is computed

**Done when:** a second run reaches the old wall in a fraction of the time, and the reset reads
as a reward rather than a punishment.

---

## Phase 7 — Art pass

Blender enters here and not before. Installing it while the game is unvalidated is wasted setup.

- Low-poly building models with three to five visible growth tiers each
- Plot environment, props, skybox, lighting tuned per device tier
- Collect and purchase animations; manager idle animations
- Poly and draw-call budgets enforced per tier

**Done when:** the game looks deliberate on a mid-range phone at a stable frame rate.

---

## Phase 8 — Social layer

Scoped from the brief's team and ranked ideas. Neither exists in the source game, so both are
designed here rather than copied.

- Global and friends leaderboards on lifetime earnings
- Seasonal ranked tiers with resets
- Shared plots, if we still want them — decided with Phase 6 data in hand

**Done when:** there is a reason to come back tomorrow that is not just a bigger number.

---

## Phase 9 — Monetisation, polish, launch

- Developer products and passes that do not break the economy's pacing
- Analytics on the drop-off points
- Sound, music, loading, onboarding
- Store page, thumbnails, icon

---

## Rules about phases

- One phase per PR series. A PR states its phase; Codex checks completeness against *that* phase.
- Missing art before Phase 7 is intentional. Missing social features before Phase 8 is intentional.
- **PLAYTEST** gates are hard stops. Nothing in the next phase starts until the playtest happens.
