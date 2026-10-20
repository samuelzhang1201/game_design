extends GutTest
## P2-B3: a capture feeds FamilyLosses once, replay-safe, and lands in the battle's family_changes.

const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var province: String
var realm: String

func before_each() -> void:
	repo = SuiteData.repo()
	repo.balance["family_loss_opinion_captured_cadre"] = -1
	state = GameState.new()
	state.rng = Rng.new(52)
	realm = repo.resolve_realm("player_realm")
	province = String(repo.provinces.keys()[0])
	repo.balance.recruitment_eligible_permille = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000
	_add_unit("source", realm, 3, "noble")
	_add_unit("holder", repo.resolve_realm("raider_realm"), 20, "commoner")
	state.battles = [{"id": 52, "att": ["holder"], "def": ["source"], "town": "", "place_x_m": 0, "place_y_m": 0}]
	var c := Character.new()
	c.id = "h1"
	c.family_name = "Harrow"
	c.kingdom = realm
	c.opinion = 10
	state.characters["h1"] = c

func _add_unit(code: String, kingdom: String, count: int, identity: String) -> void:
	state.army_roster[code] = {"regiment_code": code, "kingdom_code": kingdom, "is_naval": "0"}
	state.regiments[code] = {}
	state.military_rosters[code] = {"commander_id": "", "cohort_ids": [code]}
	state.military_cohorts[code] = {"id": code, "unit_code": code, "source_province": province,
		"source_population_field": "rural_population", "stage": "active", "identity": identity,
		"family_name": "Harrow" if identity == "noble" else "",
		"initial": count, "fit": count, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0}

func _capture(id: String, cohort: String = "source") -> Dictionary:
	return PrisonerSystem.capture(repo, state, {"capture_id": id, "battle_id": 52,
		"participants": {"holder": 1}, "reason": "Surrender accepted",
		"changes": [{"cohort_id": cohort, "from": "fit", "to": "captured_current", "count": 3}]})

func test_noble_cadre_capture_moves_opinion_once() -> void:
	assert_false(_capture("c1").has("error"))
	assert_eq((state.characters["h1"] as Character).opinion, 7)
	var rows: Array = state.battles[0]["family_changes"]
	assert_eq(rows.size(), 1)
	var reason := String(rows[0]["reason"])
	assert_true(reason.contains("captured") and reason.contains(BattleSystem.place_label(repo, state, state.battles[0])), reason)

func test_replay_changes_nothing() -> void:
	_capture("c1")
	var rows: Array = state.battles[0]["family_changes"].duplicate(true)
	assert_false(_capture("c1").has("error"))
	assert_eq((state.characters["h1"] as Character).opinion, 7)
	assert_eq(state.battles[0]["family_changes"], rows)

func test_commoner_capture_records_no_row() -> void:
	_add_unit("plain", realm, 3, "commoner")
	state.battles[0]["def"] = ["plain"]
	assert_false(_capture("c2", "plain").has("error"))
	assert_eq((state.characters["h1"] as Character).opinion, 10)
	assert_eq(state.battles[0].get("family_changes", []), [])
