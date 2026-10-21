## What this changes

<!-- One paragraph. What the player can now do that they could not before. -->

## Phase

<!-- e.g. Phase 1 — the number system and the economy core. See docs/ROADMAP.md -->

## Reviewer focus

<!-- Point Codex at the risky part. Delete the lines that do not apply. -->

- [ ] Touches money arithmetic — check every value is a BigNumber, no raw-number mixing
- [ ] Implements or changes an economy formula — check against docs/RESEARCH-advcap.md
- [ ] New remote or client-supplied value — check server-side validation
- [ ] Touches offline accrual or any elapsed-time calculation
- [ ] Touches persisted data — check version bump and migration
- [ ] Touches plot state or anything that could become singleton
- [ ] Scales with unit count rather than business count

## Economy values verified against the real game

<!-- Which numbers you checked in the Steam build, and what they were. Delete if N/A. -->

## Testing done

<!-- What was actually played, on what device tier, and what happened. -->

## Checklist

- [ ] `--!strict` on every new file
- [ ] `selene src tests` clean
- [ ] `stylua --check src tests` clean
- [ ] `luau-lsp analyze` clean
- [ ] `rojo build` succeeds
- [ ] Balance values live in `src/shared/Config`, not inline
