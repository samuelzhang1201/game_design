class_name Map3DWorldLoader
extends RefCounted
## Opens a pack's BUILT world (tools/map3d) for the view (spec 2026-09-20
## §1, Task 14). The build is DATA — terrain, meta, rivers, fields; the sun,
## the sky, the sea and the framing shots belong to the view's authored scene
## (and to tools/map3d/shoot.gd). A build made before 2026-09-20 still carries
## its own Sun, Environment, Sea and cameras: they are removed on load, so a
## world never holds two suns or two skies.

## The build's format: 2 is data only (build_terrain.gd writes it into the
## `map3d_world` meta); an older build has none and is stripped on load.
const FORMAT_VERSION := 2
## What a build before format 2 put beside the terrain.
const OLD_BUILD_NODES := ["Sun", "Environment", "Sea", "Camera3D", "CameraMid", "CameraNear"]


## The world at `scene_path`, stripped and with its own terrain material, or
## null when the file is missing or is not a built world (no `map3d_world` meta).
static func instance(scene_path: String) -> Node3D:
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	var w: Node3D = packed.instantiate() as Node3D if packed != null else null
	if w == null or not w.has_meta("map3d_world"):
		if w != null:
			w.free()
		return null
	strip_old_build(w)
	own_terrain_material(w)
	return w


## Removes an old build's sun, sky, sea and framing cameras (none in format 2).
static func strip_old_build(world: Node3D) -> void:
	for node_name: String in OLD_BUILD_NODES:
		var n := world.get_node_or_null(node_name)
		if n != null:
			world.remove_child(n)
			n.free()


## Each instance gets its OWN terrain material: the loaded one is shared, and
## the first view's teardown left the second's ground untinted (owner 2026-09-19).
static func own_terrain_material(world: Node3D) -> void:
	for t in world.find_children("*", "Terrain3D", true, false):
		var m: Resource = t.get("material")
		if m != null:
			t.set("material", m.duplicate(true))
