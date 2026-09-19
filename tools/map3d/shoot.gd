extends SceneTree
## SPIKE: render the built Terrain3D world through one framing to a PNG.
##   Godot --path . -s tools/map3d/shoot.gd -- --camera Camera3D --out /tmp/x.png [--map ID]
## The build is data only (2026-09-20), so this brings its own sun and sky
## (Map3DEnvironment, the view's numbers), the view's sea layer and its own
## framing camera.

const BuildTerrain := preload("res://tools/map3d/build_terrain.gd")

## The build's old framing shots (moved from build_terrain.gd, 2026-09-20):
## name -> [offset from the pivot (m), pitch, near, far]; the pivot is the world
## centre for Camera3D, the player's capital for the other two.
const FRAMES := {
	"Camera3D": [Vector3(0, 70000, 75000), -45.0, 50.0, 400000.0],
	"CameraMid": [Vector3(0, 14000, 16000), -40.0, 20.0, 200000.0],
	"CameraNear": [Vector3(0, 3000, 4200), -35.0, 5.0, 100000.0],
}


func _init() -> void:
	var cam_name := "Camera3D"
	var out := "user://terrain3d_shot.png"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--camera":
			cam_name = args[i + 1]
		elif args[i] == "--out":
			out = args[i + 1]
	var map_id := _map_id()
	BuildTerrain.map_id = map_id
	var repo := DataRepository.load_all("res://data")
	repo.load_map(map_id)
	var scene: Node3D = Map3DWorldLoader.instance(_scene_path(map_id))
	root.add_child(scene)
	scene.add_child(Map3DEnvironment.make_environment(repo))
	scene.add_child(Map3DEnvironment.make_sun(repo))
	scene.add_child(_camera(cam_name))
	var sea := Map3DLayerSea.new()  # the game's own banded sea, as the view dresses it
	sea.name = "Sea"
	scene.add_child(sea)
	sea.build(Map3DContext.new(repo, scene.get_meta("map3d_world"), scene))
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()


## The framing `cam_name` from FRAMES, made current.
func _camera(cam_name: String) -> Camera3D:
	var frame: Array = FRAMES[cam_name]
	var pivot := Vector2.ZERO
	if cam_name != "Camera3D":
		pivot = BuildTerrain.capital_xz(BuildTerrain.world_info())
	var cam := Camera3D.new()
	cam.name = cam_name
	cam.fov = 45.0
	cam.near = frame[2]
	cam.far = frame[3]
	cam.position = (frame[0] as Vector3) + Vector3(pivot.x, 0.0, pivot.y)
	cam.rotation_degrees = Vector3(frame[1], 0.0, 0.0)
	cam.current = true
	return cam


## --map ID, else data/maps.csv's default pack.
func _map_id() -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--map")
	return args[at + 1] if at >= 0 and at + 1 < args.size() else DataRepository.default_pack_id()


func _scene_path(map_id: String) -> String:
	return "res://assets/map3d/%s/world.tscn" % map_id
