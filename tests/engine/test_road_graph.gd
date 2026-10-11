extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The road network (spec 2026-09-27-courier-core §1). Fixtures in pack px on
## beria's measure (1 px = 1000 m). Every height tier is forced to 1000‰ so
## the hand sums hold whatever cells lie under the fixture.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	RoadGraph.forget()
	repo.road_speed = {"road": 1000, "trail": 500, "offroad": 250, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	repo.balance["courier_graph_snap_px"] = 2.0


func after_all() -> void:
	RoadGraph.forget()


func _routes() -> Dictionary:
	return {
		"r1": {"group": "roads", "polyline": PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])},
		# joins r1 MID-LINE, a hair off its vertex: the snap merges them
		"r2": {"group": "trails", "polyline": PackedVector2Array([Vector2(10.4, 0.3), Vector2(10, 10)])},
		"r3": {"group": "trails", "polyline": PackedVector2Array([Vector2(100, 100), Vector2(110, 100)])},
		"r4": {"group": "searoutes", "polyline": PackedVector2Array([Vector2(20, 0), Vector2(100, 100)])},
	}


func test_the_snap_merges_a_mid_line_join() -> void:
	var g := RoadGraph.build(repo, _routes())
	# r1: 3 nodes; r2 adds only (10,10); r3: 2; the sea route adds nothing.
	assert_eq(g.nodes.size(), 6)


func test_the_fastest_route_and_its_cost_by_hand() -> void:
	var g := RoadGraph.build(repo, _routes())
	var a := g.nearest(Vector2i(0, 0))
	var b := g.nearest(Vector2i(10000, 10000))
	var tree := g.shortest(a)
	# road 10 km at 1000‰: 10,000 m -> 10,000 clear-road metres x 1000 units
	# trail 10 km at 500‰: 20,000 clear-road metres x 1000 units
	assert_eq(int(tree["dist"][b]), 10_000_000 + 20_000_000)
	assert_eq(g.route(tree, b), [[10000, 0, "road"], [10000, 10000, "trail"]])


func test_a_separate_network_is_unreached() -> void:
	var g := RoadGraph.build(repo, _routes())
	var tree := g.shortest(g.nearest(Vector2i(0, 0)))
	assert_eq(int(tree["dist"][g.nearest(Vector2i(110000, 100000))]), -1)
	assert_ne(g.nearest(Vector2i(110000, 100000), tree["dist"]), g.nearest(Vector2i(110000, 100000)),
		"among the reached, the nearest is on the capital's own network")


## Perf 2026-10-02: a graph never changes once built, so a start's tree is
## run once and kept — the same tree, asked again, with no second Dijkstra.
func test_a_start_s_tree_is_run_once_and_kept() -> void:
	var g := RoadGraph.build(repo, _routes())
	var a := g.shortest(0)
	var runs := g.dijkstra_runs
	var b := g.shortest(0)
	assert_eq(g.dijkstra_runs, runs, "asked again, not run again")
	assert_eq(b["dist"], a["dist"])
	assert_eq(b["prev"], a["prev"])
	g.shortest(1)
	assert_eq(g.dijkstra_runs, runs + 1, "another start is its own tree")


func test_stretch_need_rounds_up() -> void:
	assert_eq(RoadGraph.stretch_need(1000, 1_000_000_000), 1000)
	assert_eq(RoadGraph.stretch_need(1000, 500_000_000), 2000)
	assert_eq(RoadGraph.stretch_need(1, 3), 333_333_334)


func test_the_capital_reaches_nearly_the_whole_pack() -> void:
	var fresh := SuiteData.repo()
	RoadGraph.forget()
	var g := RoadGraph.of_pack(fresh)
	var cap: Dictionary = fresh.burgs[String(fresh.kingdoms[fresh.resolve_realm("player_realm")]["capital_burg"])]
	var tree := g.shortest(g.nearest(ArmySystem.pack_to_metres(fresh, Vector2(float(cap["x"]), float(cap["y"])))))
	var reached := 0
	for d: int in tree["dist"]:
		if d >= 0:
			reached += 1
	assert_gt(float(reached) / float(g.nodes.size()), 0.95, "97% of nodes are one component (2026-09-27)")
	RoadGraph.forget()


## --- the courier's network (owner 2026-10-11): rivers, and the way round ---

func _wall(wall: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	for y in 4:
		bytes[y * 9 + 4] = wall
	return MarchPath.build(repo, 9, 5, 1000, bytes, true)


func _river_routes() -> Dictionary:
	return {
		"r1": {"group": "roads", "polyline": PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])},
		"r2": {"group": "trails", "polyline": PackedVector2Array([Vector2(10, 0), Vector2(20, 10)])},
	}


func _river() -> Dictionary:
	return {"rv": {"polyline": PackedVector2Array([Vector2(10.4, 0.3), Vector2(10, 10), Vector2(20, 10)])}}


## The river joins the road at (10, 0) (snapped), then runs (10, 10), (20, 10).
## Road 0 -> (10, 0): 10,000 m at 1000 = 10,000,000. Trail (10, 0) -> (20, 10):
## 14,142 m at 500 = 28,284,000. River at 800: 10 km = 12,500 m of road x 1000
## = 12,500,000 each, (10, 0) -> (10, 10) -> (20, 10) = 25,000,000 < the trail.
func test_a_river_joins_at_a_snapped_vertex_and_is_a_route() -> void:
	repo.road_speed["river"] = 800
	var g := RoadGraph.build(repo, _river_routes(), _river())
	assert_eq(g.nodes.size(), 4, "road ends, the trail's end, and the river's two new points")
	var a := g.nearest(Vector2i(0, 0))
	var b := g.nearest(Vector2i(20000, 10000))
	var tree := g.shortest(a)
	assert_eq(int(tree["dist"][b]), 10_000_000 + 25_000_000)
	assert_eq(g.route(tree, b), [[10000, 0, "road"], [10000, 10000, "river"], [20000, 10000, "river"]])
	assert_eq(RoadGraph.build(repo, _river_routes()).nodes.size(), 3, "without rivers")


