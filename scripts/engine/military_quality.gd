class_name MilitaryQuality
extends RefCounted

## Identity advantages come only from active, fit people. The wounded still
## draw food and wages; captives, dead and released personnel draw neither.
static func profile(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var fit := {"commoner": 0, "noble": 0}
	var wounded := {"commoner": 0, "noble": 0}
	if state != null:
		for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
			var cohort: Dictionary = state.military_cohorts.get(id, {})
			var identity := String(cohort.get("identity", ""))
			if cohort.get("stage", "") != "active" or cohort.get("unit_code", "") != code or not fit.has(identity):
				continue
			fit[identity] += int(cohort.get("fit", 0))
			wounded[identity] += int(cohort.get("wounded", 0))
	return from_counts(repo, int(fit["commoner"]), int(fit["noble"]), int(wounded["commoner"]), int(wounded["noble"]))

## Pure recruitment preview and the same arithmetic used by live rosters.
static func from_counts(repo: DataRepository, commoner_fit: int, noble_fit: int,
		commoner_wounded: int = 0, noble_wounded: int = 0) -> Dictionary:
	var fit := {"commoner": commoner_fit, "noble": noble_fit}
	var living := {"commoner": commoner_fit + commoner_wounded, "noble": noble_fit + noble_wounded}
	var power_milli := 0
	var discipline_milli := 0
	var supply_milli := 0
	var wage_milli := 0
	var breakdown: Array = []
	for identity: String in ["commoner", "noble"]:
		var row: Dictionary = repo.noble_quality[identity]
		var power := int(fit[identity]) * int(row["power_permille"])
		var discipline := int(fit[identity]) * int(row["discipline_permille"])
		var supply := int(living[identity]) * int(row["supply_permille"])
		var wage := int(living[identity]) * int(row["wage_per_1000_per_month"])
		power_milli += power
		discipline_milli += discipline
		supply_milli += supply
		wage_milli += wage
		breakdown.append({"identity": identity, "fit": int(fit[identity]), "living": int(living[identity]),
			"power_milli": power, "discipline_milli": discipline, "supply_milli": supply, "wage_milli": wage,
			"reason": "%s: fit personnel grant power and discipline; fit and wounded draw food and monthly wages" % identity})
	var total_fit := commoner_fit + noble_fit
	@warning_ignore("integer_division")
	var power_permille := power_milli / total_fit if total_fit > 0 else 0
	@warning_ignore("integer_division")
	var discipline_permille := discipline_milli / total_fit if total_fit > 0 else 0
	@warning_ignore("integer_division")
	var monthly_wages := wage_milli / 1000
	return {"fit_by_identity": fit, "living_by_identity": living, "fit": total_fit,
		"living": int(living["commoner"]) + int(living["noble"]), "power_permille": power_permille,
		"discipline_permille": discipline_permille, "supply_milli": supply_milli,
		"wage_milli": wage_milli, "monthly_wages": monthly_wages, "breakdown": breakdown}

## Whole gold rounded once over the crown's actual active personnel, even
## reserves with no deployed regiment. The saved event consumes empty months.
static func settle_month(repo: DataRepository, state: GameState) -> Dictionary:
	var event_id := "military_wages:%d" % state.tick
	if state.military_events.has(event_id):
		return (state.military_events[event_id]["result"] as Dictionary).duplicate(true)
	var wage_milli := 0
	var breakdown: Array = []
	var codes := state.military_rosters.keys()
	codes.sort()
	for code: String in codes:
		if ArmySystem.realm_of(repo, code, state) != repo.resolve_realm("player_realm"):
			continue
		var quality := profile(repo, state, code)
		wage_milli += int(quality["wage_milli"])
		breakdown.append({"unit_code": code, "wage_milli": int(quality["wage_milli"]), "breakdown": quality["breakdown"]})
	@warning_ignore("integer_division")
	var gold := wage_milli / 1000
	var reason := "Monthly military wages for active fit and wounded personnel"
	var lines: Array = []
	if gold > 0:
		var line := WorldLedger.apply(repo, state, "metrics.treasury", -gold, reason, event_id)
		if line.has("error"):
			return line
		line["delta"] = int(line["delta"])
		line["value"] = int(line["value"])
		lines.append(line)
	var result := {"status": "applied", "monthly_wages": gold, "breakdown": breakdown, "lines": lines, "reason": reason}
	state.military_events[event_id] = {"request": {"kind": "military_wages", "tick": state.tick}, "result": result.duplicate(true)}
	return result
