# WAR ROOM v2 — C: Deploy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orders given in the WAR ROOM are DRAFTS — pencilled pennants, no fee, no courier — until the player unrolls the resolutions scroll, reviews them and seals them; then each runs as the real order with its own courier and fee. Leaving the room with drafts asks Deploy / Discard / Keep; kept drafts are saved.

**Architecture:** `WarDrafts` (pure, `scripts/engine/`) holds the rules over `GameState.war_drafts` (saved); `Game` is the only writer (`plant_draft`, `strike_draft`, `discard_drafts`, `deploy_drafts`, `review_drafts`). `ActionSystem` sets a regiment's draft aside whenever a real march or garrison order is executed for it. The shared `ArmyOrderMenu` gains a `drafting` switch the WAR ROOM's instance turns on. `WarPennants` plants a translucent "draft" pennant and the HUD a pencil line. `WarDeployScroll` (the button, the review and the seal) and `WarLeavePrompt` are new `scripts/ui/` pieces in `WarRoomScreen`; `GameRoot.leave_war_room(then)` is the one door out of the room.

**Tech Stack:** Godot 4.7, typed GDScript, GUT, `tools/snapshot_screen.gd`.

**Spec:** `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` §3 (rulings 9–11). Plans A and B are merged; CLAUDE.md's WAR ROOM paragraph describes the room as it stands.

## Global Constraints

- Every design value in `data/*.csv` (`balance.csv` `war_deploy_*`, `war_draft_*`; row text in `data/army_route_orders.csv`); notes start `WAR ROOM v2 C (owner 2026-10-02, spec §3…)`.
- State changes only through `Game` (UI never writes `Game.state`); every order still goes through `Game.try_execute` (invariant 8: its fee and courier).
- `scripts/war_room/` never names `Game`; `scripts/engine/` never depends on `scripts/ui/` or `scripts/war_room/`.
- Save = one JSON: `war_drafts` round-trips through `GameState.to_dict` / `from_dict`; a save without it loads with none.
- Determinism: drafts carry whole metres (`dest_x_m` / `dest_y_m`), never floats.
- UI flows verified by REAL input in shots (`--resolution WxH`); never a 3D snapshot headless.
- Work in `.claude/worktrees/war-room-v2-c` on `design/war-room-v2-c`; never switch the main checkout's branch.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A draft whose regiment is given a real order on the 3D map** must disappear from the table and the scroll, and the news must say so — pin: Task 1 + Task 3 tests.
2. **Deploying when the chest cannot pay for every draft** must run what it can in regiment-code order and leave the rest as drafts, each with its reason — pin: Task 2 test.
3. **Leaving by ANY door with drafts** (another tab, the LEDGER, the MISSIVE board, the close button, Quit) must ask, and Escape on the prompt must leave the player in the room with nothing lost — pin: Task 5 tests.
4. **A save and load mid-plan** must bring the drafts back on the table — pin: Task 1 test.
5. **Deploy pressed twice or while the seal plays** must never run a draft twice — pin: Task 6 test.

---

### Task 0: Worktree setup and a green baseline

- [ ] Same as plan B's Task 0, in `.claude/worktrees/war-room-v2-c` (copy `.godot`, drop the gdai line from `.godot/extension_list.cfg`, link `assets/3D/terrain/{beria,textures,trees}`, copy the ignored `assets/3D` files, `--import`), and the plan workspace's `t.sh` runner. Run `$W/t.sh res://tests/war_room res://tests/ui/test_war_room_screen.gd res://tests/engine/test_war_room.gd` — all pass.

---

### Task 1: `WarDrafts` and the saved drafts

**Files:**
- Create: `scripts/engine/war_drafts.gd`
- Modify: `scripts/engine/game_state.gd` (`war_drafts` field, `to_dict`, `from_dict`), `scripts/engine/action_system.gd` (`ARMY_MARCH` / `ARMY_GARRISON` set a draft aside)
- Test: `tests/engine/test_war_drafts.gd`

**Interfaces:**
- Produces: `GameState.war_drafts: Dictionary` — regiment code → `{order: "march"|"garrison", dest_x_m: int, dest_y_m: int, tick: int, day: int, refused: String}`. `WarDrafts` (static): `plant(repo, state, code, order: String, dest_px: Vector2) -> void` (replaces any draft of that regiment; `dest_px` ignored for a garrison); `strike(state, code) -> bool`; `codes(state) -> Array` (sorted); `any(state) -> bool`; `of(state, code) -> Dictionary`; `dest_px(repo, draft) -> Vector2`; `request_of(repo, state, code) -> ActionRequest` (the real order the draft stands for) and `request_from(repo, code, draft) -> ActionRequest` (the same from a draft in hand). `ActionSystem.execute` of `ARMY_MARCH`/`ARMY_GARRISON` erases `state.war_drafts[code]` when present and appends the effect `{"metric": "war_draft", "delta": 0.0, "reason": "<label>'s draft in the war room is set aside"}`.

- [ ] **Step 1: Failing tests** — create `tests/engine/test_war_drafts.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's drafts (spec 2026-10-02-war-room-v2 §3.1): pencilled orders,
## saved, one per regiment, set aside by a real order.

var repo: DataRepository
var state: GameState
var code := ""


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break


func _somewhere() -> Vector2:
	return ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)) + Vector2(20, 0)


func test_a_draft_is_planted_in_whole_metres_and_replaces_the_last() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var d := WarDrafts.of(state, code)
	assert_eq(String(d["order"]), "march")
	assert_true(d["dest_x_m"] is int and d["dest_y_m"] is int)
	assert_almost_eq(WarDrafts.dest_px(repo, d).distance_to(_somewhere()), 0.0, 0.01)
	WarDrafts.plant(repo, state, code, "garrison", Vector2.ZERO)
	assert_eq(String(WarDrafts.of(state, code)["order"]), "garrison")
	assert_eq(WarDrafts.codes(state), [code], "one draft a regiment")


func test_strike_and_any() -> void:
	assert_false(WarDrafts.any(state))
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	assert_true(WarDrafts.any(state))
	assert_true(WarDrafts.strike(state, code))
	assert_false(WarDrafts.strike(state, code), "nothing left to strike")
	assert_false(WarDrafts.any(state))


func test_a_draft_stands_for_its_real_order() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var req := WarDrafts.request_of(repo, state, code)
	assert_eq(req.action_code, "ARMY_MARCH")
	assert_eq(String(req.params["regiment"]), code)
	assert_almost_eq(Vector2(float(req.params["x"]), float(req.params["y"])).distance_to(_somewhere()), 0.0, 0.01)
	WarDrafts.plant(repo, state, code, "garrison", Vector2.ZERO)
	assert_eq(WarDrafts.request_of(repo, state, code).action_code, "ARMY_GARRISON")


func test_drafts_survive_a_save_and_a_load() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(WarDrafts.codes(back), [code])
	assert_eq(int(WarDrafts.of(back, code)["dest_x_m"]), int(WarDrafts.of(state, code)["dest_x_m"]))


func test_an_old_save_has_no_drafts() -> void:
	var d := state.to_dict()
	d.erase("war_drafts")
	assert_eq(GameState.from_dict(d).war_drafts, {})


func test_a_real_order_sets_the_draft_aside_and_says_so() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("ARMY_GARRISON", {"regiment": code})
	assert_eq(actions.validate(req, state), "")
	var out := actions.execute(req, state)
	assert_false(WarDrafts.any(state))
	var said := (out["effects"] as Array).filter(func(e: Dictionary) -> bool: return String(e.get("metric", "")) == "war_draft")
	assert_eq(said.size(), 1)
```

