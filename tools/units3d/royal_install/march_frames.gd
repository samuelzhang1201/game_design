extends SceneTree
## Real-window frames of the royal MARCH over ground (visual review of LOCO-ROY-MARCH; NEVER --headless).
##   Godot --path . -s res://tools/units3d/royal_install/march_frames.gd -- --out DIR [--frames N]
##       [--stride M] [--yaw DEG] [--near 1]
## The royal figure plays MARCH from phase 0 over one loop and travels `stride` model metres (default
## army_art.csv's) along its forward axis, as the map carries it, over a plane at the seat (the seated
## plane) striped every 0.25 m across the way it goes; the camera stands still. A planted hoof holds
## its place on the stripes; one that glides moves along them. --near frames the legs only.

const Shell = preload("res://scripts/map3d/map3d_pivot_provider.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args: Dictionary = {"out": "", "frames": "16", "stride": "", "yaw": "90", "near": "0"}
	var user: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, user.size() - 1, 2):
		args[user[i].trim_prefix("--")] = user[i + 1]
	if args.out == "":
		push_error("usage: -- --out DIR")
		quit(2)
		return
	var stride: float = float(args.stride) if args.stride != "" else _stride()
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.46, 0.43, 0.35)
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.2, 0.18, 0.15)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	(plane.mesh as PlaneMesh).size = Vector2(16, 8)
	plane.mesh.surface_set_material(0, ground_mat)
	world.add_child(plane)
	for k: int in range(-32, 33):
		var stripe := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 0.0005, 0.012 if k % 4 else 0.03)
		box.material = stripe_mat
		stripe.mesh = box
		stripe.position = Vector3(0.0, 0.0003, float(k) * 0.25)
		world.add_child(stripe)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.7)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var model: Node3D = load("res://scenes/models/units/royal.tscn").instantiate()
	world.add_child(model)
	var camera := Camera3D.new()
	world.add_child(camera)
	var near: bool = args.near == "1"
	var yaw_view: float = deg_to_rad(float(args.yaw))
	var centre := Vector3(0.0, 0.35 if near else 1.0, -stride * 0.5)
	var distance: float = 3.4 if near else 6.0
	camera.position = centre + Vector3(sin(yaw_view) * distance, 0.25 if near else 0.9, cos(yaw_view) * distance)
	camera.look_at(centre)
	camera.fov = 40
	await process_frame
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var length: float = player.get_animation("MARCH").length
	var frames: int = int(args.frames)
	DirAccess.make_dir_recursive_absolute(args.out)
	for frame: int in frames:
		var phase: float = float(frame) / float(frames)
		model.position = Vector3(0.0, 0.0, -stride * phase)  # the model's forward is -Z
		Shell.seek(player, sk, "MARCH", phase * length)
		for k: int in 3:
			await process_frame
		root.get_texture().get_image().save_png(args.out.path_join("%02d.png" % frame))
	print("MARCH_FRAMES stride=", stride, " -> ", args.out)
	quit(0)


func _stride() -> float:
	var text: String = FileAccess.get_file_as_string("res://data/screens/map3d/army_art.csv")
	for line: String in text.split("\n"):
		if line.begins_with("royal,"):
			return float(line.split(",")[3])
	return 0.0
