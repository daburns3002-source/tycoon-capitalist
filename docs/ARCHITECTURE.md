# Architecture

## The three-agent loop

```
  Claude (Opus 5.5)          GitHub repo             Codex
  ─────────────────          ───────────             ─────
  designs + writes    ──push──▶  branch  ──PR──▶   reviews
  Luau, models, maps                                  │
        ▲                                             │
        └──────────── reads review comments ──────────┘
                             │
               CI: selene, stylua, rojo build, luau-lsp analyze
                             │
                    Rojo live-sync ──▶ Roblox Studio
                             │
                    Studio MCP ──▶ playtest, console, screenshots
```

Nobody edits anything by hand in Studio. Everything that matters is a file in the repo.

## Repo layout

```
/
├── src/
│   ├── shared/          → ReplicatedStorage.Shared
│   │   ├── Economy/         BigNumber, formatter, cost + revenue + angel math (PURE)
│   │   ├── Config/          business table, milestones, upgrades, device tiers (PURE DATA)
│   │   ├── Net/             remote definitions
│   │   └── Util/
│   ├── server/          → ServerScriptService.Server
│   │   ├── Plot/            plot state, building state, unit counts
│   │   ├── Tick/            production cycles, manager automation, offline accrual
│   │   ├── Prestige/        angel reset flow
│   │   ├── Data/            DataStore profiles, schema versions, migrations
│   │   └── Net/             remote handlers, validation
│   └── client/          → StarterPlayerScripts.Client
│       ├── Input/           touch / mouse / gamepad → one interaction model
│       ├── Camera/
│       ├── World/           building instancing, growth tiers
│       ├── UI/              HUD, business panels, buy controls, number pops
│       └── Fx/
├── tests/               pure-Luau tests for the economy; run headless in CI
├── assets/              Blender sources + export scripts
├── docs/
└── .github/workflows/   CI
```

## The three layers

**1. The economy layer (`src/shared/Economy`) is pure.** No Roblox API, no instances, no mutable
state. Given a business id, a unit count and a set of multipliers it returns numbers. This is the
only layer whose behaviour must match the source game exactly, and because it is pure it can be
unit-tested against real in-game values. Every other layer is a consumer of it.

**2. The simulation layer (`src/server`) is authoritative.** It owns cash, unit counts, managers,
upgrades, angels, lifetime earnings and persistence. It advances production cycles on a server
tick and computes offline earnings from a trusted timestamp.

**3. The presentation layer (`src/client`) is disposable.** It renders the plot, the buildings and
the UI, and predicts timer fills for smoothness. It never decides an outcome. Deleting it and
rewriting it must not change a single number.

## Why the number system comes first

AdVenture Capitalist prices reach ~2^1024. A Luau `number` is a float64 that overflows to `inf`
just past that and loses all precision long before. A tycoon built on plain numbers breaks
somewhere past the Movie Studio and every system that touched money has to be rewritten.

So Phase 1 is a `BigNumber` (mantissa + exponent, normalised on every operation) and a short-scale
formatter, both unit-tested, before anything is visible on screen.

## Device tiering

Poly budget, draw distance, shadow quality, particle counts and building detail all read from a
tier resolved once at join. A phone and a desktop run identical code with different numbers. This
is a first-class concern, not a late optimisation — "easily accessible from multiple devices" is
in the brief.

## Plot-shaped state

Even while the game is solo, progression lives on a *plot record* keyed by player, never in
module-level globals. Whether shared plots ship or not, singleton state is the standard way a
Roblox project becomes unextendable, and the cost of avoiding it now is close to zero.
