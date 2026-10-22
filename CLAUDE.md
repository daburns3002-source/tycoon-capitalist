# Tycoon Capitalist — builder rulebook

This repo is built by Claude and reviewed by Codex. This file is the build contract.
The reviewer's rulebook is `AGENTS.md`; the two must not contradict each other.

Design reference: `docs/RESEARCH-advcap.md`. Phase plan: `docs/ROADMAP.md`.
Architecture: `docs/ARCHITECTURE.md`. Setup state: `docs/SETUP.md`.

## What this project is

**AdVenture Capitalist's exact economy inside a low-poly walkable Roblox tycoon.**

**The AdVenture Capitalist panel is the game; the plot is the shell around it.** The player walks
up to a board on their plot, clicks into it, and the full idle game opens as a screen-filling
panel: ten business rows, tap to collect, buy units, hit a milestone and watch the cycle time
halve, hire a manager to make it passive, reset for Angel Investors when growth flattens.

The buildings on the plot grow with their unit counts as a *display* of progress. No mechanics
hang off them -- the panel is the single authoritative surface for the economy.

The economy is copied to the digit. The 3D plot, the art direction and the social layer are new
design work — the source game has no movement, no items, no teams and no ranked ladder.

## Where we are

Phase 1 complete: the number system and the economy core. `src/shared/Economy` holds BigNumber,
Format, Cost, Cycle, Revenue and Angels; `src/shared/Config/Businesses.luau` holds the exact
Earth table. All pure.

Phase 2 **built, verified in Studio, not yet playtested by a human**: a grey-box plot with a
board, server-authoritative plot state, a production tick, and the panel. The economy suite runs
green in Studio (103 assertions) and the loop has been driven end to end through the remotes, but
nobody has judged how it *feels*.

Phase 4's styling foundation landed early, on request: `UI/Theme` and `UI/Bubbly` carry the
Steal An Egg look -- stroked type, sticker buttons, icon chips, gradient numbers, press pops.
The rest of Phase 4 (layouts per device, number pops on collect, sound) is still ahead.

Next: run the Phase 2 playtest. Then Phase 3, all ten businesses. See `docs/ROADMAP.md`.

## Commands

```bash
rokit install                    # install the pinned toolchain
wally install                    # install packages
rojo serve                       # live-sync into Studio
rojo build -o build.rbxl         # build a place file
selene src tests                 # lint
stylua src tests                 # format
stylua --check src tests         # what CI runs
python scripts/guard.py          # the project's own non-negotiables, machine-checked
python scripts/verify_economy.py # re-derive every economy anchor from the config
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --defs=globalTypes.d.luau src tests
```

Run the lint, format, type-check and build locally before opening a PR. CI runs exactly these.

## Tests

The economy layer is pure, so it is genuinely unit-testable and there is no excuse for it not to
be. `tests/` holds plain Luau assertion modules that CI type-checks and that run headlessly.

Every economy function gets a test with a value verified against the real game. "It looks right"
is not a test. The source game is installed at
`C:\Program Files (x86)\Steam\steamapps\common\AdVenture Capitalist` — open it and read the number.

Known-good anchors to keep in the suite:

| Assertion | Expected |
|---|---|
| 2nd Car Wash unit cost | $820.80 |
| First 100 Oil Companies, total | $319,433,276,243,943 |
| First angel at lifetime earnings | ~$44,444,444,445 |
| $1 quadrillion lifetime to angels | 150 |
| $1 quintillion lifetime to angels | 4,743 |
| $1 sextillion lifetime to angels | 150,000 |
| $1 septillion lifetime to angels | 4,743,416 |
| 400 of every business, Oil cycle | exactly 9 s (36864 / 2^12) |
| Lemonade Stand displayed 2nd price | $4.00 (base 4/1.07) |

**The wiki is wrong about the Car Wash.** It states the second unit costs $829.92, which is
728 × 1.14; the initial cost is 720, so the correct price is 720 × 1.14 = **$820.80**. Do not
re-copy that figure. It is a reminder that the wiki is a secondary source and the Steam build
is the primary one — when they disagree, open the game.

