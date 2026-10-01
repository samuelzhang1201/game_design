class_name WarExplode
extends RefCounted
## The folio's exploded view (spec 2026-10-01-war-room-design §4): each part of
## an arm's STATIC parts model flies straight out from the figure's centre.
## The game's skinned mesh cannot be taken apart at runtime (a shader has no
## bone index), so the parts are their own file, exported from Blender.

## arm -> a parts model to read in place of the arm's own file (a seam for
## tests, which have no Blender export to point at; empty in the game).
static var overrides: Dictionary = {}


## The parts model of `arm`, its own file only: archers get none until they
## have their own model (Ruling 23 — their kit rows, sallet, jack and buckler,
## would label a spearman's close helm and heater).
static func parts_path(arm: String) -> String:
	if overrides.has(arm):
		return String(overrides[arm])
	return "res://assets/3D/units/%s/%s_parts.glb" % [arm, arm]


## Part name -> its offset when fully apart: straight out from `centre` by
## `distance`; a part at the centre goes up.
static func offsets(centres: Dictionary, centre: Vector3, distance: float) -> Dictionary:
	var out: Dictionary = {}
	for name: String in centres:
		var d: Vector3 = (centres[name] as Vector3) - centre
		out[name] = (d.normalized() if d.length() > 0.0001 else Vector3.UP) * distance
	return out
