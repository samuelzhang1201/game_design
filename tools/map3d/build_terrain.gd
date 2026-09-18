@tool
extends RefCounted
## SPIKE (2026-09-18, throwaway): the beria pack as a Terrain3D landscape at
## CAMPAIGN scale (owner: 50 m per pack px, a 128 x 46 km world). Nothing in
## the game reads this.
##   python3 tools/map3d/bake_world.py      heights + control → bake/
## then from the editor (gdai execute_editor_script):
##   build_scene(), open the scene, import_into(<its Terrain3D>, <scene root>), save
## (load the source into a fresh GDScript: the editor caches the open file).
## The ground wears the owner's Poly Haven sets (textures/, packed by
## pack_textures.py) plus the Terrain3D demo's Cliff. Settlements are
## placeholder discs sized by tier, to judge the spacing — no trees yet.
## Constants live here, not in balance.csv, because this is a probe.

const MAP := "beria"
const ROOT := "res://assets/map3d/beria"
const TEX := "res://assets/map3d/textures"
const BAKE := "res://assets/map3d/beria/bake"
const SEA_Y := 5.0               # m: the water plane, just over the waterline
const PLAYER_REALM := "kelvarn"  # realm_bindings.csv player_realm — the near camera frames its capital

# [key, metres per tile repeat, detiling rotation]; order is bake_world.py's
# texture ids. No per-texture tint: bake_world.py's colour map carries every
# colour, so the far view and the near view agree.
const TEXTURES := [
	["cliff", 320.0, 0.1],
	["leafy_grass", 160.0, 0.16],
	["dry_decay_leaves", 160.0, 0.2],
	["dirt_floor", 180.0, 0.16],
	["rocky_trail", 240.0, 0.12],
	["excavated_soil_wall", 240.0, 0.1],
	["sand_03", 120.0, 0.2],
	["leafy_grass", 200.0, 0.22],
]

# Settlement placeholder: diameter in metres and colour per burgs.csv group.
const TIERS := {
	"capital": [1200.0, Color("#C8102E")],
	"city": [700.0, Color("#E07B00")],
	"fort": [350.0, Color("#6B4E9B")],
	"town": [350.0, Color("#F2C300")],
	"village": [180.0, Color("#F5F5F0")],
}
const DISC_HEIGHT := 60.0

# Terrain3D material: demo/Demo.tscn's parameters, every one of them — a
# fresh Terrain3DMaterial saved the rest as null and drew flat grey.
const SHADER_PARAMS := {
	"bias_distance": 512.0,
	"blend_sharpness": 0.5,
	"depth_blur": 0.0,
	"dual_scale_far": 170.0,
	"dual_scale_near": 100.0,
	"dual_scale_reduction": 0.3,
	"dual_scale_texture": 0,
	"enable_macro_variation": true,
	"enable_projection": true,
	"flat_terrain_normals": false,
	"macro_variation1": Color(0.9, 0.92, 0.95, 1),
	"macro_variation2": Color(0.95, 0.92, 0.85, 1),
	"macro_variation_slope": 0.333,
	"mipmap_bias": 1.0,
	"noise1_angle": 0.1,
	"noise1_offset": Vector2(0.5, 0.5),
	"noise1_scale": 0.0004,
	"noise2_scale": 0.00076,
	"projection_threshold": 0.87,
	"tri_scale_reduction": 0.3,
	"auto_base_texture": 0,
	"auto_overlay_texture": 1,
	"auto_slope": 0.45,
	"auto_height_reduction": 0.05,
}


static func world_info() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BAKE + "/world.json"))


## World XZ of a pack pixel.
static func pack_to_world(world: Dictionary, px: Vector2) -> Vector2:
	var o: Array = world["pack_origin"]
	return Vector2(o[0], o[1]) + px * float(world["m_per_px"])


