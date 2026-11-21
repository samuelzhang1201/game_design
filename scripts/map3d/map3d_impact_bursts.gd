class_name Map3DImpactBursts
extends RefCounted
## The pooled one-shot bursts at a blow's meeting point (spec
## 2026-11-21-infantry-melee-scrum-design.md): sparks on a block, dust on a hit,
## each kind a one-shot GPUParticles3D scene authored in the editor
## (`GameArt.IMPACT_BURSTS`, an ArtTable by kind). At most `max_live` burn at
## once; an idle one of its kind is restarted before a new one is made.
## Its nodes carry no owner (a save never writes them).

var _parent: Node3D
var _table: ArtTable
var _max_live: int
var _pool: Dictionary = {}  ## kind -> [GPUParticles3D]


func _init(parent: Node3D, table: ArtTable, max_live: int) -> void:
	_parent = parent
	_table = table
	_max_live = max_live


## Shows one `kind` burst at `at`, scaled to `size` (the scenes are authored
## in figure heights: figures are camera-scaled miniatures); false when
## `max_live` already burn or the kind has no scene.
func burst(kind: String, at: Vector3, size := 1.0) -> bool:
	var scene := _table.of(kind) as PackedScene if _table != null else null
	if scene == null or not is_instance_valid(_parent) or live_count() >= _max_live:
		return false
	var pool: Array = _pool.get(kind, [])
	_pool[kind] = pool
	var node: GPUParticles3D = null
	for p: Variant in pool:
		if is_instance_valid(p) and not (p as GPUParticles3D).emitting:
			node = p
			break
	if node == null:
		node = scene.instantiate() as GPUParticles3D
		if node == null:
			return false
		_parent.add_child(node)
		pool.append(node)
	node.global_position = at
	node.scale = Vector3.ONE * size
	node.restart()
	node.emitting = true
	return true


func live_count() -> int:
	var n := 0
	for pool: Array in _pool.values():
		for p: Variant in pool:
			if is_instance_valid(p) and (p as GPUParticles3D).emitting:
				n += 1
	return n
