extends GutTest

const SuiteData = preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## A unit's figures stand the same distance apart on the march, standing and in
## a battle (owner 2026-11-18: 我要求间隔一直保持不变).


## The nearest-neighbour distance among `points`, world metres.
func _pitch(points: Array) -> float:
	var best := INF
	for i in points.size():
		for j in range(i + 1, points.size()):
			best = minf(best, (points[i] as Vector2).distance_to(points[j]))
	return best


## The widest distance among `points`, world metres.
func _span(points: Array) -> float:
	var best := 0.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			best = maxf(best, (points[i] as Vector2).distance_to(points[j]))
	return best


func test_entering_a_battle_keeps_the_figures_spacing() -> void:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := preload("res://tests/fixtures/battle_scenario.gd").contact(repo, 10)
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	var foe := String(state.foes.keys()[0])
	var here := ctx.to_world(ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, foe, state)))
	ctx.camera.position = Vector3(here.x, 500, here.y + 500)
	ctx.camera.look_at(Vector3(here.x, 0, here.y))
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	layer.shown = true
	layer.refresh()
	var xz := func(node: Node3D) -> Vector2: return Vector2(node.global_position.x, node.global_position.z)
	var before := {}
	for code: String in [foe, String(Play.land_regiments(repo, 400)[0])]:
		var block: Dictionary = layer.built_piece(code)
		assert_ne(block.get("layout", ""), "physical_groups")
		before[code] = [_pitch((block["figs"] as Array).map(xz)), _span((block["figs"] as Array).map(xz))]
	assert_false(BattleSystem.discover_contacts(repo, state).is_empty(), "real contact starts the encounter")
	layer.refresh()
	layer.step(0.1)  # the walk-in begins: it lasts its farthest walker's paced length (Map3DBattleGroups.walk_in_s)
	var walk_s := 0.0
	for code: String in before:
		for group: Dictionary in layer.built_piece(code)["groups"]:
			walk_s = maxf(walk_s, float(group["piece"].get("walk", {}).get("s", 0.0)))
	layer.step(walk_s + 0.1)
	for code: String in before:
		var piece: Dictionary = layer.built_piece(code)
		assert_eq(piece.get("layout", ""), "physical_groups")
		var stood: Array = (piece["groups"] as Array).map(func(group: Dictionary) -> Vector2: return xz.call(group["piece"]["node"]))
		gut.p("%s: block %.2f / %.2f m, battle %.2f / %.2f m" % [code, before[code][0], before[code][1], _pitch(stood), _span(stood)])
		assert_almost_eq(_pitch(stood), float(before[code][0]), 0.5, code + " keeps its spacing into the battle")
		assert_almost_eq(_span(stood), float(before[code][1]), 0.5, code + " keeps its whole block into the battle")
