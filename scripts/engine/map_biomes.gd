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

## The alpha of `biome_id`'s tile at a vertex the LAND cells `ids` share.
## The layers are drawn in ascending biome id, one over the other, so the
## alpha that leaves the vertex an even mix of every biome around it is
## this biome's count over the count of every drawn biome up to and
## including it: the first-drawn biome at 1, the last at its bare share —
## painted in that order the coverage sums to exactly one, so the seam is
## a cross-fade and never a pale band. Water cells do not count (the
## coast stays crisp, as MapTerrain keeps it), nor do biomes without art
## (`drawn`; empty means every biome is drawn), since nothing of theirs
## is painted there to mix with.
static func _share(ids: Array, cells: Dictionary, biome_id: int, drawn: Dictionary) -> float:
	var under := 0
	var same := 0
	for id in ids:
		var cell: Dictionary = cells[id]
		if MapTerrain.is_water(cell):
			continue
		var b := int(cell.get("biome_id", -1))
		if b > biome_id or not (drawn.is_empty() or drawn.has(b)):
			continue
		under += 1
		if b == biome_id:
			same += 1
	return float(same) / float(under) if under > 0 else 1.0

## The mesh arrays of one biome's land in native map coordinates: per cell
## (id order) a centre vertex then one ring vertex per polygon vertex, a
## triangle per edge, and every vertex's UV = its position / tile_px.
## `soft` (map_biome_soft, owner 2026-09-14: the hard cell edges read
## false) cross-fades the biomes at their seams through the vertex ALPHA:
## a ring vertex is pulled from 1 toward `_share` by `soft`, so a cell's
## tile is whole at its centre and mixes with its neighbours' along its
## rim — a gradient a cell wide. The centre stays 1: only this biome's
## mesh covers a cell's middle, so fading it there would show the sheet
## (the first cut did, and lone cells turned to pale blots). `touching`
## is MapTerrain.vertex_cells(repo), passed in so twelve biomes share
## one; built here when soft asks and none came. `drawn` is the set of
## biome ids that have art (MapBiomes.art_of).
static func build(repo: DataRepository, biome_id: int, tile_px: float,
		soft: float = 0.0, touching: Dictionary = {}, drawn: Dictionary = {}) -> Dictionary:
	var tile := maxf(tile_px, 1.0)
	var fade := clampf(soft, 0.0, 1.0)
	if fade > 0.0 and touching.is_empty():
		touching = MapTerrain.vertex_cells(repo)
	var ids: Array = repo.cells.keys()
	ids.sort()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
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
		cols.append(Color.WHITE)  # the hub: only this biome's mesh covers a cell's middle
		for v in ring:
			var p: Vector2 = repo.vertices[v]
			verts.append(p)
			uvs.append(p / tile)
			var alpha := 1.0
			if fade > 0.0 and touching.has(v):
				alpha = lerpf(1.0, _share(touching[v], repo.cells, biome_id, drawn), fade)
			cols.append(Color(1.0, 1.0, 1.0, alpha))
		var n := ring.size()
		for i in n:
			idx.append(base)
			idx.append(base + 1 + i)
			idx.append(base + 1 + (i + 1) % n)
	return {"vertices": verts, "uvs": uvs, "colors": cols, "indices": idx}

static func to_mesh(built: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_TEX_UV] = built["uvs"]
	if built.has("colors"):
		arrays[Mesh.ARRAY_COLOR] = built["colors"]
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
	var soft := repo.bal("map_biome_soft")
	var touching := MapTerrain.vertex_cells(repo) if soft > 0.0 else {}
	for id in ids:
		var built := build(repo, int(id), tile, soft, touching, art)
		if (built["indices"] as PackedInt32Array).is_empty():
			continue
		out.append({"biome_id": int(id), "texture": String(art[id]), "mesh": to_mesh(built)})
	_cache[key] = out
	return out
