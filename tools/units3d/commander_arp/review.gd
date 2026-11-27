extends SceneTree
## Look check of the INSTALLED commander (scenes/models/units/commander.tscn) in a real Godot
## window, under the map's own environment and sun: one shot per clip with four figures abreast
## at four phases of it, each under another realm's flag (Map3DCommanderFigure.set_flag), the
## installed cavalry beside the STANDBY row for scale and metal, and side-on shots of two
## standing figures: the cloth's two faces in the sun, then seen from behind the sun. Never --headless (no 3D is rendered there):
##
##   Godot --path . --resolution 2560x1440 -s tools/units3d/commander_arp/review.gd -- --out DIR [--backlight F]
##
## Writes DIR/<CLIP>.png, banner_front.png, banner_back.png, banner_shade.png. --backlight brackets the cloth's
## backlight (light through the sheet, 0 off .. 1) for the shots only; the kept value is the scene's.

const CLIPS: Array[String] = ["MARCH", "MARCH_WALK", "STANDBY", "COMMAND"]
const PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
const GAP := 3.6  ## metres between the figures of a row
const TURN := 125.0  ## degrees: three-quarter on, as the map stands a mounted piece (army_art.csv stand_deg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[args.find("--out") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var cam := _stage(world)
	var flags: Array = (load("res://assets/2D/flags/realms/national_flags.tres") as ArtTable).art.values()
	var scene := load(Map3DCommanderFigure.SCENE) as PackedScene
	var row := Node3D.new()
	world.add_child(row)
	var figs: Array[Node3D] = []
	for i in PHASES.size():
		var fig := scene.instantiate() as Node3D
		fig.position.x = (i - 1.5) * GAP
		fig.rotation.y = deg_to_rad(TURN)  # the installed figure faces -Z
		row.add_child(fig)
		figs.append(fig)
	var knight := (load("res://scenes/models/units/cavalry.tscn") as PackedScene).instantiate() as Node3D
	knight.position.x = 2.5 * GAP
	knight.rotation.y = deg_to_rad(TURN)
	knight.visible = false
	row.add_child(knight)
	await process_frame  # an AnimationPlayer resolves its root only once in the tree
	if args.has("--backlight"):
		var mesh: MeshInstance3D = Map3DUnits.meshes(figs[0])[0]
		var cloth := mesh.get_surface_override_material(Map3DCommanderFigure.cloth_surface(mesh)) as BaseMaterial3D
		var light := float(args[args.find("--backlight") + 1])
		cloth.backlight_enabled = light > 0.0
		cloth.backlight = Color(light, light, light)
	for c in CLIPS.size():
		for i in figs.size():
			Map3DCommanderFigure.set_flag(figs[i], flags[(c + i) % flags.size()] as Texture2D)
			_pose(figs[i], CLIPS[c], PHASES[i])
		knight.visible = CLIPS[c] == "STANDBY"
		if knight.visible:
			_pose(knight, "STANDBY", 0.0)
		cam.fov = 30.0
		cam.position = Vector3(6.5 if knight.visible else 4.0, 4.2, 21.0 if knight.visible else 17.5)
		cam.look_at(Vector3(1.8 if knight.visible else 0.0, 2.1, 0.0))
		await _shoot("%s/%s.png" % [out, CLIPS[c]])
	knight.visible = false
	for i in figs.size():
		figs[i].visible = i == 1 or i == 2  # a pale flag and a dark one with a charge that has a left and a right
	for shot: Array in [["front", 1.0, 1.0], ["back", -1.0, 1.0], ["shade", 1.0, -1.0]]:
		for i in [1, 2]:
			figs[i].rotation.y = deg_to_rad(90.0 * float(shot[1]))  # side on: the cloth's one face, then its other
			_pose(figs[i], "STANDBY", 0.0)
		cam.fov = 24.0
		cam.position = Vector3(0.0, 3.2, 16.0 * float(shot[2]))  # "shade": from behind the sun, the unlit faces
		cam.look_at(Vector3(0.0, 2.6, 0.0))
		await _shoot("%s/banner_%s.png" % [out, shot[0]])
	quit()


func _pose(fig: Node3D, clip: String, phase: float) -> void:
	var anim := Map3DUnits.find_anim(fig)
	anim.speed_scale = 0.0
	anim.play(clip)
	anim.seek(phase * anim.current_animation_length, true)


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


## Grass-dark ground, the 3D map's environment and its sun's angle, energy and colour.
func _stage(world: Node3D) -> Camera3D:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.20)
	mat.roughness = 1.0
	ground.material_override = mat
	world.add_child(ground)
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/map3d/world_environment.tres")
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.55
	sun.light_specular = 0.5
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.directional_shadow_max_distance = 80.0
	world.add_child(sun)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	return cam
