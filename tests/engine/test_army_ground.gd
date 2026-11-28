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


## The player's capital, and its point in metres (well inside its province).
func _cap() -> String:
	return String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])


func _land_m() -> Vector2i:
	return ArmyGround.town_point_m(repo, _cap())


## The hex ring `p_m` lies on round `c_m` at `pitch` (the lattice's own inverse).
func _ring_of(c_m: Vector2i, p_m: Vector2i, pitch: int) -> int:
	var d := Vector2(p_m - c_m)
	var r := roundi(d.y / (float(pitch) * sqrt(3.0) / 2.0))
	var q := roundi(d.x / float(pitch) - float(r) * 0.5)
	@warning_ignore("integer_division")
	return (absi(q) + absi(r) + absi(q + r)) / 2


func test_a_taken_point_blocks_the_sum_of_the_two_radii_round_it() -> void:
	# army_clearance.csv (spec 2026-10-14-unit-clearance-and-scouting-design, R-A):
	# no centre within r_a + r_b of a held one, the metre at it free
	var taken := ArmyGround.new_taken(repo)
	var p := _land_m()
	var foot := ArmyGround.arm_radius(repo, "infantry")
	var horse := ArmyGround.arm_radius(repo, "cavalry")
	assert_eq([foot, horse], [1140, 2200])
	assert_true(ArmyGround.is_clear(repo, taken, p, foot))
	ArmyGround.take(taken, p, foot)
	var c := foot + horse
	assert_false(ArmyGround.is_clear(repo, taken, p + Vector2i(c - 1, 0), horse))
	assert_false(ArmyGround.is_clear(repo, taken, p + Vector2i(0, c - 1), horse))
	assert_true(ArmyGround.is_clear(repo, taken, p + Vector2i(c, 0), horse), "the metre at the sum is clear")
	assert_gte(int(repo.bal("army_slot_spacing_m")), 2 * horse, "the camp pitch holds two of the widest units")


func test_with_no_clearance_a_taken_point_blocks_half_a_pitch() -> void:
	var r2 := SuiteData.no_clearance(SuiteData.repo())
	var taken := ArmyGround.new_taken(r2)
	var p := ArmyGround.town_point_m(r2, String(r2.kingdoms[r2.resolve_realm("player_realm")]["capital_burg"]))
	ArmyGround.take(taken, p)
	@warning_ignore("integer_division")
	var half := int(r2.bal("army_slot_spacing_m")) / 2
	assert_false(ArmyGround.is_free(r2, taken, p + Vector2i(half - 1, 0)))
	assert_true(ArmyGround.is_free(r2, taken, p + Vector2i(half, 0)) \
		or not ArmyGround.is_free(r2, ArmyGround.new_taken(r2), p + Vector2i(half, 0)))


func test_the_sea_is_never_free() -> void:
	assert_false(ArmyGround.is_free(repo, ArmyGround.new_taken(repo), Vector2i(-5000, -5000)))


func test_free_slot_starts_at_the_arms_ring() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	var clear := ArmyGround.clear_rings(ArmyGround.town_reach_m(repo, _cap()), spacing)
	for row: Dictionary in repo.army_split:
		var arm := String(row["arm"])
		var got := ArmyGround.free_slot(repo, c, arm, taken, _cap())
		assert_ne(got, ArmyGround.NONE)
		# its ring: never inside the arm's ring counted from the town's clear rings
		assert_gte(_ring_of(c, got, spacing), clear + int(row["start_ring"]) - 1, arm)
		assert_eq(ArmyGround.first_ring(repo, arm, _cap()), maxi(clear + int(row["start_ring"]) - 1, 1), arm)
		assert_eq(ArmyGround.first_ring(repo, arm, ""), maxi(int(row["start_ring"]), 1), arm + " in the field")


