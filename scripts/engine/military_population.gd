class_name MilitaryPopulation
extends RefCounted
## Population remains at its origin; only active service occupies civilians.

const FIELDS: Array[String] = ["rural_population", "urban_population"]

static func occupied(state: GameState, province: String, field: String = "") -> int:
	var total := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort.get("source_province", "")) != province:
			continue
		if field != "" and String(cohort.get("source_population_field", "")) != field:
			continue
		total += int(cohort.get("fit", 0)) + int(cohort.get("wounded", 0)) + int(cohort.get("captured_current", 0))
	return total

static func available(repo: DataRepository, state: GameState, province: String, field: String = "") -> int:
	if field == "":
		var total := 0
		for source: String in FIELDS:
			total += available(repo, state, province, source)
		return total
	if not field in FIELDS or state.military_conflicts.has(province):
		return 0
	var population: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.%s" % [province, field])
	if population == null:
		return 0
	return maxi(0, int(population) - occupied(state, province, field))
