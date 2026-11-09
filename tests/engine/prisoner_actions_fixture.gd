extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var province: String
var buyer: String
var seller: String
var batch_id: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = GameState.new()
	state.rng = Rng.new(52)
	buyer = repo.resolve_realm("raider_realm")
	seller = repo.resolve_realm("player_realm")
	province = String(repo.provinces.keys()[0])
	repo.balance.recruitment_eligible_permille = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000
	state.world[_treasury(buyer)] = 500
	state.metrics.treasury = 0
	_add_unit("source", buyer, 60, "noble")
	_add_unit("holder", seller, 20, "commoner")
	state.battles = [{"id": 52, "att": ["source"], "def": ["holder"]}]
	BattleReport.enroll(state, state.battles[0], "source", "att")
	var result := PrisonerSystem.capture(repo, state, {"capture_id": "capture52", "battle_id": 52,
		"participants": {"holder": 1}, "reason": "Surrender accepted",
		"changes": [{"cohort_id": "source", "from": "fit", "to": "captured_current", "count": 60}]})
	assert_false(result.has("error"), str(result))
	batch_id = String(result.batch_ids[0])
	BattleReport.snapshot(repo, state, 52)

func _treasury(realm: String) -> String:
	return "metrics.treasury" if realm == seller else "economy.kingdoms.%s.treasury" % realm

func _add_unit(code: String, realm: String, count: int, identity: String) -> void:
	state.army_roster[code] = {"regiment_code": code, "kingdom_code": realm, "is_naval": "0"}
	state.regiments[code] = {}
	state.military_rosters[code] = {"commander_id": "", "cohort_ids": [code]}
	state.military_cohorts[code] = {"id": code, "unit_code": code, "source_province": province,
		"source_population_field": "rural_population", "stage": "active", "identity": identity,
		"initial": count, "fit": count, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0}

func _proposal(id := "ransom52", count := 10) -> Dictionary:
	return {"id": id, "kind": "ransom", "batches": [{"batch_id": batch_id, "count": count, "wounded_count": 0}],
		"money": 100, "parties": {"proposer": seller, "payer": buyer}, "terms": {}, "reason": "Agreed noble ransom"}

func _act(code: String, params: Dictionary) -> Dictionary:
	return ActionSystem.new(repo).execute(ActionRequest.make(code, params), state)

func _release() -> Dictionary:
	var proposal := _proposal("release")
	proposal.kind = "release"
	proposal.money = 0
	proposal.parties.payer = ""
	return proposal