(`ActionSystem.new(repo)` as `tests/engine/test_action_system.gd` builds it; `execute` returns `{action_code, ok, effects, …}`.)

- [ ] **Step 2: Run** `$W/t.sh res://tests/engine/test_war_drafts.gd` — FAIL (`WarDrafts` missing).

- [ ] **Step 3: Implement** `scripts/engine/war_drafts.gd`:

```gdscript
class_name WarDrafts
extends RefCounted
## The WAR ROOM's drafts (owner 2026-10-02, spec 2026-10-02-war-room-v2 §3.1):
## an order pencilled on the table — no fee, no courier — until the council's
## resolutions are sealed (Game.deploy_drafts). One per regiment, the newest
## replacing the last, in whole metres; saved (GameState.war_drafts). A real
## order given the regiment elsewhere sets its draft aside (ActionSystem).

const MARCH := "march"
const GARRISON := "garrison"


static func plant(repo: DataRepository, state: GameState, code: String, order: String, dest_px: Vector2) -> void:
	var m := ArmySystem.pack_to_metres(repo, dest_px) if order == MARCH else Vector2i.ZERO
	state.war_drafts[code] = {"order": order, "dest_x_m": m.x, "dest_y_m": m.y,
		"tick": state.tick, "day": state.day, "refused": ""}


static func strike(state: GameState, code: String) -> bool:
	return state.war_drafts.erase(code)


static func any(state: GameState) -> bool:
	return not state.war_drafts.is_empty()


static func codes(state: GameState) -> Array:
	var out: Array = state.war_drafts.keys()
	out.sort()
	return out


static func of(state: GameState, code: String) -> Dictionary:
	return state.war_drafts.get(code, {})


static func dest_px(repo: DataRepository, draft: Dictionary) -> Vector2:
	return ArmySystem.metres_to_pack(repo, Vector2i(int(draft["dest_x_m"]), int(draft["dest_y_m"])))


## The real order a draft stands for.
static func request_of(repo: DataRepository, state: GameState, code: String) -> ActionRequest:
	return request_from(repo, code, of(state, code))


## The same, from a draft held in hand (Game.deploy_drafts strikes it first).
static func request_from(repo: DataRepository, code: String, draft: Dictionary) -> ActionRequest:
	if String(draft.get("order", "")) == MARCH:
		var to := dest_px(repo, draft)
		return ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": to.x, "y": to.y})
	return ActionRequest.make("ARMY_GARRISON", {"regiment": code})
```

`scripts/engine/game_state.gd`: beside `couriers`, declare

```gdscript
## The WAR ROOM's pencilled orders (spec 2026-10-02-war-room-v2 §3.1,
## WarDrafts): regiment code -> {order, dest_x_m, dest_y_m, tick, day, refused}.
var war_drafts: Dictionary = {}
```

in `to_dict` add `"war_drafts": _encode_values(war_drafts.duplicate(true)),` and in `from_dict` (beside the couriers) `s.war_drafts = _decode_values(d.get("war_drafts", {}))`. Check that `_decode_values` returns ints for `dest_x_m` (the encode keeps ints as ints; the round-trip test pins it).

`scripts/engine/action_system.gd`, at the top of both the `"ARMY_MARCH":` and `"ARMY_GARRISON":` execute branches (after `var reg := ...`):

```gdscript
			if state.war_drafts.erase(code):
				effects.append({"metric": "war_draft", "delta": 0.0,
					"reason": "%s's draft in the war room is set aside" % String(reg["label"])})
```

- [ ] **Step 4: Run** `$W/t.sh res://tests/engine/test_war_drafts.gd res://tests/engine` — PASS (the engine suite too: no other test sees a new effect metric it does not expect — if one asserts the exact effects list of a march, it gains nothing unless a draft exists).

- [ ] **Step 5: Commit** `feat(war-room): WarDrafts — pencilled orders, saved, set aside by a real order`.

---

### Task 2: `Game` writes the drafts and deploys them

**Files:**
- Modify: `scripts/ui/game.gd` (five methods)
- Test: `tests/ui/test_game_drafts.gd` (create)

**Interfaces:**
- Consumes: Task 1's `WarDrafts`.
- Produces: `Game.plant_draft(code: String, order: String, dest_px: Vector2) -> void`; `Game.strike_draft(code: String) -> void`; `Game.discard_drafts() -> void`; `Game.review_drafts() -> Dictionary` `{lines: [{code, label, order, to, days, gold, refusal}], total: int}`; `Game.deploy_drafts() -> Dictionary` `{sent: [code], refused: {code: reason}}`. Each writer emits `state_changed`.

- [ ] **Step 1: Failing tests** — create `tests/ui/test_game_drafts.gd`:

