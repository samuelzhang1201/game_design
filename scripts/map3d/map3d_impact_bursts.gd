class_name Map3DImpactBursts
extends RefCounted
## The pooled one-shot bursts at a blow's meeting point (spec
## 2026-11-21-infantry-melee-scrum-design.md): sparks on a block, dust on a hit,
## each kind a one-shot GPUParticles3D scene authored in the editor
## (`GameArt.IMPACT_BURSTS`, an ArtTable by kind) in FIGURE HEIGHTS: a burst is
## sized to the pair's figure height, its node scaled (spread and speed) and its
## own copy of the quad sized (the particles; a node's scale never reaches
## them). At most `max_live` burn at once; an idle one of its kind is restarted
## before a new one is made. A burst burns until its `finished` (a one-shot's
## `emitting` drops after its first frame). Its nodes carry no owner.

var _parent: Node3D
var _table: ArtTable
var _max_live: int
var _pool: Dictionary = {}  ## kind -> [GPUParticles3D]
var _live: Dictionary = {}  ## GPUParticles3D -> true while it burns


func _init(parent: Node3D, table: ArtTable, max_live: int) -> void:
	_parent = parent
	_table = table
	_max_live = max_live


## Shows one `kind` burst at `at`, `size` figure heights to the scene's one;
## false when `max_live` already burn or the kind has no scene.
func burst(kind: String, at: Vector3, size := 1.0) -> bool:
	var scene := _table.of(kind) as PackedScene if _table != null else null
	if scene == null or not is_instance_valid(_parent) or live_count() >= _max_live:
		return false
	var pool: Array = _pool.get(kind, [])
	_pool[kind] = pool
	var node: GPUParticles3D = null
	for p: Variant in pool:
		if is_instance_valid(p) and not _live.has(p):
			node = p
			break
	if node == null:
		node = scene.instantiate() as GPUParticles3D
		if node == null:
			return false
		node.draw_pass_1 = node.draw_pass_1.duplicate()  # its own quad, sized per burst
		node.set_meta("quad", (node.draw_pass_1 as QuadMesh).size)
		node.finished.connect(func() -> void: _live.erase(node))
		_parent.add_child(node)
		pool.append(node)
	node.global_position = at
	node.scale = Vector3.ONE * size
	(node.draw_pass_1 as QuadMesh).size = (node.get_meta("quad") as Vector2) * size
	node.restart()
	_live[node] = true
	return true


func live_count() -> int:
	for node: Variant in _live.keys():
		if not is_instance_valid(node):
			_live.erase(node)
	return _live.size()
