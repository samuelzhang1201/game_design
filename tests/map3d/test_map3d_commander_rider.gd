extends GutTest
## Map3DCommanderRider: a unit's mounted commander drawn alone ahead of its first rank (spec
## 2026-11-27-commander-figure-design, step 2). He takes no formation place and changes no
## number; the king's own unit and a ghost have none; he walks ahead of foot and gallops ahead of
## cavalry; in a battle block he stands ahead through the stand-off and is not drawn in the fight.

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const FLAGS := "res://assets/2D/flags/realms/national_flags.tres"
const FOOT: Array[String] = ["infantry", "heavy_infantry", "axemen", "archers", "militia", "artillery"]


func _ctx(repo: DataRepository, state: GameState) -> Map3DContext:
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	return ctx


func _layer(ctx: Map3DContext) -> Map3DLayerUnits:
	var layer := Map3DLayerUnits.new()
	layer.realm_flags = load(FLAGS)
	add_child_autofree(layer)
	layer.bind(ctx)
	layer.shown = true
	layer.refresh()
	return layer


func _clip(rider: Map3DCommanderRider) -> String:
	return String(rider._anim.current_animation).get_file()


func test_a_commanded_unit_leads_and_the_kings_own_does_not() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var royal := 0
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var code := String(reg["regiment_code"])
		var led := String(state.military_rosters.get(code, {}).get("commander_id", "")) != ""
		if String(reg.get("is_royal", "0")) == "1":
			royal += 1
			assert_true(led, "the fixture's royal unit has its commander in the engine")
			assert_false(Map3DCommanderRider.leads(reg, state), "the royal piece is the king himself")
		else:
			assert_eq(Map3DCommanderRider.leads(reg, state), led, code)
	assert_gt(royal, 0)
	assert_false(Map3DCommanderRider.leads({"regiment_code": "nobody"}, state), "no roster, no commander")
	assert_false(Map3DCommanderRider.leads({"regiment_code": "nobody"}, null), "the editor's preview has no state")


func test_the_clip_follows_the_units_action_and_arm() -> void:
	assert_eq(Map3DCommanderRider.clip_for("MARCH", "block", false), "MARCH_WALK", "he walks ahead of foot")
	assert_eq(Map3DCommanderRider.clip_for("MARCH", "block", true), "MARCH", "he gallops ahead of cavalry")
	for action: String in ["STANDBY", "GARRISON", "DEFEND", "ATTACK", ""]:
		assert_eq(Map3DCommanderRider.clip_for(action, "line", true), "STANDBY", action)
	assert_eq(Map3DCommanderRider.clip_for("MARCH", "physical_groups", false), "STANDBY",
		"a battle block's figures walking in are no march of his")
	var repo := SuiteData.repo()
	assert_eq(String(repo.army_art["cavalry"]["commander_gallops"]), "1")
	for arm: String in FOOT:
		assert_ne(String(repo.army_art[arm].get("commander_gallops", "")), "1", arm + " is led at the walk")


func test_the_lead_is_his_gap_and_half_his_length() -> void:
	# half length 1.2 m, one length (2.4 m) clear, at scale 2: (2.4 + 1.2) x 2 = 7.2 m
	assert_almost_eq(Map3DCommanderRider.lead_m(1.2, 1.0, 2.0), 7.2, 1e-5)
	# no gap: his tail at the first rank's front
	assert_almost_eq(Map3DCommanderRider.lead_m(1.2, 0.0, 1.0), 1.2, 1e-5)


func test_in_a_stand_off_his_lead_is_a_share_of_the_room_between_the_lines() -> void:
	# 20 m between the lines, a fifth of it: 4 m, inside his ordinary 7.2 m lead
	assert_almost_eq(Map3DCommanderRider.standoff_lead(7.2, 20.0, 0.2, 2.4), 4.0, 1e-5)
	# wide apart (or no enemy drawn): his ordinary lead
	assert_almost_eq(Map3DCommanderRider.standoff_lead(7.2, 100.0, 0.2, 2.4), 7.2, 1e-5)
	assert_almost_eq(Map3DCommanderRider.standoff_lead(7.2, INF, 0.2, 2.4), 7.2, 1e-5)
	# his half length is 2.4 m: at 12 m of room a fifth is exactly his tail on his own rank
	assert_almost_eq(Map3DCommanderRider.standoff_lead(7.2, 12.0, 0.2, 2.4), 2.4, 1e-5)
	# closer lines leave him no place
	assert_eq(Map3DCommanderRider.standoff_lead(7.2, 11.0, 0.2, 2.4), -1.0)
	# two commanders a fifth in from each side keep 60% of the room between their centres
	assert_almost_eq(20.0 - 2.0 * Map3DCommanderRider.standoff_lead(7.2, 20.0, 0.2, 2.4), 12.0, 1e-5)