## R16: the rings a town's reach covers, ceil(reach / pitch), at least one.
func test_the_rings_a_reach_clears() -> void:
	assert_eq(ArmyGround.clear_rings(3000.0, 1500), 2, "3 km at 1500 m")
	assert_eq(ArmyGround.clear_rings(1000.0, 1500), 1, "1 km at 1500 m")
	assert_eq(ArmyGround.clear_rings(3000.0, 900), 4, "3 km at 900 m: 3.33 rounds up")
	assert_eq(ArmyGround.clear_rings(0.0, 1500), 1, "no reach: still one")


## R16: round the capital the first infantry camp lies past its reach (城外).
func test_the_first_camp_round_the_capital_is_outside_its_reach() -> void:
	var c := _land_m()
	var spacing := int(repo.bal("army_slot_spacing_m"))
	var reach_m := ArmyGround.town_reach_m(repo, _cap())
	assert_eq(reach_m, float(repo.army_town_reach[String(repo.burgs[_cap()]["group"])]) * 1000.0)
	var got := ArmyGround.free_slot(repo, c, "infantry", ArmyGround.new_taken(repo), _cap())
	assert_ne(got, ArmyGround.NONE)
	assert_gte(_ring_of(c, got, spacing), ArmyGround.clear_rings(reach_m, spacing))
	assert_false(ArmyGround.in_reach(repo, _cap(), got))
	assert_ne(ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, got)), _cap(), "outside the walls")


func test_the_field_centre_goes_to_the_first() -> void:
	# a field point a cavalry piece fits on whole: its first camp round the capital (a port,
	# whose own point a horse's piece would reach the water from)
	var c := ArmyGround.free_slot(repo, _land_m(), "cavalry", ArmyGround.new_taken(repo), _cap())
	var taken := ArmyGround.new_taken(repo)
	assert_eq(ArmyGround.free_slot(repo, c, "cavalry", taken, ""), c, "an empty field: the centre")
	ArmyGround.take(taken, c)
	assert_ne(ArmyGround.free_slot(repo, c, "cavalry", taken, ""), c)


func test_a_town_centre_is_never_a_camp_slot() -> void:
	var c := _land_m()
	assert_ne(ArmyGround.free_slot(repo, c, "infantry", ArmyGround.new_taken(repo), _cap()), c)


func test_no_free_slot_returns_none() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(0, int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ArmyGround.ring(k):
			ArmyGround.take(taken, ArmyGround.slot_m(c, ax, spacing))
	assert_eq(ArmyGround.free_slot(repo, c, "infantry", taken, _cap()), ArmyGround.NONE)


func test_two_slots_in_order_are_distinct() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var a := ArmyGround.free_slot(repo, c, "infantry", taken, _cap())
	ArmyGround.take(taken, a)
	var b := ArmyGround.free_slot(repo, c, "infantry", taken, _cap())
	assert_ne(a, b)
	@warning_ignore("integer_division")
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


## Owner 2026-11-22 (我不想要他自动填补空位): a seat its holder marches out of
## stays EMPTY — no camped unit is moved onto the town's point; the camp stands
## where it is, ready for orders, and a unit marched into the town takes it.
func test_marching_out_empties_the_seat_and_the_camp_stays_put() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var old := String(cap["seat"])
	var camped: Array = cap["camped"]
	var before: Dictionary = {}
	for c: String in camped:
		before[c] = ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, c, s))
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, old, s))
	var way := _open_way(s, old)
	assert_ne(way, Vector2.ZERO, "an open way out of the camp")
	ArmySystem.set_march(repo, s, old, here + way * 5.0)
	assert_eq(ArmyGround.seat_of(repo, s, town), "", "the seat stands empty as it leaves")
	assert_eq(ArmyGround.camped_by(repo, s, old), "", "on the march it camps nowhere")
	for day in 3:
		ArmySystem.march_day(repo, s)      # it marches well clear of the point
		ArmyGround.reconcile(repo, s)
	assert_eq(ArmyGround.seat_of(repo, s, town), "", "nobody steps onto the empty seat")
	for c: String in camped:
		assert_eq(ArmyGround.camped_by(repo, s, c), town, "%s still camps by the town" % c)
		assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, c, s)), before[c], "%s stays on its camp" % c)


