extends RefCounted
## Controlled personnel fixtures use the same release/recruit transactions as play.
static func count(state: GameState, code: String, status: String) -> int:
	var n := 0
	for id: String in state.military_rosters[code]["cohort_ids"]:
		n += int(state.military_cohorts[id][status])
	return n

static func move(repo: DataRepository, state: GameState, code: String, from_status: String, to_status: String, n: int) -> Dictionary:
	return MilitaryRoster.transfer_units(repo, state, "fixture:move:%d" % state.military_events.size(),
		[{"unit_code": code, "from": from_status, "to": to_status, "count": n}], "Test personnel transfer")

static func replace(repo: DataRepository, state: GameState, code: String, n: int) -> Dictionary:
	for status: String in ["fit", "wounded", "captured_current"]:
		var old := count(state, code, status)
		if old > 0:
			var released := move(repo, state, code, status, "released", old)
			if released.has("error"):
				return released
	var origin: Dictionary = state.military_cohorts[state.military_rosters[code]["cohort_ids"][0]]
	var province := String(origin["source_province"])
	var field := String(origin["source_population_field"])
	var path := MilitaryPopulation.path(province, field)
	var eligible := int(repo.bal("recruitment_eligible_permille"))
	var required := ceili(float(MilitaryPopulation.occupied(state, province, field) + n) * 1000 / eligible)
	state.world[path] = maxi(int(WorldLedger.value_of(repo, state, path)), required)
	var id := "fixture:raise:%d" % state.military_events.size()
	return MilitaryRoster.mobilize(repo, state, id, [{"id": id, "unit_code": code,
		"source_province": province, "source_population_field": field, "identity": "commoner",
		"family_name": "", "stage": "active", "count": n}], "Test replacement recruits")
