# AdVenture Capitalist — teardown

Source game: AdVenture Capitalist, Hyper Hippo / Kongregate. Installed locally at
`C:\Program Files (x86)\Steam\steamapps\common\AdVenture Capitalist` (Steam app 346900), so every
number below can be verified in-game.

## What the game actually is

A pure idle/incremental clicker. The entire screen is a vertical scrolling list of ten businesses.
You tap a business to start a production cycle; when the timer fills, it pays out. You spend the
payout on more units of that business, on upgrades, and on managers. Managers auto-restart the
cycle, which is the moment the game stops being a clicker and becomes an idle game. When growth
stalls you reset ("Angel Investors") for a permanent profit multiplier and start over faster.

There is no avatar, no movement, no 3D space, no inventory, no teams, no ranked ladder, no PvP.
Art is flat 2D cartoon vector, not low poly. See **Gaps** at the bottom.

The loop, precisely:

1. Tap to collect → buy units → cycles get cheaper per dollar earned
2. Hit a unit-count milestone → cycle time halves → income jumps
3. Buy a manager → that business runs itself → income becomes passive
4. Buy cash upgrades (×3 profit multipliers on one business or all)
5. Growth flattens → reset for angels → +2% all profits per angel, permanently
6. Next run reaches the old wall in a fraction of the time

## Economy — Earth tier (the numbers to copy exactly)

| # | Business | Initial cost | Coefficient | Cycle (s) | Revenue / cycle |
|---|---|---|---|---|---|
| 1 | Lemonade Stand | 3.738 | 1.07 | 0.6 | 1 |
| 2 | Newspaper Delivery | 60 | 1.15 | 3 | 60 |
| 3 | Car Wash | 720 | 1.14 | 6 | 540 |
| 4 | Pizza Delivery | 8,640 | 1.13 | 12 | 4,320 |
| 5 | Donut Shop | 103,680 | 1.12 | 24 | 51,840 |
| 6 | Shrimp Boat | 1,244,160 | 1.11 | 96 | 622,080 |
| 7 | Hockey Team | 14,929,920 | 1.10 | 384 | 7,464,960 |
| 8 | Movie Studio | 179,159,040 | 1.09 | 1,536 | 89,579,520 |
| 9 | Bank | 2,149,908,480 | 1.08 | 6,144 | 1,074,954,240 |
| 10 | Oil Company | 25,798,901,760 | 1.07 | 36,864 | 29,668,737,024 |

Notes on the table:

- The player starts owning one free Lemonade Stand. The *displayed* price of the second stand is
  $4. The 3.738 figure is the formula's base offset: 4 / 1.07. Do not show 3.738 in the UI.
- Revenue scales strictly linearly with units owned. The 145th Bank adds exactly what the 1st did.
- Cost grows geometrically, revenue grows linearly. That divergence *is* the game's difficulty
  curve, and it is why the reset layer has to exist.

### Cost formulas

Price of the n-th unit (n = count after the purchase):

```
unitCost(n) = initialCost * coefficient^(n - 1)
```

Price of buying `k` units when you already own `N` (finite geometric series — buying x10 or x100
gives **no discount**, it is exactly the sum of k single buys):

```
bulkCost(N, k) = initialCost * coefficient^N * (coefficient^k - 1) / (coefficient - 1)
```

Sanity checks against the real game: 2nd Car Wash = 720 × 1.14 = $829.92. First 100 Oil Companies
= 25,798,901,760 × (1 − 1.07^100) / (1 − 1.07) = $319,433,276,243,943.

### Cycle-time halving (the milestone system)

Cycle time halves when a business reaches **25, 50, 100, 200, 300, 400** units — and halves *again*
for every business each time *all ten* businesses reach one of those milestones. Twelve halvings
maximum, so the floor is 1/4096 of the initial cycle. At 400 of everything the Oil Company's
10h14m cycle resolves in about 9 seconds.