## With the clearance rule off the seat stays empty too (leave refilled at once).
func test_with_clearance_off_marching_out_leaves_the_seat_empty() -> void:
	var r := SuiteData.no_clearance(repo)
	var s := SuiteData.campaign(r, 42)
	var town := String(r.kingdoms[r.resolve_realm("player_realm")]["capital_burg"])
	var old := ArmyGround.seat_of(r, s, town)
	assert_ne(old, "", "the capital is seated at the start")
	var here := ArmySystem.position_of(r, s, ArmySystem.regiment(r, old, s))
	ArmySystem.set_march(r, s, old, here + Vector2(5.0, 0.0))
	ArmyGround.reconcile(r, s)
	assert_eq(ArmyGround.seat_of(r, s, town), "")


## March `code` to pack point `to` and run days until it arrives.
func _arrive(s: GameState, code: String, to: Vector2) -> void:
	ArmySystem.set_march(repo, s, code, to)
	for i in 400:
		if code in ArmySystem.march_day(repo, s):
			return
	fail_test("never arrived")


## A land point in the open (no town's reach) from `from` along `dir`, pack px.
func _field_from(from: Vector2, dir := Vector2.RIGHT) -> Vector2:
	for i in range(1, 200):
		var p := from + dir * float(i) * 5.0
		if MapEconomy.cell_at(repo, p) >= 0 and ArmySystem.town_at(repo, p) == "":
			return p
	return from + dir * 40.0


## The first of east, west, north, south in which `code` marches out of the camp to the
## open field unhindered, tried on a copy: the capital's camp fills its slots round the
## walls, so a fixed direction can walk into a camped neighbour and halt in front of it.
## With `home`, the way back must be open too: marching from the field to `home`'s point it
## is camped by `home`, not halted in front of a camped unit outside the town's reach.
func _open_way(s: GameState, code: String, home := "") -> Vector2:
	var from := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var copy := GameState.from_dict(s.to_dict())
		var to := _field_from(from, dir)
		ArmySystem.set_march(repo, copy, code, to)
		for i in 400:
			if code in ArmySystem.march_day(repo, copy):
				break
		if ArmySystem.position_of(repo, copy, ArmySystem.regiment(repo, code, copy)).distance_to(to) >= 1.0:
			continue
		if home != "":
			ArmySystem.set_march(repo, copy, code, ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, home)))
			for i in 400:
				if code in ArmySystem.march_day(repo, copy):
					break
			if ArmyGround.camped_by(repo, copy, code) != home:
				continue
		return dir
	return Vector2.ZERO


func test_first_come_first_in() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var a := String(cap["seat"])
	var b := String((cap["camped"] as Array)[0])
	# nobody left in the camp to refill the seat: it stays empty when `a` leaves
	for c: String in cap["camped"]:
		s.regiments[c]["camp_town"] = ""
	var way := _open_way(s, a)
	assert_ne(way, Vector2.ZERO, "an open way out of the camp")
	var away := _field_from(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, a, s)), way)
	_arrive(s, a, away)
	assert_eq(ArmyGround.seat_of(repo, s, town), "")
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, town))
	_arrive(s, a, tp)
	assert_eq(ArmyGround.seat_of(repo, s, town), a, "the first to arrive takes the empty seat")
	var home := _open_way(s, b, town)
	assert_ne(home, Vector2.ZERO, "an open way out and home")
	_arrive(s, b, _field_from(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)), home))
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
	var dest := _field_from(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s)) + Vector2(55.0, 0.0))
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
	var home := _open_way(s, b, town)
	assert_ne(home, Vector2.ZERO, "an open way out and home")
	_arrive(s, b, _field_from(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)), home))
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


