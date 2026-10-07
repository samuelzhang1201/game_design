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


## The crown's regiments as pieces: code, believed place, naval, home sheet,
## and `garrison` — the codes a piece stands for. A town's garrison is ONE
## piece on the town, as the map draws it one counter (owner 2026-10-06,
## choice A): coded by its first regiment (the royal one first).
static func pieces(repo: DataRepository, state: GameState, drawn: Dictionary = {}) -> Array:
	var out: Array = []
	var regs := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)
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
			all += ArmySystem.headcount(repo, ArmySystem.regiment(repo, String(c), state))
		return "%d regiments · %s" % [held.size(), group(all)]
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
