extends SceneTree
## Gait review strip for one arm's MARCH (LOCO-CAV-PHASE visual review): the arm's
## shipped scene on a striped ground, walked forward at a constant model speed and
## paced by the REAL Map3DUnitRig.keep_pace (army_art.csv stride_m / phase_map),
## its AnimationPlayer advanced by hand each fixed step. Shoots `--frames` frames
## over one loop of travel from a fixed side camera and prints each hoof's
## worst bone drift over the contract support intervals (SUPPORTS); the frames
## cover one hind-left stance beside a red post at its touchdown point.
## Needs a real window (never --headless):
##   Godot --path . --resolution 1600x1000 -s tools/units3d/march_gait_review.gd -- \
##     --out DIR [--arm cavalry] [--variant map|stride|raw] [--stride 5.9] [--frames 12] [--forward -1]
## --variant map: the row's phase_map; stride: a constant stride (--stride, shipped
## 5.9); raw: march-phase.json's atlas as proposed (airborne travel ~0).

const ATLAS := "res://docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-phase.json"
const HOOVES := ["FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R"]
# cavalry contract support intervals (march-phase.json source_support_constraints)
const SUPPORTS := {"FrontHoof.L": [0.27, 0.58], "FrontHoof.R": [0.45, 0.76],
	"HindHoof.L": [0.0, 0.31], "HindHoof.R": [0.26, 0.57]}
const DT := 1.0 / 240.0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _run() -> void:
	var out := _arg("--out", "")
	var arm := _arg("--arm", "cavalry")
	var variant := _arg("--variant", "map")
	var frames := int(_arg("--frames", "12"))
	var fwd := float(_arg("--forward", "-1"))  # the installed piece faces -Z
	DirAccess.make_dir_recursive_absolute(out)
	var repo := DataRepository.load_all("res://data")
	var art: Dictionary = repo.army_art[arm]
	var knots := Map3DMarchPhase.of_art(art)
	if variant == "raw":
		knots = PackedFloat64Array()
		for k: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(ATLAS))["atlas"]["knots"]:
			knots.append(float(k["phase_num"]) / float(k["phase_den"]))
			knots.append(float(k["distance_num"]) / float(k["distance_den"]))
	elif variant == "stride":
		knots = PackedFloat64Array()
	var stride := float(_arg("--stride", String(art.get("stride_m", "1"))))
	var world := Node3D.new()
	root.add_child(world)
	_stage(world)
	var fig := (load("res://scenes/models/units/%s.tscn" % arm) as PackedScene).instantiate() as Node3D
	world.add_child(fig)
	await process_frame  # the AnimationPlayer resolves its root only once in the tree
	var anim := Map3DUnits.find_anim(fig)
	var clip := Map3DUnits.clip_named(anim, "MARCH")
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play(clip)
	anim.seek(0.0, true)
	var clip_s := anim.current_animation_length
	var skel := _skeleton(fig)
	var loop := Map3DMarchPhase.loop_m(knots) if not knots.is_empty() else stride
	var speed := Map3DMarchPhase.loop_m(Map3DMarchPhase.of_art(art)) / clip_s if \
		not Map3DMarchPhase.of_art(art).is_empty() else stride / clip_s  # model m/s, one map loop per clip
	var day_s := repo.bal("time_day_seconds")
	var day := {"from": Vector2.ZERO, "to": Vector2(speed * day_s, 0.0), "s0": 0.0}
	var piece := {"node": fig, "anims": [anim], "clip_s": clip_s, "stride_m": stride,
		"exact_pace": true, "phase_map": knots}
	# walk two loops: one to settle, one shot and measured
	var travel := 2.0 * loop  # two of this variant's own loops
	var steps := int(ceil(travel / (speed * DT)))
	var anchor := {}
	var worst := {}
	var shot := 0
	for i in steps:
		Map3DUnitRig.keep_pace(repo, piece, day, 0.5, 1, "R", DT)
		anim.advance(DT)
		skel.force_update_all_bone_transforms()
		fig.position.z += fwd * speed * DT
		var p := fposmod(anim.current_animation_position / clip_s, 1.0)
		for hoof: String in HOOVES:
			var span: Array = SUPPORTS[hoof]
			var at := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(hoof))
			if p >= float(span[0]) and p <= float(span[1]):
				if not anchor.has(hoof):
					anchor[hoof] = at.origin
				var d := Vector2(at.origin.x - anchor[hoof].x, at.origin.z - anchor[hoof].z).length()
				worst[hoof] = maxf(float(worst.get(hoof, 0.0)), d) if i > steps / 2 else 0.0
			else:
				anchor.erase(hoof)
		# shots: one hind-left stance of the measured loop, every 4 steps, beside a red
		# post planted where that hoof touched down
		if i > steps / 2 and anchor.has("HindHoof.L") and shot < 4 * frames and i % 4 == 0:
			var post := world.get_node_or_null("Post") as MeshInstance3D
			if post == null:
				post = _post(world)
				post.position = Vector3(anchor["HindHoof.L"].x + 0.12, 0.15, anchor["HindHoof.L"].z)
				(world.get_node("Cam") as Camera3D).position.z = anchor["HindHoof.L"].z
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%02d.png" % [out, variant, shot])
			shot += 1
	print("GAIT ", variant, " loop_m ", loop, " clip_s ", clip_s, " model_speed ", speed,
		" worst bone drift per stance (model m) ", worst)
	quit()


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _skeleton(c)
		if s != null:
			return s
	return null


## A sunlit striped ground (a line every 0.1 model m across the travel) and a fixed
## side camera at hoof height looking across the walk.
func _stage(world: Node3D) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for x in 64:
		for y in 64:
			img.set_pixel(x, y, Color(0.18, 0.16, 0.12) if y < 6 else Color(0.62, 0.58, 0.48))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(200.0, 200.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	ground.material_override = mat
	world.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 40.0
	cam.position = Vector3(5.5, 1.1, 0.0)
	cam.rotation_degrees = Vector3(-8.0, 90.0, 0.0)
	world.add_child(cam)
	cam.current = true


## A thin red post marking a touchdown point (review only).
func _post(world: Node3D) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	post.name = "Post"
	var box := BoxMesh.new()
	box.size = Vector3(0.015, 0.3, 0.015)
	post.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.1, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.material_override = mat
	world.add_child(post)
	return post
