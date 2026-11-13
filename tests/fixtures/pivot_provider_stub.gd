extends RefCounted
## A test turn -> pose provider: records each solve and keeps the native clip pose.

static var calls: Array = []


static func solve(_player: AnimationPlayer, _skeleton: Skeleton3D, clip: String, turn_udeg: int, phase: float) -> Dictionary:
	calls.append([clip, turn_udeg, phase])
	return {"ok": true, "reason": "", "pose": {}}
