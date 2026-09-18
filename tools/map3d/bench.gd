extends SceneTree
## SPIKE: frame time of the Terrain3D scene through CameraMid, one variable off
## at a time. Vsync off, so the numbers are the real cost.
##   GDAI_MCP_SERVER_PORT=3999 Godot --path . -s tools/map3d/bench.gd [-- --map ID --size WxH]

const FRAMES := 120

var scene: Node
var terrain: Terrain3D


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--size")
	if at >= 0:
		var wh := args[at + 1].split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	print("renderer ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_current_rendering_driver_name())
	scene = load(_scene_path()).instantiate()
	root.add_child(scene)
	terrain = scene.get_node("Terrain3D")
	(scene.get_node("CameraMid") as Camera3D).current = true
	for i in 60:
		await process_frame
	await _measure("all on")
	terrain.show_instances = false
	await _measure("trees hidden")
	terrain.show_instances = true
	(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	await _measure("sun shadows off")
	(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	(scene.get_node("Sea") as Node3D).visible = false
	await _measure("sea hidden")
	(scene.get_node("Sea") as Node3D).visible = true
	terrain.visible = false
	await _measure("terrain hidden (trees too)")
	terrain.visible = true
	terrain.show_instances = false
	(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	await _measure("trees hidden + shadows off")
	terrain.show_instances = true
	(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	for m in terrain.assets.get_mesh_count():
		terrain.assets.get_mesh_asset(m).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.instancer.update_mmis(true)
	await _measure("trees cast no shadow")
	(scene.get_node("Sun") as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	await _measure("+ 1 shadow cascade")
	quit()


func _measure(label: String) -> void:
	for i in 20:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var calls := 0
	for i in FRAMES:
		await process_frame
		calls = maxi(calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / FRAMES
	print("%-28s %6.2f ms  (%5.1f fps)  draw calls %d  window %s" % [label, ms, 1000.0 / ms, calls, root.size])


## The built scene of --map ID, else data/maps.csv's default pack.
func _scene_path() -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--map")
	var id := args[at + 1] if at >= 0 and at + 1 < args.size() else DataRepository.default_pack_id()
	return "res://assets/map3d/%s/world.tscn" % id
