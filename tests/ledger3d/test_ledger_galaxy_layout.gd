# tests/ledger3d/test_ledger_galaxy_layout.gd
extends GutTest
## Where the galaxy's stars stand (spec 2026-09-30-ledger-galaxy-design §4).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")


func _snap() -> Dictionary:
	var nodes: Array = []
	for i in 6:
		nodes.append({"id": "character:c%d" % i, "type": "character", "cluster": "court"})
	for i in 4:
		nodes.append({"id": "regiment:r%d" % i, "type": "regiment", "cluster": "war"})
	nodes.append({"id": "province:p", "type": "province", "cluster": "economy", "folded": {"manor": 9}})
	nodes.append({"id": "manor:1", "type": "manor", "cluster": "economy", "home_id": "province:p"})
	var links: Array = [{"from": "character:c0", "to": "character:c1"}, {"from": "character:c1", "to": "regiment:r0"},
		{"from": "manor:1", "to": "province:p"}]
	return {"nodes": nodes, "links": links}


func test_one_snapshot_always_lays_out_the_same_way() -> void:
	var a := LedgerGalaxyLayout.new()
	var b := LedgerGalaxyLayout.new()
	a.setup(repo, _snap(), false)
	b.setup(repo, _snap(), false)
	a.step(40)
	b.step(40)
	for id: String in a.pos:
		assert_eq(a.pos[id], b.pos[id], id)


func test_a_star_keeps_its_place_across_a_snapshot() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.step(lay.passes_left)
	var before: Dictionary = lay.pos.duplicate()
	lay.setup(repo, _snap(), false)
	for id: String in before:
		assert_eq(lay.pos[id], before[id], "kept: " + id)
	assert_gt(lay.passes_left, 0, "a new snapshot settles again")


func test_a_new_star_starts_round_its_home() -> void:
	var lay := LedgerGalaxyLayout.new()
	var snap := _snap()
	lay.setup(repo, snap, false)
	lay.step(lay.passes_left)
	snap["nodes"].append({"id": "manor:2", "type": "manor", "cluster": "economy", "home_id": "province:p"})
	lay.setup(repo, snap, false)
	var d := (lay.pos["manor:2"] as Vector3).distance_to(lay.pos["province:p"])
	assert_lt(d, 3.0 * repo.bal("ledger_galaxy_rest_m"), "a newly opened manor appears by its province")


func test_the_flat_chart_lies_in_the_plane() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), true)
	lay.step(30)
	for id: String in lay.pos:
		assert_eq((lay.pos[id] as Vector3).y, 0.0, id)


func test_a_pinned_star_stays_where_it_is_held() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.pin("character:c0", Vector3(1, 2, 3))
	lay.step(20)
	assert_eq(lay.pos["character:c0"], Vector3(1, 2, 3))


func test_the_clusters_settle_apart() -> void:
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, g, false)
	lay.step(lay.passes_left)
	var sums := {}
	var counts := {}
	for n: Dictionary in g["nodes"]:
		var c := String(n["cluster"])
		sums[c] = (sums.get(c, Vector3.ZERO) as Vector3) + (lay.pos[String(n["id"])] as Vector3)
		counts[c] = int(counts.get(c, 0)) + 1
	var mid := {}
	for c: String in sums:
		mid[c] = (sums[c] as Vector3) / float(counts[c])
	var spread := {}
	for n: Dictionary in g["nodes"]:
		var c := String(n["cluster"])
		spread[c] = float(spread.get(c, 0.0)) + (lay.pos[String(n["id"])] as Vector3).distance_to(mid[c]) / float(counts[c])
	for a: String in mid:
		for b: String in mid:
			if a < b:
				assert_gt((mid[a] as Vector3).distance_to(mid[b]), float(spread[a]) + float(spread[b]) * 0.5,
					"%s and %s read as two clusters" % [a, b])
	assert_true(lay.settled())


func test_a_star_is_sized_by_its_kind() -> void:
	var pool := LedgerGalaxyLayout.size_of(repo, {"type": "gold"}, 30)
	assert_eq(pool, repo.bal("ledger_star_pool"), "a pool is one fixed size")
	var small := LedgerGalaxyLayout.size_of(repo, {"type": "character"}, 1)
	var big := LedgerGalaxyLayout.size_of(repo, {"type": "character"}, 16)
	assert_lt(small, big, "more links, a bigger star")
	var prov := LedgerGalaxyLayout.size_of(repo, {"type": "province", "folded": {"manor": 36}}, 1)
	assert_gt(prov, small, "a province grows with what it folds")
	assert_lte(LedgerGalaxyLayout.size_of(repo, {"type": "province", "folded": {"manor": 9999}}, 999),
		repo.bal("ledger_star_max"))
