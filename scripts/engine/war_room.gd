# scripts/engine/war_room.gd
class_name WarRoom
extends RefCounted
## What the WAR ROOM's plotting table shows (owner 2026-10-01, spec
## 2026-10-01-war-room-design §3). A piece stands where we KNOW the regiment
## stands: believed_position is the one place the table reads, so intel P2's
## blur (the last ARRIVED report's place) lands here and nowhere else. The
## enemy's ghosts are believed_hosts — empty until the raid host exists.
##
## `drawn` (code -> pack px) is where the 3D map DRAWS each regiment — its
## piece walks the engine's next day by the day's share, so mid-day it stands
## up to a day's march ahead of ArmySystem.position_of (measured 6.5 pack px
## on 2026-10-02). The owner ruled the room's pieces must stand exactly where
## the map shows them (2026-10-02: war room的军队单位位置一定要和大地图一致), so
## a drawn spot wins; the screen hands it in (presentation only — the engine
## never reads it, and a regiment the map does not draw keeps the engine's).


static func believed_position(repo: DataRepository, state: GameState, reg: Dictionary,
		drawn: Dictionary = {}) -> Vector2:
	var code := String(reg.get("regiment_code", ""))
	if drawn.has(code):
		return drawn[code]
	return ArmySystem.position_of(repo, state, reg)


## P2 fills this with {code, at, low, high, source, day}; the table draws each
## as a translucent piece over an inked ring of uncertainty.
static func believed_hosts(_repo: DataRepository, _state: GameState) -> Array:
	return []


## Where the crown KNOWS of foreign men (spec 2026-10-08-war-room-draw-orders
## ruling 18): every spy report that has come in (a `spy` missive) whose
## `troops_foreign` span reaches war_intel_hint_min_heads, the newest about a
## place standing for it, then the believed hosts (intel P2). Each {id ("h" +
## the letter's id, "b" + a host's code), at (pack px), lo, hi, day, title} —
## only what a report said, never a force the crown was not told of.
static func intel_hints(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var least := int(repo.bal("war_intel_hint_min_heads"))
	var seen: Dictionary = {}
	var spies: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m.get("kind", "")) == "spy")
	spies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	for m: Dictionary in spies:
		var subj: Dictionary = m["subject"]
		var at := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
		var key := Vector2i(at.round())
		if seen.has(key):
			continue
		seen[key] = true   # the newest report about a place stands for it
		for f: Dictionary in m["facts"]:
			if String(f.get("key", "")) == "troops_foreign" and f.has("hi") and int(f["hi"]) >= maxi(least, 1):
				out.append({"id": "h%d" % int(m["id"]), "at": at, "lo": int(f["lo"]), "hi": int(f["hi"]),
					"day": int(m["day"]), "title": String(m["title"])})
	for h: Dictionary in believed_hosts(repo, state):
		out.append({"id": "b" + String(h["code"]), "at": h["at"], "lo": int(h.get("low", 0)),
			"hi": int(h.get("high", 0)), "day": int(h.get("day", 0)), "title": String(h.get("source", ""))})
	return out


## One hint by id, {} when no report stands for it now.
static func hint_of(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	for h: Dictionary in intel_hints(repo, state):
		if String(h["id"]) == id:
			return h
	return {}


## The crown's regiments as pieces: code, believed place, naval, home sheet,
## and `garrison` — the codes a piece stands for. A town's garrison is ONE
## piece on the town, as the map draws it one counter (owner 2026-10-06,
## choice A): coded by its first regiment (the royal one first).
static func pieces(repo: DataRepository, state: GameState, drawn: Dictionary = {}) -> Array:
	var out: Array = []
	var regs := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))
	var quartered: Dictionary = {}
	for g: Dictionary in MapObjects.garrisons(repo, state, regs):
		var codes: Array = g["codes"]
		for c in codes:
			quartered[String(c)] = true
		var town: Dictionary = repo.burgs[String(g["town"])]
		var at := Vector2(float(town["x"]), float(town["y"]))
		out.append({"code": String(codes[0]), "at": at, "naval": false,
			"sheet": WarSheets.sheet_of(repo, at), "garrison": codes})
	for reg: Dictionary in regs:
		var code := String(reg["regiment_code"])
		if quartered.has(code):
			continue
		var at := believed_position(repo, state, reg, drawn)
		out.append({"code": code, "at": at, "garrison": [code],
			"naval": String(reg.get("is_naval", "0")) == "1", "sheet": WarSheets.sheet_of(repo, at)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["code"]) < String(b["code"]))
	return out


