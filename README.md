# Tycoon Capitalist

A low-poly, cross-platform Roblox tycoon built on **AdVenture Capitalist's exact economy**.

You walk a plot. Ten businesses stand on it as buildings that visibly grow as you buy units.
You tap to collect, buy units until a milestone halves the cycle time, hire a manager to make
it passive, and when growth flattens you reset for Angel Investors and do it again faster.

The economy — costs, coefficients, cycle times, milestone halving, angel math — is copied from
the source game to the digit. The 3D plot, the art direction and the social layer are new.

- Design reference: [`docs/RESEARCH-advcap.md`](docs/RESEARCH-advcap.md)
- Phase plan: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Setup state: [`docs/SETUP.md`](docs/SETUP.md)
- Builder rulebook: [`CLAUDE.md`](CLAUDE.md) · Reviewer rulebook: [`AGENTS.md`](AGENTS.md)

## Quick start

```bash
rokit install          # pins Rojo, Wally, Selene, StyLua, luau-lsp
wally install
rojo serve             # then connect from Roblox Studio's Rojo plugin
```

## The loop that builds it

Claude designs and writes; everything lands as a PR; Codex reviews; CI gates lint, format, build
and type-check; Rojo syncs into Studio; the Studio MCP server drives playtests and screenshots.
Nothing is authored by hand in Studio — Studio is a renderer and a test harness, not a source
of truth.
