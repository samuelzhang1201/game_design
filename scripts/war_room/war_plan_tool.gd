class_name WarPlanTool
extends RefCounted
## The staff's tools in the player's hand (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §2.4, 2026-10-08-war-room-draw-orders
## rulings 1-3): the SIDE chosen (red theirs, blue ours; "" none yet — nothing
## draws until one is) and the kind of mark in hand ("" the hand); a drag drawn
## freehand in pack px, sampled every war_plan_sample_px of pointer travel and
## smoothed on release to war_plan_points_max points (Shift: straight); a ring
## drawn as a compass; a stroke or its handle picked on the screen; the
## session's undo. Pure: the view routes the pointer here and hands what is
## drawn to the screen, which writes it.

const HAND := "hand"
const SIDES := ["red", "blue"]

var side := ""
var kind := ""
var drawing := false
var _last := {"red": "front", "blue": "front"}   # each side's kind last in hand
var _samples := PackedVector2Array()   # pack px
var _screen := PackedVector2Array()    # the same samples on the screen
var _repo: DataRepository
var _undo: Array = []
var _redo: Array = []
var _owner := 0


func _init(repo: DataRepository) -> void:
	_repo = repo


## A side and a kind are in hand: a left press draws.
func in_hand() -> bool:
	return side != "" and kind != ""


## The colour what is drawn now takes (its side's).
var stick: String:
	get:
		return side if in_hand() else HAND


func _gesture(k: String) -> String:
	return String((_repo.war_plan_kinds.get(k, {}) as Dictionary).get("gesture", "path"))


## Takes kind `k` on side `sd`; false when either is unknown.
func pick(sd: String, k: String) -> bool:
	if not sd in SIDES or not _repo.war_plan_kinds.has(k):
		return false
	side = sd
	kind = k
	_last[sd] = k
	drawing = false
	return true


## Takes kind `k` on the side chosen; false with no side yet.
func pick_kind(k: String) -> bool:
	return pick(side, k) if side != "" else false


## A row's crayon: that side lit with NOTHING in hand — the side's select
## stick (a click selects, a drag on open table boxes that side's pieces;
## owner 2026-10-11). The hand (no slot of its own; R4): nothing in hand and no
## side lit (a drag pans) — also what the lit crayon, clicked again, drops to.
func pick_stick(s: String, lit := false) -> void:
	if s == HAND or (lit and s == side and kind == ""):
		put_down()
		side = ""
		return
	if not s in SIDES:
		return
	put_down()
	side = s


## Tab: the other side, the same kind in hand (`fallback` when the same
## cannot be used there); with nothing in hand, that side's last kind.
func switch_side(fallback := "") -> void:
	var to := "blue" if side != "blue" else "red"
	pick(to, fallback if fallback != "" else (kind if kind != "" else last_kind(to)))


## The kind last in hand on a side.
func last_kind(sd: String) -> String:
	return String(_last.get(sd, "front"))


## Esc or the hand: nothing in hand (the side stays lit).
func put_down() -> void:
	kind = ""
	drawing = false
	_samples.clear()
	_screen.clear()


## A drag ended without a stroke (a click): the kind stays in hand.
func cancel() -> void:
	drawing = false
	_samples.clear()
	_screen.clear()


func press(pack_px: Vector2, screen_px: Vector2) -> void:
	if not in_hand() or pack_px.x < 0.0:
		return
	drawing = true
	_samples = PackedVector2Array([pack_px])
	_screen = PackedVector2Array([screen_px])


func move(pack_px: Vector2, screen_px: Vector2) -> void:
	if not drawing or pack_px.x < 0.0:
		return
	if _gesture(kind) == "ring":
		_samples.resize(1)
		_screen.resize(1)
		_samples.append(pack_px)
		_screen.append(screen_px)
		return
	if screen_px.distance_to(_screen[_screen.size() - 1]) >= _repo.bal("war_plan_sample_px"):
		_samples.append(pack_px)
		_screen.append(screen_px)


## The drag's points so far, pack px (a ring: its centre and the pointer).
func preview() -> PackedVector2Array:
	return _samples


