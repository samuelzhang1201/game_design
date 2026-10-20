# P4.1 terms and P4.3 event window evidence

This step restores committed real-window evidence for the existing panels. It changes no runtime code, scenes, resources, tables or art. It does not accept all of P4, natural event frequency, user playtesting, the task menu, quotes, pursuit, gait or the WAR ROOM task block.

Source baseline: `e7f8e9858680a6585304d6afda2d1fe913008c9d`. Captured on 21 October 2026 in the dedicated `codex/p4-terms-events-window` checkout, Godot 4.7.2 `ed1daf0bf`, Metal Forward+, Apple M5 Pro. Real window sizes: 1920×1200 (fractional 1.5× design scale with a different aspect ratio) and 1280×720. No headless 3D capture or image reconstruction.

## Evidence and reproduction

All artifacts are under [evidence/P4-terms-events-window](evidence/P4-terms-events-window). `commands.sh.txt` preserves the capture commands and shared lock. `reproduce.py.txt`, `fixture.gd.txt` and `capture.tscn.txt` recreate the temporary ignored capture invocation from the baseline's `tools/snapshot_screen.gd`; no tracked tool replacement is required. `manifest.json` records input and image hashes. PNG crops use original pixels enlarged with nearest-neighbour; contact sheets are comparisons, not native-size sharpness evidence.

The existing `--battle-case encounter` stages one actual hostile column 1000 metres from the first sorted own land regiment and calls `Game.advance_day()`. Seed 42, root screen, frame 60: the real encounter window is shown with its saved pending decision and paused clock. Default received founding laws agree on all seven clauses. Top and wheel-scrolled bottom captures preserve the troop list, founding-law explanation, all clauses, formation cost and deployment/continue controls. Sixteen real wheel-down events at frames 35–50 act inside `ClauseScroll`; the final scroll position is logged. This does not test decreed received-law versions, disagreement/refusal variants, formation execution or deployment switching.

For EV-31, the ignored fixture uses that actual battle, sets the first own participant's morale to 35 and the king's position to the battlefield, restricts the in-memory candidate table to EV-31 with weight 100 and chance 1000, clears the event journal/checks, and calls `BattleEvents.offer`. It asserts a blocked royal decision, stores it as the pending decision and asks GameRoot to show its existing `Game.battle_view()` projection. All displayed prose, artwork, choices, prices, effects and refusal reasons come from existing content and engine code. The rich condition retains the starting treasury; the poor condition sets treasury to zero after offer, refreshes state observers, and displays revalidated affordability. This intentionally staged offer is UI evidence, not a natural campaign trigger or transaction/save acceptance test. The ordinary snapshot `pending_event=false` log refers to monthly story events; the separate `P4_EVENT_INPUT` / `P4_EVENT_VIEW` records the battlefield decision.

## Visual observations

Standard: the current daylight war table and dark leather windows, using `taste.md` principles “Read in a book face; shout only in titles”, “Name every reading”, “A warning speaks in the page's own rubric”, and “Sharp up close, clean from far, at any window size”. These are existing-condition and size comparisons; no new design variant or art was introduced.

- The encounter's title, body, seven clauses and persistent bottom controls are readable in the supplied top/bottom views at both sizes. The scroll area initially shows only the beginning of the terms, with an explicit scroll instruction; the bottom view exposes the remaining clauses.
- EV-31 keeps all three choices and effects within the supplied windows. The poor condition shows both the unaffordable bounty reason and absent-reserve reason in body text, while the conservative choice remains visually enabled. The rich comparison exposes the bounty's enabled state.
- The captured background is context only: no acceptance of terrain, troops, animations or other map art is implied.

Independent visual critique and final current-HEAD CI are owned by the sole Review session; see its acceptance entry below. Implementation observations alone are not independent visual acceptance.

## Checks and limits

The evidence-only change uses the harness/selector/runner/timeout self-checks and syntax/config/guide checks, without a broad GUT run. Exact results and logs are retained in the evidence directory. Final diff selection must select no GUT category. Review must inspect required checks on the actual PR HEAD before merge.

The first import emitted the documented fresh-import font/theme errors and shutdown resource leaks. Successful window captures emitted a stale terrain-bake warning, deprecated interpolation warning and shutdown ObjectDB leak warnings; these existing background issues are retained in capture logs and were not repaired here. No capture runtime script error is accepted. An early inherited temporary script stalled during startup and was stopped only by its own process ID; a baseline copy with the fixture appended produced successful captures, although one rich-condition attempt also hit the 90-second startup limit and succeeded on one retry. The startup failure has not been diagnosed or fixed. A mistyped temporary scene invocation failed before capture and was rerun correctly. Neither failed attempt is screenshot evidence. The owner's existing editor and other sessions' processes were left alone; all successful captures used the shared lock.

No choice was clicked, no full game suite or all-six-event art review was repeated, and no user signoff is claimed. Remaining P4 logic and interactive acceptance belong to their separately owned steps.

## Sole Review acceptance

Pending independent image/crop critique and current-HEAD CI. The Review updates this section with its findings and actual merge gate results; it creates no successor.
