# Signal Hub Implementation Plan

> Execute inline using superpowers:executing-plans; this session implements, one unique Review reviews and merges.

**Goal:** Move the twelve Game global events into SignalHub without changing gameplay or event timing.
**Architecture:** A typed, notification-only Node autoload before Game. Game retains state and commands. Local instance signals and built-in signals stay local; no legacy forwarding.
**Tech Stack:** Godot 4.7, typed GDScript, GUT.
**Spec:** User-approved design in this chat, 2026-10-24.

## Constraints and ownership
One bounded PR, codex/signal-hub. Own project.godot autoload entry, scripts/ui/game.gd and global-event consumers, tests/ui event consumers, two tool consumers, new SignalHub/test/guide and this plan. No engine, scene, resource, simulation, save-format or look changes. scripts/ui/CLAUDE.md belongs to active PR174; put the communication rule in scripts/ui/guide/signals.md without editing that owned file.

## Review focus
- Keep synchronous ordering and original payload signatures.
- Refused or unchanged speed produces no notification.
- Holds and speed notifications retain separate meanings.
- Freed receivers no longer receive global events.
- All legacy references, including string-based GUT observers and tool callers, migrate together.

## Single task: move global event ownership
- [x] Add GUT regression for hub presence, clock notification order/refusals/duplicates and freed receivers; run red with shared Godot lock.
- [x] Move declarations verbatim to scripts/ui/signal_hub.gd; register before Game. Qualify Game emissions and migrate typed consumers, GUT observers and tools. Document boundaries in scripts/ui/guide/signals.md.
- [x] Run focused tests then affected presentation categories once on final inputs, plus harness/guide checks. Inspect diff for unchanged payload/order, engine isolation and no stale Game event references.
- [ ] Commit, open one PR, attach it and hand off to the sole Review with frozen evidence. Review does not edit; fixes return to this implementation. Review merges only after required current-HEAD CI and independent review pass.

## Verification record
Focused: 14 tests/71 assertions pass. Broad affected run: 177 scripts/1716 tests, 1714 passed, one stale `_news(Game)` test helper failed and one unchanged conditional WAR ROOM glyph test Pending (no qualifying capital in pack). After fixing the helper, its entire script reran: 6 tests/45 assertions passed. Other broad-run inputs unchanged; no production changes after those checks. Harness: 78 Python tests pass. No new skips or gate changes. Required current-HEAD CI and unique independent Review remain merge gates.