func test_a_battle_blocks_front_is_its_foremost_reach_at_its_middle() -> void:
	# facing -z (0, -1): across is +x. Along: 4, 4, 0, each reaching 1 ahead -> front 5.
	# Across: -2, 6, 2 -> the middle of -2..6 is 2. So (2, -5).
	var front := Map3DCommanderRider.front_of(PackedVector2Array([Vector2(-2, -4), Vector2(6, -4), Vector2(2, 0)]),
		PackedFloat32Array([1.0, 1.0, 1.0]), Vector2(0, -1))
	assert_almost_eq(front.x, 2.0, 1e-5)
	assert_almost_eq(front.y, -5.0, 1e-5)
	# facing +x (1, 0): across is +z. Along: 2, 2, -1 with reaches 0.5, 0.25, 9 -> max(2.5, 2.25, 8) = 8.
	# Across: -3, 3, 0 -> middle 0. So (8, 0).
	front = Map3DCommanderRider.front_of(PackedVector2Array([Vector2(2, -3), Vector2(2, 3), Vector2(-1, 0)]),
		PackedFloat32Array([0.5, 0.25, 9.0]), Vector2(1, 0))
	assert_almost_eq(front.x, 8.0, 1e-5)
	assert_almost_eq(front.y, 0.0, 1e-5)
	assert_eq(Map3DCommanderRider.front_of(PackedVector2Array(), PackedFloat32Array(), Vector2(1, 0)), Vector2.ZERO)


func test_his_march_keeps_his_units_ground() -> void:
	# the men: 2 x a 1 s clip of 1.5 m at scale 4 -> 3 model m/s, 12 world m/s.
	# he at scale 2 covers 6 model m/s; his 1 s loop walks 3 m -> twice its own speed.
	assert_almost_eq(Map3DCommanderRider.march_rate(2.0, 1.5, 1.0, 4.0, 3.0, 1.0, 2.0), 2.0, 1e-5)
	# the same horse at the same scale on the same stride: the men's own rate
	assert_almost_eq(Map3DCommanderRider.march_rate(0.7, 2.4224, 0.43333, 3.0, 2.4224, 0.43333, 3.0), 0.7, 1e-5)
	assert_eq(Map3DCommanderRider.march_rate(2.0, 0.0, 1.0, 4.0, 3.0, 1.0, 2.0), 1.0, "an arm with no measured stride")
	assert_eq(Map3DCommanderRider.march_rate(2.0, 1.5, 1.0, 4.0, 0.0, 1.0, 2.0), 1.0)


func test_his_size_draws_his_horse_at_the_cavalrys_scale() -> void:
	var repo := SuiteData.repo()
	var he := (load(Map3DCommanderFigure.SCENE) as PackedScene).instantiate() as Node3D
	var knight := (load(GameArt.path(GameArt.ARMY_MODELS, "cavalry")) as PackedScene).instantiate() as Node3D
	autofree(he)
	autofree(knight)
	# a size draws the model box at size x the piece height: metres of world per model metre
	var his := repo.bal("map3d_commander_size") / Map3DUnits.model_size(he).y
	var theirs := float(repo.army_art["cavalry"]["size"]) / Map3DUnits.model_size(knight).y
	assert_almost_eq(his / theirs, 1.0, 0.001, "re-measure map3d_commander_size after a re-export of either model")
	assert_eq(repo.bal("map3d_commander_gallop_stride_m"), float(repo.army_art["cavalry"]["stride_m"]),
		"his gallop is the cavalry's locked run")


