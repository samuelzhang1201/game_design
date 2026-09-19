extends GutTest
## Elevation (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §1):
## cell height into metres and supply tiers.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func test_metres_from_the_cell_height() -> void:
	assert_eq(Elevation.metres_of_height(repo, 20.0), 0, "the waterline")
	assert_eq(Elevation.metres_of_height(repo, 45.0), 750)
	assert_eq(Elevation.metres_of_height(repo, 100.0), 2400)
	assert_eq(Elevation.metres_of_height(repo, 17.0), -90, "below the waterline")

func test_metres_of_a_cell_reads_its_height() -> void:
	var ids := repo.cells.keys()
	ids.sort()
	var id: int = ids[0]
	assert_eq(Elevation.metres_of_cell(repo, id),
		Elevation.metres_of_height(repo, float(repo.cells[id]["height"])))
	assert_eq(Elevation.metres_of_cell(repo, -1), 0, "no cell is the waterline")

func test_tier_edges() -> void:
	assert_eq(Elevation.tier_of(repo, 44.0)["tier"], "plains")
	assert_eq(Elevation.tier_of(repo, 45.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 61.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 62.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 71.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 72.0)["tier"], "peak")
	assert_eq(int(Elevation.tier_of(repo, 10.0)["supply_permille"]), 1000)
	assert_eq(int(Elevation.tier_of(repo, 50.0)["supply_permille"]), 1300)
	assert_eq(int(Elevation.tier_of(repo, 65.0)["supply_permille"]), 1700)
	assert_eq(int(Elevation.tier_of(repo, 90.0)["supply_permille"]), 2200)

func test_the_table_is_read_highest_first() -> void:
	var mins: Array = repo.army_height_supply.map(func(r: Dictionary) -> int: return int(r["min_height"]))
	assert_eq(mins, [72, 62, 45, 0])

## A hand-built strip of land cells 0..4 (heights 30, 50, 40, 25, 35) and
## one sea cell 5 next to cell 4. High: 1, and 4 (above its one land
## neighbour). Low: 0 and 3; 4 touches the sea, so it is never a basin.
func _strip() -> Dictionary:
	var hs := [30.0, 50.0, 40.0, 25.0, 35.0]
	var cells := {}
	for i in hs.size():
		var nb := PackedInt32Array()
		if i > 0:
			nb.append(i - 1)
		if i < hs.size() - 1:
			nb.append(i + 1)
		cells[i] = {"height": hs[i], "water": "", "neighbor_ids": nb,
			"vertex_ids": PackedInt32Array([0, 1, 2])}
	(cells[4]["neighbor_ids"] as PackedInt32Array).append(5)
	cells[5] = {"height": 10.0, "water": "ocean", "neighbor_ids": PackedInt32Array([4]),
		"vertex_ids": PackedInt32Array([0, 1, 2])}
	return cells

func test_extremes_on_a_strip() -> void:
	var e := Elevation.extremes(_strip())
	assert_eq(Array(e["high"]), [1, 4], "4 is above its one land neighbour")
	assert_eq(Array(e["low"]), [0, 3], "4 touches the sea, so it is no basin")

func test_a_plateau_keeps_one_high_point() -> void:
	var cells := _strip()
	cells[2]["height"] = 50.0  # 1 and 2 tie
	var e := Elevation.extremes(cells)
	assert_true(1 in Array(e["high"]), "the lower id wins a tie")
	assert_false(2 in Array(e["high"]))

func test_landmarks_on_the_pack() -> void:
	var marks := Elevation.landmarks(repo)
	assert_gt(marks.size(), 0)
	var prev := 1 << 30
	for m: Dictionary in marks:
		assert_true(int(m["prominence"]) <= prev, "biggest first")
		prev = int(m["prominence"])
		assert_gte(int(m["prominence"]), int(repo.bal("landmark_min_prominence_m")))
		assert_ne(String(m["name"]), "")
		assert_true(int(m["lod"]) in [0, 1, 2])
	var names := {}
	for m: Dictionary in marks:
		assert_false(names.has(m["name"]), "names are unique: " + String(m["name"]))
		names[m["name"]] = true

func test_the_lod_follows_prominence() -> void:
	for m: Dictionary in Elevation.landmarks(repo):
		var p := int(m["prominence"])
		var want := 0 if p >= int(repo.bal("landmark_lod_far_m")) \
			else (1 if p >= int(repo.bal("landmark_lod_mid_m")) else 2)
		assert_eq(int(m["lod"]), want)

func test_a_name_override_wins() -> void:
	var m: Dictionary = Elevation.landmarks(repo)[0]
	repo.landmark_name_overrides[int(m["cell"])] = "The Old Man"
	Elevation.forget()
	assert_eq(Elevation.landmark_at(repo, int(m["cell"]))["name"], "The Old Man")
	repo.landmark_name_overrides.erase(int(m["cell"]))
	Elevation.forget()

func test_local_edge() -> void:
	var m: Dictionary = Elevation.landmarks(repo)[0]
	var edge := Elevation.local_edge_m(repo, int(m["cell"]))
	assert_eq(absi(edge), int(m["prominence"]), "the prominence is the edge's size")

func test_an_override_never_collides_with_a_more_prominent_name() -> void:
	var marks := Elevation.landmarks(repo)
	var top: Dictionary = marks[0]
	var lesser: Dictionary = marks[marks.size() - 1]
	var top_name := String(top["name"])
	repo.landmark_name_overrides[int(lesser["cell"])] = top_name
	Elevation.forget()
	var top_after := String(Elevation.landmark_at(repo, int(top["cell"]))["name"])
	var lesser_after := String(Elevation.landmark_at(repo, int(lesser["cell"]))["name"])
	assert_eq(lesser_after, top_name, "the override wins its own cell")
	assert_ne(top_after, lesser_after, "names stay unique after the override")
	repo.landmark_name_overrides.erase(int(lesser["cell"]))
	Elevation.forget()
