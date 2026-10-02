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