The angel reference points all reproduce exactly from `floor(sqrt(lifetime / (400e9/9)))`, and
the 100-Oil-Company series reproduces to the dollar, so those parts of the wiki are sound.

## Non-negotiables

**1. All money is a BigNumber. Always.**
Costs in this game legitimately reach ~2^1024. A Luau `number` is a float64: it overflows to
`inf` just past that and loses precision long before. Cash, revenue, cost, lifetime earnings and
every multiplier that compounds go through `Shared.Economy.BigNumber`. A raw `+` or `*` on a money
value is a bug, not a shortcut — it is the one mistake that forces a rewrite of everything.

**2. The economy layer is pure.**
`src/shared/Economy` and `src/shared/Config` must not require a Roblox service, touch an instance,
hold mutable state or read the clock. Given inputs they return outputs. This is what makes them
testable and what makes "identical to the source game" a checkable claim rather than a hope.

**3. Server authority on everything that matters.**
Cash, unit counts, managers, upgrades, angels, lifetime earnings, offline accrual, persistence.
The client renders buildings and predicts timer fills; the server decides every number. Assume
every client is hostile — an idle game is pure currency, so it is pure exploit surface.

**4. Balance values live in `src/shared/Config`, never inline.**
The business table is data copied from the source game. Tuning is editing a frozen data module,
never editing logic. Config modules are `table.freeze`d and contain no functions.

**5. Plot-shaped state from day one.**
Progression lives on a plot record keyed by player, not in module-level globals, even while the
game is solo. Retrofitting shared plots or cross-server ranked onto singleton state is how this
kind of project dies in Phase 8.

**6. Device tiering is a first-class concern.**
Poly budgets, draw distance, shadows, particles and building detail read from a tier resolved at
join. "Easily accessible from multiple devices" is in the brief, so a phone and a desktop run the
same code with different numbers — not a desktop game with a phone apology.

**7. Strict Luau, everywhere.**
`--!strict` at the top of every file. Selene, StyLua and `luau-lsp analyze` gate every PR.

**8. Studio is not a source of truth.**
Nothing is authored by hand in Studio. If it matters, it is a file in this repo. Studio is a
renderer and a test harness, driven through Rojo and the Studio MCP server.

## Code conventions

- `PascalCase` for modules and types, `camelCase` for locals and functions
- `game:GetService()` calls at file top, assigned to locals
- One module, one responsibility; prefer a new file over a growing one
- Explicit return types on exported functions
- Underscore-prefixed names for intentionally unused arguments
- No `wait()`, no `spawn()`, no `delay()` — use `task.*`
- Every `:Connect` has a disconnect path; every instance created has a destroy path

### A luau-lsp trap worth knowing

String-literal unions (`BuyMode`, `DeviceTier`) lose their literalness in the pinned luau-lsp in
two places:

- **Narrowing an optional one widens it to `string`.** Both `if m == nil then return end` and
  `if m then return m end` discard the type, so the value then fails every downstream check.
- **A declared multi-return annotation is not applied to the inferred branches**, so a helper
  typed `(BuyMode, boolean)` hands back a union of four widened strings.

What does work: assigning a literal to a local with an explicit annotation, and a definite value
plus a flag instead of an optional. `Handlers.onBuyUnits` and `Device.tier` are both written that
way on purpose and say so in comments — the tidier spelling is the broken one.

## Workflow

1. Work on a branch. `main` is protected and rejects direct pushes, including from the owner.
2. One phase per PR series. The PR template asks for the phase — fill it in.
3. Open the PR, let CI run, let Codex review.
4. **Do not merge before Codex has actually reviewed.** Branch protection cannot enforce this:
   with zero required approvals a PR Codex never commented on merges clean, and Codex posts
   reviews rather than check runs so there is nothing to require as a status check. This step is
   a rule, not a gate.
5. Resolve every Codex conversation before merge — that part *is* a required check. But resolving
   a thread is not the same as fixing the finding, and nothing stops the author doing the former
   without the latter. Reply saying what changed, or say why it did not.
6. Squash merge, delete the branch.
7. At a **PLAYTEST** gate in the roadmap, stop and hand the build over. Do not start the next
   phase on the assumption that the playtest will pass.

## Repo layout

See `docs/ARCHITECTURE.md`.
