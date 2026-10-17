class_name MilitaryPopulation
extends RefCounted
## Residents include serving and captive people. Only death reduces residents;
## enlistment reserves them and release makes them available without adding people.
const FIELDS: Array[String] = ["rural_population", "urban_population"]

static func occupied(state: GameState, province: String, field := "") -> int:
	var total := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort["source_province"]) != province:
			continue
		if field != "" and String(cohort["source_population_field"]) != field:
			continue
		total += int(cohort["fit"]) + int(cohort["wounded"]) + int(cohort["captured_current"])
	return total

## Promises reserve released civilians at their original population source.
static func restricted(state: GameState, province: String, field := "") -> int:
	var total := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort["source_province"]) != province:
			continue
		if field != "" and String(cohort["source_population_field"]) != field:
			continue
		for promise: Dictionary in cohort.get("civilian_promises", []):
			if _promise_active(state, promise):
				total += int(promise["count"])
	return total

static func service_refusal(state: GameState, person: String) -> String:
	if person.is_empty():
		return ""
	var ids := state.military_cohorts.keys()
	ids.sort()
	for id: String in ids:
		var cohort: Dictionary = state.military_cohorts[id]
		if String(cohort.get("person_id", "")) != person:
			continue
		for promise: Dictionary in cohort.get("civilian_promises", []):
			if not _promise_active(state, promise):
				continue
			var until_day := int(promise["until_day"])
			var expiry := "indefinite" if until_day == 0 else "through absolute day %d, inclusive" % until_day
			return "%s (%s)." % [String(promise["reason"]), expiry]
	return ""

static func _promise_active(state: GameState, promise: Dictionary) -> bool:
	var until_day := int(promise["until_day"])
	return int(promise["count"]) > 0 and (until_day == 0 or until_day >= state.absolute_day())

static func available(repo: DataRepository, state: GameState, province: String, field := "") -> int:
	if field == "":
		var total := 0
		for source_field: String in FIELDS:
			total += available(repo, state, province, source_field)
		return total
	if not field in FIELDS:
		return 0
	var people: Variant = WorldLedger.value_of(repo, state, path(province, field))
	if people == null:
		return 0
	@warning_ignore("integer_division")
	var eligible := int(people) * clampi(int(repo.bal("recruitment_eligible_permille")), 0, 1000) / 1000
	return maxi(0, eligible - occupied(state, province, field) - restricted(state, province, field))

static func path(province: String, field: String) -> String:
	return "economy.provinces.%s.%s" % [province, field]
