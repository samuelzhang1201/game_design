extends GutTest
## The house type table and its tuning keys (spec 2026-09-20 §5). The meshes
## themselves are asserted by test_map3d_houses_meshes.gd once Task 3 has
## generated them.

const ROLES := ["landmark", "house", "barn"]
const GROUPS := ["capital", "city", "fort", "town", "village"]
const BAKE_KEYS := ["house_radius_ratio", "house_core_ratio", "house_barn_ratio",
	"house_spacing_m", "house_density_gamma", "house_foot_min", "house_max_slope",
	"house_shore_min_m", "house_port_shore_min_m", "house_min", "house_edge_scale",
	"house_yaw_jitter_deg", "house_road_align_m", "house_people_per_house",
	"house_max_capital", "house_max_city", "house_max_town", "house_max_fort",
	"house_max_village"]
const BAL_KEYS := ["map3d_house_view_m", "map3d_house_fade_m",
	"map3d_house_rebuild_move_m", "map3d_house_sink_m"]


func before_all() -> void:
	Game.start_campaign(42)


func test_the_table_loads_and_every_row_is_well_formed() -> void:
	var rows: Dictionary = Game.data.map3d_houses
	assert_gt(rows.size(), 6, "the type table has a usable set of houses")
	for type: String in rows:
		var r: Dictionary = rows[type]
		assert_true(ROLES.has(String(r["role"])), type + " has a known role")
		assert_gt(float(r["weight"]), 0.0, type + " has a positive weight")
		assert_gt(float(r["footprint_m"]), 0.0, type + " has a footprint")
		assert_gt(float(r["height_m"]), 0.0, type + " has a height")
		assert_true(GROUPS.has(String(r["min_group"])), type + " names a settlement group")
		assert_true(Game.data.terrain_palette.has(String(r["roof"])),
			type + "'s roof colour is in terrain_palette.csv")


func test_every_settlement_group_can_be_filled() -> void:
	# a village must find a landmark, a house and a barn, or it draws nothing
	for group: String in GROUPS:
		for role: String in ROLES:
			var found := false
			for type: String in Game.data.map3d_houses:
				var r: Dictionary = Game.data.map3d_houses[type]
				if String(r["role"]) == role and _group_allows(group, String(r["min_group"])):
					found = true
			assert_true(found, group + " can be given a " + role)


func test_the_tuning_keys_exist() -> void:
	for k: String in BAKE_KEYS:
		assert_true(Game.data.map3d_bake.has(k), "map3d_bake.csv has " + k)
	for k: String in BAL_KEYS:
		assert_true(Game.data.balance.has(k), "balance.csv has " + k)
	for tier: String in Game.data.graphics_quality:
		assert_true(Game.data.graphics_quality[tier].has("house_budget"),
			tier + " has a house_budget")


func test_the_buffer_ring_is_not_empty() -> void:
	# the whole point of §4: houses stop well inside the built ground
	var ratio: float = Game.data.map3d_bake["house_radius_ratio"]
	assert_lt(ratio, 0.85, "houses stop well inside the footprint")
	assert_gt(ratio, 0.3, "the cluster is not a dot in the middle of bare earth")


func _group_allows(group: String, min_group: String) -> bool:
	var order := GROUPS.duplicate()
	order.reverse()   # village .. capital, smallest first
	return order.find(group) >= order.find(min_group)
