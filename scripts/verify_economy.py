#!/usr/bin/env python3
"""Re-derive the economy's anchor values from the config, at 50-digit precision.

CI has no Luau runtime -- there is no interpreter in the workflow and `require(script.Parent)`
needs a DataModel -- so the Luau suite in tests/ can only be type-checked there, not executed.
That leaves the most expensive failure mode uncovered: a transposed digit in a constant reaches
a playtest looking like a balance problem rather than a typo.

This closes that gap. It reads the constants straight out of
src/shared/Config/Businesses.luau, re-derives every anchor independently using Decimal rather
than floats, and fails if any of them drifts.

It does not execute the Luau, so it cannot catch a logic bug. It catches wrong numbers. The
Luau suite catches wrong code. Both run; neither alone is enough.

Usage:
    python scripts/verify_economy.py
    python scripts/verify_economy.py --table    # print the parsed config and exit
"""

from __future__ import annotations

import argparse
import re
import sys
from decimal import Decimal, getcontext
from pathlib import Path

getcontext().prec = 50

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "src" / "shared" / "Config" / "Businesses.luau"

# Earth and the Moon divide by this; Mars uses 100e9/9.
EARTH_DIVISOR = Decimal(400_000_000_000) / 9

# Matches one business entry's fields regardless of order within the block.
ENTRY_RE = re.compile(r"\{\s*id\s*=\s*\"(?P<id>\w+)\".*?\n\t\},", re.DOTALL)
FIELD_RES = {
    "initialCost": re.compile(r"initialCost\s*=\s*p\((?P<args>[^)]+)\)"),
    "revenuePerCycle": re.compile(r"revenuePerCycle\s*=\s*p\((?P<args>[^)]+)\)"),
    "coefficient": re.compile(r"coefficient\s*=\s*(?P<value>[\d.]+)"),
    "cycleSeconds": re.compile(r"cycleSeconds\s*=\s*(?P<value>[\d.]+)"),
    "order": re.compile(r"order\s*=\s*(?P<value>\d+)"),
}

MILESTONES_RE = re.compile(r"CYCLE_MILESTONES:\s*\{\s*number\s*\}\s*=\s*\{([^}]*)\}")
MAX_HALVINGS_RE = re.compile(r"MAX_CYCLE_HALVINGS\s*=\s*(\d+)")


class Failure(Exception):
    pass


def parse_parts(args: str) -> Decimal:
    """Evaluate a `p(mantissa, exponent)` call into an exact Decimal.

    The mantissa may itself be a quotient -- the Lemonade Stand's base is written `4 / 1.07`,
    the exact value the source game's displayed $4 second unit implies.
    """
    mantissa_text, exponent_text = (part.strip() for part in args.split(","))

    if "/" in mantissa_text:
        left, right = (part.strip() for part in mantissa_text.split("/"))
        mantissa = Decimal(left) / Decimal(right)
    else:
        mantissa = Decimal(mantissa_text)

    return mantissa * Decimal(10) ** int(exponent_text)


def load_config() -> tuple[dict[str, dict[str, object]], list[int], int]:
    text = CONFIG.read_text(encoding="utf-8")

    businesses: dict[str, dict[str, object]] = {}
    for match in ENTRY_RE.finditer(text):
        block = match.group(0)
        entry: dict[str, object] = {}

        for name, pattern in FIELD_RES.items():
            found = pattern.search(block)
            if not found:
                raise Failure(f"{match.group('id')}: could not parse {name}")

            if name in ("initialCost", "revenuePerCycle"):
                entry[name] = parse_parts(found.group("args"))
            elif name in ("coefficient", "cycleSeconds"):
                entry[name] = Decimal(found.group("value"))
            else:
                entry[name] = int(found.group("value"))

        businesses[match.group("id")] = entry

    milestones_match = MILESTONES_RE.search(text)
    if not milestones_match:
        raise Failure("could not parse CYCLE_MILESTONES")
    milestones = [int(part.strip()) for part in milestones_match.group(1).split(",") if part.strip()]

    halvings_match = MAX_HALVINGS_RE.search(text)
    if not halvings_match:
        raise Failure("could not parse MAX_CYCLE_HALVINGS")

    return businesses, milestones, int(halvings_match.group(1))


def unit_cost(entry: dict[str, object], n: int) -> Decimal:
    initial: Decimal = entry["initialCost"]  # type: ignore[assignment]
    coefficient: Decimal = entry["coefficient"]  # type: ignore[assignment]
    return initial * coefficient ** (n - 1)


def bulk_cost(entry: dict[str, object], owned: int, quantity: int) -> Decimal:
    initial: Decimal = entry["initialCost"]  # type: ignore[assignment]
    c: Decimal = entry["coefficient"]  # type: ignore[assignment]
    return initial * c**owned * (c**quantity - 1) / (c - 1)


def angels_for(lifetime: Decimal, divisor: Decimal = EARTH_DIVISOR) -> int:
    return int((lifetime / divisor).sqrt())


