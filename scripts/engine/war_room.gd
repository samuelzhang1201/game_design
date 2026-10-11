# scripts/engine/war_room.gd
class_name WarRoom
extends RefCounted
## What the WAR ROOM's plotting table shows (owner 2026-10-01, spec
## 2026-10-01-war-room-design §3). A piece stands where the regiment stands:
## believed_position is the one place the table reads. The crown's OWN hosts
## are always drawn at their true state (owner 2026-10-10: the crown's own
## moves are ground truth); intel P2's blur — the last ARRIVED report's
## place — is for foreign hosts only: believed_hosts, empty until the raid
## host exists.
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
## the place's rounded px, "b" + a host's code), at (pack px), lo, hi, day, title} —
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
				out.append({"id": "h%d_%d" % [key.x, key.y], "at": at, "lo": int(f["lo"]), "hi": int(f["hi"]),
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


## The crown's units as pieces, one a unit (spec 2026-10-07-army-split-and-
## ground §5.4): code, believed place, naval, home sheet.
static func pieces(repo: DataRepository, state: GameState, drawn: Dictionary = {}) -> Array:
	var out: Array = []
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var at := believed_position(repo, state, reg, drawn)
		out.append({"code": String(reg["regiment_code"]), "at": at,
			"naval": String(reg.get("is_naval", "0")) == "1", "sheet": WarSheets.sheet_of(repo, at)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["code"]) < String(b["code"]))
	return out


## The pieces split by a sheet, computed once: "on" those inside its rect (or
## on no sheet at all and this the nearest), "off" the rest. `sheet` is a
## sheet's index or a laid union (WarSheets.union: its rect, its indices).
static func partition(repo: DataRepository, state: GameState, sheet: Variant,
		drawn: Dictionary = {}) -> Dictionary:
	var on: Array = []
	var off: Array = []
	var all := WarSheets.series(repo)
	var laid: Dictionary = sheet if sheet is Dictionary else WarSheets.union(repo, [int(sheet)])
	var valid := not laid.is_empty()
	var rect: Rect2 = laid.get("rect", Rect2())
	var held: Array = laid.get("indices", [])
	for p: Dictionary in pieces(repo, state, drawn):
		if valid and (rect.has_point(p["at"]) or (not _on_any(all, p["at"]) and held.has(int(p["sheet"])))):
			on.append(p)
		else:
			off.append(p)
	return {"on": on, "off": off}


static func on_sheet(repo: DataRepository, state: GameState, sheet: Variant,
		drawn: Dictionary = {}) -> Array:
	return partition(repo, state, sheet, drawn)["on"]


static func off_sheet(repo: DataRepository, state: GameState, sheet: Variant,
		drawn: Dictionary = {}) -> Array:
	return partition(repo, state, sheet, drawn)["off"]


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
	# each order ranked by its courier's id, then its place among his orders
	# (one courier may carry a march and the halt after it, owner 2026-10-10)
	var march: Dictionary = {}
	var halt: Dictionary = {}
	var march_k := -1
	var halt_k := -1
	for c: Dictionary in state.couriers:
		if String(c["target"]) != code or int(c["id"]) < delivered:
			continue
		var all := CourierSystem.orders_of(c)
		for i in all.size():
			var kind := String((all[i] as Dictionary).get("action_code", ""))
			var k := int(c["id"]) * 1000 + i
			if kind == "ARMY_MARCH" and k > march_k:
				march = {"courier": c, "order": all[i]}
				march_k = k
			elif kind == "ARMY_GARRISON" and k > halt_k:
				halt = {"courier": c}
				halt_k = k
	var at := Vector2(-1, -1)
	var status := ""
	var issued := 0
	if not march.is_empty():
		var o: Dictionary = march["order"]
		at = ArmySystem.metres_to_pack(repo, Vector2i(int(o["dest_x_m"]), int(o["dest_y_m"])))
		status = "riding"
		issued = int((march["courier"] as Dictionary).get("issued", 0))
	elif ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH:
		at = ArmySystem.destination_of(repo, state, code)
		status = "received"
	else:
		return {}
	if not halt.is_empty() and halt_k > march_k:
		status = "countermanded"
		issued = int((halt["courier"] as Dictionary).get("issued", 0))
	return {"at": at, "status": status, "issued": issued}


## The slip pinned beside a piece: heads under arms and whole months of stores.
static func tag_text(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := ArmySystem.regiment(repo, code, state)
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
