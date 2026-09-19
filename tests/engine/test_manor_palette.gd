extends GutTest
## ManorPalette (owner 2026-09-19): the manor colours the MANORS
## theme wears, shared by the 2D map (WorldMapView's wrappers) and the 3D
## map's ground tint, so the two maps can never colour a manor differently.

var _map: WorldMapView


func before_each() -> void:
	Game.start_campaign(42)
	_map = WorldMapView.create()
	_map.size = Vector2(640, 360)
	add_child_autofree(_map)


func _land_cells() -> Array:
	var out: Array = []
	for id: int in Game.data.cells:
		if not MapTerrain.is_water(Game.data.cells[id]):
			out.append(id)
	out.sort()
	return out


func _water_cell() -> int:
	for id: int in Game.data.cells:
		if MapTerrain.is_water(Game.data.cells[id]):
			return id
	return -1


func test_every_land_cell_wears_the_2d_maps_colours() -> void:
	var repo := Game.data
	var st := Game.state
	var bad := 0
	for id: int in _land_cells():
		if ManorPalette.province(repo, st, id) != _map.cell_province(id) \
				or ManorPalette.owner(repo, st, id) != _map.cell_owner(id) \
				or ManorPalette.house_color(repo, st, id) != _map.house_manor_color(id):
			bad += 1
	assert_eq(bad, 0, "cells whose colour differs between the palette and the 2D map")


func test_water_wears_nothing() -> void:
	var id := _water_cell()
	assert_eq(ManorPalette.theme_color(Game.data, Game.state, id, "manors"), Color(0, 0, 0, 0))


func test_a_conquest_recolours_the_manor() -> void:
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var cell := -1
	for id: int in _land_cells():
		if ManorPalette.owner(Game.data, Game.state, id) == mine:
			cell = id
			break
	var before := ManorPalette.house_color(Game.data, Game.state, cell)
	MapOwnership.set_owner(Game.data, Game.state,
		ManorPalette.province(Game.data, Game.state, cell), raider, "test: a raid")
	assert_eq(ManorPalette.owner(Game.data, Game.state, cell), raider)
	assert_ne(ManorPalette.house_color(Game.data, Game.state, cell), before,
		"the crown's manor under the raiders reads foreign")


## ECONOMY was folded into MANORS (owner 2026-09-19): one theme, the houses.
func test_the_theme_is_the_house_colour() -> void:
	var repo := Game.data
	var id := int(_land_cells()[0])
	assert_eq(ManorPalette.theme_color(repo, Game.state, id, "manors"),
		ManorPalette.house_color(repo, Game.state, id))
	assert_eq(ManorPalette.theme_color(repo, Game.state, id, "economy"), Color(0, 0, 0, 0),
		"no economy theme any more")


func test_the_edges_are_the_2d_maps_edges() -> void:
	var edges := ManorPalette.edges(Game.data)
	assert_eq(edges.size() % 2, 0, "segment pairs")
	assert_eq(edges, _map.manor_edges())