func test_he_stands_alone_ahead_of_the_first_rank_and_takes_no_place() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var frozen := SaveLoad.state_hash(state)
	var ctx := _ctx(repo, state)
	var layer := _layer(ctx)
	var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var seen := {}
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var code := String(reg["regiment_code"])
		var piece := layer.built_piece(code)
		if piece.is_empty():
			continue  # a fleet has no piece
		var rider := Map3DCommanderRider.of_piece(piece)
		if String(reg.get("is_royal", "0")) == "1":
			assert_null(rider, "no commander figure on the king's own unit")
			seen["royal"] = true
			continue
		if String(state.military_rosters.get(code, {}).get("commander_id", "")) == "":
			assert_null(rider, code + " has no commander: no figure")
			seen["leaderless"] = true
			continue
		assert_not_null(rider, code + " shows its commander")
		if rider == null:
			continue
		var root: Node3D = piece["node"]
		assert_false(rider.visible, "hung on a piece not yet seated: unseen (and unclickable) until he stands")
		layer._shown_xz[code] = Vector2.ZERO  # before the camera: seated and shown
		layer._place(code, piece)
		assert_true(root.visible)
		rider.stand()
		assert_true(rider.visible)
		# no formation place, no number: the piece's figures are its fit groups, he is none of them
		var tier := Map3DFormation.fit_tier(repo, ArmySystem.fit_count(repo, state, code), String(piece["layout"]))
		assert_eq((piece["figs"] as Array).size(), int(tier["figures"]))
		assert_eq(int(piece["figures"]), int(tier["figures"]))
		assert_false((piece["figs"] as Array).has(rider))
		assert_false((piece["anims"] as Array).has(rider._anim))
		# his horse at the cavalry's world scale, whatever arm he leads
		var k := root.scale.x * rider.scale.x
		var cavalry_k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference,
			rider._height, repo.bal("map3d_commander_size"))
		assert_almost_eq(k, cavalry_k, cavalry_k * 0.0001, code)
		# centred on the files, ahead of the first rank (the piece's front is -z): the foremost slot,
		# a figure's half depth, then one of his lengths clear and half his length, in the piece's metres
		var front_z := INF
		var left := INF
		var right := -INF
		for slot: Vector3 in piece["slots"]:
			front_z = minf(front_z, slot.z)
			left = minf(left, slot.x)
			right = maxf(right, slot.x)
		var lengths := 1.0 + 2.0 * repo.bal("map3d_commander_gap")  # his gap in lengths clear, then half his length
		var want_z := front_z - float((piece["figure_extent"] as Vector2).y) - rider._half.y * lengths * k / root.scale.x
		assert_almost_eq(rider.position.x, (left + right) * 0.5, 1e-4, code + " is centred")
		assert_almost_eq(rider.position.z, want_z, 1e-3, code + " is ahead of the first rank")
		assert_almost_eq(rider.rotation.y, 0.0, 1e-5, code + " faces his unit's way")
		for fig: Node3D in piece["figs"]:
			assert_gt(fig.position.z - rider.position.z, rider._half.y * k / root.scale.x, "every man is behind his horse")
		assert_eq(_clip(rider), "STANDBY", "standing still he stands by")
		# the banner is his realm's
		var mesh: MeshInstance3D = Map3DUnits.meshes(rider)[0]
		var cloth := mesh.get_surface_override_material(Map3DCommanderFigure.cloth_surface(mesh)) as BaseMaterial3D
		assert_eq(cloth.albedo_texture, Map3DNationalFlag.texture_for(repo, layer.realm_flags, String(reg["kingdom_code"])))
		assert_not_null(cloth.albedo_texture, "the crown's realm has flag art")
		# marching: the walk ahead of foot, the gallop ahead of cavalry
		var arm := String(piece["model"])
		piece["action"] = "MARCH"
		rider.stand()
		assert_eq(_clip(rider), "MARCH" if arm == "cavalry" else "MARCH_WALK", arm)
		seen[arm] = true
		# a click on him is a click on his unit: the picker's ray test walks the piece's meshes, his too
		# (he stands ahead of every man, so a ray straight down on him meets nobody else)
		assert_lt(Map3DPicker.ray_depth(piece, rider.global_position + Vector3.UP * 500.0, Vector3.DOWN), INF,
			code + ": a ray on him meets his unit's piece")
		assert_eq(Map3DPicker.ray_depth(piece, rider.global_position + Vector3(0.0, 500.0, -100000.0), Vector3.DOWN), INF)
		# by his horse and body, not by the air round his banner: a level ray across him at half his
		# head's height meets him, one over his head (under the banner's tip) meets nothing
		var head := Map3DUnitRig.head_m(repo, rider._figure, rider._height) * k
		assert_between(head, 0.4 * rider._height * k, 0.8 * rider._height * k, "his head stands well under the banner's tip")
		var across := root.global_basis.x.normalized()  # along the rank: the ray passes ahead of every man
		var side := rider.global_position - across * 1000.0
		assert_lt(Map3DPicker.ray_depth(piece, side + Vector3.UP * head * 0.5, across), INF, code + ": his body takes a click")
		assert_eq(Map3DPicker.ray_depth(piece, side + Vector3.UP * (head + 0.5 * (rider._height * k - head)), across), INF,
			code + ": the air round his banner takes none")
	assert_true(seen.has("royal") and seen.has("cavalry") and seen.has("infantry"), str(seen.keys()))
	assert_eq(SaveLoad.state_hash(state), frozen, "drawing him changes nothing saved")