## Step 2, on the Terrain3D node of the OPEN scene (its data only exists in
## the tree): assets, the baked maps, the settlement discs; saves regions.
static func import_into(terrain: Terrain3D, scene_root: Node) -> String:
	var began := Time.get_ticks_msec()
	var world := world_info()
	var padded: Array = world["padded"]
	var fw := int(padded[0])
	var fh := int(padded[1])

	var tex_list: Array[Terrain3DTextureAsset] = []
	for t in TEXTURES.size():
		var spec: Array = TEXTURES[t]
		var ta := Terrain3DTextureAsset.new()
		ta.name = spec[0]
		ta.id = t
		ta.albedo_texture = load("%s/%s_alb_ht.png" % [TEX, spec[0]])
		ta.normal_texture = load("%s/%s_nrm_rgh.png" % [TEX, spec[0]])
		ta.normal_depth = 1.0
		ta.ao_strength = 1.5
		ta.uv_scale = 1.0 / float(spec[1])
		ta.detiling_rotation = spec[2]
		tex_list.append(ta)
	var assets := Terrain3DAssets.new()
	assets.texture_list = tex_list
	ResourceSaver.save(assets, ROOT + "/terrain_assets.tres")
	terrain.assets = load(ROOT + "/terrain_assets.tres")
	terrain.material.auto_shader = false
	for key: String in SHADER_PARAMS:
		terrain.material.set_shader_param(key, SHADER_PARAMS[key])

	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = Image.create_from_data(fw, fh, false, Image.FORMAT_RF,
		FileAccess.get_file_as_bytes(BAKE + "/height.r32"))
	images[Terrain3DRegion.TYPE_CONTROL] = Image.create_from_data(fw, fh, false, Image.FORMAT_RF,
		FileAccess.get_file_as_bytes(BAKE + "/control.r32"))
	images[Terrain3DRegion.TYPE_COLOR] = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8,
		FileAccess.get_file_as_bytes(BAKE + "/color.rgba8"))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/terrain"))
	for f in DirAccess.get_files_at(ROOT + "/terrain"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT + "/terrain/" + f))
	terrain.vertex_spacing = float(world["vertex_m"])
	if terrain.region_size != int(world["region_size"]):
		terrain.change_region_size(int(world["region_size"]))
	terrain.data_directory = ROOT + "/terrain"
	for region in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
	var corner: Array = world["import_corner"]
	terrain.data.import_images(images, Vector3(corner[0], 0.0, corner[1]), 0.0, 1.0)
	terrain.data.save_directory(ROOT + "/terrain")

	var discs := _place_settlements(terrain, scene_root, world)
	return "imported %dx%d vertices at %.0f m in %d ms, %d regions, %s" % [
		fw, fh, terrain.vertex_spacing, Time.get_ticks_msec() - began,
		terrain.data.get_region_count(), discs]


## One MultiMesh of flat discs per tier, each disc on the ground under its burg.
static func _place_settlements(terrain: Terrain3D, scene_root: Node, world: Dictionary) -> String:
	var old := scene_root.get_node_or_null("Settlements")
	if old:
		scene_root.remove_child(old)
		old.free()
	var holder := Node3D.new()
	holder.name = "Settlements"
	scene_root.add_child(holder)
	holder.owner = scene_root
	var by_tier := {}
	var f := FileAccess.open("res://data/maps/%s/political/burgs.csv" % MAP, FileAccess.READ)
	var header := f.get_csv_line()
	var col := {}
	for i in header.size():
		col[header[i]] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < header.size():
			continue
		var tier: String = row[col["group"]]
		if not TIERS.has(tier):
			continue
		var xz := pack_to_world(world, Vector2(float(row[col["x"]]), float(row[col["y"]])))
		var y := terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
		if is_nan(y):
			continue
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(Vector3(xz.x, maxf(y, SEA_Y), xz.y))
	var counts := []
	for tier: String in by_tier:
		var spec: Array = TIERS[tier]
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(spec[0]) * 0.5
		mesh.bottom_radius = float(spec[0]) * 0.5
		mesh.height = DISC_HEIGHT
		mesh.radial_segments = 32
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[1]
		mat.roughness = 0.8
		mesh.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var pts: Array = by_tier[tier]
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = tier.capitalize()
		mmi.multimesh = mm
		holder.add_child(mmi)
		mmi.owner = scene_root
		counts.append("%s=%d" % [tier, pts.size()])
	return "settlements " + ", ".join(counts)


