extends SceneTree
## The model SCENE of each type tripo_harbour.py exported (the walls, the
## piers, the harbour ships): scenes/models/<category>/<type>.tscn, an
## inherited scene of assets/3D/<category>/<type>/<type>.glb whose surfaces
## wear house_surface.gdshader materials — what the editor's New Inherited
## Scene and the inspector make. A type with no scene yet starts from the
## same three lines New Inherited Scene writes (Godot does not let a script
## pack a fresh inherited root); the scene is then loaded, its materials set
## and saved back by the engine. Registers each scene in
## GameArt.HOUSE_MODELS. Run after a fresh import of the .glb files:
##
##   Godot --path . -s res://tools/map3d/tripo_harbour/make_scenes.gd [-- --only a,b]
##
## NOT --headless: the dummy renderer leaves the shader's uniform defaults null.
## A scene already there keeps its UID (the art table's reference). Every
## value set here is a starting point for the editor: the bob of a ship, a
## surface's roughness, are tuned in its scene afterwards.

const SHADER := preload("res://scripts/map3d/house_surface.gdshader")
const NOTE := "One house type of the 3D map. Map3DLayerHouses draws every house of this type as ONE MultiMesh of this mesh with these surface materials (house_surface.gdshader, edited here: texture, roughness, role 1 wall / 2 tile roof / 0 untinted). The Houses node adds its colour variants and the weather to its own copies at run time; its sizes are data/map3d_houses.csv."
const SHIP_NOTE := " A SHIP: bob_on rocks it on the swell about its origin, the waterline, which the layer floats on the sea (role ship)."

## type: [category, kind, swell (roll deg, pitch deg, heave m, period s) for a ship]
const TYPES := {
	"wall": ["buildings", "fort"],
	"wall_tower": ["buildings", "fort"],
	"wall_gate": ["buildings", "fort"],
	"pier": ["buildings", "pier"],
	"pier_cliff": ["buildings", "pier"],
	"pier_stair": ["buildings", "pier"],
	"fishing_boat": ["ships", "ship", [4.0, 1.6, 0.25, 5.0]],
	"cog": ["ships", "ship", [2.5, 1.0, 0.3, 7.0]],
	"longship": ["ships", "ship", [3.0, 1.2, 0.3, 6.0]],
	"carrack": ["ships", "ship", [1.8, 0.7, 0.4, 9.0]],
}


## The warm lift of a type's stone or rock, multiplied into its colour.
const WARM := {
	"wall": Color(1.1, 1.02, 0.88), "wall_tower": Color(1.1, 1.02, 0.88), "wall_gate": Color(1.1, 1.02, 0.88),
	"pier_cliff": Color(1.16, 1.04, 0.86), "pier_stair": Color(1.16, 1.04, 0.86),
}


func _init() -> void:
	var table: ArtTable = load(GameArt.HOUSE_MODELS)
	# `-- --only a,b` dresses just those types (a re-save of the others churns them)
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--only")
	if at >= 0 and at + 1 < args.size():
		only = args[at + 1].split(",")
	for type: String in TYPES:
		if not only.is_empty() and not only.has(type):
			continue
		var spec: Array = TYPES[type]
		var path := "res://scenes/models/%s/%s.tscn" % [spec[0], type]
		var glb := "res://assets/3D/%s/%s/%s.glb" % [spec[0], type, type]
		if not FileAccess.file_exists(path):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_glb"]\n\n[node name="%s" instance=ExtResource("1_glb")]\n' % [glb, type.to_pascal_case()])
			f.close()
		var uid := ResourceLoader.get_resource_uid(path)
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id()
		var base: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var root := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		if not _dress(root, type, spec):
			root.free()
			continue
		for dep: String in [glb, SHADER.resource_path, "res://assets/3D/%s/%s/%s_%s_atlas.jpg" % [spec[0], type, type, type]]:
			_register(dep)
		var packed := PackedScene.new()
		packed.pack(root)
		root.free()
		var err := ResourceSaver.save(packed, path)
		ResourceSaver.set_uid(path, uid)   # a fresh PackedScene saves without one
		print("%s -> %s (%s)" % [type, path, error_string(err)])
		table.art[type] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	for r: Resource in table.art.values():
		_register(r.resource_path)
	_register(table.get_script().resource_path)
	var table_uid := ResourceLoader.get_resource_uid(GameArt.HOUSE_MODELS)
	print("house_models.tres: ", error_string(ResourceSaver.save(table, GameArt.HOUSE_MODELS)))
	ResourceSaver.set_uid(GameArt.HOUSE_MODELS, table_uid)
	quit()


## Every surface of the scene's mesh its house_surface material; false when
## the type's atlas is missing.
func _dress(root: Node, type: String, spec: Array) -> bool:
	var atlas_path := "res://assets/3D/%s/%s/%s_%s_atlas.jpg" % [spec[0], type, type, type]
	if not ResourceLoader.exists(atlas_path):
		push_error("%s: no atlas at %s" % [type, atlas_path])
		return false
	var atlas: Texture2D = load(atlas_path)
	root.editor_description = NOTE + (SHIP_NOTE if spec[1] == "ship" else "")
	var mi := Map3DHouses.first_mesh_instance(root)
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		for u: Dictionary in SHADER.get_shader_uniform_list():   # the defaults written out, as the inspector does
			var v: Variant = RenderingServer.shader_get_parameter_default(SHADER.get_rid(), u["name"])
			if v != null:
				mat.set_shader_parameter(u["name"], v)
		mat.resource_name = src.resource_name if src != null else type
		mat.set_shader_parameter("albedo_tex", atlas)
		mat.set_shader_parameter("roughness", 0.9)
		mat.set_shader_parameter("role", 0)   # stone, slate, timber, a hull: none takes the town's tints
		# a fortification's stone (its second surface) carries the grime in its vertex colour
		mat.set_shader_parameter("use_vertex_color", spec[1] == "fort" and i == 1)
		if spec[1] == "ship":
			var swell: Array = spec[2]
			mat.set_shader_parameter("bob_on", 1.0)
			mat.set_shader_parameter("bob_roll_deg", swell[0])
			mat.set_shader_parameter("bob_pitch_deg", swell[1])
			mat.set_shader_parameter("bob_heave_m", swell[2])
			mat.set_shader_parameter("bob_period_s", swell[3])
		# Rock and stone sit WARM beside the golden grass (taste.md): Tripo's
		# blue-grey crag and curtain read pasted on and too dark (critic 2026-10-04)
		if WARM.has(type) and not (spec[1] == "fort" and i == 0):   # never the slate
			mat.set_shader_parameter("albedo_color", WARM[type])
		mi.set_surface_override_material(i, mat)
	return true


## A script run (-s) does not load the editor's UID cache, so the saver
## writes every reference by path alone; each one is put in the cache from
## its own file (header or .import) first, so the references keep their UIDs.
func _register(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		return
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)
