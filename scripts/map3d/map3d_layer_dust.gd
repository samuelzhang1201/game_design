class_name Map3DLayerDust
extends Node3D
## MARCH DUST (owner 2026-10-07: 去掉行军后的地面印记，改成扬起的一串灰尘 —
## 短距离，持续一天左右; node World/Dust): a marching column raises a short
## string of dust behind it — soft puffs (march_dust.gdshader, its look
## scenes/map3d/materials/march_dust.tres) that swell, climb and thin out over
## the material's `life_days` of GAME time, so a paused clock holds them and a
## 4x clock clears them four times as fast. Puffs rise only while a piece is
## drawn WALKING (Map3DLayerUnits.shown_positions moved this frame) and the
## clock runs; the string is at most `tail_share` piece-heights long — farther
## behind the head a puff fades out (fade_behind). A piece is one world size at
## every zoom (Map3DUnits.height_m), so every size here is a share of it; far
## out the dust trails a regiment's flat counter the same. Presentation
## only: nothing is saved or read by the engine. Never the Game autoload. All
## puffs are ONE MultiMesh of camera-facing quads, `max_puffs` at most.

const MATERIAL := preload("res://scenes/map3d/materials/march_dust.tres")

## Raise dust at all.
@export var dust_on := true
## A puff every this share of a piece's height walked.
@export var step_share := 0.35
## The string's length behind the column, piece heights; it fades over its last half.
@export var tail_share := 4.0
## A puff's size, a share of a piece's height (each varies ±`size_jitter`).
@export var size_share := 0.8
@export var size_jitter := 0.3
## How far either side of the column's line a puff rises, a share of a piece's height.
@export var spread_share := 0.5
## How far behind the column's middle a puff rises (its rear ranks), a share of a piece's height.
@export var back_share := 1.0
## The most puffs drawn at once (the MultiMesh's capacity).
@export var max_puffs := 600

var ctx: Map3DContext
var _units: Map3DLayerUnits
var _mat: ShaderMaterial
var _mmi: MultiMeshInstance3D
## code -> {puffs: Array of [xz, born, seed, along], walked: metres, last: xz, emitted: metres walked at the last puff}
var _cols: Dictionary = {}
var _last_now := -1.0


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_units = get_node_or_null("../Units") as Map3DLayerUnits
	_mat = MATERIAL.duplicate() as ShaderMaterial
	if _mmi == null:
		_mmi = MultiMeshInstance3D.new()
		_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mmi.extra_cull_margin = 16384.0
		add_child(_mmi)  # no owner: never saved into the authored scene
	var quad := QuadMesh.new()
	quad.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = max_puffs
	mm.visible_instance_count = 0
	_mmi.multimesh = mm
	clear()


## Clear air (a new game, a load).
func clear() -> void:
	_cols.clear()
	if _mmi != null:
		_mmi.multimesh.visible_instance_count = 0


## How many puffs are in the air — a test seam.
func puff_count() -> int:
	var n := 0
	for code: String in _cols:
		n += (_cols[code]["puffs"] as Array).size()
	return n


## A puff `behind` metres behind its column's head: whole within half the
## `tail` length, gone at its end.
static func fade_behind(behind: float, tail: float) -> float:
	return 1.0 - smoothstep(tail * 0.5, tail, behind)


## Whether a puff born on `born` still hangs in the air at `now` (game days),
## `behind` metres behind its column's head.
static func alive(born: float, now: float, life_days: float, behind: float, tail: float) -> bool:
	return now - born < life_days and fade_behind(behind, tail) > 0.0


## A 0..1 seed from a column and its puff's count (the same dust every run).
static func seed_of(code: String, n: int) -> float:
	return float(hash([code, n]) & 0xffff) / 65535.0


## Per FRAME, after the pieces have stepped.
func step() -> void:
	if ctx == null or _units == null or _mat == null:
		return
	var st := ctx.state()
	visible = dust_on and _units.shown
	if not dust_on or st == null:
		return
	var now := float(st.absolute_day()) + ctx.day_share()
	if now < _last_now - 1.0:
		clear()  # time ran back: a load
	now = maxf(now, _last_now)
	_last_now = now
	var ref_m := Map3DGeometry.distance_for_bar(ctx.repo, ctx.meta, ctx.repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var h := Map3DUnits.height_m(ctx.repo, ctx.repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m)
	var running := ctx.clock_speed() > 0
	var shown := _units.shown_positions()
	for code: String in shown:
		_walk(code, shown[code], h, running, now)
	_forget(now, h)
	_fill(h, now)


## A column's walk this frame: a puff every step_share × `h` of it.
func _walk(code: String, xz: Vector2, h: float, running: bool, now: float) -> void:
	if not _cols.has(code):
		_cols[code] = {"puffs": [], "walked": 0.0, "last": xz, "emitted": -INF}
	var col: Dictionary = _cols[code]
	var d := (col["last"] as Vector2).distance_to(xz)
	var from: Vector2 = col["last"]
	col["last"] = xz
	if not running or d < 0.01:
		return
	if d > h * 2.0:
		col["emitted"] = -INF  # it jumped (a frame's walk is metres): no dust bridging the gap
		return
	var walked := float(col["walked"])
	var step_m := maxf(h * step_share, 1.0)
	var puffs: Array = col["puffs"]
	var at := maxf(float(col["emitted"]) + step_m, walked)
	while at <= walked + d:
		var p := from.lerp(xz, (at - walked) / d)
		var sd := seed_of(code, puffs.size() + int(at / step_m))
		var ahead := (xz - from).normalized()
		var side := ahead.orthogonal() * (sd - 0.5) * 2.0 * spread_share * h
		puffs.append([p + side - ahead * back_share * h, now, sd, at])
		col["emitted"] = at
		at += step_m
	col["walked"] = walked + d


## Drop the puffs that have thinned away.
func _forget(now: float, h: float) -> void:
	var life := float(_mat.get_shader_parameter("life_days"))
	for code: String in _cols.keys():
		var col: Dictionary = _cols[code]
		var keep: Array = []
		for pf: Array in col["puffs"]:
			if alive(float(pf[1]), now, life, float(col["walked"]) - float(pf[3]), tail_share * h):
				keep.append(pf)
		col["puffs"] = keep
		if keep.is_empty() and not _units.shown_positions().has(code):
			_cols.erase(code)  # a column no longer drawn, its dust settled


## Every puff into the MultiMesh, newest first so the cap drops the oldest.
func _fill(h: float, now: float) -> void:
	var mm := _mmi.multimesh
	var n := 0
	for code: String in _cols:
		var col: Dictionary = _cols[code]
		var puffs: Array = col["puffs"]
		for i in range(puffs.size() - 1, -1, -1):
			if n >= max_puffs:
				break
			var pf: Array = puffs[i]
			var xz: Vector2 = pf[0]
			var size := h * size_share * (1.0 + (float(pf[2]) - 0.5) * 2.0 * size_jitter)
			mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * size),
				Vector3(xz.x, ctx.height_at(xz), xz.y)))
			mm.set_instance_custom_data(n, Color(float(pf[1]), float(pf[2]),
				fade_behind(float(col["walked"]) - float(pf[3]), tail_share * h), 0.0))
			n += 1
	mm.visible_instance_count = n
	_mat.set_shader_parameter("now_days", now)
