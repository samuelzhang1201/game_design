extends GutTest
## The terrain the game draws itself (spec 2026-09-11): hand-computed colour
## and shading formulas over tiny fixture repos, no map pack needed.

## Two 10x10 land squares side by side: cell 1 at (0..10, 0..10) height 50,
## cell 2 at (10..20, 0..10) height 60. Light from the west by default.
func _two_cells(light: Vector2 = Vector2(-1, 0), strength := 0.02,
		altitude_gain := 0.0) -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_relief_strength": strength, "map_relief_min": 0.5,
		"map_relief_max": 1.5, "map_light_x": light.x, "map_light_y": light.y,
		"map_altitude_gain": altitude_gain, "map_sea_depth_gamma": 1.0}
	r.terrain_palette = {"biome_1": "#808080", "sea_deep": "#000000",
		"sea_shallow": "#ffffff", "lake": "#0000ff"}
	r.biomes = {1: {"biome_id": "1", "label": "Test", "color": "#ff0000"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10),
		3: Vector2(0, 10), 4: Vector2(20, 0), 5: Vector2(20, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 50.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 60.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([1])},
	}
	return r

func test_cell_center_is_the_mean_of_its_vertices() -> void:
	var r := _two_cells()
	assert_eq(MapTerrain.cell_center(r, r.cells[1]), Vector2(5, 5))
	assert_eq(MapTerrain.cell_center(r, r.cells[2]), Vector2(15, 5))

## gradient = sum over land neighbours of (h_n - h_c) * unit(p_n - p_c) / N.
## Cell 1: (60 - 50) * (1, 0) / 1 = (10, 0). Cell 2: (50 - 60) * (-1, 0) = (10, 0).
func test_gradient_points_uphill() -> void:
	var r := _two_cells()
	assert_eq(MapTerrain.gradient_of(r, r.cells[1]), Vector2(10, 0))
	assert_eq(MapTerrain.gradient_of(r, r.cells[2]), Vector2(10, 0))

## shade = 1 - strength * dot(gradient, light): a slope rising toward the
## east faces a light in the west, so it brightens: 1 - 0.02 * ((10,0).(-1,0))
## = 1 + 0.2 = 1.2. With the light in the east the same slope darkens to 0.8.
func test_slopes_facing_the_light_brighten_and_those_facing_away_darken() -> void:
	var west := _two_cells(Vector2(-1, 0))
	assert_almost_eq(MapTerrain.shade_of(west, west.cells[1]), 1.2, 0.0001)
	var east := _two_cells(Vector2(1, 0))
	assert_almost_eq(MapTerrain.shade_of(east, east.cells[1]), 0.8, 0.0001)

func test_the_light_direction_is_normalised() -> void:
	var r := _two_cells(Vector2(-3, 0))
	assert_almost_eq(MapTerrain.light_dir(r).x, -1.0, 0.0001)
	assert_almost_eq(MapTerrain.shade_of(r, r.cells[1]), 1.2, 0.0001,
		"a longer light vector does not shade harder")

## strength 0.1 gives 1 + 1.0 = 2.0, clamped to map_relief_max 1.5; the
## light from the east gives 0.0, clamped to map_relief_min 0.5.
func test_shade_clamps_to_the_relief_bounds() -> void:
	var bright := _two_cells(Vector2(-1, 0), 0.1)
	assert_almost_eq(MapTerrain.shade_of(bright, bright.cells[1]), 1.5, 0.0001)
	var dark := _two_cells(Vector2(1, 0), 0.1)
	assert_almost_eq(MapTerrain.shade_of(dark, dark.cells[1]), 0.5, 0.0001)

## A cell with no land neighbours is flat: shade 1, times the altitude term
## 1 + gain * (h - 20) / 80. At h 60 and gain 0.5 that is 1.25.
func test_altitude_brightens_a_flat_cell() -> void:
	var r := _two_cells(Vector2(-1, 0), 0.02, 0.5)
	r.cells[2]["neighbor_ids"] = PackedInt32Array()
	assert_eq(MapTerrain.gradient_of(r, r.cells[2]), Vector2.ZERO)
	assert_almost_eq(MapTerrain.shade_of(r, r.cells[2]), 1.25, 0.0001)

## Land colour = the palette tint for its biome times the shade. A flat
## cell with tint #808080 is exactly #808080.
func test_land_colour_is_the_biome_tint_times_the_shade() -> void:
	var r := _two_cells()
	r.cells[1]["neighbor_ids"] = PackedInt32Array()
	var c := MapTerrain.cell_color(r, r.cells[1])
	assert_almost_eq(c.r, Color("#808080").r, 0.0001)
	assert_almost_eq(c.g, Color("#808080").g, 0.0001)
	assert_almost_eq(c.b, Color("#808080").b, 0.0001)
	# With the west light the shade is 1.2, so every channel is 1.2x.
	var lit := MapTerrain.cell_color(_two_cells(), _two_cells().cells[1])
	assert_almost_eq(lit.r, Color("#808080").r * 1.2, 0.0001)

## A biome without a palette row falls back to the pack's own biome colour.
func test_unlisted_biome_falls_back_to_the_pack_colour() -> void:
	var r := _two_cells()
	r.cells[1]["neighbor_ids"] = PackedInt32Array()
	r.terrain_palette.erase("biome_1")
	var c := MapTerrain.cell_color(r, r.cells[1])
	assert_almost_eq(c.r, 1.0, 0.0001)
	assert_almost_eq(c.g, 0.0, 0.0001)