## The pieces split by a sheet, computed once: "on" those inside its rect (or
## on no sheet at all and this the nearest), "off" the rest.
static func partition(repo: DataRepository, state: GameState, sheet_index: int,
		drawn: Dictionary = {}) -> Dictionary:
	var on: Array = []
	var off: Array = []
	var all := WarSheets.series(repo)
	var rect := Rect2()
	var valid := sheet_index >= 0 and sheet_index < all.size()
	if valid:
		rect = all[sheet_index]["rect"]
	for p: Dictionary in pieces(repo, state, drawn):
		if valid and (rect.has_point(p["at"]) or (not _on_any(all, p["at"]) and int(p["sheet"]) == sheet_index)):
			on.append(p)
		else:
			off.append(p)
	return {"on": on, "off": off}


static func on_sheet(repo: DataRepository, state: GameState, sheet_index: int,
		drawn: Dictionary = {}) -> Array:
	return partition(repo, state, sheet_index, drawn)["on"]


static func off_sheet(repo: DataRepository, state: GameState, sheet_index: int,
		drawn: Dictionary = {}) -> Array:
	return partition(repo, state, sheet_index, drawn)["off"]


static func _on_any(all: Array, at: Vector2) -> bool:
	for s: Dictionary in all:
		if (s["rect"] as Rect2).has_point(at):
			return true
	return false


## The clip a frozen piece is posed in.
static func pose_action(order: String) -> String:
	match order:
		ArmySystem.ORDER_MARCH:
			return "MARCH"
		ArmySystem.ORDER_GARRISON:
			return "GARRISON"
	return "STANDBY"


## The pennant over a march order: where the newest ARMY_MARCH courier still
## riding for the regiment carries it ("riding"; one the regiment has since
## been ordered past — a newer order delivered — is set aside and plants
## nothing), else the march the column is under ("received"); {} when neither.
## A garrison courier NEWER than the march's countermands it: the pennant
## stands with status "countermanded" (its `issued` the garrison courier's day)
## until he arrives, so Cancel march visibly lands on it. `issued` is the
## absolute day the courier left (riding / countermanded).
static func pennant_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var delivered := int(ArmySystem.state_of(repo, state, code).get("order_id", 0))
	var march: Dictionary = {}
	var halt: Dictionary = {}
	for c: Dictionary in state.couriers:
		if String(c["target"]) != code or int(c["id"]) < delivered:
			continue
		var kind := String(c.get("order", {}).get("action_code", ""))
		if kind == "ARMY_MARCH" and (march.is_empty() or int(c["id"]) > int(march["id"])):
			march = c
		elif kind == "ARMY_GARRISON" and (halt.is_empty() or int(c["id"]) > int(halt["id"])):
			halt = c
	var at := Vector2(-1, -1)
	var status := ""
	var issued := 0
	if not march.is_empty():
		var o: Dictionary = march["order"]
		at = ArmySystem.metres_to_pack(repo, Vector2i(int(o["dest_x_m"]), int(o["dest_y_m"])))
		status = "riding"
		issued = int(march.get("issued", 0))
	elif ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH:
		at = ArmySystem.destination_of(repo, state, code)
		status = "received"
	else:
		return {}
	if not halt.is_empty() and (march.is_empty() or int(halt["id"]) > int(march["id"])):
		status = "countermanded"
		issued = int(halt.get("issued", 0))
	return {"at": at, "status": status, "issued": issued}


## The slip pinned beside a piece: heads under arms and whole months of stores.
static func tag_text(repo: DataRepository, state: GameState, code: String) -> String:
	var held := MapObjects.garrison_of(repo, state, code)
	if held.size() > 1:
		var all := 0
		for c in held:
			all += ArmySystem.headcount(repo, ArmySystem.regiment(repo, String(c)))
		return "%d regiments · %s" % [held.size(), group(all)]
	var reg := ArmySystem.regiment(repo, code)
	var heads := group(ArmySystem.headcount(repo, reg))
	var st := ArmySystem.state_of(repo, state, code)
	var use := ArmySystem.supply_use(repo, reg, state)
	if st.is_empty() or use <= 0:
		return heads
	@warning_ignore("integer_division")  # whole months in hand
	return "%s · stores %d mo" % [heads, int(st["supplies"]) / use]


static func group(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
