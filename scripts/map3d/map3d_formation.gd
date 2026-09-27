class_name Map3DFormation
extends RefCounted
## A regiment's piece as a FORMATION of figures (owner 2026-09-27: 兵人模型需要有
## 人数区分，分成6个人数等级 — one; two side by side; three in a triangle; two
## ranks of two; the five of a die; a 1+2+3 wedge). The tiers and their slots
## are data/army_formations.csv; the maths is pure and the one scene-tree
## function, build(), only instances and places figures. Never reaches for
## the Game autoload.


## The formation row for `heads` men: the last row whose min_heads it reaches.
static func tier_of(repo: DataRepository, heads: float) -> Dictionary:
	var best: Dictionary = {}
	for row: Dictionary in repo.army_formations:
		if heads >= float(row["min_heads"]):
			best = row
	return best if not best.is_empty() else {"figures": 1, "slots": [Vector2.ZERO]}


## The slots in the model's own metres (x right, z toward the rear): each
## slot's spacing units times the figure's own footprint — `extent` its half
## width and half length — times `gap`, so horses stand a horse apart and
## men a man apart.
static func offsets(row: Dictionary, extent: Vector2, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s: Vector2 in row.get("slots", [Vector2.ZERO]):
		out.append(Vector2(s.x * extent.x * 2.0 * gap, s.y * extent.y * 2.0 * gap))
	return out


## The whole formation's half extents (model metres): the farthest slot plus
## one figure's own half extent, each way.
static func half_extent(offs: PackedVector2Array, extent: Vector2) -> Vector2:
	var far := Vector2.ZERO
	for o in offs:
		far = Vector2(maxf(far.x, absf(o.x)), maxf(far.y, absf(o.y)))
	return far + extent


## A Node3D holding one instance of `scene` per offset (x, z), all facing the
## parent's way, each casting its shadow (owner 2026-09-27: 兵人需要增加阴影).
## `first` is an already-made figure for the first slot (the caller measured
## it); none is saved (no owner).
static func build(scene: PackedScene, offs: PackedVector2Array, first: Node3D) -> Node3D:
	var root := Node3D.new()
	for i in offs.size():
		var fig: Node3D = first if i == 0 and first != null else scene.instantiate() as Node3D
		if fig == null:
			continue
		fig.name = "Figure%d" % i
		fig.position = Vector3(offs[i].x, 0.0, offs[i].y)
		root.add_child(fig)
		for m: MeshInstance3D in Map3DUnits.meshes(fig):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## Every figure's AnimationPlayer under a built formation, in slot order.
static func anims_of(root: Node) -> Array:
	var out: Array = []
	for fig: Node in root.get_children():
		var a := Map3DUnits.find_anim(fig)
		if a != null:
			out.append(a)
	return out
