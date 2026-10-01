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