## World XZ of the player realm's capital, for the near cameras.
static func capital_xz(world: Dictionary) -> Vector2:
	var capital := ""
	var f := FileAccess.open("res://data/maps/%s/political/kingdoms.csv" % MAP, FileAccess.READ)
	var header := f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= header.size() and row[header.find("kingdom_code")] == PLAYER_REALM:
			capital = row[header.find("capital_burg")]
	f = FileAccess.open("res://data/maps/%s/political/burgs.csv" % MAP, FileAccess.READ)
	header = f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= header.size() and row[header.find("burg_code")] == capital:
			return pack_to_world(world, Vector2(float(row[header.find("x")]), float(row[header.find("y")])))
	return Vector2.ZERO


## Step 1: the scene around the terrain (no data yet).
static func build_scene() -> String:
	var world := world_info()
	var span := Vector2(world["pack_px"][0], world["pack_px"][1]) * float(world["m_per_px"])
	var root := Node3D.new()
	root.name = "BeriaTerrain"
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = int(world["region_size"])
	terrain.vertex_spacing = float(world["vertex_m"])
	var mat := Terrain3DMaterial.new()
	mat.show_checkered = false
	# NONE: under Compatibility on macOS, FLAT/NOISE fetch height-map layer -1
	# outside the regions, which Apple GL clamps to layer 0 — the whole map
	# repeated to the horizon (2026-09-17).
	mat.world_background = 0
	mat.auto_shader = false
	root.add_child(terrain)
	terrain.owner = root
	terrain.material = mat

	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = span * 12.0  # its edge must sit past the far camera's horizon
	sea.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#1F5570")
	sm.albedo_color.a = 0.96  # at 0.8 the padded regions' sea floor showed as a dark rectangle
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.55
	sm.metallic_specular = 0.2
	sm.disable_receive_shadows = true
	sea.material_override = sm
	sea.position = Vector3(0, SEA_Y, 0)
	_add(root, sea)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, 45, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60000.0
	_add(root, sun)

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("#2F5878")
	psm.sky_horizon_color = Color("#A9BFCC")
	psm.ground_horizon_color = Color("#A9BFCC")
	psm.ground_bottom_color = Color("#2E4A5C")
	psm.sun_angle_max = 1.0
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.35
	e.ambient_light_sky_contribution = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("#A9BFCC")
	e.fog_density = 0.0000008
	env.environment = e
	_add(root, env)

	# The whole realm, the country round the player's capital, and the capital.
	var capital := capital_xz(world)
	_camera(root, "Camera3D", Vector3(0, 70000, 75000), -45.0, 50.0, 400000.0)
	_camera(root, "CameraMid", Vector3(capital.x, 14000, capital.y + 16000), -40.0, 20.0, 200000.0)
	_camera(root, "CameraNear", Vector3(capital.x, 3000, capital.y + 4200), -35.0, 5.0, 100000.0)

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, ROOT + "/world.tscn")
	root.free()
	return "scene err=%d, capital at %s" % [err, capital]


static func _camera(root: Node, cam_name: String, pos: Vector3, pitch: float, near: float, far: float) -> void:
	var cam := Camera3D.new()
	cam.name = cam_name
	cam.fov = 45.0
	cam.near = near
	cam.far = far
	cam.position = pos
	cam.rotation_degrees = Vector3(pitch, 0, 0)
	_add(root, cam)


static func _add(root: Node, n: Node) -> void:
	root.add_child(n)
	n.owner = root
