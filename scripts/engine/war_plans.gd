class_name WarPlans
extends RefCounted
## The WAR ROOM's plans (owner 2026-10-07, spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.1, §2.2): the
## player's own paper on the plotting table — SUPPOSED enemy pieces (one land
## arm, a headcount, a side) and the staff's STROKES (axis arrows, front lines,
## phase lines, objectives). Saved whole in `GameState.war_plans`, whole metres
## of the pack's measure; no engine rule reads them (WarGround's read-only
## reading of a supposed piece aside). Written only through Game. Every write
## raises `rev`, the key the room's caches turn on.

const UNKNOWN := "unknown"
const PIECES := "pieces"
const STROKES := "strokes"
const COLOURS := ["blue", "red", "ink"]
const _ROMAN := [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]


static func empty() -> Dictionary:
	return {PIECES: {}, STROKES: {}, "next_id": 0, "rev": 0}


## The land arms a supposed piece may be: every unit type that is not a
## separate force (the fleet), in the pack's order.
static func arms(repo: DataRepository) -> Array:
	var out: Array = []
	var types: Dictionary = repo.world_table("military", "unit_types")
	for arm: String in types:
		if String((types[arm] as Dictionary).get("separate", "0")) != "1":
			out.append(arm)
	return out


## The sides a supposed host may take: every kingdom but the crown's, by code,
## then Unknown.
static func sides(repo: DataRepository) -> Array:
	var mine := repo.resolve_realm("player_realm")
	var out: Array = repo.kingdoms.keys().filter(func(k: String) -> bool: return k != mine)
	out.sort()
	out.append(UNKNOWN)
	return out


## Heads as the form keeps them: within war_plan_heads_min..max, a whole
## number of war_plan_heads_step (the nearest).
static func heads_of(repo: DataRepository, heads: int) -> int:
	var step := maxi(int(repo.bal("war_plan_heads_step")), 1)
	var h := roundi(float(heads) / float(step)) * step
	return clampi(h, int(repo.bal("war_plan_heads_min")), int(repo.bal("war_plan_heads_max")))


## The side the Place form offers first: the ground's holder when foreign,
## else the side chosen last, else Unknown.
static func default_side(repo: DataRepository, state: GameState, at_px: Vector2, last: String) -> String:
	var cell := MapEconomy.cell_at(repo, at_px)
	var prov := MapManors.province_of(repo, cell, state) if cell >= 0 else ""
	var holder := MapOwnership.owner_of(repo, state, prov) if prov != "" else ""
	if holder != "" and holder != repo.resolve_realm("player_realm") and repo.kingdoms.has(holder):
		return holder
	return last if last in sides(repo) else UNKNOWN


static func _on_land(repo: DataRepository, at_px: Vector2) -> bool:
	var cell := MapEconomy.cell_at(repo, at_px)
	return cell >= 0 and not MapTerrain.is_water(repo.cells[cell])


## Why a supposed piece cannot stand there; "" when it can.
static func refusal(repo: DataRepository, state: GameState, arm: String, _heads: int, side: String, at_px: Vector2) -> String:
	if not arm in arms(repo):
		return "A supposed host is foot, bows, horse or guns"
	if not side in sides(repo):
		return "No such side"
	if not _on_land(repo, at_px):
		return "A supposed host stands on land"
	var cap := int(repo.bal("war_plan_pieces_max"))
	if (state.war_plans[PIECES] as Dictionary).size() >= cap:
		return "The table holds %d supposed hosts already" % cap
	return ""


static func _metres(repo: DataRepository, at_px: Vector2) -> Vector2i:
	return ArmySystem.pack_to_metres(repo, at_px)


static func _next_id(state: GameState, prefix: String) -> String:
	state.war_plans["next_id"] = int(state.war_plans["next_id"]) + 1
	return "%s%d" % [prefix, int(state.war_plans["next_id"])]


static func bump(state: GameState) -> void:
	state.war_plans["rev"] = int(state.war_plans["rev"]) + 1


## Places a supposed piece; its id, "" when refused.
static func place(repo: DataRepository, state: GameState, arm: String, heads: int, side: String,
		at_px: Vector2, facing_deg := 0) -> String:
	if refusal(repo, state, arm, heads, side, at_px) != "":
		return ""
	var m := _metres(repo, at_px)
	var id := _next_id(state, "p")
	state.war_plans[PIECES][id] = {"arm": arm, "heads": heads_of(repo, heads), "side": side,
		"x_m": m.x, "y_m": m.y, "facing_deg": posmod(facing_deg, 360)}
	bump(state)
	return id


