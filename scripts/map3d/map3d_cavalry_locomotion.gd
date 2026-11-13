class_name Map3DCavalryLocomotion
extends RefCounted
## The cavalry's pivot for ANY committed turn, leaving and rejoining MARCH (LOCO-CAV-PROVIDER;
## owner rulings R-A / R-C 2026-11-10; coordinator ruling 2026-11-11: stop, start and hold only at
## the admitted MARCH phase, PLAN.march_phase). Candidate only, no ordinary caller; its interface is
## the shared Map3DPivotProvider `solve`, so the body's yaw is BodyMotion's and the root never moves.
## The installed PIVOT clips are 180-degree source fixtures whose ends lie 0.26 m from any MARCH
## pose, so they are never played: the operation is solved by the royal horse's solver
## (Map3DRoyalPivot.sample: every hoof steps once per PLAN.step_deg through the seated STANDBY stand,
## legs by Map3DCavalryPivot against planted hoof frames), which is rig-generic over the horse's
## named chains. Only the binding is the cavalry's: its plan, and its bone landmarks taken from the
## installed skin itself (head at the bone's origin, tail at its leg child's bind origin), since the
## cavalry's source fixtures are not retained. Plan: assets/3D/units/cavalry/cavalry_pivot_plan.json.
## Reads no clock or state and certifies nothing.

const Horse = preload("res://scripts/map3d/map3d_royal_pivot.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const PLAN_PATH: String = "res://assets/3D/units/cavalry/cavalry_pivot_plan.json"

static var _plan: Dictionary = {}
static var _bound_by_id: Dictionary = {}  # skeleton instance id -> {ok, reason, rest, patches, stand}


## Certifier provider (tools/units3d/certify_locomotion.py), through the shared shell.
static func pose(player: AnimationPlayer, skeleton: Skeleton3D, request: Dictionary) -> void:
	Provider.apply(solve, player, skeleton, request)


## One phase of a `turn_udeg` pivot: {ok, reason, pose: {bone: local Transform3D}}.
static func solve(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, turn_udeg: int,
		phase: float) -> Dictionary:
	if clip != ("PIVOT_RIGHT" if turn_udeg > 0 else "PIVOT_LEFT"):
		return {"ok": false, "reason": "clip %s does not turn %d" % [clip, turn_udeg], "pose": {}}
	var bound: Dictionary = bind(player, skeleton)
	if not bound.ok:
		return {"ok": false, "reason": bound.reason, "pose": {}}
	var march: Dictionary = Provider.locals(player, skeleton, "MARCH",
		float(plan().march_phase) * player.get_animation("MARCH").length, bound.rest.bones)
	var out: Dictionary = Horse.sample(bound.rest, phase, turn_udeg, march, bound.stand, bound.patches, plan())
	if not out.ok:
		return {"ok": false, "reason": str(out.diagnostics), "pose": {}}
	return {"ok": true, "reason": "", "pose": out.locals}


## Bone landmarks in each bone's own bind frame: the head at its origin, the tail at the bind
## origin of its child along a hoof chain (so a chain is connected exactly), else one unit up its
## Y axis (a bone's length runs along +Y in the rig's export; unused off the legs).
static func landmarks(skeleton: Skeleton3D, skin: Skin) -> Dictionary:
	var binds: Dictionary = {}
	for i: int in skin.get_bind_count():
		binds[skin.get_bind_name(i)] = skin.get_bind_pose(i).affine_inverse()
	var chain_child: Dictionary = {}
	for hoof: String in Horse.HOOVES:
		var names: Array = []
		for part: String in Horse._CHAINS[hoof.get_slice(".", 0)]:
			names.append(part + "." + hoof.get_slice(".", 1))
		for i: int in range(names.size() - 1):
			chain_child[names[i]] = names[i + 1]
	var out: Dictionary = {}
	for i: int in skeleton.get_bone_count():
		var name: String = skeleton.get_bone_name(i)
		var tail: Vector3 = Vector3.UP
		if chain_child.has(name):
			tail = (binds[name].affine_inverse() * binds[chain_child[name]]).origin
		out[name] = {"head": Vector3.ZERO, "tail": tail}
	return out


static func plan() -> Dictionary:
	if _plan.is_empty():
		_plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	return _plan


## {ok, reason, rest, patches, stand}: the kernel rest, hoof patches and seated stand of this
## figure, built once per skeleton (never evicted: fine for the certifier; the consumer keys it on
## the shared skin and mesh, as for the royal piece).
static func bind(player: AnimationPlayer, skeleton: Skeleton3D) -> Dictionary:
	var id: int = skeleton.get_instance_id()
	if not _bound_by_id.has(id):
		var meshes: Array[Node] = skeleton.find_children("*", "MeshInstance3D", true, false)
		var mesh: MeshInstance3D = null
		for node: Node in meshes:
			if (node as MeshInstance3D).skin != null and (node as MeshInstance3D).mesh != null \
					and (node as MeshInstance3D).mesh.get_surface_count() > 0 \
					and (mesh == null or (node as MeshInstance3D).name == "cavalry"):
				mesh = node
		if mesh == null:
			return {"ok": false, "reason": "cavalry figure has no skinned body mesh"}
		var rest: Dictionary = Horse.rest_of(skeleton, mesh.skin, landmarks(skeleton, mesh.skin))
		var hooves: Dictionary = Horse.patches(mesh, plan())
		var stand: Dictionary = Horse.seat(rest, Provider.locals(player, skeleton, "STANDBY", 0.0, rest.bones), hooves)
		if stand.is_empty():
			return {"ok": false, "reason": "cavalry stand could not be seated"}
		_bound_by_id[id] = {"ok": true, "reason": "", "rest": rest, "patches": hooves, "stand": stand}
	return _bound_by_id[id]
