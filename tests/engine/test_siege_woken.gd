extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Player siege spec §5, §8, step 4b: a foreign town's standing roster units
## wake as its defenders when a siege opens and go back with their losses; the
## enemy weighs the militia an empty town would raise, and besieges an empty
## town instead of raiding it (RAID only for a plain manor).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## Kingdom `k`'s land roster units with no state, on `town`'s seat or camped by
## it, in code order (what the spec calls the town's standing roster units).
func _standing(s: GameState, town: String, k: String) -> Array:
	var out: Array = []
	for c: String in s.army_roster:
		var r: Dictionary = s.army_roster[c]
		if String(r["kingdom_code"]) != k or s.foes.has(c) or s.regiments.has(c) or String(r.get("is_naval", "0")) == "1":
			continue
		if String(s.town_seat.get(town, "")) == c or String(r.get("camp_town", "")) == town:
			out.append(c)
	out.sort()
	return out


## A crown unit opens a siege of a raider town with standing units on its
## seat: {s, town, id, unit, standing (before), seat}.
func _woken() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var raider := repo.resolve_realm("raider_realm")
	var towns: Array = s.town_seat.keys()
	towns.sort()
	var town := ""
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == raider and not _standing(s, t, raider).is_empty():
			town = t
			break
	assert_ne(town, "", "a raider town with a standing garrison")
	var standing := _standing(s, town, raider)
	var unit := String(Play.land_regiments(repo)[0])
	Play.place(repo, s, unit, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var seat := ArmyGround.seat_of(repo, s, town)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [unit], "task_test")
	return {"s": s, "town": town, "id": id, "unit": unit, "standing": standing, "seat": seat}


## A crown town held by no unit, not the capital.
func _empty_crown_town(s: GameState) -> String:
	var player := repo.resolve_realm("player_realm")
	var towns: Array = repo.burgs.keys()
	towns.sort()
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == player and ArmyGround.seat_of(repo, s, t) == "" \
				and String(repo.burgs[t].get("is_capital", "0")) == "0" \
				and SiegeSystem.defenders_of(repo, s, t).is_empty() \
				and EnemyAi.defenders_of(repo, s, "town", t, s.regiments.keys()).is_empty():
			return t
	return ""


## The main host in ADVANCE, every column at `at`, aiming for kind/id.
func _arrive(s: GameState, kind: String, id: String, at: Vector2i) -> String:
	var main := Play.host(repo, "main")
	for c: String in EnemyAi.regiments_of(s, main):
		Play.place(repo, s, c, at, ArmySystem.ORDER_STANDBY)
	var mind: Dictionary = s.ai_hosts[main]
	mind["mode"] = EnemyAi.MODE_ADVANCE
	mind["target_kind"] = kind
	mind["target_id"] = id
	return main


## --- woken garrisons ----------------------------------------------------------

func test_standing_units_wake_as_the_towns_defenders() -> void:
	var f := _woken()
	var s: GameState = f.s
	var rec: Dictionary = s.sieges[f.id]
	assert_eq(rec["woken"], f.standing, "every standing unit at the town, in code order")
	assert_eq(TownMilitia.standing_at(repo, s, f.town, repo.resolve_realm("raider_realm")), [], "none left standing")
	for c: String in f.standing:
		assert_true(s.foes.has(c), "%s is a foe now" % c)
		assert_eq(String(s.foes[c]["host"]), "", "in no host")
		assert_eq(String(s.foes[c]["garrison_of"]), f.town)
	assert_eq(SiegeSystem.defenders_of(repo, s, f.town), f.standing, "they defend the town")
	assert_eq(rec["militia"], [], "a garrison raises no militia")
	assert_eq(ArmyGround.seat_of(repo, s, f.town), f.seat, "the seat holder keeps its seat")
	assert_ne(ArmySystem.works_of(repo, ArmySystem.regiment(repo, f.seat, s), s), "", "and fights from the works")
	assert_eq(MilitaryBootstrap._integrity_error(repo, s), "", "the personnel model holds")


func test_the_woken_unit_returns_with_its_losses() -> void:
	var f := _woken()
	var s: GameState = f.s
	var code := String(f.seat)
	var living := MilitaryRoster.living(s, code)
	var died := MilitaryRoster.transfer_units(repo, s, "test:deaths",
		[{"unit_code": code, "from": "fit", "to": "dead", "count": 10}], "test: ten fall on the walls")
	assert_false(died.has("error"), str(died))
	assert_eq(TownMilitia.send_back(repo, s), [], "not while its siege runs")
	s.sieges.erase(f.id)
	var events := TownMilitia.send_back(repo, s)
	assert_eq(events.size(), (f.standing as Array).size(), "every woken unit goes back")
	assert_eq(String(events[0]["kind"]), "garrison_returned")
	for c: String in f.standing:
		assert_false(s.foes.has(c), "%s is a roster unit again" % c)
		assert_true(s.army_roster.has(c), "its row kept")
	assert_eq(MilitaryRoster.living(s, code), living - 10, "the roster row's men less the dead")
	assert_eq(ArmyGround.seat_of(repo, s, f.town), code, "back on its seat")
	assert_eq(TownMilitia.standing_at(repo, s, f.town, repo.resolve_realm("raider_realm")), f.standing,
		"standing again, woken by the next siege")
	assert_eq(TownMilitia.send_back(repo, s), [], "once")


