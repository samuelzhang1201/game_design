extends GutTest
## The BIOMES LAYER (experiment 2026-09-14): the land of each biome as one
## textured mesh whose UVs tile a seamless ground texture in native map px.
## Hand-built fixture: three 10x10 squares in a row — two of biome 1, one of
## biome 2 — and a sea cell that must never be tiled.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_biome_tile_px": 20.0, "map_biome_alpha": 0.5, "map_biome_soft": 0.0}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10),
		3: Vector2(0, 10), 4: Vector2(20, 0), 5: Vector2(20, 10),
		6: Vector2(30, 0), 7: Vector2(30, 10), 8: Vector2(40, 0), 9: Vector2(40, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 50.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 50.0,
			"biome_id": 2, "water": "", "neighbor_ids": PackedInt32Array([1, 3])},
		3: {"vertex_ids": PackedInt32Array([4, 6, 7, 5]), "height": 50.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([2, 4])},
		4: {"vertex_ids": PackedInt32Array([6, 8, 9, 7]), "height": 10.0,
			"biome_id": 1, "water": "ocean", "neighbor_ids": PackedInt32Array([3])},
	}
	r.biome_art = [
		{"biome_id": "1", "key": "broadleaf", "texture": "res://x/broadleaf.png"},
		{"biome_id": "2", "key": "steppe", "texture": "res://x/steppe.png"},
		{"biome_id": "3", "key": "ice", "texture": "res://x/ice.png"},
	]
	return r

func after_each() -> void:
	MapBiomes.invalidate()

## Biome 1 has two land squares: each is a fan of a centre and four ring
## vertices (10 vertices), four triangles each (24 indices). The sea square
## of biome 1 is not in it.
func test_a_biome_is_the_fans_of_its_land_cells() -> void:
	var b := MapBiomes.build(_repo(), 1, 20.0)
	assert_eq((b["vertices"] as PackedVector2Array).size(), 10)
	assert_eq((b["indices"] as PackedInt32Array).size(), 24)
	assert_eq((b["uvs"] as PackedVector2Array).size(), 10)
	var b2 := MapBiomes.build(_repo(), 2, 20.0)
	assert_eq((b2["vertices"] as PackedVector2Array).size(), 5, "one square of biome 2")

## UV = position / tile_px: the tile spans 20 native px, so the vertex at
## (10, 10) sits one half tile along, and (30, 10) at 1.5 tiles. Tiling is
## in the sheet's own space, so neighbouring cells continue the same tile.
func test_uvs_tile_the_sheet_in_native_px() -> void:
	var b := MapBiomes.build(_repo(), 1, 20.0)
	var verts: PackedVector2Array = b["vertices"]
	var uvs: PackedVector2Array = b["uvs"]
	assert_eq(verts[0], Vector2(5, 5), "the first fan's hub")
	assert_eq(uvs[0], Vector2(0.25, 0.25))
	var i := verts.find(Vector2(30, 10))
	assert_true(i >= 0)
	assert_eq(uvs[i], Vector2(1.5, 0.5))

## One layer per biome that has art AND land: biome 3 has art but no cell,
## so it is not a layer; a mesh is kept between calls.
func test_layers_are_one_mesh_per_biome_with_art_and_land() -> void:
	var r := _repo()
	var layers := MapBiomes.layers(r)
	assert_eq(layers.size(), 2)
	assert_eq(int(layers[0]["biome_id"]), 1)
	assert_eq(String(layers[0]["texture"]), "res://x/broadleaf.png")
	assert_eq(int(layers[1]["biome_id"]), 2)
	assert_eq((layers[0]["mesh"] as ArrayMesh).get_surface_count(), 1, "one draw call")
	assert_true(MapBiomes.layers(r)[0]["mesh"] == layers[0]["mesh"], "kept between frames")
	MapBiomes.invalidate()
	assert_false(MapBiomes.layers(r)[0]["mesh"] == layers[0]["mesh"], "rebuilt after invalidate")

func test_a_pack_without_biome_art_has_no_layers() -> void:
	var r := _repo()
	r.biome_art = []
	assert_eq(MapBiomes.layers(r).size(), 0)

## Hard edges (soft 0): every vertex fully opaque.
func test_without_softening_every_vertex_is_opaque() -> void:
	var b := MapBiomes.build(_repo(), 1, 20.0, 0.0)
	for c: Color in (b["colors"] as PackedColorArray):
		assert_eq(c.a, 1.0)

## Cross-fade (soft 1). The layers paint in ascending biome id, so at a
## seam vertex the FIRST biome stays at 1 and the next carries its share:
## vertex (10,0) touches cells 1 and 2 (biomes 1, 2) -> biome 1's mesh 1/1
## = 1.0, biome 2's 1/2 — painted in that order the vertex is an even mix
## with nothing of the sheet showing. Vertex (0,0) touches only cell 1 ->
## 1.0; vertex (30,0) touches cell 3 and the SEA cell 4 -> the sea does
## not count, 1.0 (the coast stays crisp). Every centre stays 1.0: only
## its own mesh covers a cell's middle.
func test_softening_fades_a_vertex_by_its_biomes_share_of_the_land_around_it() -> void:
	var b := MapBiomes.build(_repo(), 1, 20.0, 1.0)
	var verts: PackedVector2Array = b["vertices"]
	var cols: PackedColorArray = b["colors"]
	assert_eq(cols.size(), verts.size())
	assert_almost_eq(cols[verts.find(Vector2(0, 0))].a, 1.0, 0.0001, "inside the biome")
	assert_almost_eq(cols[verts.find(Vector2(10, 0))].a, 1.0, 0.0001, "first painted: whole at the seam")
	assert_almost_eq(cols[verts.find(Vector2(30, 0))].a, 1.0, 0.0001, "on the coast")
	assert_almost_eq(cols[verts.find(Vector2(5, 5))].a, 1.0, 0.0001, "cell 1's centre")
	assert_almost_eq(cols[verts.find(Vector2(25, 5))].a, 1.0, 0.0001, "cell 3's centre")
	var other := MapBiomes.build(_repo(), 2, 20.0, 1.0)
	var ov: PackedVector2Array = other["vertices"]
	var oc: PackedColorArray = other["colors"]
	assert_almost_eq(oc[ov.find(Vector2(10, 0))].a, 0.5, 0.0001, "painted second: half over the first")
	assert_almost_eq(oc[ov.find(Vector2(15, 5))].a, 1.0, 0.0001, "cell 2's centre")

## A neighbour whose biome has no art is not in the mix: biome 2's mesh at
## (10,0) with only biome 2 drawn -> 1/1 = 1.0, a crisp edge to the sheet.
func test_a_biome_without_art_does_not_fade_its_neighbours() -> void:
	var b := MapBiomes.build(_repo(), 2, 20.0, 1.0, {}, {2: "res://x/steppe.png"})
	var verts: PackedVector2Array = b["vertices"]
	var cols: PackedColorArray = b["colors"]
	assert_almost_eq(cols[verts.find(Vector2(10, 0))].a, 1.0, 0.0001)

## soft 0.5 pulls a seam vertex only halfway from 1 toward its share:
## 1 + (0.5 - 1) * 0.5 = 0.75.
func test_softening_is_a_dial() -> void:
	var b := MapBiomes.build(_repo(), 2, 20.0, 0.5)
	var verts: PackedVector2Array = b["vertices"]
	var cols: PackedColorArray = b["colors"]
	assert_almost_eq(cols[verts.find(Vector2(10, 0))].a, 0.75, 0.0001)
