---
name: visual-review
description: Use when changing anything the player sees in Crown and Council — map look, UI layout, icons, colours, fonts, installed art, shaders, the 3D map — or when the owner says something looks ugly, muddy, cluttered, rough, wrong, blurry, or asks to make it look better.
---

# Visual review

## Overview
Claude can see images. The failure is not blindness; it is judging from
the code, or from one full-screen shot, against no standard but its own
eye. A visual change is done when it has been **looked at up close,
compared, and critiqued by someone who did not make it**.

## The loop

1. **Load the taste.** Read `taste.md` (next to this file) and look at the
   relevant images in `docs/references/`. Write down in one line which
   principles this change touches. This is the standard; "better" means
   better *by these principles*, not by preference.
2. **Shoot the before**, through the real path, at a fractional window:
   - screen/UI: `Godot --path . res://scenes/tools/snapshot_screen.tscn -- --out B.png --resolution 2560x1600 [--screen …] [--layer …] [--manor …]`
   - map: `res://tools/snapshot_map.tscn -- --out B.png --size 2560 --zoom 1` and `--zoom 3`
   - 3D map: `--layer "3d map" --zoom3d M` at near and far
   Output goes in the scratchpad or `assets/flux/out/` (git-ignored).
3. **Make 2–3 variants**, not one. For tuning values, bracket them: less, proposed, more.
4. **Build a contact sheet.** Show the whole screen, plus a zoomed crop of the thing itself:
   `python3 .claude/skills/visual-review/contact_sheet.py SHEET.png B.png V1.png V2.png --labels before,v1,v2`
   `… --crop x,y,w,h --zoom 3` for icons, edges, text. Read both sheets.
5. **Independent critique.** Dispatch a fresh subagent with only the sheets,
   `taste.md` and the rubric below. Ask it to rank the variants, name defects,
   and state which principle each defect breaks. Do not show it your reasoning.
6. **Fix what it found**, re-shoot, re-sheet. Stop when the critic finds no
   defect that breaks a principle, or when the next move is new art. New art needs
   the owner's go-ahead.
7. **Report with the pictures:** before/after sheet (publish or give the path),
   which principle each change serves, and what is still wrong and why.

## When the owner says "quick"
"Quick" means fewer rounds, not fewer steps. Never drop these three: two
variants, the zoomed crop, and one critic pass. They cost minutes. What a
hurried owner does not want is a second round of complaints.

## Scope
- **Layout, spacing, sizing, refit/re-install of existing art:** go ahead.
- **Removing information** (a stat, a label, a column): do it in a variant, and
  ask the owner before it ships.
- **New art or regeneration:** ask first. Never queue a batch.

## When there is no reference
Take the nearest one. For UI, that is Crusader Kings III, whose look the dark theme copies. For the map, it is the images in `docs/references/`. Otherwise use the current game's best-regarded screen. Name which one you used in the report.

## Rubric (the critic answers each, in one line)
| Axis | Question |
|---|---|
| Hierarchy | What does the eye land on first? Is that the most important thing? |
| Value | Squint: do the elements separate by light/dark, or is it mud? |
| Colour | One family? Any hue that belongs to another picture? |
| Medium | Does everything share one medium (photo / paint / vector)? Any stickers? |
| Edges | Hard cuts, trays, rings, halos where things should fade? |
| Scale | Right size against its neighbours and at both ends of the zoom? |
| Sharpness | Crisp at the crop? Blur from resolution, or from the art itself? |
| Noise | Anything drawn that carries no information? |

## Red flags
- "I checked the code; it should look fine." → You did not look.
- Only one full-screen shot → Small things are invisible at that size. Crop and zoom.
- One variant → Nothing to compare against. Make at least two.
- "Looks better to me" → Name the principle. Get the critic.
- Shooting only at 1280x720 → Most real monitors are fractional sizes.
- "The owner is busy, so one variant and no critic" → That is exactly when a miss costs most. See "quick".

## When the owner rules
When the owner says it's ugly, or approves something, add the principle and its reason to `taste.md`. The file is the project's memory of taste.
