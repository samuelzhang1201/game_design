extends SceneTree
## SPIKE: render the Terrain3D scene through one of its cameras to a PNG.
##   Godot --path . -s tools/map3d/shoot.gd -- --camera Camera3D --out /tmp/x.png [--map ID]

func _init() -> void:
	var cam_name := "Camera3D"
	var out := "user://terrain3d_shot.png"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--camera":
			cam_name = args[i + 1]
		elif args[i] == "--out":
			out = args[i + 1]
	var scene: Node = load(_scene_path()).instantiate()
	root.add_child(scene)
	var cam: Camera3D = scene.get_node(cam_name)
	cam.current = true
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()


## The built scene of --map ID, else data/maps.csv's default pack.
func _scene_path() -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--map")
	var id := args[at + 1] if at >= 0 and at + 1 < args.size() else DataRepository.default_pack_id()
	return "res://assets/map3d/%s/world.tscn" % id
