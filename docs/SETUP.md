# Setup — current state

Local: `C:\Dev\AdCapRoblox` (deliberately out of OneDrive — the sync client fights Rojo's file
watcher and git's index).

Source game for verification: `C:\Program Files (x86)\Steam\steamapps\common\AdVenture Capitalist`
(Steam app 346900).

## Verified on this machine

| Tool | Version | Notes |
|---|---|---|
| Git | 2.55.0 | |
| GitHub CLI | 2.102.0 | authenticated as `daburns3002-source` |
| Rokit | 1.2.0 | toolchain manager |
| Rojo | 7.7.1 | pinned in `rokit.toml` |
| Wally | 0.3.2 | pinned |
| Selene | 0.32.0 | pinned |
| StyLua | 2.6.0 | pinned |
| luau-lsp | 1.70.1 | pinned |
| Node | 24.20.0 | |
| Python | 3.12.10 | |
| Roblox Studio | installed | three versions present |
| Roblox Studio MCP | **connected** | bridge responds; one Studio instance visible |
| Blender | not installed | deferred to Phase 7, by design |

## Phase 0 done

- Repo created at https://github.com/daburns3002-source/tycoon-capitalist, **public**
- Toolchain ported forward from the `quiver` repo, which already had a green CI run
- Rojo project maps `src/{shared,server,client}` and `tests` into the DataModel
- Local gate passes end to end: `selene` clean, `stylua --check` clean, `rojo build` succeeds,
  `luau-lsp analyze` clean
- GitHub Actions CI green on the first run, 20s: Selene, StyLua `--check`, `rojo build`,
  sourcemap, `luau-lsp analyze`, artifact upload
- Branch protection on `main`, enforced for admins too — verified by a rejected direct push
- Squash-only merges, branch deleted on merge
- `CLAUDE.md` and `AGENTS.md` written as a matched pair — builder and reviewer contracts
- PR template points Codex at BigNumber correctness, economy fidelity and offline-accrual trust
- `.gitattributes` pins LF so local and CI format checks agree
- Docs: source-game teardown with exact tables, nine-phase roadmap, architecture

## Why the repo is public

GitHub refuses branch protection on a private repo without a Pro subscription. Without protection
`main` accepts direct pushes and nothing is gated at all, so public was the cheaper trade.
`quiver` is public for the same reason.

## Branch protection on `main`

| Rule | Setting |
|---|---|
| Changes must go through a PR | yes |
| Required approving reviews | 0 — Codex reviews by comment, and GitHub will not let you approve your own PR |
| Required status check | `Lint, format and build`, strict (branch must be up to date) |
| Conversation resolution | required — no *open* thread can be left unresolved at merge |
| Linear history | required |
| Force pushes / deletions | blocked |
| Applies to admins | **yes** — verified by a rejected direct push as the repo owner |

### What this actually enforces, and what it does not

Worth being precise, because it is easy to assume more than is true. Codex raised this on the PR
that added this section, and it was right.

**Enforced by GitHub:** every change goes through a PR; `main` rejects direct pushes even from the
owner; CI must be green and the branch must be up to date; no force pushes; no merge commits; and
any review thread that *exists* must be resolved before merging.

**Not enforced by GitHub:**

- **That a review happened at all.** With zero required approvals, a PR that Codex never comments
  on satisfies every rule above and merges clean. Codex posts reviews and comments, not check
  runs, so there is nothing to add as a required status check.
- **That a finding was addressed rather than dismissed.** The PR author has write access, so they
  can resolve their own threads. Conversation resolution stops a thread being *forgotten*; it
  cannot tell the difference between fixed and waved away.

So the review gate is a convention, not a mechanism. The things that genuinely cannot be skipped
are CI and the no-direct-push rule — which is why the project's own rules are machine-checked in
CI (`scripts/guard.py`) rather than left to a reviewer's attention.

Required approvals stays at **0** deliberately: GitHub will not let the repo owner approve their
own PR, so any non-zero count would deadlock every PR on a solo project. The alternative worth
revisiting if this ever gets a second human is `required_approving_review_count: 1` with
CODEOWNERS.

### Emergency bypass

*You cannot push to `main` directly*, by design. To bypass:

```bash
gh api -X DELETE repos/daburns3002-source/tycoon-capitalist/branches/main/protection/enforce_admins
```

Re-enable it with `-X POST` on the same path.

## Blocked on you

### 1. Publishing, before persistence can be trusted

**This is the one that matters.** `game.PlaceId` is 0 -- the place has never been published --
and DataStores are keyed to a universe, so Studio reports:

```
You must publish this place to the web to access DataStore.
```

Enabling *Studio Access to API Services* alone will not help; there is nothing for it to point
at. Both steps are needed, in order:

1. **File > Publish to Roblox As...** Private by default, so nobody can find or join it.
2. **File > Game Settings > Security > Enable Studio Access to API Services**, then Save.

Deferred by choice -- the user does not want to publish yet. Until then, see the warning below.

### 2. Reference screenshots for the UI

The Steal An Egg look was built from the game's store art and gameplay footage rather than from
the live game, since web search could not identify the typeface. If an exact font match matters,
Roblox renders only built-in font enums unless a font asset is uploaded, so that is the route.

### 3. Codex usage limits

Codex hit its code-review usage cap partway through Phase 3. Reviews stop until it resets, and
`CLAUDE.md`'s rule is not to merge before Codex has actually reviewed -- so a run of commits on
PR #3 is unreviewed.

## Untested, and known to be

**The save path has never run.** Serialisation round-trips and offline accrual are covered by
152 assertions, but every one of those runs against in-memory state. The code that actually
touches a DataStore -- `Data/Profiles.luau` -- has only ever executed its failure branch, because
Studio cannot reach a DataStore for an unpublished place.

Still untested without publishing:

- that a profile written on one session is read back on the next, through Roblox's DataStore
  rather than the fake
- autosave on its interval, and the `BindToClose` write
- a welcome-back card driven by a real absence rather than a remote fired by hand

**The session lock is now tested**, against an in-memory fake rather than a real DataStore.
`Profiles.configure` injects a store, a job id and a clock, so the suite drives the whole
protocol -- a lock taken, a second server refused and given no data, its write abandoned, the
lock aged past its timeout and taken, the losing server abandoning its next write, a clean
release, and the next server loading immediately. Twenty assertions.

That leaves only the parts that genuinely need a published universe: that Roblox's own
`UpdateAsync` behaves as the fake assumes, autosave on a timer, and `BindToClose`.

## Deferred, deliberately

**Blender** — Phase 7. Installing it before the economy and the loop are validated is wasted
setup. When we get there: `winget install BlenderFoundation.Blender`, then
`claude mcp add blender uvx blender-mcp`, then enable the *Interface: Blender MCP* add-on and
start the server from the N-panel in the viewport.

**Moon and Mars business tiers, seasonal events** — Earth's ten businesses only. The later tiers
are more of the same maths and add nothing to validate.

## Note on the two parked projects

`C:\Dev\PhasmoRoblox` and `C:\Dev\ArcheroRoblox` are both fully scaffolded and both stopped before
a playable loop existed. This repo reuses their infrastructure precisely so that Phase 0 cost
under an hour rather than a day, and so the first real session can go straight at Phase 1 and
Phase 2 — the number system and something walkable you can actually hold.

Phase 2 is the first **PLAYTEST** gate for a reason: if tapping a building for sixty seconds is
not fun, that is worth discovering in week one.