## Owner 2026-11-22: a crown column halted short of a held town it was bound for, within
## army_spread_reach_m of the town's point, camps by that town as a host spreads round its
## target: the free slot nearest its halt point inside the circle. Further out, or bound for
## a town the crown does not hold, it camps in the field.
func test_a_column_halted_short_of_its_held_town_camps_by_it() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var b := String((cap["camped"] as Array)[0])
	var tp := ArmyGround.town_point_m(repo, town)
	var pitch := int(repo.bal("army_slot_spacing_m"))
	var reach := int(repo.bal("army_spread_reach_m"))
	var entry: Dictionary = s.regiments[b]
	entry["camp_town"] = ""
	# halted three pitches due east of the capital, bound for its point
	var halt := tp + Vector2i(3 * pitch, 0)
	ArmyGround._put(entry, halt)
	entry["halted_by"] = String(cap["seat"])
	entry["halt_aim_m"] = [tp.x, tp.y]
	var arm := MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, b, s))
	var expected := ArmyGround.free_slot(repo, tp, arm, ArmyGround.held_taken(repo, s, b), town, false, halt, 0, reach)
	assert_ne(expected, ArmyGround.NONE, "a free slot inside the circle")
	ArmyGround.settle(repo, s, b, halt)
	assert_eq(ArmyGround.camped_by(repo, s, b), town, "camped by the town it was bound for")
	assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), expected)
	assert_lte(MarchClearance.dist2(expected, tp), reach * reach)
	# past the circle: the field
	var far := tp + Vector2i(reach + pitch, 0)
	ArmyGround._put(entry, far)
	ArmyGround.settle(repo, s, b, far)
	assert_ne(String(entry["camp_town"]), town, "beyond army_spread_reach_m it is not camped by the town")
	# with no halt aim the old rule holds: the field
	entry.erase("halt_aim_m")
	ArmyGround._put(entry, halt)
	ArmyGround.settle(repo, s, b, halt)
	assert_ne(String(entry["camp_town"]), town, "with no halt aim it camps where it halted")


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


## A state with no roster reads the pack's split (ArmySystem.roster), and so
## its opening seats too (spec §2.4: one way in).
func test_a_state_with_no_roster_reads_the_packs_seats() -> void:
	var s := GameState.new()
	assert_true(s.army_roster.is_empty(), "premise: no roster")
	var seats := ArmySplit.seats_of(repo)
	var towns := seats.keys()
	towns.sort()
	assert_false(towns.is_empty(), "premise: the pack fills a seat")
	var town := String(towns[0])
	assert_eq(ArmyGround.seat_of(repo, s, town), String(seats[town]))
	assert_eq(ArmyGround.seated_in(repo, s, String(seats[town])), town)

## Ring two has corners farther out than its side midpoints. The closest
## unbounded slot may lie outside the limit while another legal slot exists.
func test_bounded_slot_search_finds_inner_side_slots_and_refuses_overflow() -> void:
	var r := SuiteData.flat_ground(SuiteData.repo())
	var centre := _land_m()
	var taken := ArmyGround.new_taken(r)
	var pitch := int(r.bal("army_slot_spacing_m"))
	ArmyGround.take(taken, centre)
	for ax: Vector2i in ArmyGround.ring(1):
		ArmyGround.take(taken, ArmyGround.slot_m(centre, ax, pitch))
	var near := centre + Vector2i(pitch * 3, 0)
	var bound := pitch * 2 - 1
	var unbounded := ArmyGround.free_slot(r, centre, "infantry", taken, "", true, near, 1)
	assert_gt(Vector2(unbounded - centre).length(), float(bound), "premise: nearest free corner is outside")
	var bounded := ArmyGround.free_slot(r, centre, "infantry", taken, "", true, near, 1, bound)
	assert_ne(bounded, ArmyGround.NONE, "a side slot within the same ring is still available")
	assert_lte(Vector2(bounded - centre).length(), float(bound))
	assert_eq(ArmyGround.free_slot(r, centre, "infantry", taken, "", true, near, 1, pitch - 1), ArmyGround.NONE)