func test_a_unit_whose_commander_fell_is_seen_leaderless() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var layer := _layer(_ctx(repo, state))
	var code := ""
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if Map3DCommanderRider.of_piece(layer.built_piece(String(reg["regiment_code"]))) != null:
			code = String(reg["regiment_code"])
			break
	assert_ne(code, "")
	state.military_rosters[code]["commander_id"] = ""
	layer.refresh()
	assert_null(Map3DCommanderRider.of_piece(layer.built_piece(code)), "no commander, no figure")
	assert_eq((layer.built_piece(code)["node"] as Node3D).get_children().filter(
		func(n: Node) -> bool: return n is Map3DCommanderRider).size(), 0)


func test_a_seen_foe_shows_its_commander_and_a_ghost_never_does() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var foe := String(state.foes.keys()[0])
	state.foes[foe]["x_m"] = -1000000
	state.foes[foe]["y_m"] = -1000000
	Sighting.record(state, foe, {"kind": Sighting.KIND_UNIT, "code": foe, "x_m": 200, "y_m": 300,
		"day": state.absolute_day(), "source": Sighting.SEEN, "men": 1000})
	assert_ne(String(state.military_rosters[foe]["commander_id"]), "", "the ghost's live unit has a commander")
	var ctx := _ctx(repo, state)
	var layer := _layer(ctx)
	var ghost := Sighting.GHOST_CODE + foe
	assert_true(layer.has_piece(ghost))
	assert_false(layer.has_piece(foe), "the foe itself is out of sight")
	assert_null(Map3DCommanderRider.of_piece(layer.built_piece(ghost)), "a ghost reads nothing live")
	# seen (the fixture's contact): the foe's own commander under the foe's own banner
	repo = SuiteData.open_country(SuiteData.repo())
	state = Scenario.contact(repo, 10)
	foe = String(state.foes.keys()[0])
	ctx = _ctx(repo, state)
	layer = _layer(ctx)
	var rider := Map3DCommanderRider.of_piece(layer.built_piece(foe))
	assert_not_null(rider, "a seen enemy unit shows its commander")
	var realm := String(ArmySystem.regiment(repo, foe, state)["kingdom_code"])
	assert_ne(realm, repo.resolve_realm("player_realm"))
	var mesh: MeshInstance3D = Map3DUnits.meshes(rider)[0]
	var cloth := mesh.get_surface_override_material(Map3DCommanderFigure.cloth_surface(mesh)) as BaseMaterial3D
	assert_eq(cloth.albedo_texture, Map3DNationalFlag.texture_for(repo, layer.realm_flags, realm), "under its own realm's banner")


