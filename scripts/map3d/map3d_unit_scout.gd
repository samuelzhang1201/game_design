class_name Map3DUnitScout
extends RefCounted
## A marching crown unit's SCOUTING FAN (spec 2026-10-14-unit-clearance-and-
## scouting-design (d)): the sector it sweeps (`Sighting.scout_shape`), drawn as
## a polar-grid mesh draped on the ground, a WORLD-space sibling of the pieces
## under the Units node (not a child of the tilted piece), at the piece's drawn
## XZ and turned to its drawn yaw. View-only: it has no owner (never saved) and
## nothing reaches the engine. The look is `unit_scout_fan.tres` + shader; the
## mesh is a (rings+1) x (spokes+1) lattice, UV u = share of the arc -1..1,
## v = share of the radius 0..1, apex at the centre.

const MATERIAL := preload("res://scenes/map3d/materials/unit_scout_fan.tres")
const PREFIX := "Scout_"

## code -> {node, at (world XZ), yaw}: the fans standing.
var _fans: Dictionary = {}


## The fan's radius in world metres: the engine's metres over the pack's px, in built metres.
static func world_radius(repo: DataRepository, meta: Dictionary, r_m: int) -> float:
	return float(r_m) * float(meta.get("m_per_px", 50.0)) / float(ArmySystem.metres_per_pack_px(repo))


## A stable 0..1 sweep phase from the regiment's code (no RNG, no clock).
static func phase_of(code: String) -> float:
	return Map3DMarchLag.phase(code, 0)


## The fan's mesh in the node's local frame (node at `at`, turned `yaw`; local
## -Z is the heading): ring i at radius share i/rings, spoke j at angle
## (j/spokes*2-1) x half_arc off the heading; each vertex dropped onto the
## ground under its world position plus `lift_m`.
static func mesh_of(height_at: Callable, at: Vector2, yaw: float, radius: float, half_arc: float,
		rings: int, spokes: int, lift_m: float) -> ArrayMesh:
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var v := float(i) / rings
		for j in spokes + 1:
			var u := float(j) / spokes * 2.0 - 1.0
			var th := u * half_arc
			var local := Vector3(sin(th), 0.0, -cos(th)) * (v * radius)
			var w := xf * local
			verts.append(Vector3(local.x, float(height_at.call(Vector2(w.x, w.z))) + lift_m, local.z))
			uvs.append(Vector2(u, v))
			normals.append(Vector3.UP)
	for i in rings:
		for j in spokes:
			var a := i * (spokes + 1) + j
			idx.append_array([a, a + spokes + 1, a + 1, a + 1, a + spokes + 1, a + spokes + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The codes whose fan stands (tests).
func codes() -> Array:
	var out := _fans.keys()
	out.sort()
	return out


func fan_node(code: String) -> MeshInstance3D:
	return (_fans[code]["node"] as MeshInstance3D) if _fans.has(code) else null


## One frame: a fan stands for each code in `wanted` ({code: {at, yaw, r_m,
## arc_deg}}) under `host`, re-draped only when its piece moved past `redrape_m`
## or turned past `redrape_deg`; every other fan is freed.
func sync(host: Node3D, height_at: Callable, repo: DataRepository, meta: Dictionary, wanted: Dictionary,
		rings: int, spokes: int, lift_m: float, redrape_m: float, redrape_deg: float) -> void:
	for code: String in _fans.keys():
		if not wanted.has(code):
			drop(code)
	for code: String in wanted:
		var w: Dictionary = wanted[code]
		var at: Vector2 = w["at"]
		var yaw: float = w["yaw"]
		var radius := world_radius(repo, meta, int(w["r_m"]))
		var half := deg_to_rad(float(w["arc_deg"]) / 2.0)
		var fan: Dictionary = _fans.get(code, {})
		if not fan.is_empty() and (fan["at"] as Vector2).distance_to(at) <= redrape_m \
				and absf(angle_difference(float(fan["yaw"]), yaw)) <= deg_to_rad(redrape_deg) \
				and is_equal_approx(float(fan["radius"]), radius):
			continue
		var node: MeshInstance3D
		if fan.is_empty():
			node = MeshInstance3D.new()
			node.name = PREFIX + code.replace(":", "_")
			node.material_override = MATERIAL
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.set_instance_shader_parameter("half_arc", half)
			node.set_instance_shader_parameter("phase", phase_of(code))
			host.add_child(node)  # no owner: never saved
		else:
			node = fan["node"]
		node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y))
		node.mesh = mesh_of(height_at, at, yaw, radius, half, rings, spokes, lift_m)
		_fans[code] = {"node": node, "at": at, "yaw": yaw, "radius": radius}


func drop(code: String) -> void:
	if _fans.has(code):
		(_fans[code]["node"] as Node).queue_free()
		_fans.erase(code)


func clear() -> void:
	for code: String in _fans.keys():
		drop(code)
