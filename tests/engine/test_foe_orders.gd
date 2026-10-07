extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A foe is a column of the raider realm in the field (GameState.foes), and
## ArmySystem.state_of now reads it: no army order and no courier may ever
## be aimed at one (spec 2026-10-07-enemy-ai-and-battle-design §2).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func _foe_state() -> Array:
	var s := SuiteData.campaign(repo, 11)
	var code := String((repo.raid_hosts[0]["regiments"] as Array)[0])
	var home := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	s.foes[code] = {"morale": 80, "wounded": 0, "supplies": 40, "x_m": home.x, "y_m": home.y}
	return [s, code]


func test_orders_aimed_at_a_foe_are_refused() -> void:
	var pair := _foe_state()
	var s: GameState = pair[0]
	var code: String = pair[1]
	var actions := ActionSystem.new(repo)
	var near := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(5.0, 0.0)
	var march := ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": near.x, "y": near.y})
	var stand := ActionRequest.make("ARMY_GARRISON", {"regiment": code})
	assert_ne(actions.validate(march, s), "", "no march for a foe")
	assert_ne(actions.validate(stand, s), "", "no halt for a foe")
	assert_ne(actions.validate_place(march, s), "", "not even a war-room pencil")
	var supply := ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code})
	assert_ne(actions.validate(supply, s), "", "no supply warrant for a foe")


func test_no_courier_is_dispatched_to_a_foe() -> void:
	var pair := _foe_state()
	var s: GameState = pair[0]
	var code: String = pair[1]
	var id_before := s.next_courier_id
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	assert_eq(c, {}, "no courier for a foe")
	assert_true(s.couriers.is_empty())
	assert_eq(s.next_courier_id, id_before, "no id spent")


func test_a_courier_whose_target_became_a_foe_is_lost() -> void:
	var s := SuiteData.campaign(repo, 11)
	var mine := String((MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0] as Dictionary)["regiment_code"])
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, mine, {"action_code": "ARMY_GARRISON"})
	assert_false(c.is_empty(), "the player's own regiment gets its courier")
	s.foes[mine] = {"morale": 80, "wounded": 0, "supplies": 40, "x_m": 1, "y_m": 1}
	var events := CourierSystem.ride_day(repo, s)
	assert_true(s.couriers.is_empty(), "he does not ride on to an enemy column")
	assert_eq(String((events[0] as Dictionary).get("type", "")), "lost")