## Ocean grades from sea_deep at h 0 to sea_shallow at h 20 (gamma 1 here);
## a lake is the lake colour whatever its height.
func test_water_colours() -> void:
	var r := _two_cells()
	var deep := {"vertex_ids": PackedInt32Array([0, 1, 2]), "height": 0.0,
		"biome_id": 0, "water": "ocean", "neighbor_ids": PackedInt32Array()}
	var half := deep.duplicate()
	half["height"] = 10.0
	var shelf := deep.duplicate()
	shelf["height"] = 20.0
	var lake := deep.duplicate()
	lake["water"] = "lake"
	lake["height"] = 15.0
	assert_almost_eq(MapTerrain.cell_color(r, deep).r, 0.0, 0.0001)
	assert_almost_eq(MapTerrain.cell_color(r, half).r, 0.5, 0.0001)
	assert_almost_eq(MapTerrain.cell_color(r, shelf).r, 1.0, 0.0001)
	assert_eq(MapTerrain.cell_color(r, lake), Color("#0000ff"))
	assert_true(MapTerrain.is_water(lake))
	assert_false(MapTerrain.is_water(r.cells[1]))

## Three triangles sharing vertex 0: land A (tint white), land B (tint
## black), ocean C (h 0, sea_deep blue). All flat. A ring vertex blends only
## the cells of its own class: on A's fan vertex 0 is the mean of A and B =
## grey; on C's fan it is C alone = blue. C is listed as a neighbour of A
## and B but, being water, does not tilt them.
func _shore() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_relief_strength": 0.02, "map_relief_min": 0.5,
		"map_relief_max": 1.5, "map_light_x": -1.0, "map_light_y": 0.0,
		"map_altitude_gain": 0.0, "map_sea_depth_gamma": 1.0}
	r.terrain_palette = {"biome_1": "#ffffff", "biome_2": "#000000",
		"sea_deep": "#0000ff", "sea_shallow": "#ffffff", "lake": "#00ff00"}
	r.biomes = {1: {"color": "#ff0000"}, 2: {"color": "#ff0000"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(0, 10),
		3: Vector2(-10, 0), 4: Vector2(0, -10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2]), "height": 50.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2, 3])},
		2: {"vertex_ids": PackedInt32Array([0, 2, 3]), "height": 50.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1, 3])},
		3: {"vertex_ids": PackedInt32Array([0, 4, 1]), "height": 0.0, "biome_id": 0,
			"water": "ocean", "neighbor_ids": PackedInt32Array([1, 2])},
	}
	return r

func test_vertex_cells_lists_every_cell_touching_a_vertex() -> void:
	var adj := MapTerrain.vertex_cells(_shore())
	assert_eq(adj[0], [1, 2, 3])
	assert_eq(adj[3], [2])

func test_build_fans_each_cell_and_blends_ring_vertices_within_their_class() -> void:
	var built := MapTerrain.build(_shore())
	var verts: PackedVector2Array = built["vertices"]
	var cols: PackedColorArray = built["colors"]
	var idx: PackedInt32Array = built["indices"]
	# 3 cells x (1 centre + 3 ring) vertices; 3 triangles x 3 indices each.
	assert_eq(verts.size(), 12)
	assert_eq(cols.size(), 12)
	assert_eq(idx.size(), 27)
	assert_eq(idx.size() % 3, 0)
	# Cell 1 first: centre at index 0, its ring vertex 0 at index 1.
	assert_eq(verts[0], Vector2(10, 10) / 3.0)
	assert_eq(cols[0], Color(1, 1, 1, 1), "A's centre is white")
	assert_eq(verts[1], Vector2(0, 0))
	assert_almost_eq(cols[1].r, 0.5, 0.0001, "vertex 0 on A blends A and B")
	assert_almost_eq(cols[1].b, 0.5, 0.0001)
	# Cell 3 (ocean) is third: centre at 8, its ring vertex 0 at 9.
	assert_eq(verts[9], Vector2(0, 0))
	assert_eq(cols[9], Color(0, 0, 1, 1), "vertex 0 on C is water only")
	# Every triangle of a cell starts at that cell's centre.
	assert_eq(idx[0], 0)
	assert_eq(idx[3], 0)
	assert_eq(idx[9], 4, "cell 2's fan starts at its own centre")

func test_to_mesh_builds_a_triangle_surface() -> void:
	var mesh := MapTerrain.to_mesh(MapTerrain.build(_shore()))
	assert_not_null(mesh)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_TRIANGLES)

func test_shared_mesh_is_built_once_per_repo() -> void:
	var r := _shore()
	var a := MapTerrain.shared_mesh(r)
	assert_true(a == MapTerrain.shared_mesh(r), "the same repo gets the same mesh")
	assert_false(a == MapTerrain.shared_mesh(_shore()), "another repo gets its own")

## The committed pack builds, in native coordinates, covering the map.
func test_the_pack_builds_a_mesh_that_spans_the_map() -> void:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)
	var built := MapTerrain.build(repo)
	var b := MapGeometry.bounds(built["vertices"])
	assert_lte(b.position.x, 1.0)
	assert_lte(b.position.y, 1.0)
	assert_gte(b.end.x, float(repo.map_info["width"]) - 1.0)
	assert_gte(b.end.y, float(repo.map_info["height"]) - 1.0)
	assert_eq((built["colors"] as PackedColorArray).size(),
		(built["vertices"] as PackedVector2Array).size())
