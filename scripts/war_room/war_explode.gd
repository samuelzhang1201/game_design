class_name WarExplode
extends RefCounted
## The folio's exploded view (spec 2026-10-01-war-room-design §4): each part of
## an arm's STATIC parts model flies straight out from the figure's centre.
## The game's skinned mesh cannot be taken apart at runtime (a shader has no
## bone index), so the parts are their own file, exported from Blender.

## arm -> a parts model to read in place of the arm's own file (a seam for
## tests, which have no Blender export to point at; empty in the game).
static var overrides: Dictionary = {}


## The parts model of `arm` (archers wear the spearman's kit).
static func parts_path(arm: String) -> String:
	var a := "infantry" if arm == "archers" else arm
	if overrides.has(a):
		return String(overrides[a])
	return "res://assets/3D/units/%s/%s_parts.glb" % [a, a]


## Part name -> its offset when fully apart: straight out from `centre` by
## `distance`; a part at the centre goes up.
static func offsets(centres: Dictionary, centre: Vector3, distance: float) -> Dictionary:
	var out: Dictionary = {}
	for name: String in centres:
		var d: Vector3 = (centres[name] as Vector3) - centre
		out[name] = (d.normalized() if d.length() > 0.0001 else Vector3.UP) * distance
	return out