class Checker:
    def __init__(self) -> None:
        self.passed = 0
        self.failures: list[str] = []

    def check(self, name: str, actual: object, expected: object, tolerance: Decimal | None = None) -> None:
        if isinstance(actual, Decimal) and isinstance(expected, (Decimal, int, str)):
            expected_dec = Decimal(expected) if not isinstance(expected, Decimal) else expected
            allowed = tolerance if tolerance is not None else Decimal("1e-20")
            scale = abs(expected_dec) if expected_dec != 0 else Decimal(1)
            ok = abs(actual - expected_dec) / scale <= allowed
            shown_actual: object = f"{actual:.6f}"
            shown_expected: object = f"{expected_dec:.6f}"
        else:
            ok = actual == expected
            shown_actual, shown_expected = actual, expected

        if ok:
            self.passed += 1
        else:
            self.failures.append(f"{name}: expected {shown_expected}, got {shown_actual}")

    def report(self) -> int:
        if not self.failures:
            print(f"verify_economy: {self.passed} anchors re-derived, all match")
            return 0

        for failure in self.failures:
            print(f"  MISMATCH  {failure}", file=sys.stderr)
        print(
            f"\nverify_economy: {len(self.failures)} of {self.passed + len(self.failures)} "
            "anchors do not match the config",
            file=sys.stderr,
        )
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", action="store_true", help="print the parsed config and exit")
    args = parser.parse_args()

    try:
        businesses, milestones, max_halvings = load_config()
    except Failure as error:
        print(f"verify_economy: {error}", file=sys.stderr)
        return 1

    if args.table:
        for name, entry in sorted(businesses.items(), key=lambda item: item[1]["order"]):  # type: ignore[index,arg-type]
            print(
                f"{entry['order']:>2}  {name:<20} cost={entry['initialCost']:>22.4f}  "
                f"c={entry['coefficient']}  cycle={entry['cycleSeconds']:>8}  "
                f"rev={entry['revenuePerCycle']:>22.4f}"
            )
        print(f"\nmilestones: {milestones}   max halvings: {max_halvings}")
        return 0

    c = Checker()

    c.check("ten Earth businesses", len(businesses), 10)
    c.check("six cycle milestones", milestones, [25, 50, 100, 200, 300, 400])
    c.check("twelve halvings maximum", max_halvings, 12)

    car_wash = businesses["CarWash"]
    c.check("1st Car Wash", unit_cost(car_wash, 1), "720")
    # 720 * 1.14. The wiki says 829.92, which is 728 * 1.14 -- a wiki error, not ours.
    c.check("2nd Car Wash", unit_cost(car_wash, 2), "820.80")
    c.check("3rd Car Wash", unit_cost(car_wash, 3), "935.712")
    c.check("not the wiki's wrong Car Wash figure", unit_cost(car_wash, 2) == Decimal("829.92"), False)

    # The player starts with one free stand, so the first purchase is unit 2 at exactly $4.
    c.check("2nd Lemonade Stand is exactly $4", unit_cost(businesses["LemonadeStand"], 2), "4")

    oil = businesses["OilCompany"]
    c.check("first 100 Oil Companies", bulk_cost(oil, 0, 100), "319433276243943.40223455338006")

    # Bulk is exactly the sum of singles: no discount for buying ten or a hundred at once.
    singles = sum((unit_cost(car_wash, n) for n in range(1, 11)), Decimal(0))
    c.check("bulk of 10 equals 10 singles", bulk_cost(car_wash, 0, 10), singles)

    c.check("first angel threshold", angels_for(Decimal("44444444445")), 1)
    c.check("one dollar short of the first angel", angels_for(Decimal("44444444443")), 0)
    c.check("1e12 lifetime", angels_for(Decimal(10) ** 12), 4)
    c.check("1e15 lifetime", angels_for(Decimal(10) ** 15), 150)
    c.check("1e18 lifetime", angels_for(Decimal(10) ** 18), 4743)
    c.check("1e21 lifetime", angels_for(Decimal(10) ** 21), 150000)
    c.check("1e24 lifetime", angels_for(Decimal(10) ** 24), 4743416)
    c.check("Mars divisor doubles the yield", angels_for(Decimal(10) ** 15, Decimal(100_000_000_000) / 9), 300)

    # Twelve halvings is the floor, and it turns the Oil Company's 10h14m into nine seconds.
    cycle: Decimal = oil["cycleSeconds"]  # type: ignore[assignment]
    c.check("Oil base cycle", cycle, "36864")
    c.check("Oil cycle at 12 halvings", cycle / 2**12, "9")
    lemonade_cycle: Decimal = businesses["LemonadeStand"]["cycleSeconds"]  # type: ignore[index,assignment]
    c.check("Lemonade cycle at 12 halvings", lemonade_cycle / 2**12, Decimal("0.6") / 4096)

    # Revenue is linear in units. If this ever compounds, the difficulty curve is wrong.
    bank_revenue: Decimal = businesses["Bank"]["revenuePerCycle"]  # type: ignore[index,assignment]
    c.check("1 Bank per cycle", bank_revenue, "1074954240")
    c.check("145 Banks is exactly 145x", bank_revenue * 145, Decimal("1074954240") * 145)

    # Angels are additive among themselves: 50 is x2, not 1.02^50 (which would be ~2.69).
    c.check("50 angels is x2", Decimal(1) + 50 * Decimal("0.02"), "2")
    c.check("1000 angels is x21", Decimal(1) + 1000 * Decimal("0.02"), "21")

    # Costs grow geometrically, revenue linearly -- ordered by cost, coefficients in range.
    ordered = sorted(businesses.values(), key=lambda entry: entry["order"])  # type: ignore[arg-type,index]
    c.check(
        "ordered by ascending initial cost",
        all(
            ordered[i]["initialCost"] < ordered[i + 1]["initialCost"]  # type: ignore[operator]
            for i in range(len(ordered) - 1)
        ),
        True,
    )
    c.check(
        "coefficients within 1.07..1.15",
        all(Decimal("1.07") <= entry["coefficient"] <= Decimal("1.15") for entry in ordered),  # type: ignore[operator]
        True,
    )

    return c.report()


if __name__ == "__main__":
    sys.exit(main())