```gdscript
extends GutTest
## Game's drafts (spec 2026-10-02-war-room-v2 §3): planted, reviewed, sealed —
## each draft runs as the real order, in code order; what the chest cannot pay
## stays a draft with its reason.

var codes: Array = []


func before_each() -> void:
	Game.start_campaign(44)
	codes.clear()
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			codes.append(String(r["regiment_code"]))
	codes.sort()


func _near(code: String) -> Vector2:
	return ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code)) + Vector2(15, 0)


func test_review_lists_each_draft_with_its_cost_and_the_total() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	var r := Game.review_drafts()
	assert_eq((r["lines"] as Array).size(), 2)
	assert_eq(String(r["lines"][0]["code"]), codes[0], "in code order")
	var want := 0
	for l: Dictionary in r["lines"]:
		assert_gt(int(l["gold"]), 0)
		want += int(l["gold"])
	assert_eq(int(r["total"]), want)


func test_deploy_runs_every_draft_once_as_its_real_order() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	var riders := Game.state.couriers.size()
	var out := Game.deploy_drafts()
	assert_eq(out["sent"], [codes[0], codes[1]])
	assert_eq(Game.state.couriers.size(), riders + 2, "a courier each")
	assert_false(WarDrafts.any(Game.state))
	assert_eq(Game.deploy_drafts()["sent"], [], "nothing runs twice")


func test_what_the_chest_cannot_pay_stays_a_draft_with_its_reason() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "march", _near(codes[1]))
	var one := int(Game.review_drafts()["lines"][0]["gold"])
	Game.state.metrics["treasury"] = float(one)   # enough for the first only
	var r := Game.review_drafts()
	assert_eq(String(r["lines"][0]["refusal"]), "")
	assert_ne(String(r["lines"][1]["refusal"]), "", "the review says so before the seal")
	var out := Game.deploy_drafts()
	assert_eq(out["sent"], [codes[0]])
	assert_true((out["refused"] as Dictionary).has(codes[1]))
	assert_true(WarDrafts.any(Game.state))
	assert_ne(String(WarDrafts.of(Game.state, codes[1])["refused"]), "")


func test_discard_and_strike() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	Game.strike_draft(codes[0])
	assert_eq(WarDrafts.codes(Game.state), [codes[1]])
	Game.discard_drafts()
	assert_false(WarDrafts.any(Game.state))
```

