extends SceneTree
## Real-window frames of a horsed pivot (visual review of Map3DRoyalPivot, or with --arm cavalry of
## Map3DCavalryLocomotion; NEVER --headless).
##   Godot --path . -s res://tools/units3d/royal_install/pivot_frames.gd -- --out DIR
##       [--arm royal|cavalry] [--turn UDEG] [--frames N] [--mode provider|native] [--plan key=value ...] [--yaw DEG]
## provider: the pivot posed by the arm's provider `solve`. native: the installed PIVOT clip seeked
## (the bake-only playback the provider replaces). Either way the node yaws as BodyMotion does
## (positive turn = RIGHT, decreasing yaw), on a plane at the seat (the seated plane), lit by
## one sun. Frames 0 and N - 1 are the operation's ends; frame -1 is MARCH at the plan's phase.

const PROVIDERS: Dictionary = {"royal": "res://scripts/map3d/map3d_royal_pivot.gd",
	"cavalry": "res://scripts/map3d/map3d_cavalry_locomotion.gd"}
const Shell = preload("res://scripts/map3d/map3d_pivot_provider.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args: Dictionary = {"out": "", "arm": "royal", "turn": "90000000", "frames": "9", "mode": "provider", "yaw": "35"}
	var plan_args: Array[String] = []
	var user: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < user.size():
		var key: String = user[i].trim_prefix("--")
		if key == "plan":
			plan_args.append(user[i + 1])
		else:
			args[key] = user[i + 1]
		i += 2
	var Provider: GDScript = load(PROVIDERS[args.arm])
	var plan: Dictionary = Provider.plan().duplicate()
	for pair: String in plan_args:
		plan[pair.get_slice("=", 0)] = float(pair.get_slice("=", 1))
	Provider._plan = plan
	root.size = Vector2i(1200, 900)
	var world := Node3D.new()
	root.add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.40, 0.33)
	plane.material = mat
	ground.mesh = plane
	world.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.7)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var model: Node3D = load("res://scenes/models/units/%s.tscn" % args.arm).instantiate()
	world.add_child(model)
	var camera := Camera3D.new()
	world.add_child(camera)
	var yaw_view: float = deg_to_rad(float(args.yaw))
	camera.position = Vector3(sin(yaw_view) * 5.2, 1.9, cos(yaw_view) * 5.2)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.fov = 40
	await process_frame
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var turn: int = int(args.turn)
	var clip: String = "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
	var frames: int = int(args.frames)
	DirAccess.make_dir_recursive_absolute(args.out)
	for frame: int in range(-1, frames):
		var phase: float = 0.0 if frame < 0 else float(frame) / float(frames - 1)
		var name: String = "march" if frame < 0 else "%02d" % frame
		model.basis = Basis(Vector3.UP, -deg_to_rad(float(turn) / 1e6) * phase)
		if frame < 0:
			Shell.seek(player, sk, "MARCH", float(plan.march_phase) * player.get_animation("MARCH").length)
		elif args.mode == "native":
			Shell.seek(player, sk, clip, phase * player.get_animation(clip).length)
		else:
			var out: Dictionary = Provider.solve(player, sk, clip, turn, phase)
			if not out.ok:
				push_error("pivot_frames: " + out.reason)
				quit(1)
				return
			Shell.seek(player, sk, clip, 0.0)
			Shell.set_pose(sk, out.pose)
		for k: int in 3:
			await process_frame
		root.get_texture().get_image().save_png(args.out.path_join(name + ".png"))
	print("PIVOT_FRAMES ", args.mode, " ", turn, " -> ", args.out)
	quit(0)
