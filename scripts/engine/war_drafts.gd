class_name WarDrafts
extends RefCounted
## The WAR ROOM's drafts (owner 2026-10-02, spec 2026-10-02-war-room-v2 §3.1):
## an order pencilled on the table — no fee, no courier — until the council's
## resolutions are sealed (Game.deploy_drafts). One per regiment, the newest
## replacing the last, in whole metres; saved (GameState.war_drafts). A real
## order given the regiment elsewhere sets its draft aside (ActionSystem).

const MARCH := "march"
const GARRISON := "garrison"


## A march draft may name `waypoints` (pack px, in order) and the load it
## should carry, `carry` days (spec 2026-10-07-march-waypoints ruling 8; -1
## leaves the load alone).
static func plant(repo: DataRepository, state: GameState, code: String, order: String, dest_px: Vector2,
		waypoints: Array = [], carry := -1) -> void:
	var m := ArmySystem.pack_to_metres(repo, dest_px) if order == MARCH else Vector2i.ZERO
	var d := {"order": order, "dest_x_m": m.x, "dest_y_m": m.y,
		"tick": state.tick, "day": state.day, "refused": ""}
	if order == MARCH and not waypoints.is_empty():
		var wm: Array = []
		for w: Vector2 in waypoints:
			wm.append(ArmySystem.pack_to_metres(repo, w))
		d["waypoints_m"] = MarchRoute.to_pairs(wm)
	if order == MARCH and carry >= 0:
		d["carry_days"] = carry
	state.war_drafts[code] = d


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


## A draft's waypoints in pack px, in order.
static func waypoints_px(repo: DataRepository, draft: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2i in MarchRoute.from_pairs(draft.get("waypoints_m", [])):
		out.append(ArmySystem.metres_to_pack(repo, p))
	return out


## Every real order a draft stands for, in the order they run: the load
## (SUPPLY_CARRY_SET, only when it changes the regiment's) before the march.
static func requests_from(repo: DataRepository, state: GameState, code: String, draft: Dictionary) -> Array:
	var out: Array = []
	if String(draft.get("order", "")) == MARCH and draft.has("carry_days") \
			and int(draft["carry_days"]) != ArmySystem.carry_of(repo, ArmySystem.state_of(repo, state, code)):
		out.append(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": int(draft["carry_days"])}))
	out.append(request_from(repo, code, draft))
	return out


## The real order a draft stands for.
static func request_of(repo: DataRepository, state: GameState, code: String) -> ActionRequest:
	return request_from(repo, code, of(state, code))


## The same, from a draft held in hand (Game.deploy_drafts strikes it first).
static func request_from(repo: DataRepository, code: String, draft: Dictionary) -> ActionRequest:
	if String(draft.get("order", "")) == MARCH:
		var to := dest_px(repo, draft)
		var params := {"regiment": code, "x": to.x, "y": to.y}
		if draft.has("waypoints_m"):
			var pairs: Array = []
			for w: Vector2 in waypoints_px(repo, draft):
				pairs.append([w.x, w.y])
			params["waypoints"] = pairs
		return ActionRequest.make("ARMY_MARCH", params)
	return ActionRequest.make("ARMY_GARRISON", {"regiment": code})
