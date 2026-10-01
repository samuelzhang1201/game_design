# scripts/engine/war_room.gd
class_name WarRoom
extends RefCounted
## What the WAR ROOM's plotting table shows (owner 2026-10-01, spec
## 2026-10-01-war-room-design §3). A piece stands where we KNOW the regiment
## stands: believed_position is the one place the table reads, so intel P2's
## blur (the last ARRIVED report's place) lands here and nowhere else. The
## enemy's ghosts are believed_hosts — empty until the raid host exists.


static func believed_position(repo: DataRepository, state: GameState, reg: Dictionary) -> Vector2:
	return ArmySystem.position_of(repo, state, reg)


## P2 fills this with {code, at, low, high, source, day}; the table draws each
## as a translucent piece over an inked ring of uncertainty.
static func believed_hosts(_repo: DataRepository, _state: GameState) -> Array:
	return []


## The crown's regiments as pieces: code, believed place, naval, home sheet.
static func pieces(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var at := believed_position(repo, state, reg)
		out.append({"code": String(reg["regiment_code"]), "at": at,
			"naval": String(reg.get("is_naval", "0")) == "1", "sheet": WarSheets.sheet_of(repo, at)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["code"]) < String(b["code"]))
	return out


## On a sheet: inside its rect, or on no sheet at all and this the nearest.
static func on_sheet(repo: DataRepository, state: GameState, sheet_index: int) -> Array:
	var all := WarSheets.series(repo)
	if sheet_index < 0 or sheet_index >= all.size():
		return []
	var r: Rect2 = all[sheet_index]["rect"]
	return pieces(repo, state).filter(func(p: Dictionary) -> bool:
		return r.has_point(p["at"]) or (not _on_any(all, p["at"]) and int(p["sheet"]) == sheet_index))


static func off_sheet(repo: DataRepository, state: GameState, sheet_index: int) -> Array:
	var on := on_sheet(repo, state, sheet_index).map(func(p: Dictionary) -> String: return String(p["code"]))
	return pieces(repo, state).filter(func(p: Dictionary) -> bool: return not String(p["code"]) in on)


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


## The pennant over a march order: where the newest courier carries it
## ("riding"), else the march the column is under ("received"); {} when
## neither.
static func pennant_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var c := CourierSystem.pending_for(state, code)
	if not c.is_empty():
		var order: Dictionary = c.get("order", {})
		if String(order.get("action_code", "")) == "ARMY_MARCH":
			return {"at": ArmySystem.metres_to_pack(repo, Vector2i(int(order["x_m"]), int(order["y_m"]))),
				"status": "riding"}
		return {}
	if ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH:
		return {"at": ArmySystem.destination_of(repo, state, code), "status": "received"}
	return {}


## The slip pinned beside a piece: heads under arms and whole months of stores.
static func tag_text(repo: DataRepository, state: GameState, code: String) -> String:
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
