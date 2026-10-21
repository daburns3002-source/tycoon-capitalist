# Tests

The economy layer is pure -- no services, no instances, no clock, no RNG -- so testing it needs
nothing more than calling a function and comparing the answer. `TestRunner.luau` is a 120-line
assertion harness rather than a dependency, because a test framework with its own Wally entry,
runner and config file is a thing to maintain rather than a thing that helps.

## Running the suite

CI type-checks these files but cannot execute them: there is no Luau runtime in the workflow and
`require(script.Parent)` needs a DataModel. Two ways to actually run them:

**In Studio** -- `rojo serve`, connect, then in the command bar:

```lua
require(game.ServerStorage.Tests["Economy.spec"]).run()
```

Or via the Studio MCP server, which is how this is normally driven.

**In CI** -- `scripts/verify_economy.py` independently re-derives every anchor value at 50-digit
decimal precision, reading the constants straight out of `src/shared/Config/Businesses.luau`. It
does not execute the Luau, so it cannot catch a logic bug; it does catch a typo'd constant, a
transposed digit or a drifted coefficient, which is the failure mode that would otherwise reach a
playtest silently.

Both run. Neither alone is enough.

## What the anchors are

Values with a known-correct answer, from the Steam build or derived from the formulas in
`docs/RESEARCH-advcap.md`:

| Assertion | Expected |
|---|---|
| 1st Car Wash | $720 |
| 2nd Car Wash | $820.80 |
| 2nd Lemonade Stand | exactly $4.00 |
| First 100 Oil Companies | $319,433,276,243,943 |
| First angel | $44,444,444,445 lifetime |
| $1e15 / $1e18 / $1e21 / $1e24 lifetime | 150 / 4,743 / 150,000 / 4,743,416 angels |
| 50 angels | x2 all profits |
| 400 of every business | Oil cycle exactly 9s |
| 145 Banks | exactly 145x one Bank |

## The wiki is wrong about one of them

The fandom wiki states the second Car Wash costs $829.92. That is 728 x 1.14; the initial cost is
720, so the correct price is $820.80. Every other wiki figure reproduces exactly -- the angel
reference points to the digit, and the 100-Oil-Company series to the dollar -- so the table is
sound and that one worked example is not.

When a secondary source and the Steam build disagree, the build wins.