(Every army order and its courier's fee are paid from `treasury` — `ActionSystem._apply(..., "treasury", ...)`, `OrderCosts.charge`.)

- [ ] **Step 2: Run** `$W/t.sh res://tests/ui/test_game_drafts.gd` — FAIL.

- [ ] **Step 3: Implement** in `scripts/ui/game.gd` (next to `try_execute`):

```gdscript
## The WAR ROOM's drafts (spec 2026-10-02-war-room-v2 §3): pencilled, not
## sent. Game is their only writer.
func plant_draft(code: String, order: String, dest_px: Vector2) -> void:
	WarDrafts.plant(data, state, code, order, dest_px)
	state_changed.emit()


func strike_draft(code: String) -> void:
	if WarDrafts.strike(state, code):
		state_changed.emit()


func discard_drafts() -> void:
	if WarDrafts.any(state):
		state.war_drafts.clear()
		state_changed.emit()


## The resolutions as they would be sealed now (spec §3.3): each draft's
## line — who, the order, where to, days, its gold — and why it would be
## refused. The gold is MEASURED, not summed from tables: each order is run on
## a copy of the state as the drafts before it leave it (the order's own cost,
## its always-rows and its courier's fee, whatever they are), so the review
## and the seal can never disagree; a line the chest cannot pay is refused and
## spends nothing, and the lines after it are counted without it.
func review_drafts() -> Dictionary:
	var lines: Array = []
	var total := 0
	var sim := GameState.from_dict(state.to_dict())
	for code: String in WarDrafts.codes(state):
		var req := WarDrafts.request_of(data, state, code)
		var reg := ArmySystem.regiment(data, code)
		var refusal := engine.actions.validate(req, sim)
		var gold := 0
		if refusal == "":
			var trial := GameState.from_dict(sim.to_dict())
			var chest := float(trial.metrics.get("treasury", 0.0))
			engine.actions.execute(req, trial)
			gold = int(round(chest - float(trial.metrics.get("treasury", 0.0))))
			if gold > int(chest):
				refusal = "The chest cannot pay for this one too."
			else:
				sim = trial
				total += gold
		var d := WarDrafts.of(state, code)
		var to := "where it stands"
		var days := 0
		if req.action_code == "ARMY_MARCH":
			var dest := WarDrafts.dest_px(data, d)
			to = Intel.place_label(data, state, dest)
			var from := ArmySystem.position_of(data, state, reg)
			days = ArmySystem.march_days(data, state, code, from.distance_to(dest) * float(ArmySystem.metres_per_pack_px(data)))
		lines.append({"code": code, "label": String(reg.get("label", code)), "order": String(d["order"]),
			"to": to, "days": days, "gold": gold, "refusal": refusal})
	return {"lines": lines, "total": total}


## Seal and send (spec §3.3): every draft the review passes runs through
## try_execute as its real order, in code order — a courier and a fee each;
## one the review refuses stays a draft with its reason. A draft is struck
## BEFORE its order runs, so ActionSystem's set-aside note never fires for its
## own deploy.
func deploy_drafts() -> Dictionary:
	var sent: Array = []
	var refused: Dictionary = {}
	for line: Dictionary in review_drafts()["lines"]:
		var code := String(line["code"])
		var d := WarDrafts.of(state, code)
		var why := String(line["refusal"])
		if why == "":
			state.war_drafts.erase(code)
			var out := try_execute(WarDrafts.request_from(data, code, d))
			if bool(out.get("ok", false)):
				sent.append(code)
				continue
			why = String(out.get("error", ""))
		d["refused"] = why
		state.war_drafts[code] = d
		refused[code] = why
	state_changed.emit()
	return {"sent": sent, "refused": refused}
```

(The draft is struck from the state before its order runs, so the order is built from the draft held in hand — `WarDrafts.request_from`, Task 1.)


- [ ] **Step 4: Run** `$W/t.sh res://tests/ui/test_game_drafts.gd res://tests/engine/test_war_drafts.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): Game plants, reviews, strikes and deploys the drafts`.

---

### Task 3: The WAR ROOM's order menu pencils drafts

**Files:**
- Modify: `scripts/ui/army_order_menu.gd` (`drafting`, COMMIT, the route menu, `_run` news), `scripts/ui/war_room_screen.gd` (`_orders.drafting = true`), `data/army_route_orders.csv` (rows `commit_draft`, `strike`), `scripts/engine/war_room.gd` (`pennant_of` does not change)
- Test: `tests/ui/test_war_room_screen.gd` (update the two COMMIT tests, add)

**Interfaces:**
- Consumes: Task 2's `Game.plant_draft`, `Game.strike_draft`.
- Produces: `ArmyOrderMenu.drafting: bool` — when true COMMIT plants a draft (`Game.plant_draft(code, "march", dest)`) and publishes "<label>'s march is pencilled in."; the route menu opens over a regiment WITH A DRAFT too, offering `edit` (re-aim; the next COMMIT replaces the draft) and `strike` (`STRIKE` id 202: `Game.strike_draft`); outside drafting nothing changes. `_run` also publishes any `war_draft` effect's reason (a real order on the 3D map that set a draft aside).

- [ ] **Step 1: Failing tests** — in `tests/ui/test_war_room_screen.gd`, change `test_a_real_drag_from_a_piece_commits_a_march_and_plants_a_riding_pennant` to expect a draft:

```gdscript
	screen.orders().id_pressed.emit(ArmyOrderMenu.COMMIT)
	await wait_process_frames(2)
	assert_eq(String(WarDrafts.of(Game.state, code).get("order", "")), "march", "the war room pencils a draft")
	assert_true(WarRoom.pennant_of(Game.data, Game.state, code).is_empty(), "no courier rides for a draft")
	assert_not_null((view.get_node("%Pennants") as WarPennants).pennant(code + "_draft"))
```

(rename it `test_a_real_drag_from_a_piece_pencils_a_draft`); change `test_a_click_on_a_riding_pennant_opens_edit_route_and_cancel_march` into `test_a_click_on_a_draft_pennant_offers_edit_and_strike` (the pennant hit is the draft's; assert `menu.get_item_index(ArmyOrderMenu.EDIT) >= 0`, `menu.get_item_index(ArmyOrderMenu.STRIKE) >= 0`, then `menu.id_pressed.emit(ArmyOrderMenu.STRIKE)` and `assert_false(WarDrafts.any(Game.state))`); and add:

```gdscript
func test_an_order_on_the_map_sets_the_rooms_draft_aside_and_says_so() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	Game.set_clock_speed(0)
	var code := String(_land_piece(r.war_room_screen())["code"])
	Game.plant_draft(code, "march", _land_near(r.war_room_screen(), ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))))
	r.war_room_screen().close()
	var heard: Array = []
	Game.news_published.connect(func(t: String) -> void: heard.append(t))
	var map_menu := r.current_screen.find_child("ArmyOrders", true, false) as ArmyOrderMenu
	assert_false(map_menu.drafting, "the 3D map's orders are sent at once")
	map_menu._run(ActionRequest.make("ARMY_GARRISON", {"regiment": code}))
	assert_false(WarDrafts.any(Game.state))
	assert_true(heard.any(func(t: String) -> bool: return t.contains("draft")), "the news says the draft is set aside")
```

(Closing the room with drafts will ASK from Task 5 on; this test calls `close()` directly, which stays the forced close.)

- [ ] **Step 2: Run** `$W/t.sh res://tests/ui/test_war_room_screen.gd` — FAIL.

- [ ] **Step 3: Implement** — `data/army_route_orders.csv` gains

```csv
commit_draft,Pencil it in,"A draft: no courier, no fee, until the council's resolutions are sealed","WAR ROOM v2 C (owner 2026-10-02, spec §3.1): the war room's COMMIT plants a draft"
strike,Strike the draft,Rub the pencilled march out,"WAR ROOM v2 C (spec §3.1): the route menu over a draft's pennant"
```

`scripts/ui/army_order_menu.gd`:

```gdscript
const STRIKE := 202

## The WAR ROOM's menu (spec 2026-10-02-war-room-v2 §3.1): COMMIT pencils a
## draft instead of sending the order, and the route menu opens over a draft.
var drafting := false
```

`_open_confirm`: `_add_row("commit_draft" if drafting else _row_key("commit", _aiming), COMMIT, "")`. `_commit`:

```gdscript
func _commit() -> void:
	if _aiming == "" or _pending.x < 0.0:
		return
	var code := _aiming
	var to := _pending
	_set_aim("")
	if drafting:
		Game.plant_draft(code, WarDrafts.MARCH, to)
		Game.publish_news("%s's march is pencilled in." % _name_of(code))
		return
	_run(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": to.x, "y": to.y}))
```

`_open_route` opens when the regiment has a draft too, and over a draft offers edit and strike:

```gdscript
func _open_route(code: String, at: Vector2) -> void:
	if Game.state == null:
		return
	var draft := drafting and WarDrafts.of(Game.state, code).size() > 0
	if not draft and ArmySystem.order_of(Game.data, Game.state, code) != ArmySystem.ORDER_MARCH \
			and WarRoom.pennant_of(Game.data, Game.state, code).is_empty():
		return
	_set_aim("")
	_code = code
	clear()
	_add_row("edit", EDIT, _paused_reason())
	if draft:
		_add_row("strike", STRIKE, "")
	else:
		_add_row(_row_key("halt", code), HALT, _paused_reason() if _paused_reason() != "" \
			else _refusal("ARMY_GARRISON", code))
	_pop(at)
```

`_on_chosen` gains `STRIKE: if _code != "": Game.strike_draft(_code); return`. In `_run`, right after the `ok` check and BEFORE the paused-clock early returns (a draft set aside must be said even on a stopped clock):

```gdscript
	var said: Dictionary = out.get("outcome", {})
	for e: Dictionary in said.get("effects", []):
		if String(e.get("metric", "")) == "war_draft":
			Game.publish_news(String(e["reason"]))
``` In `WarRoomScreen._ready()`: `_orders.drafting = true`.

The view's `route_clicked` pick must find draft pennants: Task 4 plants them as `code + "_draft"` nodes with `set_meta("code", code)` — `WarPennants.screen_hits` reads `meta("code")` (read it; if it reads the node name, read the meta instead).

- [ ] **Step 4: Run** `$W/t.sh res://tests/ui/test_war_room_screen.gd res://tests/ui/test_army_order_menu.gd` (whatever the menu's own tests are: `ls tests/ui | grep -i order`) — the screen tests need Task 4's draft pennant; if `pennant(code + "_draft")` fails only for that, do Task 4 before committing this one and commit both together. Ledger the order.

- [ ] **Step 5: Commit** `feat(war-room): the room's COMMIT pencils a draft; a draft's pennant offers edit and strike`.

---

### Task 4: Draft pennants and pencil lines

**Files:**
- Modify: `scripts/war_room/war_pennants.gd` (draft pennants), `scripts/war_room/war_room_rake.gd` (`_routes` + drafts), `scripts/war_room/war_hud.gd` (pencil lines), `data/balance.csv` (`war_draft_alpha`, `war_draft_pencil_*`), `data/war_palette.csv` (`pencil`)
- Test: `tests/war_room/test_war_room_view.gd`

**Interfaces:**
- Consumes: `WarDrafts.of`, `dest_px` (the state handed to the view).
- Produces: a draft pennant node named `<code>_draft` (meta `code`, meta `draft` true), translucent (`GeometryInstance3D.transparency` = 1 − `war_draft_alpha` on every mesh), its slip "draft"; `WarHud.draw_state(..., routes, drafts: Array = [])` draws each `[a, b]` in `drafts` as a pencil line (`pencil`, `war_draft_pencil_px`, dashed `war_draft_pencil_dash_px`).

- [ ] **Step 1: Failing test** — append to `tests/war_room/test_war_room_view.gd`:

```gdscript
func test_a_draft_plants_a_pale_pennant_with_a_draft_slip() -> void:
	var p: Dictionary = WarRoom.pieces(repo, state)[0]
	var code := String(p["code"])
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	WarDrafts.plant(repo, state, code, "march", (p["at"] as Vector2) + Vector2(10, 0))
	view.refresh()
	await wait_process_frames(1)
	var pen := (view.get_node("%Pennants") as WarPennants).pennant(code + "_draft")
	assert_not_null(pen)
	assert_eq(String(pen.get_meta("code")), code)
	assert_eq((pen.get_node("Slip") as Label3D).text, "draft")
	for m: MeshInstance3D in Map3DUnits.meshes(pen):
		assert_almost_eq(m.transparency, 1.0 - repo.bal("war_draft_alpha"), 0.001)
	WarDrafts.strike(state, code)
	view.refresh()
	await wait_process_frames(1)
	assert_null((view.get_node("%Pennants") as WarPennants).pennant(code + "_draft"))
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** — in `WarPennants.rebuild`, after the real pennants' `want`, for each piece with a draft: `var d := WarDrafts.of(state, code); if d.size() > 0 and String(d["order"]) == WarDrafts.MARCH: var at := WarDrafts.dest_px(_repo, d); if rect.has_point(at): want.append([code + "_draft", at, "draft", 0])`. `SLIPS` gains `"draft": "draft"`. In `_build`, set `root.set_meta("code", code.trim_suffix("_draft"))` and, when `status == "draft"`, `root.set_meta("draft", true)` and after the art is added, `for m: MeshInstance3D in Map3DUnits.meshes(root): m.transparency = 1.0 - _repo.bal("war_draft_alpha")`, and the slip's `modulate.a = _repo.bal("war_draft_alpha")`. `WarRoomRake._routes()` stays the real pennants'; add `_drafts()` returning `[[piece_screen_px, draft_dest_screen_px], ...]` for the laid sheet's drafted regiments (same projection code as `_routes`), and pass it as `draw_state`'s new last argument. `WarHud` stores `_drafts` and in `_draw` draws each as `WarSheetInk.dashed` pieces in `pencil` at `war_draft_pencil_px`. Balance:

```csv
war_draft_alpha,0.45,"WAR ROOM v2 C (spec §3.1): a draft pennant's opacity — pencilled, not planted"
war_draft_pencil_px,1.4,"WAR ROOM v2 C (spec §3.1): the pencil line from a piece to its draft, screen px"
war_draft_pencil_dash_px,5,"WAR ROOM v2 C (spec §3.1): its dashes, screen px"
```

Palette: `pencil,#5A5048CC,"WAR ROOM v2 C: graphite on vellum — a draft's line"`. Add the keys to `tests/engine/test_war_room_data.gd`.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/ui/test_war_room_screen.gd res://tests/engine/test_war_room_data.gd` — PASS (Task 3's tests too).

- [ ] **Step 5: Commit** `feat(war-room): a draft is a pale pennant with a pencil line`.

---

### Task 5: Leaving the room with drafts asks

**Files:**
- Create: `scripts/ui/war_leave_prompt.gd`
- Modify: `scenes/war_room_screen.tscn` (`%LeavePrompt`), `scripts/ui/war_room_screen.gd` (`request_close`, `ask_leave`), `scripts/ui/game_root.gd` (`leave_war_room`; every door), `data/balance.csv` (none)
- Test: `tests/ui/test_war_room_screen.gd`

**Interfaces:**
- Produces: `WarLeavePrompt` (PanelContainer): `signal chosen(choice: String)` — `"deploy"`, `"discard"`, `"keep"`, `"stay"` (Escape / ×); `open() -> void`. `WarRoomScreen.ask_leave(then: Callable) -> void`; `WarRoomScreen.request_close() -> void` (the × button: `GameRoot.leave_war_room(Callable())`). `GameRoot.leave_war_room(then: Callable) -> void` — not visible: `then`; no drafts: `close()` then `then`; drafts: `ask_leave(then)`. `deploy` opens the deploy scroll's review (Task 6) and, once sealed, closes the room and runs `then`; `discard` → `Game.discard_drafts()`, close, `then`; `keep` → close, `then`; `stay` → nothing.

- [ ] **Step 1: Failing tests** — append to `tests/ui/test_war_room_screen.gd`:

```gdscript
func _room_with_a_draft() -> GameRoot:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var code := String(_land_piece(r.war_room_screen())["code"])
	Game.plant_draft(code, "march", ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code)) + Vector2(10, 0))
	return r


func test_another_tab_with_drafts_asks_and_stay_keeps_the_room() -> void:
	var r: GameRoot = await _room_with_a_draft()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(1)
	var prompt := r.war_room_screen().get_node("%LeavePrompt") as WarLeavePrompt
	assert_true(prompt.visible, "asked")
	assert_true(r.war_room_screen().visible)
	assert_false(r.ledger_screen().visible, "not gone yet")
	prompt.chosen.emit("stay")
	await wait_process_frames(1)
	assert_true(r.war_room_screen().visible)
	assert_true(WarDrafts.any(Game.state), "nothing lost")


func test_keep_leaves_and_goes_on_and_the_drafts_stay() -> void:
	var r: GameRoot = await _room_with_a_draft()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(1)
	(r.war_room_screen().get_node("%LeavePrompt") as WarLeavePrompt).chosen.emit("keep")
	await wait_process_frames(2)
	assert_false(r.war_room_screen().visible)
	assert_true(r.ledger_screen().visible, "the tab the player chose opens")
	assert_true(WarDrafts.any(Game.state))


func test_discard_leaves_with_none() -> void:
	var r: GameRoot = await _room_with_a_draft()
	r.war_room_screen().request_close()
	await wait_process_frames(1)
	(r.war_room_screen().get_node("%LeavePrompt") as WarLeavePrompt).chosen.emit("discard")
	await wait_process_frames(1)
	assert_false(r.war_room_screen().visible)
	assert_false(WarDrafts.any(Game.state))


func test_no_drafts_no_question() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(1)
	assert_false(r.war_room_screen().visible)
	assert_false((r.war_room_screen().get_node("%LeavePrompt") as WarLeavePrompt).visible)
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** — `scripts/ui/war_leave_prompt.gd`:

```gdscript
class_name WarLeavePrompt
extends PanelContainer
## Leaving the WAR ROOM with orders still pencilled (owner 2026-10-02, spec
## 2026-10-02-war-room-v2 §3.2): Deploy (unroll the resolutions), Discard (rub
## them out), Keep (they stay, saved, on the table next time) — or Escape / ×
## to stay in the room. A leather window, as everything held up to the eye.

signal chosen(choice: String)


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 18, "window"))
	UiPalette.style_title(%Question, 18)
	for pair: Array in [[%Deploy, "deploy"], [%Discard, "discard"], [%Keep, "keep"], [%Stay, "stay"]]:
		var b := pair[0] as Button
		UiPalette.command_button(b)
		b.pressed.connect(_choose.bind(String(pair[1])))
	UiPalette.primary_button(%Deploy, 15)


func open() -> void:
	visible = true
	(%Deploy as Button).grab_focus()


func _choose(choice: String) -> void:
	visible = false
	chosen.emit(choice)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.keycode == KEY_ESCAPE:
		_choose("stay")
		get_viewport().set_input_as_handled()
```

In `scenes/war_room_screen.tscn` add, after `Folio`:

```
[node name="LeavePrompt" type="PanelContainer" parent="."]
unique_name_in_owner = true
visible = false
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -230.0
offset_top = -90.0
offset_right = 230.0
offset_bottom = 90.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("6_leave")

[node name="Col" type="VBoxContainer" parent="LeavePrompt"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Question" type="Label" parent="LeavePrompt/Col"]
unique_name_in_owner = true
layout_mode = 2
text = "Orders are still pencilled on the table."
horizontal_alignment = 1
autowrap_mode = 3

[node name="Row" type="HBoxContainer" parent="LeavePrompt/Col"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 10

[node name="Deploy" type="Button" parent="LeavePrompt/Col/Row"]
unique_name_in_owner = true
layout_mode = 2
text = "Deploy…"

[node name="Discard" type="Button" parent="LeavePrompt/Col/Row"]
unique_name_in_owner = true
layout_mode = 2
text = "Discard"

[node name="Keep" type="Button" parent="LeavePrompt/Col/Row"]
unique_name_in_owner = true
layout_mode = 2
text = "Keep"

[node name="Stay" type="Button" parent="LeavePrompt/Col/Row"]
unique_name_in_owner = true
layout_mode = 2
text = "Stay"
```

with `[ext_resource type="Script" path="res://scripts/ui/war_leave_prompt.gd" id="6_leave"]` and `load_steps` +1.

`scripts/ui/war_room_screen.gd`:

```gdscript
var _leave_then := Callable()


## The × button: leave through GameRoot's one door (a question when drafts stand).
func request_close() -> void:
	var root := get_parent() as GameRoot
	if root != null:
		root.leave_war_room(Callable())
	else:
		close()


## Ask before leaving with drafts (spec §3.2); `then` runs once the room is left.
func ask_leave(then: Callable) -> void:
	_leave_then = then
	(%LeavePrompt as WarLeavePrompt).open()


func _on_leave(choice: String) -> void:
	var then := _leave_then
	_leave_then = Callable()
	match choice:
		"discard":
			Game.discard_drafts()
			close()
		"keep":
			close()
		_:
			return   # stay ("deploy" is Task 6's: it unrolls the scroll)
	if then.is_valid():
		then.call()
```

In `_ready()`: `%Close.pressed.connect(request_close)` (replacing `close`), `(%LeavePrompt as WarLeavePrompt).chosen.connect(_on_leave)`. Until Task 6 the prompt's Deploy button behaves as Stay.

`scripts/ui/game_root.gd`:

```gdscript
## The one door out of the WAR ROOM (spec 2026-10-02-war-room-v2 §3.2): with
## drafts on the table the room asks first; `then` runs once it is left.
func leave_war_room(then: Callable) -> void:
	if _war_room_screen == null or not _war_room_screen.visible:
		if then.is_valid():
			then.call()
		return
	if not WarDrafts.any(Game.state):
		_war_room_screen.close()
		if then.is_valid():
			then.call()
		return
	_war_room_screen.ask_leave(then)
```

Route every door through it:
- `toggle_war_room`: `if _war_room_screen.visible: leave_war_room(Callable()); return`.
- `toggle_ledger` and `toggle_missives`: at their top, `if _war_room_screen.visible and WarDrafts.any(Game.state): leave_war_room(toggle_ledger); return` (resp. `toggle_missives`), so the call comes back once the room is left; keep their existing `_war_room_screen.close()` line for the no-draft case.
- `_on_bottom_tab(tab)`: first line `if tab != "WAR ROOM" and _war_room_screen.visible and WarDrafts.any(Game.state): leave_war_room(_on_bottom_tab.bind(tab)); return`.
- `_on_missive_show` (the board's Show on map): wrap its `_war_room_screen.close()` the same way (`leave_war_room(_on_missive_show.bind(subject)); return` when drafts stand).
- Quit to Desktop: `_menu_button("Quit to Desktop", func() -> void: leave_war_room(get_tree().quit))`.
- `_switch_to`'s `close(false)` stays FORCED (an event, a restart): the drafts are kept; add `if WarDrafts.any(Game.state): Game.publish_news("The war room's drafts are kept on the table.")` before it.

- [ ] **Step 4: Run** `$W/t.sh res://tests/ui/test_war_room_screen.gd res://tests/ui` — PASS (other UI tests that switch tabs with no drafts are unaffected).

- [ ] **Step 5: Commit** `feat(war-room): leaving with drafts asks — Deploy, Discard, Keep or Stay`.

---

### Task 6: The resolutions scroll — review, seal and send

**Files:**
- Create: `scripts/ui/war_deploy_scroll.gd`
- Modify: `scenes/war_room_screen.tscn` (`%Deploy`), `scripts/ui/war_room_screen.gd` (wiring, `_deploy_then`), `data/balance.csv` (`war_deploy_*`)
- Test: `tests/ui/test_war_deploy_scroll.gd` (create), `tests/ui/test_war_room_screen.gd`

**Interfaces:**
- Consumes: `Game.review_drafts`, `Game.deploy_drafts`, `HouseArms.texture_of_house` (the crown's arms; `council_seal.png` the fallback), `EnvelopeFlight.fly(host, from, to, big, repo)`.
- Produces: `WarDeployScroll` (Control, bottom-right of the room): the rolled button (greyed with no drafts); `unroll()` shows the review — title "Resolutions of the council", one line per `review_drafts` line ("<label> → <to> · <days> days · <gold> gold", red with its refusal), the total, **Seal and send** and **Not yet**; `seal()` plays the seal (`war_deploy_wax_s`, `_press_s`, `_roll_s`) then flies (`EnvelopeFlight`) and calls `Game.deploy_drafts()` ONCE; `signal sealed(result: Dictionary)`; `signal withdrawn`; `sealing() -> bool`.

- [ ] **Step 1: Failing tests** — create `tests/ui/test_war_deploy_scroll.gd`:

```gdscript
extends GutTest
## The council's resolutions (spec 2026-10-02-war-room-v2 §3.3): the scroll
## lists the drafts with their costs, the seal sends them once.

var scroll: WarDeployScroll
var codes: Array = []


func before_each() -> void:
	Game.start_campaign(44)
	codes.clear()
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			codes.append(String(r["regiment_code"]))
	codes.sort()
	scroll = WarDeployScroll.new()
	scroll.size = Vector2(1000, 600)
	add_child_autofree(scroll)
	await wait_process_frames(1)


func _draft(i: int) -> void:
	Game.plant_draft(codes[i], "march", ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, codes[i])) + Vector2(12, 0))


func test_the_button_is_grey_without_drafts() -> void:
	scroll.refresh()
	assert_true(scroll.button().disabled)
	_draft(0)
	scroll.refresh()
	assert_false(scroll.button().disabled)


func test_unrolled_it_lists_each_draft_and_the_total() -> void:
	_draft(0)
	_draft(1)
	scroll.unroll()
	await wait_process_frames(1)
	assert_true(scroll.review_open())
	assert_eq(scroll.line_labels().size(), 2)
	assert_string_contains(scroll.total_text(), str(int(Game.review_drafts()["total"])))


func test_the_seal_sends_once_however_often_it_is_pressed() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	var riders := Game.state.couriers.size()
	scroll.seal()
	scroll.seal()   # pressed again while the wax is still warm
	assert_true(scroll.sealing())
	await wait_seconds(Game.data.bal("war_deploy_wax_s") + Game.data.bal("war_deploy_press_s")
		+ Game.data.bal("war_deploy_roll_s") + 1.2)
	assert_signal_emit_count(scroll, "sealed", 1)
	assert_eq(Game.state.couriers.size(), riders + 1)
	assert_false(WarDrafts.any(Game.state))


func test_not_yet_rolls_it_away_and_keeps_the_drafts() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	scroll.withdraw()
	assert_false(scroll.review_open())
	assert_signal_emitted(scroll, "withdrawn")
	assert_true(WarDrafts.any(Game.state))
```

and in `tests/ui/test_war_room_screen.gd`:

```gdscript
func test_deploy_from_the_leave_prompt_seals_then_leaves_for_the_chosen_tab() -> void:
	var r: GameRoot = await _room_with_a_draft()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(1)
	(r.war_room_screen().get_node("%LeavePrompt") as WarLeavePrompt).chosen.emit("deploy")
	var scroll := r.war_room_screen().get_node("%Deploy") as WarDeployScroll
	assert_true(scroll.review_open())
	scroll.seal()
	await wait_until(func() -> bool: return not r.war_room_screen().visible, 6.0)
	assert_true(r.ledger_screen().visible)
	assert_false(WarDrafts.any(Game.state))
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `scripts/ui/war_deploy_scroll.gd` — a Control laid over the whole room (mouse IGNORE except its own children) holding: the button (a `Button` `%ScrollButton`, flat, drawn as a rolled vellum scroll with a red ribbon by its own `draw` callback — a parchment rect with two `WarReportRoll.draw_roller` ends and a ribbon band in `rubric`), anchored bottom-right `war_deploy_button_px` square with `war_deploy_margin_px`; and the review (`%Review`, a `PaperStyle` panel centred, `war_deploy_review_w_px` wide, rollers top and bottom) with `%Lines` (VBox of Labels in `UiPalette.ink("soft")`, a refused one in `UiPalette.ink("bad")` with its reason in a second line), `%Total`, `%Seal` and `%NotYet` buttons.

```gdscript
class_name WarDeployScroll
extends Control
## The council's resolutions (owner 2026-10-02: 右下角新增一个deploy按钮（做成
## 机密卷轴密封的动画）; spec 2026-10-02-war-room-v2 §3.3): a rolled scroll
## bottom right, grey with nothing pencilled; unrolled, the drafts as lines
## with their costs and reasons; sealed — wax, the crown's seal pressed, rolled,
## tied and flown — every draft runs once as its real order (Game.deploy_drafts).

signal sealed(result: Dictionary)
signal withdrawn

var _phase := ""      # "", "wax", "press", "roll", "fly"
var _t := 0.0
var _seal_tex: Texture2D


func button() -> Button:
	return %ScrollButton


func review_open() -> bool:
	return (%Review as Control).visible


func sealing() -> bool:
	return _phase != ""


func refresh() -> void:
	button().disabled = Game.state == null or not WarDrafts.any(Game.state) or sealing()


func unroll() -> void:
	if sealing():
		return
	var r := Game.review_drafts()
	for c in %Lines.get_children():
		%Lines.remove_child(c)
		c.queue_free()
	for l: Dictionary in r["lines"]:
		var lab := Label.new()
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var what := "%s → %s · %d day%s" % [l["label"], l["to"], int(l["days"]), "" if int(l["days"]) == 1 else "s"] \
			if String(l["order"]) == WarDrafts.MARCH else "%s stands to its post" % l["label"]
		lab.text = "%s · %s gold" % [what, WarRoom.group(int(l["gold"]))]
		if String(l["refusal"]) != "":
			lab.text += "\n   " + String(l["refusal"])
			lab.add_theme_color_override("font_color", UiPalette.ink("bad"))
		else:
			lab.add_theme_color_override("font_color", UiPalette.ink("soft"))
		%Lines.add_child(lab)
	(%Total as Label).text = "In all · %s gold" % WarRoom.group(int(r["total"]))
	(%Review as Control).visible = true


func line_labels() -> Array:
	return %Lines.get_children()


func total_text() -> String:
	return (%Total as Label).text


func withdraw() -> void:
	if sealing():
		return
	(%Review as Control).visible = false
	withdrawn.emit()


## Seal and send: the wax, the press, the roll, the flight, then the orders —
## once, however often it is pressed.
func seal() -> void:
	if sealing() or not review_open():
		return
	_phase = "wax"
	_t = 0.0
	refresh()


func _process(delta: float) -> void:
	if _phase == "" or _phase == "fly":
		return
	_t += delta
	var need := Game.data.bal("war_deploy_%s_s" % _phase)
	if _t >= need:
		_t = 0.0
		match _phase:
			"wax": _phase = "press"
			"press": _phase = "roll"
			"roll":
				_phase = "fly"
				_fly()
	(%Review as Control).queue_redraw()


func _fly() -> void:
	var from := (%Review as Control).get_global_rect()
	(%Review as Control).visible = false
	var to := Rect2(Vector2(get_viewport_rect().size.x + 80.0, from.position.y), from.size * 0.2)
	var f := EnvelopeFlight.fly(self, from, to, true, Game.data)
	f.landed.connect(_send)


func _send() -> void:
	var result := Game.deploy_drafts()
	_phase = ""
	refresh()
	var n := (result["sent"] as Array).size()
	Game.publish_news("The council's resolutions are sealed: %d courier%s ride%s." % [n, "" if n == 1 else "s", "s" if n == 1 else ""])
	sealed.emit(result)
```

The review's `draw` callback (connect `%Review.draw`) paints, by `_phase` and `_t / need`: a wax blob growing under the last line (`wax`: a `UiPalette`/war-table wax colour circle, `ui_table_palette` `wax_mid`), the crown's arms pressed into the wax (`press`: `_seal_tex` scaling from 1.35 to 1.0 at its spot), and the paper's height shrinking toward a roller (`roll`: draw a covering rect of the room behind it? — simpler: tween `%Review.scale.y` from 1 to 0.08 about its centre during `roll`). `EnvelopeFlight.fly(host: Control, from, to, big, repo)` adds itself under `host` and emits `landed` (no arguments) when it arrives.

Scene: in `scenes/war_room_screen.tscn` add `%Deploy` (full-rect Control, `mouse_filter` 2, script `war_deploy_scroll.gd`) with children `%ScrollButton` (Button, anchored bottom-right) and `%Review` (PanelContainer, centred, hidden) → VBox → `Title` Label "Resolutions of the council", `%Lines` VBox, `%Total` Label, HBox → `%Seal` Button "Seal and send", `%NotYet` Button "Not yet". In the script's `_ready`: style `%Review` with `WarTable.report_style()` (or the column panel style under the leather chrome), `UiPalette.style_title` the title, `UiPalette.primary_button(%Seal, 15)`, `UiPalette.command_button(%NotYet)`, connect `%ScrollButton.pressed → unroll`, `%Seal.pressed → seal`, `%NotYet.pressed → withdraw`, take `_seal_tex` from the crown's own arms (spec §3.3: the crown's seal) — `HouseArms.texture_of_house(Game.data, Game.state, HouseArms.royal_family(Game.data))` — and fall back to `res://assets/2D/ui/war_table/council_seal.png`, then to a plain wax disc.

`WarRoomScreen`: declare `var _deploy_then := Callable()` and give `_on_leave` its deploy branch, above the `_:` case:

```gdscript
		"deploy":
			_deploy_then = then   # the seal closes the room and runs it (_on_sealed)
			(%Deploy as WarDeployScroll).unroll()
			return
```

`refresh()` and `open()` call `(%Deploy as WarDeployScroll).refresh()`; `_ready` connects `sealed` to

```gdscript
func _on_sealed(_result: Dictionary) -> void:
	var then := _deploy_then
	_deploy_then = Callable()
	if then.is_valid():   # deploying on the way out: leave, then go on
		close()
		then.call()
```

and `withdrawn` to `func(): _deploy_then = Callable()` (Not yet from the leave prompt's Deploy: the player stays in the room).

Balance:

```csv
war_deploy_button_px,64,"WAR ROOM v2 C (spec §3.3): the rolled scroll's size bottom right, design px"
war_deploy_margin_px,18,"WAR ROOM v2 C: its margin from the room's corner, design px"
war_deploy_review_w_px,520,"WAR ROOM v2 C (spec §3.3): the unrolled resolutions' width, design px"
war_deploy_wax_s,0.35,"WAR ROOM v2 C (spec §3.3): seconds the wax takes to drip"
war_deploy_press_s,0.3,"WAR ROOM v2 C: seconds the crown's seal takes to press"
war_deploy_roll_s,0.45,"WAR ROOM v2 C: seconds the sealed scroll takes to roll before it flies"
```

and the data test's list.

- [ ] **Step 4: Run** `$W/t.sh res://tests/ui/test_war_deploy_scroll.gd res://tests/ui/test_war_room_screen.gd res://tests/ui/test_game_drafts.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): the council's resolutions — a scroll to review, seal and send the drafts`.

---

### Task 7: Shots, review, documents, the suite

**Files:**
- Modify: `tools/snapshot_screen.gd` (`--war-deploy review|seal`, `--war-leave TAB`), `CLAUDE.md`, the spec's §12

- [ ] **Step 1: Flags** — `--war-deploy review` (after any `--war-drag --war-commit`, which now pencils a draft): a real click on `%Deploy`'s `%ScrollButton`, moment `war` when the review is open; `--war-deploy seal` then a real click on `%Seal`, moment after `war_deploy_*` seconds + the flight. `--war-leave TAB`: a real click on that bottom tab with drafts standing; the moment shows the prompt. Document both in the `--war-room` comment block.

- [ ] **Step 2: Shoot** (real window, `--resolution 2560x1600`): a draft pencilled (`--war-piece CODE --war-drag fx,fy --war-commit`), the review, mid-seal, the leave prompt. Visual review (the skill): contact sheet + an independent critic; fix what breaks a principle (sizes, alphas, colours — all data).

- [ ] **Step 3: Documents** — CLAUDE.md's WAR ROOM paragraph, after the rake's sentence about COMMIT: "Since v2's plan C (spec §3) the room's COMMIT PENCILS A DRAFT (`ArmyOrderMenu.drafting`, `WarDrafts`, `GameState.war_drafts` saved): a pale pennant (`war_draft_alpha`) with a pencil line, no courier and no fee; a draft's pennant offers Edit route… and Strike the draft; a real order to the regiment on the 3D map sets its draft aside (`ActionSystem`, a `war_draft` effect the news reads). The resolutions scroll bottom right (`WarDeployScroll`, `war_deploy_*`) unrolls the drafts with their days and gold (`Game.review_drafts`, the chest counted down in code order, a refused line red with its reason), and Seal and send drips the wax, presses the crown's seal, rolls it and flies it off before every draft runs ONCE as its real order (`Game.deploy_drafts`; a refused one stays a draft with its reason). Leaving by any door with drafts asks Deploy / Discard / Keep / Stay (`WarLeavePrompt`, `GameRoot.leave_war_room`, the one door; an event's forced switch keeps them silently)." In the spec's §12, note any ruling of this plan worth keeping.

- [ ] **Step 4: The full suite** — `./run_tests.sh` — all pass, exit 0.

- [ ] **Step 5: Commit** `docs + tools: the WAR ROOM's drafts and their seal`.
