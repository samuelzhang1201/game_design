extends GutTest


func test_projection_actions_override_orders_and_snapshot_is_copied() -> void:
	var signals := Map3DBattleSignals.new()
	var snapshot := {"map_units": {"own": {"action": "ATTACK"}, "seen": {"action": "DEFEND"}}}
	signals.apply_snapshot(snapshot)
	snapshot["map_units"]["own"]["action"] = "GARRISON"
	assert_eq(signals.action_for("own", "STANDBY"), "ATTACK")
	assert_eq(signals.action_for("seen", "STANDBY"), "DEFEND")
	assert_eq(signals.action_for("hidden", "GARRISON"), "GARRISON")
	for action: String in ["GARRISON", "MARCH"]:
		signals.apply_snapshot({"map_units": {"own": {"action": action}}})
		assert_eq(signals.action_for("own", "STANDBY"), action)
	signals.apply_snapshot({"map_units": {"own": {"action": "SECRET"}}})
	assert_eq(signals.action_for("own", "STANDBY"), "STANDBY")
	signals.apply_snapshot({})
	assert_eq(signals.action_for("own", "STANDBY"), "STANDBY", "stale battle pose is cleared")


func test_signals_follow_real_piece_and_disappear_with_projection() -> void:
	var signals := Map3DBattleSignals.new()
	var root := Node3D.new()
	add_child_autofree(root)
	var model := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(model)
	model.free()
	var pieces := {"own": {"node": root, "height_m": 2.0, "extent": Vector2.ONE},
		"ghost:old": {"node": root, "height_m": 2.0, "extent": Vector2.ONE}}
	signals.apply_snapshot({"battle_signals": [
		{"key": "flag", "kind": "refusal", "unit_code": "own"},
		{"key": "ghost", "kind": "refusal", "unit_code": "ghost:old"},
		{"key": "hidden", "kind": "herald", "unit_code": "unseen"}]})
	var scenes := {"refusal": scene, "herald": scene}
	signals.sync(pieces, scenes, 1.0, 1.5, preload("res://tests/suite_data.gd").repo(), func(_xz: Vector2) -> float: return 0.0)
	assert_eq(signals.count(), 1, "only the informed real unit gets a signal")
	assert_eq(root.get_child_count(), 1)
	signals.sync(pieces, scenes, 1.0, 1.5, preload("res://tests/suite_data.gd").repo(), func(_xz: Vector2) -> float: return 0.0)
	assert_eq(root.get_child_count(), 1, "camera refresh never duplicates the signal")
	signals.apply_snapshot({})
	signals.sync(pieces, scenes, 1.0, 1.5, preload("res://tests/suite_data.gd").repo(), func(_xz: Vector2) -> float: return 0.0)
	assert_eq(signals.count(), 0, "withdrawn projection drops the flag")


func test_real_unit_rigs_supply_attack_defend_garrison_and_march() -> void:
	for arm: String in ["infantry", "archers", "cavalry", "royal"]:
		var scene := load(GameArt.path(GameArt.ARMY_MODELS, arm)) as PackedScene
		var node := scene.instantiate()
		autofree(node)
		var anim := Map3DUnits.find_anim(node)
		assert_not_null(anim, arm)
		if anim == null:
			continue
		for action: String in ["ATTACK", "DEFEND", "GARRISON", "MARCH"]:
			assert_ne(Map3DUnits.clip_named(anim, action), "", arm + " " + action)

func test_real_march_precedes_stationary_battle_pose() -> void:
	var signals := Map3DBattleSignals.new()
	signals.apply_snapshot({"map_units": {"retreating": {"action": "DEFEND"}}})
	assert_eq(signals.action_for("retreating", "MARCH"), "MARCH", "A withdrawing army must walk its real route")

func test_signal_stands_on_ground_at_its_own_offset() -> void:
	var signals := Map3DBattleSignals.new()
	var root := Node3D.new()
	add_child_autofree(root)
	root.position = Vector3(0, 100, 0)
	var model := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(model)
	model.free()
	var pieces := {"own":{"node":root,"height_m":2.0,"extent":Vector2.ONE}}
	signals.apply_snapshot({"battle_signals":[{"key":"herald","kind":"herald","unit_code":"own"}]})
	var repo := preload("res://tests/suite_data.gd").repo()
	repo.balance["map3d_unit_seat_clear"] = 0.0
	repo.balance["map3d_unit_sink_m"] = 0.0
	signals.sync(pieces, {"herald":scene}, 1.0, 1.5, repo, func(_xz: Vector2) -> float: return 20.0)
	var herald: Node3D = root.get_child(0)
	assert_almost_eq(herald.global_position.y, 20.0, 0.001, "The offset signal cannot inherit a regiment's higher seat")

func test_unbound_layer_keeps_snapshot_until_world_can_load() -> void:
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.apply_battle_snapshot({"map_units":{"own":{"action":"ATTACK"}}})
	assert_null(layer.ctx)
	assert_eq(layer._battle.action_for("own", "STANDBY"), "ATTACK")
