class_name MapBiomes
extends RefCounted
## THE BIOMES LAYER — an EXPERIMENT (owner 2026-09-14). The land of every
## biome is laid with a seamless ground tile (library §5 T- tiles, colour
## pencil: forest canopy, pasture, steppe, marsh, tundra, ice), drawn over
## the political wash and under the water and the roads at balance.csv
## map_biome_alpha (under the 0.72 wash it could not be seen at all).
## data/biome_art.csv says which tile a biome wears; a biome without a row
## keeps the plain sheet.
##
## One mesh per biome — the fans of its land cells, exactly the way
## MapTerrain fans them, but with UVs in TILES (native px / map_biome_tile_px)
## so the sheet repeats in the map's own space and neighbouring cells
## continue the same tile. A frame is one draw_mesh per biome with art
## (twelve at most), never anything per cell. Pure over the repository, no
## RNG, cached per repo instance.
##
## TO REMOVE THE EXPERIMENT: delete this file, data/biome_art.csv,
## assets/biomes/, assets/flux/biome_art.csv and install_biomes, the two
## map_biome_* rows of balance.csv, tests/engine/test_map_biomes.gd, and the
## blocks marked BIOMES LAYER in DataRepository, WorldMapView, the view test
## and tools/snapshot_map.gd.

## repo instance id -> Array of {biome_id: int, texture: String, mesh: ArrayMesh}
static var _cache: Dictionary = {}

static func invalidate() -> void:
	_cache.clear()

## biome_id -> texture path, first row per biome; rows without a texture
## are skipped.
static func art_of(repo: DataRepository) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in repo.biome_art:
		var id := int(row.get("biome_id", -1))
		var texture := String(row.get("texture", ""))
		if id >= 0 and texture != "" and not out.has(id):
			out[id] = texture
	return out

## The mesh arrays of one biome's land in native map coordinates: per cell
## (id order) a centre vertex then one ring vertex per polygon vertex, a
## triangle per edge, and every vertex's UV = its position / tile_px.
static func build(repo: DataRepository, biome_id: int, tile_px: float) -> Dictionary:
	var tile := maxf(tile_px, 1.0)
	var ids: Array = repo.cells.keys()
	ids.sort()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for id in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or int(cell.get("biome_id", -1)) != biome_id:
			continue
		var ring: PackedInt32Array = cell["vertex_ids"]
		if ring.size() < 3:
			continue
		var base := verts.size()
		var hub := MapTerrain.cell_center(repo, cell)
		verts.append(hub)
		uvs.append(hub / tile)
		for v in ring:
			var p: Vector2 = repo.vertices[v]
			verts.append(p)
			uvs.append(p / tile)
		var n := ring.size()
		for i in n:
			idx.append(base)
			idx.append(base + 1 + i)
			idx.append(base + 1 + (i + 1) % n)
	return {"vertices": verts, "uvs": uvs, "indices": idx}

static func to_mesh(built: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_TEX_UV] = built["uvs"]
	arrays[Mesh.ARRAY_INDEX] = built["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## The layers to draw, ascending by biome id: one per biome that has art
## AND land in this pack. Built on first use, kept for the repo's life.
static func layers(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var art := art_of(repo)
	var ids: Array = art.keys()
	ids.sort()
	var tile := repo.bal("map_biome_tile_px")
	for id in ids:
		var built := build(repo, int(id), tile)
		if (built["indices"] as PackedInt32Array).is_empty():
			continue
		out.append({"biome_id": int(id), "texture": String(art[id]), "mesh": to_mesh(built)})
	_cache[key] = out
	return out
