class_name Map3DFormation
extends RefCounted
## A regiment's piece as a FORMATION of figures by its STRENGTH (owner
## 2026-09-30: 满员 3×3; 减员 前中后 1/2/3; 残兵 前后排 1/2 — replacing the six
## headcount tiers of 2026-09-27). The tiers and their slots are
## data/army/army_formations.csv; the maths is pure and the one scene-tree
## function, build(), only instances and places figures. Never reaches for
## the Game autoload.


## The formation row for a regiment at `fit_permille` strength
## (ArmySystem.fit_permille): the last row whose min_fit_permille it reaches.
static func tier_of(repo: DataRepository, fit_permille: int) -> Dictionary:
	var best: Dictionary = {}
	for row: Dictionary in repo.army_formations:
		if fit_permille >= int(row["min_fit_permille"]):
			best = row
	return best if not best.is_empty() else {"figures": 1, "slots": [Vector2.ZERO]}


## A tier's slots for `layout`: "line" its line_slots (one rank abreast,
## spec 2026-10-11-war-room-front-line-design §2), else its block.
static func slots_of(row: Dictionary, layout: String) -> Array:
	if layout == LINE and row.has("line_slots"):
		return row["line_slots"]
	return row.get("slots", [Vector2.ZERO])


const BLOCK := "block"
const LINE := "line"


## The layout a regiment's piece stands in: its stance's `formation`
## (data/battle/battle_stances.csv) once it stands (not marching), else the block.
static func layout_of(repo: DataRepository, state: GameState, code: String) -> String:
	if state == null or ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH:
		return BLOCK
	var row: Dictionary = repo.battle_stances.get(BattleSystem.stance_of(state, code), {})
	var layout := String(row.get("formation", BLOCK))
	return layout if layout != "" else BLOCK


## The slots in the model's own metres (x right, z toward the rear): each
## slot's spacing units times the figure's own footprint — `extent` its half
## width and half length — times `gap`, so horses stand a horse apart and
## men a man apart; the ranks a further `depth` apart (army_art.csv
## rank_depth: a man seen from the front hides the man behind him).
static func offsets(row: Dictionary, extent: Vector2, gap: float, depth := 1.0, layout := BLOCK) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s: Vector2 in slots_of(row, layout):
		out.append(Vector2(s.x * extent.x * 2.0 * gap, s.y * extent.y * 2.0 * gap * depth))
	return out


## An arm's army_art.csv rank_depth, 1 when it names none.
static func rank_depth(art: Dictionary) -> float:
	var d := String(art.get("rank_depth", ""))
	return float(d) if d != "" else 1.0


## The whole formation's half extents (model metres): the farthest slot plus
## one figure's own half extent, each way.
static func half_extent(offs: PackedVector2Array, extent: Vector2) -> Vector2:
	var far := Vector2.ZERO
	for o in offs:
		far = Vector2(maxf(far.x, absf(o.x)), maxf(far.y, absf(o.y)))
	return far + extent


## A Node3D holding one instance of `scene` per offset (x, z), all facing the
## parent's way. Each casts its shadow (owner 2026-09-27: 兵人需要增加阴影)
## because the figure's scene says so (scenes/models/units/<arm>.tscn,
## edited in the editor). `first` is an already-made figure for the first slot
## (the caller measured it); none is saved (no owner).
static func build(scene: PackedScene, offs: PackedVector2Array, first: Node3D) -> Node3D:
	var root := Node3D.new()
	for i in offs.size():
		var fig: Node3D = first if i == 0 and first != null else scene.instantiate() as Node3D
		if fig == null:
			continue
		fig.name = "Figure%d" % i
		fig.position = Vector3(offs[i].x, 0.0, offs[i].y)
		root.add_child(fig)
	return root


## Every figure's AnimationPlayer under a built formation, in slot order.
static func anims_of(root: Node) -> Array:
	var out: Array = []
	for fig: Node in root.get_children():
		var a := Map3DUnits.find_anim(fig)
		if a != null:
			out.append(a)
	return out


## A regiment's whole piece from its figure `scene` and its army_art.csv row
## `art`, in formation `tier` with `gap` (Map3DLayerUnits' formation_gap): one
## figure measured, then the FORMATION built round it — {node (not yet in the
## tree, no owner), anims, height_m, head_m, half_w_m, extent, figures,
## stand_deg, size, stride_m, exact_pace, clip_s}; {} when the scene makes no Node3D.
static func piece(repo: DataRepository, scene: PackedScene, art: Dictionary, tier: Dictionary,
		gap: float, layout := BLOCK) -> Dictionary:
	var one := scene.instantiate() as Node3D
	if one == null:
		return {}
	var span := Map3DUnits.model_size(one)
	var ext := Map3DUnits.stand_extent(one)
	var offs := offsets(tier, ext, gap, rank_depth(art), layout)
	var node := build(scene, offs, one)
	var anims := anims_of(node)
	var half := half_extent(offs, ext)
	var clip := Map3DUnits.clip_named(anims[0], "MARCH") if not anims.is_empty() else ""
	return {"node": node, "anims": anims, "height_m": span.y,
		"figs": node.get_children(), "slots": Array(Array(offs).map(func(o: Vector2) -> Vector3: return Vector3(o.x, 0.0, o.y))),
		"head_m": Map3DUnitRig.head_m(repo, one, span.y),
		"half_w_m": maxf(half.x, half.y), "extent": half, "figures": offs.size(), "layout": layout,
		"lag_cap": repo.bal("map3d_march_lag_cap_share") * minf(ext.x, ext.y),
		"stand_deg": float(art.get("stand_deg", "0")),
		"size": float(art.get("size", "1")), "stride_m": float(art.get("stride_m", "0")),
		"exact_pace": String(art.get("exact_pace", "0")) == "1",
		"clip_s": (anims[0] as AnimationPlayer).get_animation(clip).length if clip != "" else 0.0}


## A regiment's piece (piece) from its arm's model (army_models.tres, loaded once
## and kept between views) and army_art.csv row, laid out `layout`; {} for an
## empty row or an arm with no model (a fleet).
static func of_regiment(repo: DataRepository, reg: Dictionary, tier: Dictionary, gap: float,
		layout := BLOCK) -> Dictionary:
	if reg.is_empty():
		return {}
	var model := MapObjects.army_piece(repo, reg)
	var path := GameArt.path(GameArt.ARMY_MODELS, model)
	var scene := Map3DAssetCache.scene(path) if path != "" else null
	if path != "" and scene == null:
		Map3DWorldLoader.warn_once("units:" + path, "map3d units: no model at " + path)
	if scene == null:
		return {}
	var built := piece(repo, scene, repo.army_art.get(model, {}), tier, gap, layout)
	built["model"] = model  # keys its march's sound (Map3DUnitSound)
	if bool(built.get("exact_pace", false)):  # each man his own height and cadence (Map3DMarchLag.stature)
		var spread := repo.bal("map3d_march_stature_spread")
		built["statures"] = range(built["figs"].size()).map(func(i: int) -> float:
			return Map3DMarchLag.stature(String(reg.get("regiment_code", "")), i, spread))
		for i in built["figs"].size():
			(built["figs"][i] as Node3D).scale = Vector3.ONE * float(built["statures"][i])
	return built
