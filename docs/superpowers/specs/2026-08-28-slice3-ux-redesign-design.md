# Slice 3 — UX Redesign: Conversation Scenes + Scene Architecture

Status: implements the owner's `how_to_play.md` (13 requirements, cited as R1–R13).
Base: `main` @ post-slice-2 merge. Engine layer untouched — this is a UI/flow slice;
determinism and all engine tests must survive unchanged.

## 1. Goal

Replace the single stacked council screen with a staged, visual-novel-style flow:
a main menu (R13), a turn-by-turn council conversation where one minister speaks and
you answer before the next jumps in (R3, R4), a Council round-table voice that
announces events and summaries (R2, R5), a kingdom info card that carries the
numbers so ministers don't have to (R1, R7, R9), a slower, readable day-run (R6),
and natural-language phrasing throughout (R8). R to restart anywhere (R12).

## 2. Scene architecture (R11 — the proposal, then binding)

One root state machine; every screen is a self-contained child scene with a
signal-only upward interface. UI reads state via `Game`, mutates only via
`Game.try_execute / submit_free_text / apply_event_choice` (unchanged rule).

```
scenes/
  main_menu.tscn        MainMenu       — title + "press Space" (R13)
  game_root.tscn        GameRoot       — flow state machine + global input (R12)
  kingdom_card.tscn     KingdomCard    — info card: metrics + deltas (R1, R9)
  conversation.tscn     ConversationScene — VN stage: one portrait, dialogue box (R3-R5)
  court.tscn            CourtScreen    — orders + End Turn + summary log (no roster, R10)
  calendar_overlay (existing, slowed)  — hosts KingdomCard during day-run (R6, R9)
  characters/* (existing)              — + round_table portrait (R5)
```

**GameRoot states:** `MENU → CONVERSATION → COURT → DAY_RUN → CONVERSATION …`

- `GameRoot` owns exactly one active child screen at a time (`_switch_to(scene)`),
  forwards `R` (restart → fresh campaign → MENU) and `Space` (MENU only) from
  `_unhandled_input`. Screens never know about each other; they emit
  `finished(payload)` and GameRoot decides the next state. This is the scalable
  seam: slice-4 recruitment or a settings screen become new states + scenes with
  zero edits to existing screens.
- `Game` autoload gains `restart()` (fresh `start_campaign` + clears voicer state).
  Engine untouched.

## 3. The conversation flow (R2, R3, R4, R5, R7, R8)

On entering CONVERSATION (after `Game.next_tick()`), GameRoot builds a **beat
queue** from the TickReport and hands it to ConversationScene:

1. **Event beat** (if `report.event` non-empty): speaker = **The Council**
   (round-table portrait, R5), text = voiced event scene (existing tiers),
   choices = the event's choices as buttons. Must be resolved to advance
   (existing End-Turn gating logic reused). Choice outcome is narrated in prose
   (template outcome line + drift lines) — no numbers (R7).
2. **Minister beats**: one beat per minister who has a concern or suggestion this
   tick (concerns grouped with that minister's pitch into a single natural speech —
   template concern line + pitch line joined; R3). Each beat shows ONLY that
   minister's portrait (large: the existing 48×48 pixel art scaled ×4 nearest,
   left-of-center) with name plate and the dialogue box at mid-bottom (R4).
3. **Reply phase after every beat** (R3): the dialogue box offers
   - quick replies in natural language (R8): the minister's own pitch as an
     acceptance phrase (template `reply_<pitch_key>` rows, e.g. "Very well —
     raise the levies."), executed via the existing suggestion ActionRequest;
   - a free-text line ("Speak your mind…") wired to `submit_free_text` (caps
     unchanged); executed orders are answered by that minister in prose;
   - "Wave them on" (continue) → next beat.
4. **Summary beat** (R2): speaker = The Council (round table): one or two template
   sentences summarizing the session (what was decided, what was left) — built
   from executed outcomes' labels, no numbers (R7). Then `finished` → COURT.

Numeric detail is never spoken (R7); it lives on the KingdomCard (R9) and in the
opinion-log tooltips (readable-causality invariant preserved — CS-2.2).

## 4. KingdomCard (R1, R9) and the day-run (R6)

- `KingdomCard`: a framed card listing the six headline metrics + date, styled
  like the conversation frames. API: `show_values(state)`,
  `show_changes(deltas)` — each delta row rendered as `Gold 519 → 538 (+19)`
  with reason tooltip. Used two places:
  - COURT: docked right side, values mode (R1).
  - DAY_RUN: centered on the calendar overlay under the running date, changes
    mode fed from the tick's `metric_deltas` (R9).
- Day-run pacing (R6): `DAY_SECONDS` 0.09 → **0.22** (≈3.3 s per fortnight) via
  new balance key `dayrun_day_seconds`; click-to-skip unchanged. News flashes
  unchanged.

## 5. CourtScreen (R10) — the trimmed order screen

The old council screen minus: roster row (R10), per-minister transcript frames
(conversation replaced them). Keeps: summary log (Council/Herald lines only),
free-text order bar (natural placeholder), End Turn (+ Enter), natural-language
suggestion buttons — labels switch from `NAME: ACTION_CODE` to the pitch text
(R8), tooltips keep the tradeoff line.

## 6. Data additions (templates.csv only — no engine changes)

- `reply_<pitch_key>` rows (one per existing pitch key): the natural-language
  acceptance phrasing (R8).
- `council_summary_*` rows: session-summary sentence patterns (R2).
- Round-table art: `assets/portraits/round_table.png` via `tools/gen_portraits.py`
  (new 16×16 grid: circular table + five colored figures), with
  `scenes/characters/round_table.tscn` so the Council speaker resolves like any
  character (R5).

## 7. Testing

- Engine suite untouched and green (this slice never edits `scripts/engine/`).
- New UI tests: GameRoot state transitions (Space starts, R restarts, event beat
  gates advance); ConversationScene renders one-portrait-per-beat and advances on
  reply/continue; quick-reply executes the underlying ActionRequest; KingdomCard
  delta rendering; day-run speed reads the balance key.
- Rewrites: existing council_screen UI tests migrate to CourtScreen/GameRoot
  equivalents — intent preserved test-by-test (gating, caps, portraits-in-frames
  logic moves to ConversationScene), never weakened.
- The suite stays offline (CC_FORCE_OFFLINE); voicing paths keep template
  fallbacks.

## 8. Out of scope

Debates (PRD Step 3 proper — this slice builds the conversation stage they will
use), recruitment, factions. `council_screen.gd` is retired gradually: COURT
reuses its order-bar/suggestion logic; dead code removed at the end of the slice.