## The drag let go: {kind, colour, pts (pack px), r (pack px)} to draw, or {}
## for a drag shorter than war_plan_min_len_px on the screen. `px_per_pack`:
## screen px a pack px now (the smoothing's tolerance is the screen's).
func release(pack_px: Vector2, screen_px: Vector2, shift: bool, px_per_pack: float) -> Dictionary:
	if not drawing:
		return {}
	drawing = false
	if pack_px.x >= 0.0:
		_samples.append(pack_px)
		_screen.append(screen_px)
	var travel := 0.0
	for i in range(1, _screen.size()):
		travel = maxf(travel, _screen[0].distance_to(_screen[i]))
	var samples := _samples
	_samples = PackedVector2Array()
	_screen = PackedVector2Array()
	if travel < _repo.bal("war_plan_min_len_px") or samples.size() < 2:
		return {}
	var out := {"kind": kind, "colour": side, "r": 0.0, "samples": samples}
	if _gesture(kind) == "ring":
		out["pts"] = PackedVector2Array([samples[0]])
		out["r"] = samples[0].distance_to(samples[samples.size() - 1])
	elif shift:
		out["pts"] = PackedVector2Array([samples[0], samples[samples.size() - 1]])
	else:
		var tol := _repo.bal("war_plan_simplify_px") / maxf(px_per_pack, 0.0001)
		out["pts"] = WarPlanGeometry.simplify(samples, tol, int(_repo.bal("war_plan_points_max")))
	return out


## What a screen point picks among `strokes` ({id, kind, ctrl, r}, screen
## px): the chosen stroke's handle first (a ring's: 0 its centre, 1 its rim
## east of it), then the nearest line or rim within `radius`; {id, handle} or {}.
static func hit(repo: DataRepository, strokes: Array, at: Vector2, chosen: String, radius: float) -> Dictionary:
	for s: Dictionary in strokes:
		if String(s["id"]) != chosen:
			continue
		var handles := handles_of(repo, s)
		for i in handles.size():
			if handles[i].distance_to(at) <= radius:
				return {"id": chosen, "handle": i}
	var best := {}
	var best_d := radius
	for s: Dictionary in strokes:
		var ctrl: PackedVector2Array = s["ctrl"]
		var d := WarPlanGeometry.ring_hit(ctrl[0], float(s["r"]), at) \
			if String((repo.war_plan_kinds.get(String(s["kind"]), {}) as Dictionary).get("gesture", "")) == "ring" \
			else WarPlanGeometry.hit(WarPlanGeometry.curve(ctrl, 4.0), at)
		if d <= best_d:
			best_d = d
			best = {"id": String(s["id"]), "handle": -1}
	return best


## A stroke's handles on the screen: its control points; a ring its centre
## and a point on its rim.
static func handles_of(repo: DataRepository, s: Dictionary) -> PackedVector2Array:
	var ctrl: PackedVector2Array = s["ctrl"]
	if String((repo.war_plan_kinds.get(String(s["kind"]), {}) as Dictionary).get("gesture", "")) == "ring":
		return PackedVector2Array([ctrl[0], ctrl[0] + Vector2(float(s["r"]), 0.0)])
	return ctrl


## Before an edit: the plans as they were (a deep copy is the caller's).
func remember(before: Dictionary) -> void:
	_push({"plans": before})


## A drawn march or halt pencilled: each regiment's draft as it was ({} =
## none) and as it was left (`after`), so the step is put back only while the
## drafts are still as it left them.
func remember_drafts(before: Dictionary, after: Dictionary = {}) -> void:
	_push({"drafts": before, "expect": after})


func _push(entry: Dictionary) -> void:
	_undo.append(entry)
	while _undo.size() > int(_repo.bal("war_plan_undo_max")):
		_undo.pop_front()
	_redo.clear()


## The stacks belong to one game: a different state (a new campaign, a load)
## empties them.
func own(state_id: int) -> void:
	if state_id != _owner:
		_owner = state_id
		_undo.clear()
		_redo.clear()


## The entry to put back ({"plans": …} or {"drafts": …}); {} when there is
## nothing to undo. `now_of(entry)` gives the present counterpart, kept for redo.
## `holds(entry)`, when given, says whether the entry still applies: one that
## does not is dropped and {"stale": true} returned (the next is not tried).
func undo(now_of: Callable, holds := Callable()) -> Dictionary:
	return _step(_undo, _redo, now_of, holds)


func redo(now_of: Callable, holds := Callable()) -> Dictionary:
	return _step(_redo, _undo, now_of, holds)


func _step(from: Array, to: Array, now_of: Callable, holds: Callable) -> Dictionary:
	if from.is_empty():
		return {}
	var e: Dictionary = from.pop_back()
	if holds.is_valid() and not bool(holds.call(e)):
		return {"stale": true}
	to.append(now_of.call(e))
	return e