This is the single most important feel mechanic in the game. It is what makes a grind suddenly
pay off, and it has to be exact.

### Managers

| Kind | Bought with | Effect |
|---|---|---|
| Normal | cash | Auto-restarts that business's cycle forever, including while offline |
| Accountant | angels | −10% unit cost for that business; display switches to $/sec |
| Discount | cash | −99.999% unit cost for that business (very late game) |
| EZ Upgrader | 1 angel | UI convenience — quick-buy button for upgrades |

Normal managers are the idle unlock. Accountants and angel upgrades are **lost on reset** and must
be re-bought; the angels spent on them are gone permanently.

### Cash upgrades

Flat multipliers bought with money, mostly ×3 profit on one business, with more expensive ones
hitting all businesses at once. Permanent within a run, lost on reset.

### Angel Investors (prestige)

Each angel gives **+2% to all profits**, additive — 50 angels = ×2 overall, 1000 angels = ×21.
The bonus applies only after a reset. Angels persist across every reset forever.

```
divisor      = 400e9 / 9          -- ≈ 44,444,444,444.4
angelsOnReset = floor( sqrt(lifetimeEarnings / divisor)
                     - sqrt(earningsInPreviousSessions / divisor) )
```

So the first angel lands at ~$44.44B lifetime earnings. Because the requirement is tied to
*lifetime* earnings and not to your current angel count, spending angels never makes the next one
cheaper. If you have sacrificed more angels than `sqrt(prevEarnings / divisor)`, the payout becomes
`sqrt(lifetime / divisor) - lifetimeAngelsSacrificed`.

Reference points: $1 quadrillion → 150 angels. $1 quintillion → 4,743. $1 sextillion → 150,000.
Every ×1000 in lifetime earnings alternates the mantissa between 150 and 4,743 and adds a digit.

### Number handling — a real engineering constraint

Costs legitimately reach ~2^1024 (≈179.769 uncentillion) before the game calls them infinite.
Luau `number` is a float64 and tops out around 1.8e308, which is only ~2^1024 — right at the edge
and with no precision left for the sums. **The economy cannot run on plain Luau numbers.** It needs
a mantissa/exponent BigNumber module (store `{m, e}`, normalise on every op) used everywhere money
is touched, plus a short-scale name formatter (K, M, B, T, aa/ab… or million→uncentillion).

Getting this wrong at the start means rewriting every system later, so it is Phase 1 work.

### Later tiers (for scope awareness, not Phase 1)

The real game adds Moon and Mars tiers with their own ten businesses, coefficients and divisors
(Mars uses 100e9 rather than 400e9), plus ~20 rotating seasonal events each with a full business
set. Full tables are on the wiki if we get there.

## Gaps between the source game and the brief

The brief mentions loving "the movement, the items, the team based aspect, the ranked, and the art
style" and asks for low poly 3D. AdVenture Capitalist has none of the first four and is not 3D.
These are therefore **additions**, not replications, and each is a real system:

| Brief item | In AdVenture Capitalist? | What it would mean here |
|---|---|---|
| Movement | No | Walk an avatar around a 3D plot and interact with buildings — a Roblox tycoon layer |
| Items | No | An inventory/cosmetic/boost system that does not exist in the source |
| Team-based | No | Shared plots or co-op income — changes the whole data model |
| Ranked | No | Leaderboards or competitive seasons — needs cross-server data |
| Low poly art | No (flat 2D vector) | A 3D art direction invented for this game |

The economy can be copied exactly. The presentation and the social layers have to be designed.
Decide these before Phase 1, because "team-based" in particular decides whether progression is
per-player or per-plot, and that is not retrofittable.

## Sources

- https://adventure-capitalist.fandom.com/wiki/Businesses
- https://adventure-capitalist.fandom.com/wiki/Angel_Investors
- https://adventure-capitalist.fandom.com/wiki/Managers
- https://adventure-capitalist.fandom.com/wiki/Coefficient
- Local install, Steam app 346900
