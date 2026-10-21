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

- Toolchain ported forward from the `quiver` repo, which already had a green CI run
- Rojo project maps `src/{shared,server,client}` and `tests` into the DataModel
- Local gate passes end to end: `selene` clean, `stylua --check` clean, `rojo build` succeeds,
  `luau-lsp analyze` clean
- `CLAUDE.md` and `AGENTS.md` written as a matched pair — builder and reviewer contracts
- PR template points Codex at BigNumber correctness, economy fidelity and offline-accrual trust
- `.gitattributes` pins LF so local and CI format checks agree
- Docs: source-game teardown with exact tables, nine-phase roadmap, architecture

## Blocked on you

### 1. Open a place in Roblox Studio

The Studio MCP bridge is connected and I can see one Studio instance, but no place is open, so
`get_studio_state` returns "Place is not open". Open any baseplate and I can drive playtests,
read the console and take screenshots from Phase 2 onward.

Then install the **Rojo** plugin in Studio if it is not already there, so `rojo serve` can sync.

### 2. Connect Codex to the repo

Authorise Codex on `github.com` for `daburns3002-source/tycoon-capitalist`. Reviews then land as
PR comments I can read and act on directly. Conversation resolution is a required check on `main`,
so Codex's findings gate the merge rather than being advisory.

### 3. Reference screenshots for the UI

The brief asks for Steal an Egg's UI and font. Web search could not identify the typeface and the
Roblox discover page would not load its results headlessly, so I need to see it: a few screenshots
of the HUD, a shop or upgrade panel, and a button, or just the game's Roblox link.

This matters more than it sounds. Roblox only renders its built-in font enums unless a font asset
is uploaded, so matching a custom typeface may mean uploading one — worth knowing before Phase 4.

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