## A road from (1.5, 2.5) to (7.5, 2.5) over a scarp (column 4, rows 0-3)
## goes round by the gap (4500, 4500): two stretches of 3606 m (13e6 root)
## at offroad 250: need 3606 x 1000 / 250 = 14,424 each, x 1000 units.
func test_a_road_over_a_scarp_goes_round() -> void:
	repo.road_speed["offroad"] = 250
	var routes := {"r": {"group": "roads", "polyline": PackedVector2Array([Vector2(1.5, 2.5), Vector2(7.5, 2.5)])}}
	var g := RoadGraph.build(repo, routes, {}, _wall(150))
	assert_eq(g.nodes.size(), 2)
	var e: Array = g.edges[0][0]
	assert_eq(int(e[1]), 7212)
	assert_eq(String(e[2]), "road")
	var tree := g.shortest(0)
	assert_eq(int(tree["dist"][1]), 28_848_000)
	assert_eq(g.route(tree, 1), [[4500, 4500, "offroad"], [7500, 2500, "offroad"]])
	assert_eq(g.route(g.shortest(1), 0), [[4500, 4500, "offroad"], [1500, 2500, "offroad"]])


func test_no_way_round_keeps_the_drawn_edge() -> void:
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	for y in 5:
		bytes[y * 9 + 4] = 150
	var grid := MarchPath.build(repo, 9, 5, 1000, bytes, true)
	var routes := {"r": {"group": "roads", "polyline": PackedVector2Array([Vector2(1.5, 2.5), Vector2(7.5, 2.5)])}}
	var g := RoadGraph.build(repo, routes, {}, grid)
	var tree := g.shortest(0)
	assert_eq(int(g.edges[0][0][1]), 6000)
	assert_eq(int(tree["dist"][1]), 6_000_000)
	assert_eq(g.route(tree, 1), [[7500, 2500, "road"]])


func test_a_route_is_a_copy() -> void:
	repo.road_speed["offroad"] = 250
	var routes := {"r": {"group": "roads", "polyline": PackedVector2Array([Vector2(1.5, 2.5), Vector2(7.5, 2.5)])}}
	var g := RoadGraph.build(repo, routes, {}, _wall(150))
	var tree := g.shortest(0)
	var first := g.route(tree, 1)
	(first[0] as Array)[0] = 1
	assert_eq(g.route(tree, 1)[0][0], 4500, "the graph's own way is untouched")


func test_the_real_pack_courier_network() -> void:
	var fresh := SuiteData.repo()
	RoadGraph.forget()
	var plain := RoadGraph.of_pack(fresh)
	var g := RoadGraph.courier_of_pack(fresh)
	assert_gt(g.nodes.size(), plain.nodes.size(), "the rivers add nodes")
	assert_true(is_same(g, RoadGraph.courier_of_pack(fresh)), "cached")
	var cap: Dictionary = fresh.burgs[String(fresh.kingdoms[fresh.resolve_realm("player_realm")]["capital_burg"])]
	var tree := g.shortest(g.nearest(ArmySystem.pack_to_metres(fresh, Vector2(float(cap["x"]), float(cap["y"])))))
	var grid := MarchPath.of_pack(fresh, true)
	var detoured := 0
	var kept := 0
	var wrong := 0   # one assert at the end: thousands of edges
	for u in g.nodes.size():
		for e: Array in g.edges[u]:
			var v := int(e[0])
			if v < u:
				continue
			var a := g.nodes[u]
			var b := g.nodes[v]
			if grid.clear(a, b, [grid.cell_of(a), grid.cell_of(b)]):
				wrong += 0 if (e[4] as Array).is_empty() else 1   # a clear chord keeps the drawn edge
			elif (e[4] as Array).is_empty():
				kept += 1
				wrong += 0 if grid.road(a, b).size() == 1 else 1   # kept only for no way round
			else:
				detoured += 1
	assert_eq(wrong, 0, "every edge is drawn, or gone round, or kept for no way round")
	gut.p("steep edges detoured %d, kept for no way round %d, nodes %d (drawn %d)" % [detoured, kept, g.nodes.size(), plain.nodes.size()])
	# the routes come first, so the ids past the drawn network's are river-only nodes
	var reached := 0
	var river_only := g.nodes.size() - plain.nodes.size()
	for id in range(plain.nodes.size(), g.nodes.size()):
		if int(tree["dist"][id]) >= 0:
			reached += 1
	gut.p("river-only nodes reached from the capital: %d of %d" % [reached, river_only])
	# some headwaters never touch a road or trail (the same with no detours at all)
	assert_gt(float(reached) / float(maxi(1, river_only)), 0.8)
	RoadGraph.forget()


func test_installing_a_grid_rebuilds_the_courier_network() -> void:
	var fresh := SuiteData.repo()
	RoadGraph.forget()
	var g := RoadGraph.courier_of_pack(fresh)
	MarchPath.use(fresh, MarchPath.of_pack(fresh, true), true)
	assert_false(is_same(g, RoadGraph.courier_of_pack(fresh)))
	RoadGraph.forget()
