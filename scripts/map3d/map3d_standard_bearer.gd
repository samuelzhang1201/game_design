@tool
class_name Map3DStandardBearer
extends SkeletonModifier3D
## The designated figure keeps its legs and gait; its right arm supports the pole.
@export var grip_height := 1.05
var standard: Map3DNationalFlag
var figure: Node3D
var _hand := -1
var _upper := -1
var _forearm := -1
var _weapons: Array[int] = []

func _ready() -> void:
	var skel := get_skeleton()
	_hand = _bone(skel, ["hand.r", "R_Hand.R", "hand_r"])
	_upper = _bone(skel, ["arm_stretch.r", "R_UpperArm.R", "upperarm_r"])
	_forearm = _bone(skel, ["forearm_stretch.r", "R_Forearm.R", "lowerarm_r"])
	for key: String in ["cc_weapon.r", "cc_weapon.l", "DEF-weapon.R", "DEF-weapon.L", "Lance", "Shield"]:
		var bone := skel.find_bone(key)
		if bone >= 0: _weapons.append(bone)

static func _bone(skel: Skeleton3D, names: Array) -> int:
	for key: String in names:
		var index := skel.find_bone(key)
		if index >= 0: return index
	return -1

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _hand < 0 or not is_instance_valid(standard): return
	if _upper >= 0 and _forearm >= 0:
		_hold(skel)
	for bone: int in _weapons:
		skel.set_bone_pose_scale(bone, Vector3.ONE * 0.001)
	var local_hand := figure.global_transform.affine_inverse() * skel.global_transform * skel.get_bone_global_pose(_hand).origin
	standard.position = local_hand - Vector3.UP * grip_height

func _hold(skel: Skeleton3D) -> void:
	var shoulder := skel.get_bone_global_pose(_upper).origin
	var elbow := skel.get_bone_global_pose(_forearm).origin
	var hand := skel.get_bone_global_pose(_hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(hand)
	if a < 0.001 or b < 0.001: return
	var side := signf(shoulder.x)
	var target := shoulder + Vector3(side * 0.12, -0.30, -0.27) * ((a + b) / 0.58)
	var reach := clampf(shoulder.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var axis := shoulder.direction_to(target)
	var along := (a * a - b * b + reach * reach) / (2.0 * reach)
	var bend := Vector3(side, 0.0, 0.3)
	bend = (bend - axis * bend.dot(axis)).normalized()
	var wanted_elbow := shoulder + axis * along + bend * sqrt(maxf(a * a - along * along, 0.0))
	var fore_pose := skel.get_bone_global_pose(_forearm)
	_aim(skel, _upper, _forearm, wanted_elbow)
	# Keep the pre-rotation basis: mounted rigs inherit the upper arm rotation.
	var fore_direction := elbow.direction_to(hand)
	var wanted_direction := wanted_elbow.direction_to(target)
	fore_pose.origin = wanted_elbow
	fore_pose.basis = Basis(Quaternion(fore_direction, wanted_direction)) * fore_pose.basis
	skel.set_bone_global_pose(_forearm, fore_pose)
	var hand_pose := skel.get_bone_global_pose(_hand)
	hand_pose.origin = target
	hand_pose.basis = skel.get_bone_global_rest(_hand).basis
	skel.set_bone_global_pose(_hand, hand_pose)

static func _aim(skel: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var from := pose.origin.direction_to(skel.get_bone_global_pose(child).origin)
	var to := pose.origin.direction_to(target)
	if from.length_squared() < 0.1 or to.length_squared() < 0.1: return
	pose.basis = Basis(Quaternion(from, to)) * pose.basis
	skel.set_bone_global_pose(bone, pose)