## A piece or a stroke point in pack px.
static func at_px(repo: DataRepository, item: Dictionary) -> Vector2:
	return ArmySystem.metres_to_pack(repo, Vector2i(int(item["x_m"]), int(item["y_m"])))


static func move_piece(repo: DataRepository, state: GameState, id: String, to_px: Vector2, facing_deg: int) -> bool:
	var p: Dictionary = (state.war_plans[PIECES] as Dictionary).get(id, {})
	if p.is_empty() or not _on_land(repo, to_px):
		return false
	var m := _metres(repo, to_px)
	p["x_m"] = m.x
	p["y_m"] = m.y
	p["facing_deg"] = posmod(facing_deg, 360)
	bump(state)
	return true


static func edit_piece(repo: DataRepository, state: GameState, id: String, arm: String, heads: int, side: String) -> bool:
	var p: Dictionary = (state.war_plans[PIECES] as Dictionary).get(id, {})
	if p.is_empty() or not arm in arms(repo) or not side in sides(repo):
		return false
	p["arm"] = arm
	p["heads"] = heads_of(repo, heads)
	p["side"] = side
	bump(state)
	return true


## Removes a piece or a stroke by id.
static func remove(state: GameState, id: String) -> bool:
	var gone: bool = (state.war_plans[PIECES] as Dictionary).erase(id) or (state.war_plans[STROKES] as Dictionary).erase(id)
	if gone:
		bump(state)
	return gone


## Puts a snapshot of war_plans back (the room's undo): a change like any other.
static func restore(state: GameState, plans: Dictionary) -> void:
	var rev := int(state.war_plans["rev"])
	state.war_plans = plans.duplicate(true)
	state.war_plans["rev"] = maxi(rev, int(plans.get("rev", 0))) + 1


## The supposed pieces standing in a pack-px rect, by id, each with its `id`
## and `at` (pack px).
static func pieces_in(repo: DataRepository, state: GameState, rect: Rect2) -> Array:
	var out: Array = []
	var ids: Array = (state.war_plans[PIECES] as Dictionary).keys()
	ids.sort()
	for id: String in ids:
		var p: Dictionary = (state.war_plans[PIECES][id] as Dictionary).duplicate()
		p["at"] = at_px(repo, p)
		if rect.has_point(p["at"]):
			p["id"] = id
			out.append(p)
	return out


## Removes every piece (`kind` PIECES) or stroke (STROKES) lying in a rect;
## how many went.
static func clear(repo: DataRepository, state: GameState, kind: String, rect: Rect2) -> int:
	var hits: Array = pieces_in(repo, state, rect) if kind == PIECES else strokes_in(repo, state, rect)
	for h: Dictionary in hits:
		(state.war_plans[kind] as Dictionary).erase(String(h["id"]))
	if not hits.is_empty():
		bump(state)
	return hits.size()


# --- strokes ----------------------------------------------------------------

## Why a stroke cannot be drawn; "" when it can. A path needs two points to
## war_plan_points_max; a ring one point and a radius.
static func stroke_refusal(repo: DataRepository, state: GameState, kind: String, colour: String,
		pts_px: PackedVector2Array, r_px: float, name: String) -> String:
	if not repo.war_plan_kinds.has(kind):
		return "No such mark"
	if not colour in COLOURS:
		return "No such colour"
	var shape := _shape_refusal(repo, kind, pts_px, r_px)
	if shape != "":
		return shape
	if name.length() > int(repo.bal("war_plan_name_chars")):
		return "A name of at most %d letters" % int(repo.bal("war_plan_name_chars"))
	var cap := int(repo.bal("war_plan_strokes_max"))
	if (state.war_plans[STROKES] as Dictionary).size() >= cap:
		return "The table holds %d marks already" % cap
	return ""


static func _shape_refusal(repo: DataRepository, kind: String, pts_px: PackedVector2Array, r_px: float) -> String:
	match String(repo.war_plan_kinds[kind]["gesture"]):
		"ring":
			if pts_px.size() != 1 or r_px <= 0.0:
				return "A ring is a centre and a radius"
		"point":
			if pts_px.size() != 1:
				return "A point is one place"
		_:
			if pts_px.size() < 2:
				return "A line needs two points"
	if pts_px.size() > int(repo.bal("war_plan_points_max")):
		return "A line of at most %d points" % int(repo.bal("war_plan_points_max"))
	return ""


static func _pts_m(repo: DataRepository, pts_px: PackedVector2Array) -> Array:
	var out: Array = []
	for p in pts_px:
		var m := _metres(repo, p)
		out.append([m.x, m.y])
	return out


