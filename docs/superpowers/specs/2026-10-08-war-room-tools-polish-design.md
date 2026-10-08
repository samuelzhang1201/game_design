# WAR ROOM — the map tools polished: logic (A), the sheet's layout and ink (B), the tool roll (C), performance and cleanup (D) — design

Owner request 2026-10-08 (translated): "Optimise the war room map tools' logic
and look." The owner chose a full pass (the tool roll and drawing, selecting
and drawing orders, the sheet's ink) in the order A → B → C → D, each batch
designed in chat and approved before it is built. The owner allowed ComfyUI
art for this task, picked by Claude.

Builds on `2026-10-08-war-room-draw-orders-design.md` (selection, drawn
orders, the two-sided roll) and
`2026-10-07-war-room-annotations-and-planning-pieces-design.md` (the plans).

## Diagnosis (2026-10-08)

Real-window shots at 1920×1080 (overview; box + blue arrow + supply; red
arrow on an intel hint; leaning in with a hover) and a read-only audit of
`scripts/war_room/` and the screen side. Findings are grouped into the four
batches below; file:line evidence is in the audit, reproduced per item in
the plan.

## Batch A — interaction logic (owner-approved 2026-10-08)

Rulings marked **[R]** were proposed by Claude and approved by the owner.

### Selection

- **A1. A red selection holds.** Selecting a supposed piece or an intel hint
  while our regiment's folio is docked closes the folio WITHOUT clearing the
  selection again (today `selection_cleared` → folio `closed` →
  `clear_selection` empties the red selection just made; a red box likewise).
- **A2 [R]. A box selects exactly what lies in it** — it replaces the
  selection (never removes what it boxes). Shift-click still toggles one.
  The box takes OUR side if any of our pieces lie in it, else the other
  side's, whatever side was last lit. Membership is tested at the DRAWN spot
  (`WarPieces._spread`'s node positions, what the player sees), not the
  engine spot.
- **A3. A sheet laid drops from the selection every code not on it**; with
  none left the blue arrow is greyed again.
- **A4 [R]. A fleet** may be clicked (its folio opens) but the blue arrow is
  greyed for a selection holding only fleets, `why` "Fleets are ordered on the
  map"; fleets in a mixed selection are left out of the march.

### Drawing

- **A5 [R]. A click still works with a stick in hand.** A press that does not
  move past the click slop is a CLICK and goes where it would with the hand:
  select / Shift-toggle a piece, open a pennant's menu, or let the selection
  go on open table. Only a press that moves draws.
- **A6 [R]. The blue arrow is laid down after one march** (the stick goes
  back to the hand when the march's confirm opens). Fronts, phase lines,
  objectives and the red arrow stay in hand for the next.
- **A7. The hand carries only the CHOSEN stroke.** A press on an unchosen
  stroke chooses it on release (a click) and pans if it moves; a press on
  the chosen stroke's body or handles drags it.
- **A8. Red and blue alike.** A Shift-drawn blue arrow is fitted as a straight
  two-point route. A red arrow drawn with several supposed pieces / hints
  selected writes one arrow per selected item (each from its own spot to the
  tip). A red arrow for an intel hint is tied to the hint's PLACE, so a
  newer report on the same place keeps it (a hint's id is its place).
- **A9. The name box never traps the keyboard.** After a phase line or
  objective, the name box commits its prefilled name when it loses focus or
  the table is pressed; while it is open the room's keys still reach the
  desk once it has lost focus.
- **A10. Esc in the documented order**: the stick, then the chosen stroke,
  then the selection, and only then the docked folio (the desk sees Esc
  before the folio).
- **A11. No flicker on release.** The live stroke stays drawn until the plan
  texture holding it has been painted; a stroke being dragged is left out of
  the baked texture while it is dragged (it is not drawn twice).

### Undo

- **A12. The undo stack is the session's**: emptied on a load and a new
  reign, and a refused write pushes nothing.
- **A13 [R]. Cmd-Z undoes a drawn march too**: the drafts the march planted
  are struck and any draft they replaced restored (`Game.strike_draft` /
  `plant_draft`). One undo step a march, in the same stack as the marks.

### Spec alignment

- **A14.** Tab with nothing in hand takes the other side's last kind (ruling
  2 of the draw-orders spec).
- **A15.** A front's default facing stays the drawer's LEFT (the code);
  `data/war_plan_kinds.csv`'s note is corrected to say so.

### Testing (A)

A GUT test per item under `tests/war_room/` and `tests/ui/`, driven through
the real input path (`WarPlanInput`, the desk's key handler, the view's
pointer), then snapshot shots of select, box, draw and confirm.

## Batch B — the sheet's layout and ink (to design)

Supply preview drawn off the parchment onto the oak; the key slip clipped at
the room's right edge; the index chart filling a third of the view and its
column letters crowded; town names small, pale and hidden by pieces while the
graticule figures are the loudest ink; sea hatching over most of a sheet;
the march confirm over the margin slip, small type; intel-hint notes
unreadable; the hover slip not seen in the shot (to check).

## Batch C — the tool roll (to design)

Smaller roll; painted glyphs (ComfyUI, both models, Claude picks); hover ring
on slots; a cursor per tool on the table; a click on a faint slot and a
scraper miss say why in the news; the side in hand made obvious; a preview
while turning a front's facing.

## Batch D — performance and cleanup (to design)

Order arrows rebuilt on every pan / turn frame (cache them in table space,
redraw on state change); the supply ribbon rebuilt per box-drag motion; the
order tip's ground reading per motion event (throttle to the hover dwell);
dead code from the pen, the rake and the piece menu; `war_rake_min_px`
renamed for what it now means.
