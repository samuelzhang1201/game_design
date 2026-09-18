@tool
extends RefCounted
## SPIKE (2026-09-17, throwaway): plant Poly Haven trees on the Terrain3D
## landscape as texture cards. Run AFTER build_terrain.gd's import_into, on the
## same open scene's Terrain3D:
##   plant(<its Terrain3D>) and save the scene
## The cards are render_impostors.py's side views (trees/trees.json holds
## each card's size in metres). A candidate every SPACING m, jittered, becomes
## a tree with the probability of its pixel's forest share; the species comes
## from which forest biome it is. Seeded, so a re-run plants the same wood.

const MAP := "beria"
const ROOT := "res://assets/map3d/beria"
const TREES := "res://assets/map3d/trees"
const SEED := 20260917
const SPACING := 3.5            # m between candidates
const SEA_LEVEL := 20.0
const MIN_HEIGHT_M := 3.0       # nothing on the beach
const MAX_SLOPE_NORMAL_Y := 0.7 # steeper ground (normal.y below this) stays bare
const OPEN_LAND_CHANCE := 0.02  # lone trees on grassland and savanna
const CLUSTER_FREQ := 0.012     # groves: noise per m...
const CLUSTER_GAIN := 1.1       # ...how far it swings a pixel's chance

# [card key, species, scale on the rendered size, relative weight in its species]
const CARDS := [
	["tree_small_02", "broadleaf", 2.5, 1.0],
	["island_tree_02", "broadleaf", 2.5, 0.7],
	["fir_tree_01_0", "conifer", 1.0, 1.0],
	["fir_tree_01_1", "conifer", 1.0, 1.0],
	["fir_tree_01_2", "conifer", 1.0, 0.25],
]

# Biome id → [forest density 0..1, conifer share of it].
const FOREST := {
	3: [0.0, 0.0],   # savanna: open land
	4: [0.0, 0.0],   # grassland: open land
	5: [0.45, 0.0],  # tropical seasonal forest
	6: [0.8, 0.1],   # temperate deciduous
	7: [0.9, 0.0],   # tropical rainforest
	8: [0.85, 0.6],  # temperate rainforest
	9: [0.75, 0.95], # taiga
	12: [0.15, 0.2], # wetland
	13: [0.25, 0.4], # hill band
	14: [0.08, 0.9], # mountain band
}


static func plant(terrain: Terrain3D) -> String:
	var began := Time.get_ticks_msec()
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(TREES + "/trees.json"))
	var dir := "res://assets/maps/%s" % MAP
	var weights: Array[Image] = []
	for k in 4:
		var wi := Image.load_from_file(ProjectSettings.globalize_path(dir + "/world_biome_weights_%d.png" % k))
		wi.convert(Image.FORMAT_RGBA8)
		weights.append(wi)
	var ww := weights[0].get_width()
	var wh := weights[0].get_height()
	var map_w := 2560.0
	var map_h := 929.0
	# build_terrain.gd centres the pack: px (0,0) sits at this world corner.
	var origin := Vector2(-1280.0, -465.0)

	# --- mesh assets: one texture card per rendered tree ---------------------------
	var meshes: Array[Terrain3DMeshAsset] = []
	var species_cards := {"broadleaf": [], "conifer": []}
	for c in CARDS.size():
		var spec: Array = CARDS[c]
		var info: Dictionary = manifest[spec[0]]
		var size := Vector2(info["width_m"], info["height_m"]) * float(spec[2])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("%s/%s.png" % [TREES, spec[0]])
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var ma := Terrain3DMeshAsset.new()
		ma.name = spec[0]
		ma.generated_type = 1  # texture card
		ma.generated_faces = 2
		ma.generated_size = size
		ma.height_offset = size.y * 0.5
		ma.material_override = mat
		ma.lod0_range = 3000.0
		ma.last_lod = 0
		ma.last_shadow_lod = 0
		ma.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		meshes.append(ma)
		species_cards[spec[1]].append(c)
	terrain.assets.mesh_list = meshes
	ResourceSaver.save(terrain.assets, ROOT + "/terrain_assets.tres")

	# --- candidates ----------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var per_mesh: Array = []
	for c in CARDS.size():
		per_mesh.append({"xforms": [], "colors": PackedColorArray()})
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = CLUSTER_FREQ
	noise.fractal_octaves = 3
	var planted := 0
	var y := SPACING * 0.5
	while y < map_h:
		var x := SPACING * 0.5
		while x < map_w:
			var px := Vector2(x + rng.randf_range(-0.45, 0.45) * SPACING,
				y + rng.randf_range(-0.45, 0.45) * SPACING)
			var roll := rng.randf()
			var pick := rng.randf()
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.75, 1.25)
			var tint := rng.randf_range(0.62, 0.85)
			x += SPACING
			var world := Vector3(origin.x + px.x, 0.0, origin.y + px.y)
			var h := terrain.data.get_height(world)
			if is_nan(h) or h < MIN_HEIGHT_M:
				continue
			if terrain.data.get_normal(world).y < MAX_SLOPE_NORMAL_Y:
				continue
			var wx := clampi(int(px.x * ww / map_w), 0, ww - 1)
			var wy := clampi(int(px.y * wh / map_h), 0, wh - 1)
			var total := 0.0
			var density := 0.0
			var conifer := 0.0
			var open := 0.0
			for k in 4:
				var col := weights[k].get_pixel(wx, wy)
				var ch := [col.r8, col.g8, col.b8, col.a8]
				for c in 4:
					var v: float = ch[c]
					if v <= 0.0:
						continue
					var id := k * 4 + c + 1
					total += v
					if id == 3 or id == 4:
						open += v
					if FOREST.has(id):
						density += v * FOREST[id][0]
						conifer += v * FOREST[id][0] * FOREST[id][1]
			if total <= 0.0:
				continue
			var grove := clampf(1.0 + CLUSTER_GAIN * noise.get_noise_2d(px.x, px.y) * 1.6, 0.0, 2.0)
			var chance := density / total * grove + OPEN_LAND_CHANCE * open / total
			if roll >= chance:
				continue
			var species := "conifer" if density > 0.0 and pick < conifer / density else "broadleaf"
			var card := _weighted(species_cards[species], rng.randf())
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			per_mesh[card]["xforms"].append(Transform3D(basis, Vector3(world.x, h, world.z)))
			var colors: PackedColorArray = per_mesh[card]["colors"]
			colors.append(Color(tint * 0.95, tint, tint * 0.85, 1.0))
			per_mesh[card]["colors"] = colors
			planted += 1
		y += SPACING

	for c in CARDS.size():
		terrain.instancer.clear_by_mesh(c)
		var xf: Array[Transform3D] = []
		xf.assign(per_mesh[c]["xforms"])
		if xf.is_empty():
			continue
		terrain.instancer.add_transforms(c, xf, per_mesh[c]["colors"], true)
	terrain.data.save_directory(ROOT + "/terrain")
	var counts := []
	for c in CARDS.size():
		counts.append("%s=%d" % [CARDS[c][0], per_mesh[c]["xforms"].size()])
	return "planted %d trees in %d ms: %s" % [planted, Time.get_ticks_msec() - began, ", ".join(counts)]


static func _weighted(cards: Array, r: float) -> int:
	var total := 0.0
	for c: int in cards:
		total += float(CARDS[c][3])
	var acc := 0.0
	for c: int in cards:
		acc += float(CARDS[c][3]) / total
		if r <= acc:
			return c
	return cards[-1]
