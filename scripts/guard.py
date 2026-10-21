#!/usr/bin/env python3
"""Deterministic guards for the non-negotiables in CLAUDE.md.

Selene checks Luau style. StyLua checks formatting. luau-lsp checks types. None of them know
anything about *this project's* rules -- that money is never a plain number, that the economy
layer is pure, that config modules are frozen data. Those rules were written down for a human
or an AI to notice by eye, which means they get enforced unevenly or not at all.

This script makes them mechanical. It is intentionally dependency-free and runs in under a
second, locally and in CI.

Usage:
    python scripts/guard.py            # check, exit 1 on any violation
    python scripts/guard.py --list     # list the guards and exit

Every guard can be suppressed on a single line with a trailing comment:

    local total = cash + bonus -- guard:allow money-arith (both are already BigNumbers)

A suppression without a parenthesised reason is itself a violation, because an unexplained
escape hatch is how a guard quietly stops meaning anything.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Directories that hold first-party Luau we are responsible for.
SOURCE_ROOTS = ("src", "tests")

# Vendored or generated files that are not ours to police.
EXCLUDED_NAMES = {"globalTypes.d.luau"}

# The economy and config layers must be pure: no Roblox services, no instances, no clock,
# no mutable module state. This is what makes "identical to the source game" testable.
PURE_DIRS = ("src/shared/Economy", "src/shared/Config")

# The one module allowed to do raw arithmetic on mantissa/exponent components.
MONEY_ARITH_EXEMPT = ("src/shared/Economy/BigNumber.luau",)

MONEY_WORDS = (
    "cash",
    "cost",
    "price",
    "revenue",
    "profit",
    "earnings",
    "balance",
    "money",
    "funds",
    "payout",
)

SUPPRESS_RE = re.compile(r"--\s*guard:allow\s+([a-z-]+)\s*(\(.*\))?")

# `cashTotal + x`, `x * unitCost`, `revenue - fee`. Deliberately broad: a false positive costs
# one suppression comment with a reason, a false negative costs a rewrite of every system that
# touched money.
#
# The `(?![\w.(])` tail excludes a money word followed by `.` or `(` -- that is a table or a
# function being reached into, not a scalar being multiplied. Without it, `x * Revenue.perCycle(y)`
# trips the guard because the *module* is named Revenue, which says nothing about whether the
# arithmetic is safe. `state.cash * 2` is still caught, because there the money word is the
# member and nothing follows it.
_WORDS = "|".join(MONEY_WORDS)
MONEY_ARITH_RES = (
    re.compile(rf"\b\w*(?:{_WORDS})\w*\s*[-+*/]\s*", re.IGNORECASE),
    re.compile(rf"[-+*/]\s*\w*(?:{_WORDS})\w*(?![\w.(])", re.IGNORECASE),
)

IMPURE_RES = (
    (re.compile(r"\bgame:GetService\b"), "requires a Roblox service"),
    (re.compile(r"\bgame\.\w"), "reaches into the DataModel"),
    (re.compile(r"\bInstance\.new\b"), "creates an instance"),
    (re.compile(r"\bos\.(time|clock|date)\b"), "reads the clock"),
    (re.compile(r"\btick\s*\("), "reads the clock"),
    (re.compile(r"\bDateTime\b"), "reads the clock"),
    (re.compile(r"\btask\.\w"), "schedules work"),
    (re.compile(r"\bmath\.random\b"), "is nondeterministic"),
)

BANNED_RES = (
    (re.compile(r"(?<![.\w])wait\s*\("), "use task.wait"),
    (re.compile(r"(?<![.\w])spawn\s*\("), "use task.spawn"),
    (re.compile(r"(?<![.\w])delay\s*\("), "use task.delay"),
    (re.compile(r"(?<![.\w])print\s*\(.*[Cc]ash"), "do not log money values"),
)


@dataclass
class Violation:
    path: str
    line: int
    guard: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: [{self.guard}] {self.message}"


@dataclass
class Guard:
    name: str
    description: str
    violations: list[Violation] = field(default_factory=list)


GUARDS = {
    "strict": Guard("strict", "every Luau file opens with --!strict"),
    "money-arith": Guard("money-arith", "no raw arithmetic on money-named values"),
    "purity": Guard("purity", "the economy and config layers touch no services, clock or RNG"),
    "frozen-config": Guard("frozen-config", "config modules are table.freeze'd pure data"),
    "banned-api": Guard("banned-api", "no wait/spawn/delay, no logging money"),
    "suppression": Guard("suppression", "every guard:allow carries a parenthesised reason"),
}


def luau_files() -> list[Path]:
    found: list[Path] = []
    for root in SOURCE_ROOTS:
        base = REPO / root
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.luau")):
            if path.name in EXCLUDED_NAMES:
                continue
            found.append(path)
    return found


def rel(path: Path) -> str:
    return path.relative_to(REPO).as_posix()


BLOCK_OPEN_RE = re.compile(r"--\[(=*)\[")


def strip_strings_and_comments(line: str, in_block: str | None) -> tuple[str, str | None]:
    """Blank out string literals and comments so matches are real code.

    Returns the code part of the line and the block-comment state to carry into the next one.
    `in_block` holds the closing delimiter being waited for (`]]`, `]=]`, ...) or None.

    Luau's `--[[ ... ]]` block comments are the reason this is stateful. Every module here opens
    with a prose header, and lines inside it do not start with `--`, so a line-at-a-time stripper
    reads the documentation as code -- which made this script flag its own explanation of the
    money-arith rule as a violation of it.

    Crude on purpose: it does not parse Luau, it only stops a word inside a string or a sentence
    inside a comment from tripping a regex.
    """
    remaining = line
    code_parts: list[str] = []

    while remaining:
        if in_block is not None:
            end = remaining.find(in_block)
            if end == -1:
                remaining = ""
                break
            remaining = remaining[end + len(in_block) :]
            in_block = None
            continue

        opened = BLOCK_OPEN_RE.search(remaining)
        line_comment = remaining.find("--")

        # A plain `--` comment that is not a block opener ends the line.
        if line_comment != -1 and (opened is None or opened.start() != line_comment):
            code_parts.append(remaining[:line_comment])
            remaining = ""
            break

        if opened is None:
            code_parts.append(remaining)
            remaining = ""
            break

        code_parts.append(remaining[: opened.start()])
        in_block = "]" + opened.group(1) + "]"
        remaining = remaining[opened.end() :]

    code = "".join(code_parts)
    return re.sub(r"(\"[^\"]*\"|'[^']*')", '""', code), in_block


def suppressions(line: str) -> set[str]:
    return {match.group(1) for match in SUPPRESS_RE.finditer(line)}


def check_file(path: Path) -> None:
    name = rel(path)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    if not lines or lines[0].strip() != "--!strict":
        GUARDS["strict"].violations.append(
            Violation(name, 1, "strict", "file does not open with --!strict")
        )

    is_pure = any(name.startswith(d) for d in PURE_DIRS)
    is_config = name.startswith("src/shared/Config")
    money_exempt = name in MONEY_ARITH_EXEMPT

    if is_config:
        if "table.freeze" not in text:
            GUARDS["frozen-config"].violations.append(
                Violation(name, 1, "frozen-config", "config module is not table.freeze'd")
            )
        block: str | None = None
        for number, raw in enumerate(lines, start=1):
            code, block = strip_strings_and_comments(raw, block)
            if re.search(r"\bfunction\b", code) and "frozen-config" not in suppressions(raw):
                GUARDS["frozen-config"].violations.append(
                    Violation(
                        name, number, "frozen-config", "config modules hold data, not functions"
                    )
                )

    block = None
    for number, raw in enumerate(lines, start=1):
        allowed = suppressions(raw)

        for match in SUPPRESS_RE.finditer(raw):
            if not match.group(2):
                GUARDS["suppression"].violations.append(
                    Violation(
                        name,
                        number,
                        "suppression",
                        f"guard:allow {match.group(1)} needs a parenthesised reason",
                    )
                )

        code, block = strip_strings_and_comments(raw, block)
        if not code.strip():
            continue

        if not money_exempt and "money-arith" not in allowed:
            for pattern in MONEY_ARITH_RES:
                if pattern.search(code):
                    GUARDS["money-arith"].violations.append(
                        Violation(
                            name,
                            number,
                            "money-arith",
                            "raw arithmetic on a money-named value; use BigNumber",
                        )
                    )
                    break

        if is_pure and "purity" not in allowed:
            for pattern, why in IMPURE_RES:
                if pattern.search(code):
                    GUARDS["purity"].violations.append(
                        Violation(name, number, "purity", f"{PURE_DIRS[0].split('/')[-1]} layer {why}")
                    )
                    break

        if "banned-api" not in allowed:
            for pattern, why in BANNED_RES:
                if pattern.search(code):
                    GUARDS["banned-api"].violations.append(
                        Violation(name, number, "banned-api", why)
                    )
                    break


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list the guards and exit")
    args = parser.parse_args()

    if args.list:
        for guard in GUARDS.values():
            print(f"{guard.name:16} {guard.description}")
        return 0

    files = luau_files()
    if not files:
        print("guard: no Luau files found under src/ or tests/", file=sys.stderr)
        return 1

    for path in files:
        check_file(path)

    total = sum(len(g.violations) for g in GUARDS.values())
    if total == 0:
        print(f"guard: {len(files)} file(s) checked, {len(GUARDS)} guards, 0 violations")
        return 0

    for guard in GUARDS.values():
        if not guard.violations:
            continue
        print(f"\n{guard.name} -- {guard.description}")
        for violation in guard.violations:
            print(f"  {violation}")

    plural = "s" if total != 1 else ""
    print(f"\nguard: {total} violation{plural} across {len(files)} file(s)", file=sys.stderr)
    print(
        "Suppress a false positive on its line with: "
        "-- guard:allow <name> (reason)",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
