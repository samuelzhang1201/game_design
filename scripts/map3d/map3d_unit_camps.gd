class_name Map3DUnitCamps
extends RefCounted
## The camps pitched behind lines held camp_after_days (ArmySystem.camped; spec
## 2026-10-11-war-room-front-line-design §3), for Map3DLayerUnits: the
## CAMP_MODELS table's `camp` scene seated behind the piece; none while the
## table or its file is missing (a warning once, never an error), struck when
## the regiment moves on. Takes everything from Map3DContext, never the Game autoload.

var camps: Dictionary = {}  ## code -> the camp model pitched behind its line


## The point `d` world metres BEHIND a piece at `xz` turned `yaw` (its +Z is
## its rear): a camp pitched behind a line facing south lies north of it.
static func behind(xz: Vector2, yaw: float, d: float) -> Vector2:
	return xz + Vector2(sin(yaw), cos(yaw)) * d


## Pitches, moves or strikes `code`'s camp under `layer` for its piece at `xz`
## turned `yaw` at scale `k`, `back_m` model metres past the line's half depth.
func sync(layer: Node3D, ctx: Map3DContext, code: String, piece: Dictionary, xz: Vector2,
		yaw: float, k: float, back_m: float) -> void:
	var repo := ctx.repo
	var wanted := ctx.state() != null and not code.begins_with(Sighting.GHOST_CODE) \
		and ArmySystem.camped(repo, ctx.state(), code)
	if not wanted:
		if camps.has(code):
			(camps[code] as Node3D).queue_free()
			camps.erase(code)
		return
	if not camps.has(code):
		var path := GameArt.path(GameArt.CAMP_MODELS, "camp")
		var scene := Map3DAssetCache.scene(path) if path != "" else null
		if path != "" and scene == null:
			Map3DWorldLoader.warn_once("units:" + path, "map3d units: no model at " + path)
		var camp := scene.instantiate() as Node3D if scene != null else null
		if camp == null:
			return
		camp.name = "Camp_" + code.replace(":", "_")
		layer.add_child(camp)  # no owner: never saved into the authored scene
		camps[code] = camp
	var node: Node3D = camps[code]
	var at := behind(xz, yaw, (float((piece["extent"] as Vector2).y) + back_m) * k)
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, at, Vector2(1.0, 1.0), yaw, k)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)).scaled(Vector3(k, k, k)),
		Vector3(at.x, float(sit["y"]), at.y))


## Every camp whose regiment has no piece any more is struck.
func prune(pieces: Dictionary) -> void:
	for code: String in camps.keys():
		if not pieces.has(code):
			(camps[code] as Node3D).queue_free()
			camps.erase(code)