func _loop(kind: String, pts: Array) -> Dictionary:
	var poly := PackedVector2Array(pts)
	return {"kind": kind, "polyline": poly, "bbox": MapGeometry.bounds(poly)}


func test_is_dry_is_the_coast_loops_by_parity() -> void:
	# A hand-made shore: land 0..100 square, a lake 40..60 in it, an island 45..55 in the lake.
	var r := DataRepository.new()
	r.coasts = [_loop("land", [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]),
		_loop("lake", [Vector2(40, 40), Vector2(60, 40), Vector2(60, 60), Vector2(40, 60)]),
		_loop("land", [Vector2(45, 45), Vector2(55, 45), Vector2(55, 55), Vector2(45, 55)])]
	assert_true(MapEconomy.is_dry(r, Vector2(20, 20)), "inside the land loop: one loop, dry")
	assert_false(MapEconomy.is_dry(r, Vector2(42, 50)), "in the lake: two loops, wet")
	assert_true(MapEconomy.is_dry(r, Vector2(50, 50)), "on the island: three loops, dry")
	assert_false(MapEconomy.is_dry(r, Vector2(120, 50)), "out at sea: no loop, wet")


func test_a_harbour_slot_at_sea_is_not_free() -> void:
	# The trap behind the harbour regiments on the water (owner 2026-11-28): cell_at falls back
	# to the NEAREST land cell, so a camp slot out at sea passed as land. Hand-checked on the
	# default pack's harbour town at (1370.5, 676.7): its horse and archers took ring 2's
	# east slots (1383.7 and 1379.3, y 676.7), outside every coast loop, each with a land cell by
	# cell_at. Here: from every port town, the first point east of it outside the loops.
	var found := 0
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if String(b.get("is_port", "0")) != "1":
			continue
		for step in range(1, 20):
			var p := Vector2(float(b["x"]) + step, float(b["y"]))
			if not MapEconomy.is_dry(repo, p):
				assert_false(ArmyGround.is_free(repo, ArmyGround.new_taken(repo), ArmySystem.pack_to_metres(repo, p),
					true), "%s +%d px is sea" % [code, step])
				if MapEconomy.cell_at(repo, p) >= 0:
					found += 1
				break
	assert_gt(found, 0, "some sea point by a port still has a cell by cell_at (the trap)")


func test_no_land_unit_starts_on_the_water() -> void:
	# Every land unit of every realm at the campaign's start stands inside the drawn shore, its
	# camped piece whole (the harbour archers' centre was ashore, their spread figures not).
	var state: GameState = SuiteData.campaign(repo, 42)
	var checked := 0
	for code: String in ArmySystem.roster(repo, state):
		var reg := ArmySystem.regiment(repo, code, state)
		if String(reg.get("is_naval", "0")) == "1":
			continue
		var p := ArmySystem.position_of(repo, state, reg)
		checked += 1
		if ArmyGround.seated_in(repo, state, code) != "":
			# a seat is its town's own point: that point, at least, is ashore
			assert_true(MapEconomy.is_dry(repo, p), "%s's seat is on the water at %s" % [code, p])
			continue
		# a camp's whole drawn piece: the centre and eight points at its arm's radius
		var m := ArmySystem.pack_to_metres(repo, p)
		var r := ArmyGround.unit_radius(repo, reg)
		for i in 9:
			var a := TAU * float(i) / 8.0
			var at := m + (Vector2i(roundi(r * cos(a)), roundi(r * sin(a))) if i < 8 else Vector2i.ZERO)
			assert_true(MapEconomy.is_dry(repo, ArmySystem.metres_to_pack(repo, at)),
				"%s's piece reaches the water at %s" % [code, ArmySystem.metres_to_pack(repo, at)])
	assert_gt(checked, 20)
