extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The hex ground (spec 2026-10-07-army-split-and-ground §4.2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_rings_have_six_k_slots_starting_east_counter_clockwise() -> void:
	assert_eq(ArmyGround.ring(0), [Vector2i.ZERO])
	assert_eq(ArmyGround.ring(1), [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)])
	for k in range(1, 6):
		assert_eq(ArmyGround.ring(k).size(), 6 * k)


func test_slot_metres_on_the_lattice() -> void:
	# pitch 400: east (400, 0); north-east (200, -346) — y grows down the map
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, 0), 400), Vector2i(1400, 1000))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, -1), 400), Vector2i(1200, 654))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(0, 1), 400), Vector2i(1200, 1346))


func test_start_rings_are_the_tables() -> void:
	for row: Dictionary in repo.army_split:
		assert_eq(ArmyGround.start_ring(repo, String(row["arm"])), int(row["start_ring"]))


## A land point well inside the player's capital province, in metres.
func _land_m() -> Vector2i:
	var cap: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	return ArmySystem.pack_to_metres(repo, Vector2(float(cap["x"]), float(cap["y"])))


func test_a_taken_point_blocks_half_a_pitch_round_it() -> void:
	var taken := ArmyGround.new_taken(repo)
	var p := _land_m()
	assert_true(ArmyGround.is_free(repo, taken, p))
	ArmyGround.take(taken, p)
	var half := int(repo.bal("army_slot_spacing_m")) / 2
	assert_false(ArmyGround.is_free(repo, taken, p + Vector2i(half - 1, 0)))
	assert_true(ArmyGround.is_free(repo, taken, p + Vector2i(half, 0)) \
		or not ArmyGround.is_free(repo, ArmyGround.new_taken(repo), p + Vector2i(half, 0)),
		"free unless that ground is itself water or blocked")


func test_the_sea_is_never_free() -> void:
	assert_false(ArmyGround.is_free(repo, ArmyGround.new_taken(repo), Vector2i(-5000, -5000)))


func test_free_slot_starts_at_the_arms_ring() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for row: Dictionary in repo.army_split:
		var arm := String(row["arm"])
		var got := ArmyGround.free_slot(repo, c, arm, taken, true)
		assert_ne(got, ArmyGround.NONE)
		# its ring: the lattice distance from the centre, never inside start_ring
		var d := Vector2(got - c).length()
		assert_gte(d, float(spacing * int(row["start_ring"])) * 0.85, arm)


func test_the_field_centre_goes_to_the_first() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	assert_eq(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c, "an empty field: the centre")
	ArmyGround.take(taken, c)
	assert_ne(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c)


func test_a_town_centre_is_never_a_camp_slot() -> void:
	var c := _land_m()
	assert_ne(ArmyGround.free_slot(repo, c, "infantry", ArmyGround.new_taken(repo), true), c)


func test_no_free_slot_returns_none() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(0, int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ArmyGround.ring(k):
			ArmyGround.take(taken, ArmyGround.slot_m(c, ax, spacing))
	assert_eq(ArmyGround.free_slot(repo, c, "infantry", taken, true), ArmyGround.NONE)


func test_two_slots_in_order_are_distinct() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var a := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	ArmyGround.take(taken, a)
	var b := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	assert_ne(a, b)
	assert_gte(Vector2(a - b).length(), float(int(repo.bal("army_slot_spacing_m")) / 2))


# --- seats and camps (spec §4.1, §4.3–4.4) -----------------------------------

func _state() -> GameState:
	return SuiteData.campaign(repo, 3)


func _realm() -> String:
	return repo.resolve_realm("player_realm")


## The player's seated unit at its capital, the capital, and the units camped there.
func _capital(s: GameState) -> Dictionary:
	var town := String(repo.kingdoms[_realm()]["capital_burg"])
	var camped: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, _realm(), s):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(repo, s, c) == town and ArmyGround.seated_in(repo, s, c) == "":
			camped.append(c)
	return {"town": town, "seat": ArmyGround.seat_of(repo, s, town), "camped": camped}


func test_the_seat_and_the_camp_at_the_start() -> void:
	var s := _state()
	var cap := _capital(s)
	assert_ne(String(cap["seat"]), "")
	assert_eq(ArmyGround.seated_in(repo, s, String(cap["seat"])), String(cap["town"]))
	assert_eq(ArmyGround.camped_by(repo, s, String(cap["seat"])), String(cap["town"]), "the seat is camped too")
	assert_false((cap["camped"] as Array).is_empty(), "the capital has a camp round it")


func test_works_and_morale_go_to_the_seat_supply_to_the_camp() -> void:
	var s := _state()
	var cap := _capital(s)
	var seat := ArmySystem.regiment(repo, String(cap["seat"]), s)
	var camper := ArmySystem.regiment(repo, String((cap["camped"] as Array)[0]), s)
	assert_ne(ArmySystem.works_of(repo, seat, s), "")
	assert_eq(ArmySystem.works_of(repo, camper, s), "", "a camp fights on the field's terrain")
	assert_eq(SupplyLines.home_town(repo, s, String(camper["regiment_code"])), String(cap["town"]))


