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
	assert_eq(lay.passes_left, 0, "the same stars: nothing settles again (final review I1b)")


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


## Owner 2026-10-01 (3个cluster布局可以靠的再近一点，node更分散一点): the
## three clusters' anchors stand nearer (each pair under 72 m, 85-100 before;
## the lone Intelligence star stands where its title clears the others'), a
## star repels another cluster's only ledger_galaxy_cross_repel as hard, so the
## settled clusters are nearer too (under 80 m apart, ~95-130 before), and a
## cluster's stars stand further apart — the court's mean nearest neighbour
## over 13 m (11.2 before) — while the clusters still settle apart (above).
func test_the_clusters_stand_nearer_and_their_stars_spread() -> void:
	var at := LedgerGalaxyLayout.anchors(repo, false)
	for a: String in ["economy", "war", "court"]:
		for b: String in ["economy", "war", "court"]:
			if a < b:
				assert_lt((at[a] as Vector3).distance_to(at[b]), 72.0, "%s and %s anchored nearer" % [a, b])
	assert_lt(repo.bal("ledger_galaxy_cross_repel"), 1.0, "another cluster's stars push less")
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, g, false)
	lay.step(lay.passes_left)
	var court: Array[Vector3] = []
	var sums := {}
	var counts := {}
	for n: Dictionary in g["nodes"]:
		var c := String(n["cluster"])
		sums[c] = (sums.get(c, Vector3.ZERO) as Vector3) + (lay.pos[String(n["id"])] as Vector3)
		counts[c] = int(counts.get(c, 0)) + 1
		if c == "court":
			court.append(lay.pos[String(n["id"])])
	for a: String in sums:
		for b: String in sums:
			if a < b and counts[a] > 1 and counts[b] > 1:
				var d := ((sums[a] as Vector3) / float(counts[a])).distance_to((sums[b] as Vector3) / float(counts[b]))
				assert_lt(d, 80.0, "%s and %s settle near" % [a, b])
	var sum := 0.0
	for i in court.size():
		var best := INF
		for j in court.size():
			if i != j:
				best = minf(best, court[i].distance_to(court[j]))
		sum += best
	assert_gt(sum / float(court.size()), 13.0, "the court's stars spread")


## Critic, round 2 (owner 2026-10-01: node更分散一点 — the King's inner ring
## had got tighter while the court's edge spread): a hub's springs lengthen
## with its links and no two stars' drawn discs come within reach of each
## other, so the core opens as well as the edge — its mean nearest neighbour
## over 16 m (11.0 before, 14.4 in round 1) and over 0.23 of the court's
## extent, the share of the framed view it gets (0.187 before, 0.197 round 1).
func test_the_kings_core_opens_and_no_discs_touch() -> void:
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, g, false)
	lay.step(lay.passes_left)
	var deg := {}
	var core := {"character:you": true}
	for l: Dictionary in g["links"]:
		for e: String in [String(l["from"]), String(l["to"])]:
			deg[e] = int(deg.get(e, 0)) + 1
		if String(l["from"]) == "character:you":
			core[String(l["to"])] = true
		elif String(l["to"]) == "character:you":
			core[String(l["from"])] = true
	var court: Array[String] = []
	var by := {}
	for n: Dictionary in g["nodes"]:
		by[String(n["id"])] = n
		if String(n["cluster"]) == "court":
			court.append(String(n["id"]))
	var draw := repo.bal("ledger_star_draw_scale")
	for a in court.size():
		for b in range(a + 1, court.size()):
			var ra := LedgerGalaxyLayout.size_of(repo, by[court[a]], int(deg.get(court[a], 0))) * draw
			var rb := LedgerGalaxyLayout.size_of(repo, by[court[b]], int(deg.get(court[b], 0))) * draw
			assert_gt((lay.pos[court[a]] as Vector3).distance_to(lay.pos[court[b]]), ra + rb,
				"%s and %s do not touch" % [court[a], court[b]])
	var ring: Array[String] = court.filter(func(id: String) -> bool: return core.has(id))
	assert_gt(ring.size(), 5, "the King and his court")
	var nn := 0.0
	for i in ring:
		var best := INF
		for j in ring:
			if i != j:
				best = minf(best, (lay.pos[i] as Vector3).distance_to(lay.pos[j]))
		nn += best / float(ring.size())
	var mid := Vector3.ZERO
	for id in court:
		mid += lay.pos[id]
	mid /= float(court.size())
	var extent := 0.0
	for id in court:
		extent = maxf(extent, (lay.pos[id] as Vector3).distance_to(mid))
	assert_gt(nn, 16.0, "the core's stars stand apart")
	assert_gt(nn / extent, 0.23, "and take more of the court's framed view")


## Critic, round 2: the flat chart lays every cluster in one plane, where at
## the 3D share they bled together — it has its own cross-cluster share, and
## the 3D chart does not read it.
func test_the_flat_chart_has_its_own_cross_share() -> void:
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var lays := []
	for v: float in [0.2, 1.0]:
		repo.balance["ledger_galaxy_cross_repel_flat"] = v
		var flat := LedgerGalaxyLayout.new()
		flat.setup(repo, g, true)
		flat.step(30)
		var deep := LedgerGalaxyLayout.new()
		deep.setup(repo, g, false)
		deep.step(30)
		lays.append([flat, deep])
	assert_ne(lays[0][0].pos["character:you"], lays[1][0].pos["character:you"], "the flat chart reads it")
	assert_eq(lays[0][1].pos["character:you"], lays[1][1].pos["character:you"], "the 3D chart does not")


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


