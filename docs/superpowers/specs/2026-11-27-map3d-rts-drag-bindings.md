# 3D map: RTS drag bindings (step 3 of the UI overhaul)

Date: 2026-11-27. Owner ruling (2026-11-27): "Right drag + WASD". Replaces
ruling R4 of `2026-10-07-army-split-and-ground-design.md` (a Shift + left
drag boxed, a plain drag panned).

## Bindings (`Map3DInput`)

| Input | Does |
|---|---|
| left drag on open map | draws the selection box; while held, the units it would select glow (owner 2026-11-27: yes to a preview); on release the player's LAND units it touches become the selection (replacing it) |
| Shift + left drag | the same box, ADDING its units to the selection |
| left click | as before: selects; Shift toggles a unit; an aimed order takes its destination (no box while an order aims); a press on the planned route bends it; a press on the compass eases north |
| right drag | pans the map |
| right click (no drag) | as before: the order menu of the unit under it, else the spy offer |
| middle drag | turns the camera |
| WASD / arrows | pan (already there, `Map3DInput.key_pan`; never while a LineEdit / TextEdit has focus) |
| wheel / pinch / two-finger drag | unchanged |

A click and a drag are told apart by `Map3DInput.CLICK_SLOP` (press to
pointer distance), for the left and the right button alike. A right drag
starts panning once past the slop, catching up the whole offset so the
ground stays under the pointer.

## Owner rulings

- **R1 — turning is on the middle drag** (owner 2026-11-27, "Keep middle
  drag"). The right drag used to turn the view; the middle drag (which used to
  pan) now turns. There was no keyboard turn to keep. The compass press still
  eases back to north.

## Implementer defaults (for the owner to confirm)

- **D2 — no box while an order aims.** During a MARCH aim a left drag draws
  nothing and selects nothing; its click is still the destination.
- **D3 — the war room keeps its own drag rules** (`scripts/war_room/`, its own
  input code); this change is the campaign map's only.