func test_in_a_stand_off_he_is_ahead_of_the_block_and_in_the_fight_not_drawn() -> void:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := Scenario.contact(repo, 10)
	var foe := String(state.foes.keys()[0])
	var own := ""
	for code: String in state.regiments:
		if Vector2(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])).distance_to(
				Vector2(int(state.foes[foe]["x_m"]), int(state.foes[foe]["y_m"]))) < 2000:
			own = code
	assert_ne(own, "")
	var ctx := _ctx(repo, state)
	assert_false(BattleSystem.discover_contacts(repo, state).is_empty())
	assert_eq(int(state.battles[0].get("rounds", 0)), 0, "contact made, no round fought: the stand-off")
	var layer := _layer(ctx)  # a view opened on the battle: its figures stand on their points, nobody walks in
	var share := repo.bal("map3d_commander_standoff_share")
	# the fixture's lines stand a horse's length apart: no place for a commander between them
	for code: String in [own, foe]:
		var rider := Map3DCommanderRider.of_piece(layer.built_piece(code))
		assert_not_null(rider, code)
		rider.stand()
		assert_false(rider.visible, code + ": lines this close leave him no place")
	# the foe a further 3 km off: room for both
	var away := Vector2(int(state.foes[foe]["x_m"]) - int(state.regiments[own]["x_m"]),
		int(state.foes[foe]["y_m"]) - int(state.regiments[own]["y_m"])).normalized() * 3000.0
	for row: Dictionary in state.battles[0]["groups"][foe]:
		row["x_m"] = int(row["x_m"]) + int(away.x)
		row["y_m"] = int(row["y_m"]) + int(away.y)
	state.foes[foe]["x_m"] = int(state.foes[foe]["x_m"]) + int(away.x)
	state.foes[foe]["y_m"] = int(state.foes[foe]["y_m"]) + int(away.y)
	layer = _layer(ctx)
	var riders := {}
	for code: String in [own, foe]:
		var piece := layer.built_piece(code)
		assert_eq(piece.get("layout", ""), "physical_groups")
		var rider := Map3DCommanderRider.of_piece(piece)
		assert_not_null(rider, code)
		rider.stand()
		riders[code] = rider
		var face := WarFront.facing_vector(int(piece["facing_deg"]))
		var root: Node3D = piece["node"]
		var k := rider.global_basis.get_scale().x
		var foremost := _reach(piece, root, face)
		# the nearest enemy figure's near side, measured the same way from this unit's root
		var room := -_reach(layer.built_piece(foe if code == own else own), root, -face) - foremost
		assert_gt(room * share, rider._half.y * k, "the widened lines leave him his place")
		assert_true(rider.visible, code + " stands before his block in the stand-off")
		assert_eq(_clip(rider), "STANDBY")
		var at := Vector2(rider.global_position.x - root.global_position.x, rider.global_position.z - root.global_position.z)
		# a share of the room between the lines, never past his ordinary lead
		assert_almost_eq(at.dot(face), foremost + minf(room * share, rider._half.y * (1.0 + 2.0 * repo.bal("map3d_commander_gap")) * k), 0.01,
			code + " is ahead of the first rank")
		var ahead := -rider.global_basis.z
		assert_almost_eq(Vector2(ahead.x, ahead.z).normalized().dot(face), 1.0, 1e-4, code + " faces the enemy with his unit")
		assert_eq(int(piece["figures"]), (piece["groups"] as Array).size(), "no group is his")
	# while a block's figures still walk to their points the room is not settled: not drawn yet
	layer.built_piece(own)["easing"] = true
	(riders[own] as Map3DCommanderRider).stand()
	assert_false((riders[own] as Node3D).visible, "hidden while his block walks in")
	assert_false((riders[own] as Map3DCommanderRider)._anim.active, "and his clip stops with him")
	layer.built_piece(own)["easing"] = false
	(riders[own] as Map3DCommanderRider).stand()
	assert_true((riders[own] as Node3D).visible, "shown once the block stands")
	# hidden with his piece (symbol mode, a hidden view): his clip stops
	(layer.built_piece(own)["node"] as Node3D).visible = false
	(riders[own] as Map3DCommanderRider).stand()
	assert_false((riders[own] as Map3DCommanderRider)._anim.active, "a hidden piece's commander animates nothing")
	(layer.built_piece(own)["node"] as Node3D).visible = true
	(riders[own] as Map3DCommanderRider).stand()
	assert_true((riders[own] as Map3DCommanderRider)._anim.active)
	var apart := (riders[own] as Node3D).global_position.distance_to((riders[foe] as Node3D).global_position)
	assert_gt(apart, 2.0 * (riders[own] as Map3DCommanderRider)._half.y * (riders[own] as Node3D).global_basis.get_scale().x,
		"the two commanders stand more than a horse's length apart between the lines")
	state.battles[0]["rounds"] = 1
	for code: String in [own, foe]:
		var rider := Map3DCommanderRider.of_piece(layer.built_piece(code))
		rider.stand()
		assert_false(rider.visible, code + ": not drawn in the fight until he rides to the left rear (step 3)")



## The farthest a battle piece's drawn figures reach along `face` from `root` (their far sides).
func _reach(piece: Dictionary, root: Node3D, face: Vector2) -> float:
	var out := -INF
	for group: Dictionary in piece["groups"]:
		var node: Node3D = group["piece"]["node"]
		out = maxf(out, Vector2(node.global_position.x - root.global_position.x,
			node.global_position.z - root.global_position.z).dot(face) + float(group["piece"]["extent"].y) * node.scale.x)
	return out