func test_a_woken_unit_in_battle_waits() -> void:
	var f := _woken()
	var s: GameState = f.s
	s.battles.append({"id": 999, "att": [f.unit], "def": [f.seat], "town": f.town})
	s.sieges.erase(f.id)
	TownMilitia.send_back(repo, s)
	assert_true(s.foes.has(f.seat), "not while it fights")
	s.battles.clear()
	TownMilitia.send_back(repo, s)
	assert_false(s.foes.has(f.seat), "once the battle is over")


func test_a_town_lost_leaves_its_woken_units_foes() -> void:
	var f := _woken()
	var s: GameState = f.s
	s.occupations[f.town] = {"town": f.town, "occupier": repo.resolve_realm("player_realm"),
		"from": repo.resolve_realm("raider_realm"), "house": "", "host": "", "by": "test", "day": 1, "cells": {}}
	s.sieges.erase(f.id)
	assert_eq(TownMilitia.send_back(repo, s), [], "no town of theirs to go back to")
	for c: String in f.standing:
		assert_true(s.foes.has(c), "%s stays an ordinary foe" % c)
		assert_false((s.foes[c] as Dictionary).has("garrison_of"), "its mark dropped")


func test_woken_units_round_trip_the_save() -> void:
	var f := _woken()
	var s2 := GameState.from_dict((f.s as GameState).to_dict())
	assert_eq(s2.sieges[f.id]["woken"], f.standing)
	assert_eq(String(s2.foes[f.seat]["garrison_of"]), f.town)


func test_an_old_saves_siege_wakes_none() -> void:
	var s := SuiteData.campaign(repo, 7)
	var raider := repo.resolve_realm("raider_realm")
	var town := ""
	for t: String in s.town_seat:
		if SiegeSystem.holder_of(repo, s, t) == raider:
			town = t
	var before := _standing(s, town, raider)
	var id := SiegeRecord._open(repo, s, town, repo.resolve_realm("player_realm"), false)
	assert_eq(s.sieges[id]["woken"], [], "no woken units for a siege already running")
	assert_eq(_standing(s, town, raider), before)


## --- the enemy's sight of a militia ------------------------------------------

func test_defend_power_is_the_militias_power() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _empty_crown_town(s)
	assert_ne(town, "", "an empty crown town")
	var arms := TownMilitia.size(repo, s, town)
	var types := repo.world_table("military", "unit_types")
	var elements := {}
	var men := 0
	for arm: String in arms:
		@warning_ignore("integer_division")
		elements[arm] = int(arms[arm]) / int(types[arm]["crew"])
		men += int(arms[arm])
	var b: Dictionary = repo.burgs[town]
	var want := ArmySystem.power_of_arms(repo, elements, men, int(repo.bal("army_start_training")),
		int(repo.bal("army_start_morale")), "defend", ArmySystem.terrain_at(repo, Vector2(float(b["x"]), float(b["y"]))),
		TownMilitia.works_of_town(repo, town))
	assert_gt(want, 0)
	assert_eq(TownMilitia.defend_power(repo, s, town), want)
	repo.town_militia.clear()
	assert_eq(TownMilitia.defend_power(repo, s, town), 0, "no militia, no defence")


func test_the_enemy_weighs_an_empty_towns_militia() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var town := _empty_crown_town(s)
	var main := _arrive(s, EnemyAi.KIND_TOWN, town, Play.town_m(repo, town))
	var found := (EnemyAi._gather(repo, s, main) as Array).filter(func(c: Dictionary) -> bool:
		return String(c["kind"]) == EnemyAi.KIND_TOWN and String(c["id"]) == town)
	assert_eq(found.size(), 1, "the town is a candidate")
	assert_eq(int(found[0]["defence"]), TownMilitia.defend_power(repo, s, town), "its would-be militia")


## --- the arrival --------------------------------------------------------------

func test_an_empty_town_is_besieged_not_raided() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var town := _empty_crown_town(s)
	assert_ne(town, "", "an empty crown town")
	var main := _arrive(s, EnemyAi.KIND_TOWN, town, Play.town_m(repo, town))
	assert_eq(EnemyAi.arrival_mode(repo, s, main), EnemyAi.MODE_DEPLOYING, "besieged")
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[main]["mode"]) in [EnemyAi.MODE_DEPLOYING, EnemyAi.MODE_SIEGE], true)
	var rec := SiegeRecord.of_host(s, main)
	assert_false(rec.is_empty(), "the morning's arrival opens the record")
	var militia: Array = rec["militia"]
	assert_eq(militia.size(), 1, "the town's militia rises")
	assert_true(s.regiments.has(String(militia[0])), "the crown's")
	assert_eq(ArmyGround.seat_of(repo, s, town), String(militia[0]), "on the seat before any column walks in")
	assert_eq(EnemyAi.garrison_of(repo, s, town), militia, "the town's garrison")


func test_a_plain_manor_is_still_raided() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var player := repo.resolve_realm("player_realm")
	var cell := -1
	for prov: String in MapOwnership.provinces_of(repo, s, player):
		for c: int in MapManors.manors_of_province(repo, prov, s):
			if MapManors.burg_of(repo, c) == "" and EnemyAi.target_held(repo, s, EnemyAi.KIND_MANOR, str(c)) \
					and EnemyAi.defenders_of(repo, s, EnemyAi.KIND_MANOR, str(c), s.regiments.keys()).is_empty():
				cell = c
				break
		if cell >= 0:
			break
	assert_gt(cell, -1, "an open crown manor")
	var main := _arrive(s, EnemyAi.KIND_MANOR, str(cell), EnemyAi.target_point_m(repo, EnemyAi.KIND_MANOR, str(cell)))
	assert_eq(EnemyAi.arrival_mode(repo, s, main), EnemyAi.MODE_RAID)