func test_marching_out_empties_the_seat_and_the_camp_refills_it() -> void:
	var s := _state()
	var cap := _capital(s)
	var old := String(cap["seat"])
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, old, s))
	ArmySystem.set_march(repo, s, old, here + Vector2(5.0, 0.0))
	var now := ArmyGround.seat_of(repo, s, String(cap["town"]))
	assert_ne(now, old)
	assert_ne(now, "", "a camped unit steps in the same day")
	assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, now, s)),
		ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, String(cap["town"]))))
	assert_eq(ArmyGround.camped_by(repo, s, old), "", "on the march it camps nowhere")


## March `code` to pack point `to` and run days until it arrives.
func _arrive(s: GameState, code: String, to: Vector2) -> void:
	ArmySystem.set_march(repo, s, code, to)
	for i in 400:
		if code in ArmySystem.march_day(repo, s):
			return
	fail_test("never arrived")


## A land point in the open (no town's reach) east of `from`, pack px.
func _field_east_of(from: Vector2) -> Vector2:
	for i in range(1, 200):
		var p := from + Vector2(float(i) * 5.0, 0.0)
		if MapEconomy.cell_at(repo, p) >= 0 and ArmySystem.town_at(repo, p) == "":
			return p
	return from + Vector2(40.0, 0.0)


func test_first_come_first_in() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var a := String(cap["seat"])
	var b := String((cap["camped"] as Array)[0])
	# nobody left in the camp to refill the seat: it stays empty when `a` leaves
	for c: String in cap["camped"]:
		s.regiments[c]["camp_town"] = ""
	var away := _field_east_of(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, a, s)))
	_arrive(s, a, away)
	assert_eq(ArmyGround.seat_of(repo, s, town), "")
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, town))
	_arrive(s, a, tp)
	assert_eq(ArmyGround.seat_of(repo, s, town), a, "the first to arrive takes the empty seat")
	_arrive(s, b, _field_east_of(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s))))
	_arrive(s, b, tp)
	assert_eq(ArmyGround.seat_of(repo, s, town), a)
	assert_eq(ArmyGround.camped_by(repo, s, b), town, "the later one camps round the town")
	assert_ne(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)), tp)


func test_a_foreign_town_is_the_field() -> void:
	var s := _state()
	var code := String(_capital(s)["seat"])
	var foreign := ""
	var codes := repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		if MapOwnership.owner_of(repo, s, String(repo.burgs[t]["province_code"])) != _realm():
			foreign = t
			break
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, foreign))
	_arrive(s, code, tp)
	assert_eq(ArmyGround.seated_in(repo, s, code), "")
	assert_eq(ArmyGround.camped_by(repo, s, code), "")
	assert_false(s.town_seat.has(foreign) and String(s.town_seat[foreign]) == code)


func test_a_unit_with_no_free_slot_stands_where_it_arrived() -> void:
	var s := _state()
	var code := String(_capital(s)["seat"])
	var dest := _field_east_of(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s)) + Vector2(55.0, 0.0))
	var saved: Variant = repo.balance["army_slot_max_rings"]
	repo.balance["army_slot_max_rings"] = 0.0
	# no ring past the centre: the field centre or nothing
	_arrive(s, code, dest)
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	repo.balance["army_slot_max_rings"] = saved
	assert_eq(at.distance_to(dest) < 2.0, true, "it holds the ground it reached")


## Ruling (Task 2/4): a town ringed by blocked ground still camps its units —
## settle retries on any terrain before it keeps the arrival point.
func test_a_town_among_blocked_ground_still_camps_its_arrivals() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var b := String((cap["camped"] as Array)[0])
	var saved: Dictionary = repo.army_camp_blocked.duplicate()
	for t: String in ["plains", "hills", "mountains"]:
		repo.army_camp_blocked[t] = true
	for id: int in repo.army_terrain_biomes:
		repo.army_camp_blocked[String(repo.army_terrain_biomes[id])] = true
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, town))
	_arrive(s, b, _field_east_of(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s))))
	_arrive(s, b, tp)
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s))
	repo.army_camp_blocked = saved
	assert_eq(ArmyGround.camped_by(repo, s, b), town)
	assert_ne(at, tp, "it camps on the blocked ground rather than stand on the seat")


## A column halted on the road (ARMY_GARRISON on a march) settles where it
## stands: inside a held town's reach it camps by that town.
func test_a_halt_in_a_towns_reach_camps_by_it() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var b := String((cap["camped"] as Array)[0])
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s))
	ArmySystem.set_march(repo, s, b, here + Vector2(80.0, 0.0))
	assert_eq(ArmyGround.camped_by(repo, s, b), "")
	var tp := ArmyGround.town_point_m(repo, town)
	s.regiments[b]["x_m"] = tp.x + 10
	s.regiments[b]["y_m"] = tp.y
	ArmySystem.set_garrison(repo, s, b)
	assert_eq(ArmyGround.camped_by(repo, s, b), town)
	assert_ne(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)),
		ArmySystem.metres_to_pack(repo, tp), "the seat is held: it takes a camp")


func test_a_lost_town_loses_its_seat() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var foe := ""
	var ks := repo.kingdoms.keys()
	ks.sort()
	for k: String in ks:
		if k != _realm():
			foe = k
			break
	MapOwnership.set_owner(repo, s, String(repo.burgs[town]["province_code"]), foe, "test: the town falls")
	ArmyGround.reconcile(repo, s)
	assert_false(s.town_seat.has(town))
