class_name EnemyAi
extends RefCounted
## The raider realm's hosts (spec 2026-10-07-enemy-ai-and-battle-design §2-3).
## A host is a row of the pack's raid_hosts.csv: its regiments stand in
## GameState.foes (never in `regiments`) at the assembly point, and its mind is
## a row of GameState.ai_hosts. Pure and deterministic: no random number, no
## wall-clock; the commander is in the column, so a host's orders take effect
## at once, with no courier.

const MODE_ASSEMBLE := "ASSEMBLE"
const MODE_ADVANCE := "ADVANCE"


## Puts `host` (a DataRepository.raid_hosts row) in the field: a foe for each of
## its regiments, in the same shape as a player regiment's state, standing at
## the host's assembly point (whole metres of the pack's measure) with no order,
## and a mind in ASSEMBLE. A regiment the pack does not have is left out.
static func spawn(repo: DataRepository, state: GameState, host: Dictionary) -> void:
	var code := String(host["host_code"])
	var start := ArmySystem.pack_to_metres(repo,
		Vector2(float(host.get("start_x", 0)), float(host.get("start_y", 0))))
	for rc: Variant in host["regiments"]:
		var reg := ArmySystem.regiment(repo, String(rc))
		if reg.is_empty():
			continue
		var st := ArmySystem.starting_state(repo, reg)
		st["x_m"] = start.x
		st["y_m"] = start.y
		st["dest_x_m"] = start.x
		st["dest_y_m"] = start.y
		st["order"] = ArmySystem.ORDER_STANDBY
		st["host"] = code
		state.foes[String(rc)] = st
	state.ai_hosts[code] = {"mode": MODE_ASSEMBLE, "target_kind": "", "target_id": "",
		"think_day": 0, "plunder": 0, "siege_progress": 0}


## One day of the hosts' minds, in host-code order. A host assembled until its
## appear_day (the campaign's absolute day, the pack's row) sets out on that
## day's end: ASSEMBLE becomes ADVANCE. Returns the day's events,
## [{type: "host_advance", host, day}].
static func step_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var today := state.absolute_day()
	for code: String in host_codes(state):
		var mind: Dictionary = state.ai_hosts[code]
		if String(mind["mode"]) != MODE_ASSEMBLE:
			continue
		var row := _row_of(repo, code)
		if row.is_empty() or today < int(row["appear_day"]):
			continue
		mind["mode"] = MODE_ADVANCE
		events.append({"type": "host_advance", "host": code, "day": today})
	return events


## Every host's code, in dictionary order.
static func host_codes(state: GameState) -> Array:
	var codes: Array = state.ai_hosts.keys()
	codes.sort()
	return codes


## The regiment codes of a host's foes, in code order; [] for an unknown host.
static func regiments_of(state: GameState, host_code: String) -> Array:
	var out: Array = []
	for c: Variant in state.foes:
		if String((state.foes[c] as Dictionary).get("host", "")) == host_code:
			out.append(String(c))
	out.sort()
	return out


static func _row_of(repo: DataRepository, host_code: String) -> Dictionary:
	for row: Dictionary in repo.raid_hosts:
		if String(row["host_code"]) == host_code:
			return row
	return {}
