extends SceneTree
## Build assets/map3d/<map>/world.tscn headless — no editor step.
##   python3 tools/map3d/bake_world.py
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/build_world.gd
## build_terrain.gd does the work: build_scene() packs the scene around an
## empty Terrain3D; its data only initialises inside a tree, so the scene is
## instanced under root, import_into() fills and saves the regions, and the
## filled scene is packed over the first one.

const BuildTerrain := preload("res://tools/map3d/build_terrain.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print(BuildTerrain.build_scene())
	var path := BuildTerrain.ROOT + "/world.tscn"
	var scene: Node = (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var terrain := scene.get_node("Terrain3D") as Terrain3D
	print(BuildTerrain.import_into(terrain))
	var packed := PackedScene.new()
	var err := packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("saved %s err=%d" % [path, err])
	scene.queue_free()
	await process_frame
	quit(0 if err == OK else 1)
