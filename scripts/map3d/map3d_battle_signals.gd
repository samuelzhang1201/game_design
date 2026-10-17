class_name Map3DBattleSignals
extends RefCounted
## Only copied, informed map fields enter this renderer. No battle state is read.

var _units: Dictionary = {}
var _signals: Array = []
var _nodes: Dictionary = {}


func apply_snapshot(snapshot: Dictionary) -> void:
	_units = snapshot.get("map_units", {}).duplicate(true)
	_signals = snapshot.get("battle_signals", []).duplicate(true)


func action_for(code: String, fallback: String) -> String:
	if fallback == "MARCH": return fallback
	var action := String(_units.get(code, {}).get("action", ""))
	return action if action in ["ATTACK", "DEFEND", "GARRISON", "MARCH"] else fallback


## Signals accompany real, currently drawn pieces; ghosts never acquire live signals.
func sync(pieces: Dictionary, scenes: Dictionary, height_ratio: float, gap: float,
		repo: DataRepository, height_at: Callable) -> void:
	var live: Dictionary = {}
	for signal_row: Dictionary in _signals:
		var code := String(signal_row.get("unit_code", ""))
		var kind := String(signal_row.get("kind", ""))
		var scene := scenes.get(kind) as PackedScene
		if not pieces.has(code) or code.begins_with(Sighting.GHOST_CODE) or scene == null:
			continue
		var piece: Dictionary = pieces[code]
		var root: Node3D = piece["node"]
		var key := String(signal_row.get("key", ""))
		if key == "":
			continue
		if _nodes.has(key) and (not is_instance_valid(_nodes[key]) or (_nodes[key] as Node3D).get_parent() != root):
			_drop(key)
		if not _nodes.has(key):
			var node := scene.instantiate() as Node3D
			root.add_child(node)
			var model_h := Map3DUnits.model_size(node).y
			node.scale *= float(piece["height_m"]) * height_ratio / model_h
			var extent: Vector2 = piece["extent"]
			node.position = Vector3(extent.x * gap * (-1.0 if kind == "herald" else 1.0), 0.0, 0.0)
			var anim := Map3DUnits.find_anim(node)
			if anim != null:
				Map3DUnitRig.play([anim], "IDLE" if kind == "herald" else "GARRISON", 0.0)
			_nodes[key] = node
		Map3DUnitRig.plant(repo, height_at, {"node": root, "height_m": piece["height_m"], "figs": [_nodes[key]]})
		live[key] = true
	for key: String in _nodes.keys():
		if not live.has(key):
			_drop(key)


func _drop(key: String) -> void:
	if is_instance_valid(_nodes[key]):
		(_nodes[key] as Node3D).queue_free()
	_nodes.erase(key)


func count() -> int:
	return _nodes.size()
