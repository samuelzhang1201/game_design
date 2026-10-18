class_name Desertion
extends RefCounted
## Desertion (spec 2026-10-10-foraging-and-desertion §3.2): a land unit that is
## broken, untrained or unfed loses men each day. Whole men, integers only: the
## rate is per 100000 of the fit men and the fraction carries in `desert_rem`.

const SCALE := 100000


static func _is_fleet(repo: DataRepository, state: GameState, code: String) -> bool:
	return String(ArmySystem.regiment(repo, code, state).get("is_naval", "0")) == "1"


## How many of the three lines hold: morale and training under their marks, the
## days in hand at or under the supply mark. 0 for a unit that eats nothing.
static func conditions(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty():
		return 0
	var use := ArmySystem.supply_use(repo, reg, state)
	if ArmySystem.fit_count(repo, state, code) <= 0:
		return 0
	var n := 0
	if int(entry.get("morale", 0)) < int(repo.bal("desert_morale")):
		n += 1
	if int(entry.get("training", 0)) < int(repo.bal("desert_training")):
		n += 1
	if ArmySystem.days_in_hand(int(entry.get("supplies", 0)), use) <= int(repo.bal("desert_supply_days")):
		n += 1
	return n


## The law's multiplier, per mille: `desert_mult_<fine|lenient|hanging>`.
static func multiplier_permille(repo: DataRepository, state: GameState, code: String) -> int:
	return int(repo.bal("desert_mult_" + LawSystem.value(repo, state, "desertion_penalty", code)))


## Actual historical desertion, excluding other releases such as prisoners.
static func total(state: GameState, code: String) -> int:
	var count := 0
	for id: String in state.military_events:
		if not id.begins_with("desertion:"):
			continue
		var request: Dictionary = state.military_events[id].get("request", {})
		if String(request.get("kind", "")) != "transfer_units":
			continue
		for order: Dictionary in request.get("orders", []):
			if String(order.get("unit_code", "")) == code and String(order.get("from", "")) == "fit" and String(order.get("to", "")) == "released":
				count += int(order["count"])
	return count

## A day's release and fractional carry commit together; even a zero-loss
## day consumes its cursor. Repeating it cannot build up another fraction.
static func daily_loss(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = state.regiments.get(code, {})
	if _is_fleet(repo, state, code) or entry.is_empty() or not state.military_rosters.has(code):
		return 0
	var today := state.absolute_day()
	if int(entry.get("desert_day", -1)) == today:
		return 0
	var n := conditions(repo, state, code)
	var fit := ArmySystem.fit_count(repo, state, code)
	if n == 0 or fit <= 0:
		entry["desert_day"] = today
		return 0
	@warning_ignore("integer_division")
	var rate := int(repo.bal("desert_permille_per_day")) * 100 * n * multiplier_permille(repo, state, code) / 1000
	var units := fit * rate + int(entry.get("desert_rem", 0))
	@warning_ignore("integer_division")
	var lost := mini(units / SCALE, fit)
	if lost > 0:
		var result := MilitaryRoster.transfer_units(repo, state, "desertion:%d:%s" % [today, code],
			[{"unit_code": code, "from": "fit", "to": "released", "count": lost}], "Desertion into civilian life: " + code)
		if result.has("error"):
			return 0
	entry["desert_rem"] = 0 if lost >= fit else units % SCALE
	entry["desert_day"] = today
	return lost