## Task 11 (the budget): a frame's share of the settle runs at least one pass
## and never starts one it cannot finish inside the budget — with no budget
## to spare it runs exactly one, with room for all it settles the chart.
func test_a_frame_never_starts_a_pass_past_its_budget() -> void:
	var snap := _snap()
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, snap, false)
	var total := lay.passes_left
	assert_eq(lay.step_within(0.0), 1, "no budget to spare: one pass")
	assert_eq(lay.passes_left, total - 1)
	var ran := lay.step_within(1.0e9)
	assert_eq(ran, total - 1, "room for every pass: the rest")
	assert_true(lay.settled())
	assert_eq(lay.step_within(1.0e9), 0, "a settled chart runs nothing")



## Final review I1b: a redraw whose stars are the drawn ones keeps every
## place and runs no pass; one that adds a star keeps the survivors where
## they stood and runs only ledger_galaxy_resettle_passes, never the full
## settle; a chart still settling keeps the passes it had left.
func test_a_changed_redraw_keeps_the_survivors_and_settles_briefly() -> void:
	var lay := LedgerGalaxyLayout.new()
	var snap := _snap()
	lay.setup(repo, snap, false)
	assert_eq(lay.passes_left, int(repo.bal("ledger_galaxy_passes")), "the first draw settles fully")
	lay.step(lay.passes_left)
	var before: Dictionary = lay.pos.duplicate()
	snap["nodes"].append({"id": "manor:2", "type": "manor", "cluster": "economy", "home_id": "province:p"})
	lay.setup(repo, snap, false)
	for id: String in before:
		assert_eq(lay.pos[id], before[id], "a survivor keeps its place: " + id)
	assert_eq(lay.passes_left, int(repo.bal("ledger_galaxy_resettle_passes")), "a short settle")
	assert_lt(repo.bal("ledger_galaxy_resettle_passes"), repo.bal("ledger_galaxy_passes"))
	lay.step(5)
	var left := lay.passes_left
	lay.setup(repo, snap, false)
	assert_eq(lay.passes_left, left, "the same stars mid-settle: the settle goes on, not again")


func test_laying_the_chart_flat_settles_it_fully() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.step(lay.passes_left)
	lay.setup(repo, _snap(), true)
	assert_eq(lay.passes_left, int(repo.bal("ledger_galaxy_passes")), "another mode is another chart")


func test_a_pin_on_a_settled_chart_runs_a_share_of_the_settle() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.step(lay.passes_left)
	lay.pin("character:c0", Vector3(1, 2, 3))
	assert_eq(lay.passes_left, int(repo.bal("ledger_galaxy_passes") * repo.bal("ledger_galaxy_pin_share")))


## Final review I1c: past ledger_galaxy_grid_min_stars a pass repels only
## pairs within ledger_galaxy_repel_cutoff_m (a uniform grid). With a cut-off
## wider than the chart it is the all-pairs pass; it stays deterministic; and
## the realm's clusters still settle apart.
func test_the_grid_pass_is_the_all_pairs_pass_within_its_reach() -> void:
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var a := LedgerGalaxyLayout.new()
	a.setup(repo, g, false)
	a.step(20)
	repo.balance["ledger_galaxy_grid_min_stars"] = 0.0
	repo.balance["ledger_galaxy_repel_cutoff_m"] = 100000.0
	var b := LedgerGalaxyLayout.new()
	b.setup(repo, g, false)
	b.step(20)
	for id: String in a.pos:
		assert_almost_eq(b.pos[id], a.pos[id], Vector3.ONE * 1e-3, id)


func test_the_grid_layout_is_deterministic() -> void:
	repo.balance["ledger_galaxy_grid_min_stars"] = 0.0
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var a := LedgerGalaxyLayout.new()
	var b := LedgerGalaxyLayout.new()
	a.setup(repo, g, false)
	b.setup(repo, g, false)
	a.step(30)
	b.step(30)
	for id: String in a.pos:
		assert_eq(a.pos[id], b.pos[id], id)


func test_the_grid_layout_still_separates_the_clusters() -> void:
	repo.balance["ledger_galaxy_grid_min_stars"] = 0.0
	var s := GameState.new_campaign(repo, 42)
	var all := {}
	for code: String in MapOwnership.provinces_of(repo, s, repo.resolve_realm("player_realm")):
		all[code] = true
	var g := Ledger.galaxy(repo, s, all)
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
				assert_gt((mid[a] as Vector3).distance_to(mid[b]), float(spread[a]) + float(spread[b]),
					"%s and %s read as two clusters with every province open" % [a, b])
	# and the stars of a cluster do not collapse onto one another
	var ids: Array = lay.pos.keys()
	var close := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (lay.pos[ids[i]] as Vector3).distance_to(lay.pos[ids[j]]) < repo.bal("ledger_star_min"):
				close += 1
	assert_lt(close, ids.size() / 20, "hardly any two stars on top of each other")
