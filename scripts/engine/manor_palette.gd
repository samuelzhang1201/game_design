class_name ManorPalette
extends RefCounted
## The colours the MANORS theme paints each manor (owner 2026-09-19; ECONOMY
## was folded into it the same day): moved out of WorldMapView so the 2D map and the 3D map's
## ground tint (Map3DGroundTint) read ONE palette and can never colour a
## manor differently. Pure: every colour comes from the repository and the
## state it is given. Every value is balance.csv map_manor_* /
## political_palette.csv manor_*.

## The unique cell edges per repository (geometry, gathered once).
static var _edges: Dictionary = {}


## The province a cell lies in: an annexed manor's new province
## (state.manor_province), else the pack's (manors.csv, which agrees with the
## province index at every land cell's centre — checked 2026-09-19).
static func province(repo: DataRepository, state: GameState, cell_id: int) -> String:
	return MapManors.province_of(repo, cell_id, state)


## Who holds a cell now: its province's live owner, or "" for unheld land.
static func owner(repo: DataRepository, state: GameState, cell_id: int) -> String:
	var p := province(repo, state, cell_id)
	return "" if p == "" else MapOwnership.owner_of(repo, state, p)


## The MANORS view's wash: the holding house's colour — the crown its
## realm's, deepened map_manor_crown_deep toward manor_rich; another house
## its own hue — paled map_manor_foreign_pale outside the crown's realm.
## Transparent for land no house holds.
static func house_color(repo: DataRepository, state: GameState, cell_id: int) -> Color:
	var family := MapManors.owner_of(repo, state, cell_id)
	if family == "":
		return Color(0, 0, 0, 0)
	var mine := repo.resolve_realm("player_realm")
	var c: Color
	if family == MapManors.crown(state):
		c = MapPalette.color_of(repo, mine).lerp(MapPalette.named(repo, "manor_rich"),
			repo.bal("map_manor_crown_deep"))
	else:
		c = MapPalette.house_color(repo, family)
	if owner(repo, state, cell_id) != mine:
		c = c.lerp(MapPalette.named(repo, "manor_pale"), repo.bal("map_manor_foreign_pale"))
	c = _shaded(repo, state, cell_id, c)
	c.a = repo.bal("map_manor_alpha")
	return c


## What a land cell wears under `theme`: "manors" its house's colour (ECONOMY
## was folded into MANORS, owner 2026-09-19). Clear for water, unheld land
## and any other theme.
static func theme_color(repo: DataRepository, state: GameState, cell_id: int,
		theme: String) -> Color:
	var cell: Dictionary = repo.cells.get(cell_id, {})
	if cell.is_empty() or MapTerrain.is_water(cell) or theme != "manors":
		return Color(0, 0, 0, 0)
	return house_color(repo, state, cell_id)


## Neighbouring provinces told apart (owner 2026-09-13): the manor's colour
## shifted by its province's shade level (MapManors.province_shades), so
## two provinces of one house or one realm that touch never look alike.
static func _shaded(repo: DataRepository, state: GameState, cell_id: int, color: Color) -> Color:
	var levels := int(repo.bal("map_manor_shade_levels"))
	if levels <= 1:
		return color
	var level := int(MapManors.province_shades(repo, levels).get(
		MapManors.province_of(repo, cell_id, state), 0))
	return MapManors.shade(color, level, repo.bal("map_manor_shade_step"))


## Every edge of every land cell, once, as segment pairs in native
## coordinates. Geometry — gathered once per repository and kept.
static func edges(repo: DataRepository) -> PackedVector2Array:
	var key := repo.get_instance_id()
	if _edges.has(key):
		return _edges[key]
	var out := PackedVector2Array()
	var seen: Dictionary = {}
	var ids: Array = repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var ring: PackedInt32Array = cell["vertex_ids"]
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var k := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(k):
				continue
			seen[k] = true
			out.append(repo.vertices[a] as Vector2)
			out.append(repo.vertices[b] as Vector2)
	_edges[key] = out
	return out
