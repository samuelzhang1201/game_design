extends GutTest
## The BIOMES LAYER (experiment 2026-09-14): the land of each biome as one
## textured mesh whose UVs tile a seamless ground texture in native map px.
## Hand-built fixture: three 10x10 squares in a row — two of biome 1, one of
## biome 2 — and a sea cell that must never be tiled.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_biome_tile_px": 20.0, "map_biome_alpha": 0.5}
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
