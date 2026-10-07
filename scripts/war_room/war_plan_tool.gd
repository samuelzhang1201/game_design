class_name WarPlanTool
extends RefCounted
## The staff's tools in the player's hand (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §2.4, rulings 15-17): which stick (the hand,
## the blue or red crayon, the pen) and which kind of mark; a drag drawn
## freehand in pack px, sampled every war_plan_sample_px of pointer travel and
## smoothed on release to war_plan_points_max points (Shift: straight); a ring
## drawn as a compass; a stroke or its handle picked on the screen; the
## session's undo. Pure: the view routes the pointer here and hands what is
## drawn to the screen, which writes it through Game.

const HAND := "hand"
const STICKS := ["blue", "red", "ink"]

var stick := HAND
var kind := ""
var drawing := false
var _last_kind := "arrow"
var _samples := PackedVector2Array()   # pack px
var _screen := PackedVector2Array()    # the same samples on the screen
var _repo: DataRepository
var _undo: Array = []
var _redo: Array = []


func _init(repo: DataRepository) -> void:
	_repo = repo


## A stick and a kind are in hand: a left press draws.
func in_hand() -> bool:
	return stick != HAND and kind != ""


func _gesture(k: String) -> String:
	return String((_repo.war_plan_kinds.get(k, {}) as Dictionary).get("gesture", "path"))


## Picks a kind; the stick follows it when the hand is empty or it is a pen
## kind (the pen's), or when a pen kind gives way to a crayon one (the blue).
func pick_kind(k: String) -> void:
	if not _repo.war_plan_kinds.has(k):
		return
	var pen := bool(_repo.war_plan_kinds[k]["pen"])
	if pen:
		stick = "ink"
	elif stick == HAND or stick == "ink":
		stick = "blue"
	kind = k
	_last_kind = k
	drawing = false


## Picks a stick; with no kind in hand it takes the last one.
func pick_stick(s: String) -> void:
	if s == HAND:
		put_down()
		return
	if not s in STICKS:
		return
	stick = s
	if kind == "":
		kind = _last_kind
	drawing = false


## Esc or the hand: nothing in hand.
func put_down() -> void:
	stick = HAND
	kind = ""
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
	var out := {"kind": kind, "colour": stick, "r": 0.0}
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
	_undo.append(before)
	while _undo.size() > int(_repo.bal("war_plan_undo_max")):
		_undo.pop_front()
	_redo.clear()


## The plans to put back, given the plans now; {} when there is nothing to undo.
func undo(now: Dictionary) -> Dictionary:
	if _undo.is_empty():
		return {}
	_redo.append(now)
	return _undo.pop_back()


func redo(now: Dictionary) -> Dictionary:
	if _redo.is_empty():
		return {}
	_undo.append(now)
	return _redo.pop_back()