## Draws a stroke; its id, "" when refused.
static func draw(repo: DataRepository, state: GameState, kind: String, colour: String,
		pts_px: PackedVector2Array, r_px: float, name: String, dashed := false) -> String:
	if stroke_refusal(repo, state, kind, colour, pts_px, r_px, name) != "":
		return ""
	var id := _next_id(state, "s")
	state.war_plans[STROKES][id] = {"kind": kind, "colour": colour, "dashed": 1 if dashed else 0, "flip": 0,
		"name": name, "pts": _pts_m(repo, pts_px), "r_m": _metres(repo, Vector2(r_px, 0.0)).x}
	bump(state)
	return id


## A stroke's control points in pack px.
static func points_px(repo: DataRepository, s: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in s["pts"]:
		out.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
	return out


## A stroke's radius in pack px (0 but for a ring).
static func radius_px(repo: DataRepository, s: Dictionary) -> float:
	return ArmySystem.metres_to_pack(repo, Vector2i(int(s.get("r_m", 0)), 0)).x


## The pack-px box a stroke covers (a ring by its rim).
static func bounds_of(repo: DataRepository, s: Dictionary) -> Rect2:
	var pts := points_px(repo, s)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box.grow(maxf(radius_px(repo, s), 0.5))


## The strokes whose box touches a pack-px rect, by id, each with its `id`.
static func strokes_in(repo: DataRepository, state: GameState, rect: Rect2) -> Array:
	var out: Array = []
	var ids: Array = (state.war_plans[STROKES] as Dictionary).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.substr(1).to_int() < b.substr(1).to_int())
	for id: String in ids:
		var s: Dictionary = state.war_plans[STROKES][id]
		if bounds_of(repo, s).intersects(rect):
			var row := s.duplicate(true)
			row["id"] = id
			out.append(row)
	return out


static func reshape(repo: DataRepository, state: GameState, id: String, pts_px: PackedVector2Array, r_px := -1.0) -> bool:
	var s: Dictionary = (state.war_plans[STROKES] as Dictionary).get(id, {})
	if s.is_empty():
		return false
	var r := radius_px(repo, s) if r_px < 0.0 else r_px
	if _shape_refusal(repo, String(s["kind"]), pts_px, r) != "":
		return false
	s["pts"] = _pts_m(repo, pts_px)
	s["r_m"] = _metres(repo, Vector2(r, 0.0)).x
	bump(state)
	return true


static func shift(repo: DataRepository, state: GameState, id: String, offset_px: Vector2) -> bool:
	var s: Dictionary = (state.war_plans[STROKES] as Dictionary).get(id, {})
	if s.is_empty():
		return false
	var pts := points_px(repo, s)
	for i in pts.size():
		pts[i] += offset_px
	return reshape(repo, state, id, pts)


## Changes a stroke's `colour`, `dashed`, `flip` or `name`.
static func restyle(repo: DataRepository, state: GameState, id: String, changes: Dictionary) -> bool:
	var s: Dictionary = (state.war_plans[STROKES] as Dictionary).get(id, {})
	if s.is_empty():
		return false
	if changes.has("colour") and not String(changes["colour"]) in COLOURS:
		return false
	if changes.has("name") and String(changes["name"]).length() > int(repo.bal("war_plan_name_chars")):
		return false
	for k: String in ["colour", "name"]:
		if changes.has(k):
			s[k] = String(changes[k])
	for k: String in ["dashed", "flip"]:
		if changes.has(k):
			s[k] = 1 if int(changes[k]) != 0 else 0
	bump(state)
	return true


## The first default name of a kind no stroke carries yet ("Line II",
## "Obj. B", "3"); "" for a kind with none.
static func next_name(repo: DataRepository, state: GameState, kind: String) -> String:
	var pattern := String((repo.war_plan_kinds.get(kind, {}) as Dictionary).get("name_default", ""))
	if pattern == "":
		return ""
	var used := {}
	for s: Dictionary in (state.war_plans[STROKES] as Dictionary).values():
		if String(s["kind"]) == kind:
			used[String(s["name"])] = true
	var n := 1
	while true:
		var name := pattern.format({"roman": roman(n), "letter": letters(n), "n": str(n)})
		if not used.has(name):
			return name
		n += 1
	return ""


static func roman(n: int) -> String:
	var out := ""
	var left := n
	for pair: Array in _ROMAN:
		while left >= int(pair[0]):
			out += String(pair[1])
			left -= int(pair[0])
	return out if n <= 39 else str(n)


## 1 -> A, 26 -> Z, 27 -> AA (the sheets' own column letters).
static func letters(n: int) -> String:
	return WarSheets.column_letters(n - 1)
