extends GutTest
## Map3DCommanderRider: a unit's mounted commander drawn alone ahead of its first rank (spec
## 2026-11-27-commander-figure-design, step 2). He takes no formation place and changes no
## number; the king's own unit and a ghost have none; he walks ahead of foot and gallops ahead of
## cavalry; in a battle block he stands ahead through the stand-off, and in the fight rides round
## the unit's left flank to its left rear and commands there (step 3).

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
	# the fight (a round fought): he commands, whatever his unit's figures play and whatever arm he leads
	for action: String in ["ATTACK", "DEFEND", "MARCH", "GARRISON", ""]:
		assert_eq(Map3DCommanderRider.clip_for(action, "physical_groups", false, true), "COMMAND", action)
		assert_eq(Map3DCommanderRider.clip_for(action, "physical_groups", true, true), "COMMAND", action)
	assert_eq(Map3DCommanderRider.clip_for("ATTACK", "physical_groups", false, false), "STANDBY", "the stand-off")
	assert_eq(Map3DCommanderRider.clip_for("MARCH", "block", false, true), "MARCH_WALK", "only a battle block fights")
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


func test_in_a_stand_off_he_is_ahead_of_the_block() -> void:
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


func test_a_blocks_left_rear_is_outside_its_left_file_level_with_its_rear_rank() -> void:
	# facing -z (0, -1): the unit's right is +x. Each figure reaches 1 to its side: the left file's
	# outside is min(-2, 6, 2) - 1 = -3. Along the facing the places are 4, 4, 0: the rear rank is 0.
	var at := Map3DCommanderRider.left_rear_of(PackedVector2Array([Vector2(-2, -4), Vector2(6, -4), Vector2(2, 0)]),
		PackedFloat32Array([1.0, 1.0, 1.0]), Vector2(0, -1))
	assert_almost_eq(at.x, -3.0, 1e-5)
	assert_almost_eq(at.y, 0.0, 1e-5)
	# a diagonal facing (0.6, 0.8): the right is (-0.8, 0.6). Across: (10,0) -> -8, (0,10) -> 6,
	# (5,5) -> -1; less the sides 1, 2, 0.5: -9, 4, -1.5 -> left -9. Along: 6, 8, 7 -> rear 6.
	# 6 x (0.6, 0.8) - 9 x (-0.8, 0.6) = (3.6 + 7.2, 4.8 - 5.4) = (10.8, -0.6)
	at = Map3DCommanderRider.left_rear_of(PackedVector2Array([Vector2(10, 0), Vector2(0, 10), Vector2(5, 5)]),
		PackedFloat32Array([1.0, 2.0, 0.5]), Vector2(0.6, 0.8))
	assert_almost_eq(at.x, 10.8, 1e-4)
	assert_almost_eq(at.y, -0.6, 1e-4)
	# facing +x (1, 0): the right is +z, so the left is -z (north on the map) and the rear -x
	at = Map3DCommanderRider.left_rear_of(PackedVector2Array([Vector2(0, -3), Vector2(0, 3), Vector2(-2, 0)]),
		PackedFloat32Array([0.5, 0.5, 0.5]), Vector2(1, 0))
	assert_almost_eq(at.x, -2.0, 1e-5)
	assert_almost_eq(at.y, -3.5, 1e-5)
	assert_eq(Map3DCommanderRider.left_rear_of(PackedVector2Array(), PackedFloat32Array(), Vector2(1, 0)), Vector2.ZERO)
	# his centre stands outside that: half a length (1.2 m of a 2.4 m horse) clear, then half his
	# 1 m width, at scale 2: (0.5 + 1.2) x 2 = 3.4 m; no gap: his flank on the file, 0.5 m
	assert_almost_eq(Map3DCommanderRider.side_m(0.5, 1.2, 0.5, 2.0), 3.4, 1e-5)
	assert_almost_eq(Map3DCommanderRider.side_m(0.5, 1.2, 0.0, 1.0), 0.5, 1e-5)


func test_his_ride_goes_round_the_left_flank_and_never_through_the_block() -> void:
	# facing -z: the block's left file ends at x = -10, its first rank's front is 5 ahead (z = -5),
	# its rear rank's back 4 behind (z = 4).
	# From ahead of the front (0, -8) to the left rear (-13, 3): out along the front to the corner
	# that is as far left as his place and as far ahead as he stands, (-13, -8), then down the flank.
	var face := Vector2(0, -1)
	var way := Map3DCommanderRider.route(Vector2(0, -8), Vector2(-13, 3), face, -10.0, 5.0, -4.0)
	assert_eq(way, PackedVector2Array([Vector2(-13, -8), Vector2(-13, 3)]))
	# and back by the same corner
	assert_eq(Map3DCommanderRider.route(Vector2(-13, 3), Vector2(0, -8), face, -10.0, 5.0, -4.0),
		PackedVector2Array([Vector2(-13, -8), Vector2(0, -8)]))
	# both ends outside the left file (a file lost beside him), or both ahead of the front: straight
	assert_eq(Map3DCommanderRider.route(Vector2(-13, 3), Vector2(-11, 1), face, -10.0, 5.0, -4.0), PackedVector2Array([Vector2(-11, 1)]))
	assert_eq(Map3DCommanderRider.route(Vector2(4, -8), Vector2(0, -6), face, -10.0, 5.0, -4.0), PackedVector2Array([Vector2(0, -6)]))
	# from behind the block on its right (3, 20) (his unit moved off ahead of him): along behind the
	# rear rank to the corner as far left as his place and as far back as he stands, then up the flank
	assert_eq(Map3DCommanderRider.route(Vector2(3, 20), Vector2(-13, 3), face, -10.0, 5.0, -4.0),
		PackedVector2Array([Vector2(-13, 20), Vector2(-13, 3)]))
	# from behind it to ahead of it: both corners, round the rear and up the whole left flank
	assert_eq(Map3DCommanderRider.route(Vector2(3, 20), Vector2(0, -8), face, -10.0, 5.0, -4.0),
		PackedVector2Array([Vector2(-10, 20), Vector2(-10, -8), Vector2(0, -8)]))
	# the corners keep a margin off the block (3 m): the same ride passes x = -13, not along the file
	assert_eq(Map3DCommanderRider.route(Vector2(3, 20), Vector2(0, -8), face, -10.0, 5.0, -4.0, 3.0),
		PackedVector2Array([Vector2(-13, 20), Vector2(-13, -8), Vector2(0, -8)]))
	# on its right, level with it, there is no way round its left: stood there at once
	assert_true(Map3DCommanderRider.route(Vector2(15, 0), Vector2(-13, 3), face, -10.0, 5.0, -4.0).is_empty())
	# a diagonal facing (0.6, 0.8), right (-0.8, 0.6); left file at -9 across, front 12 along, back 2.
	# From 15 along, 0 across = (9, 12) to -11 across, 6 along = (8.8 + 3.6, -6.6 + 4.8) = (12.4, -1.8):
	# the corner is -11 across, 15 along = (8.8 + 9, -6.6 + 12) = (17.8, 5.4)
	face = Vector2(0.6, 0.8)
	way = Map3DCommanderRider.route(Vector2(9, 12), Vector2(12.4, -1.8), face, -9.0, 12.0, 2.0)
	assert_eq(way.size(), 2)
	assert_almost_eq(way[0].x, 17.8, 1e-4)
	assert_almost_eq(way[0].y, 5.4, 1e-4)
	assert_almost_eq(way[1].x, 12.4, 1e-4)
	assert_almost_eq(way[1].y, -1.8, 1e-4)
	# every point of the ride is outside the left file or ahead of the first rank
	var across := Vector2(-face.y, face.x)
	var from := Vector2(9, 12)
	for corner: Vector2 in way:
		for i in 21:
			var p := from.lerp(corner, i / 20.0)
			assert_true(p.dot(across) <= -9.0 + 1e-4 or p.dot(face) >= 12.0 - 1e-4, str(p))
		from = corner


func test_a_frame_of_his_ride_turns_into_his_way_and_rides_as_far_as_he_faces_it() -> void:
	# turned -z (yaw 0) with his corner 10 m ahead: 3 m of it, no turn
	var rode := Map3DCommanderRider.ride(Vector2.ZERO, 0.0, PackedVector2Array([Vector2(0, -10)]), 0.0, 3.0, 1.0)
	assert_almost_eq((rode[0] as Vector2).y, -3.0, 1e-5)
	assert_almost_eq(float(rode[1]), 0.0, 1e-5)
	assert_eq((rode[2] as PackedVector2Array).size(), 1)
	# the last stretch (his place within two radii, 2 x 4 / 0.5 = 16 m) is ridden straight onto it,
	# only as far as he faces it. His place 10 m to the west (-x): its yaw is a quarter turn, +PI/2.
	# He may turn 0.5 rad: still PI/2 - 0.5 off, he rides cos(PI/2 - 0.5) = sin 0.5 = 0.479426 of 4 m
	rode = Map3DCommanderRider.ride(Vector2.ZERO, 0.0, PackedVector2Array([Vector2(-10, 0)]), 0.0, 4.0, 0.5)
	assert_almost_eq(float(rode[1]), 0.5, 1e-5)
	assert_almost_eq((rode[0] as Vector2).x, -1.917702, 1e-4)
	assert_almost_eq((rode[0] as Vector2).y, 0.0, 1e-5)
	# his corner dead behind him: he turns on the spot, and does not ride backwards
	rode = Map3DCommanderRider.ride(Vector2.ZERO, 0.0, PackedVector2Array([Vector2(0, 10)]), 0.0, 4.0, 0.5)
	assert_eq(rode[0], Vector2.ZERO)
	assert_almost_eq(absf(float(rode[1])), 0.5, 1e-5)
	# a corner with another beyond it is an arc, not a halt: half a metre short of it with 3 m to
	# ride he rides on the way he faces, 2.5 m past it, and it is passed (he is within his 3 m)
	rode = Map3DCommanderRider.ride(Vector2(0, -9.5), 0.0, PackedVector2Array([Vector2(0, -10), Vector2(-5, -10)]), 0.0, 3.0, 1.0)
	assert_eq(rode[0], Vector2(0, -12.5))
	assert_eq(rode[2], PackedVector2Array([Vector2(-5, -10)]))
	# far from his place (100 m to the west, more than two radii of 4 / 0.5 = 8 m) he rides where he
	# faces while he turns: 0.5 rad round, 4 m along (-sin 0.5, -cos 0.5) = (-1.917702, -3.510330)
	rode = Map3DCommanderRider.ride(Vector2.ZERO, 0.0, PackedVector2Array([Vector2(-100, 0)]), 0.0, 4.0, 0.5)
	assert_almost_eq(float(rode[1]), 0.5, 1e-5)
	assert_almost_eq((rode[0] as Vector2).x, -1.917702, 1e-4)
	assert_almost_eq((rode[0] as Vector2).y, -3.510330, 1e-4)
	# arrived: he turns to his facing, 0.25 rad of the 1 rad left
	rode = Map3DCommanderRider.ride(Vector2(-5, -10), 1.0, PackedVector2Array([Vector2(-5, -10)]), 0.0, 3.0, 0.25)
	assert_eq(rode[0], Vector2(-5, -10))
	assert_almost_eq(float(rode[1]), 0.75, 1e-5)
	assert_true((rode[2] as PackedVector2Array).is_empty())


## The fixture's field battle with its two lines `gap_m` further apart than its contact (3 km
## leaves both commanders their stand-off place; 0 none), the camera on it:
## {repo, state, ctx, layer, own, foe}.
func _field(gap_m: float) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := Scenario.contact(repo, 10)
	var foe := String(state.foes.keys()[0])
	var own := ""
	for code: String in state.regiments:
		if Vector2(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])).distance_to(
				Vector2(int(state.foes[foe]["x_m"]), int(state.foes[foe]["y_m"]))) < 2000:
			own = code
	assert_false(BattleSystem.discover_contacts(repo, state).is_empty())
	var away := Vector2(int(state.foes[foe]["x_m"]) - int(state.regiments[own]["x_m"]),
		int(state.foes[foe]["y_m"]) - int(state.regiments[own]["y_m"])).normalized() * gap_m
	for row: Dictionary in state.battles[0]["groups"][foe]:
		row["x_m"] = int(row["x_m"]) + int(away.x)
		row["y_m"] = int(row["y_m"]) + int(away.y)
	state.foes[foe]["x_m"] = int(state.foes[foe]["x_m"]) + int(away.x)
	state.foes[foe]["y_m"] = int(state.foes[foe]["y_m"]) + int(away.y)
	var ctx := _ctx(repo, state)
	var at := ctx.to_world(ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, own, state)))
	ctx.camera.position = Vector3(at.x, 500.0, at.y + 500.0)
	ctx.camera.look_at(Vector3(at.x, 0.0, at.y))
	return {"repo": repo, "state": state, "ctx": ctx, "layer": _layer(ctx), "own": own, "foe": foe}


## A battle piece's block where its figures STAND, in the frame of its facing from its root:
## {face, across, left (the left file's outside), rear (the rear rank's line), front (the first rank's front)}.
func _block(ctx: Map3DContext, piece: Dictionary) -> Dictionary:
	var face := WarFront.facing_vector(int(piece["facing_deg"]))
	var across := Vector2(-face.y, face.x)
	var root: Node3D = piece["node"]
	var out := {"face": face, "across": across, "left": INF, "rear": INF, "front": -INF}
	for group: Dictionary in piece["groups"]:
		var p := Map3DBattleGroups.stand_xz(ctx, piece, group) - Vector2(root.global_position.x, root.global_position.z)
		var reach: Vector2 = (group["piece"]["extent"] as Vector2) * (group["piece"]["node"] as Node3D).scale.x
		out["left"] = minf(out["left"], p.dot(across) - reach.x)
		out["rear"] = minf(out["rear"], p.dot(face))
		out["front"] = maxf(out["front"], p.dot(face) + reach.y)
	return out


## How far behind his rear rank's line he commands, world metres.
func _back(rider: Map3DCommanderRider) -> float:
	return rider._repo.bal("map3d_commander_rear_back") * 2.0 * rider._half.y * rider.global_basis.get_scale().x


## Where a rider is drawn from his piece's root, flat world metres.
func _from_root(rider: Node3D) -> Vector2:
	var root := rider.get_parent() as Node3D
	return Vector2(rider.global_position.x - root.global_position.x, rider.global_position.z - root.global_position.z)


## Rides `rider` on, a tenth of a second a frame, until he stands; every place he was drawn at.
## Each frame his walk's hooves keep the ground: a loop of MARCH_WALK at his clip's rate carries him
## its measured stride at his scale, so rate x 0.1 s x stride x k / clip length is the frame's ground
## (held at the slowest rate while he turns on the spot).
func _ride_out(rider: Map3DCommanderRider) -> PackedVector2Array:
	var trail := PackedVector2Array([_from_root(rider)])
	var pace := rider._repo.bal("map3d_commander_walk_stride_m") * rider.global_basis.get_scale().x / rider._clip_s("MARCH_WALK")
	var fastest := 0.0
	for i in 3000:
		if not rider.riding():
			break
		rider.stand(0.1)
		trail.append(_from_root(rider))
		if rider.riding():
			var ground := trail[-1].distance_to(trail[-2])
			assert_eq(_clip(rider), "MARCH_WALK")
			assert_almost_eq(rider._anim.speed_scale, clampf(ground / 0.1 / pace, rider._repo.bal("map3d_unit_anim_min"),
				rider._repo.bal("map3d_unit_anim_max")), 1e-3, "his hooves keep the ground he covers")
			fastest = maxf(fastest, rider._anim.speed_scale)
	assert_false(rider.riding(), "he arrives")
	# (his place is drawn in single-precision world metres, thousands from the origin: a part in a thousand)
	assert_almost_eq(fastest, rider._repo.bal("map3d_commander_ride_pace"), 0.01, "on the straight he rides at his ride's pace")
	return trail


func test_when_the_fight_begins_he_rides_round_the_left_flank_to_the_left_rear_and_commands() -> void:
	var f := _field(3000.0)
	var repo: DataRepository = f["repo"]
	var state: GameState = f["state"]
	var layer: Map3DLayerUnits = f["layer"]
	var gap := repo.bal("map3d_commander_rear_gap")
	var riders := {}
	for code: String in [f["own"], f["foe"]]:
		riders[code] = Map3DCommanderRider.of_piece(layer.built_piece(code))
		(riders[code] as Map3DCommanderRider).stand()
		assert_true((riders[code] as Node3D).visible, code + " stands before his block in the stand-off")
	state.battles[0]["rounds"] = 1  # the first round is fought
	var frozen := SaveLoad.state_hash(state)
	for code: String in [f["own"], f["foe"]]:
		var rider: Map3DCommanderRider = riders[code]
		var piece := layer.built_piece(code)
		var block := _block(f["ctx"], piece)
		var face: Vector2 = block["face"]
		var across: Vector2 = block["across"]
		var k := rider.global_basis.get_scale().x
		var start := _from_root(rider)
		rider.stand()  # the fight is seen: no time has passed, he has not moved
		assert_true(rider.visible, code)
		assert_true(rider.riding(), code + " sets off for the left rear")
		assert_almost_eq(_from_root(rider).distance_to(start), 0.0, 1e-3, "he rides from where he stood, never jumps")
		assert_eq(_clip(rider), "MARCH_WALK", "the ride is at the walk")
		var trail := _ride_out(rider)
		assert_gt(trail.size(), 10, "a ride, not a jump")
		for i in range(1, trail.size()):
			var p := trail[i]
			# round the LEFT flank: outside the left file or ahead of the first rank, by his half width at least
			assert_true(p.dot(across) <= float(block["left"]) - rider._half.x * k + 0.01
				or p.dot(face) >= float(block["front"]) + rider._half.x * k - 0.01, "%s at %s is through his own block" % [code, p])
			assert_lt(p.distance_to(trail[i - 1]), repo.bal("map3d_commander_ride_pace") * repo.bal("map3d_commander_walk_stride_m")
				* k / rider._clip_s("MARCH_WALK") * 0.1 + 0.01, "no frame outruns his walk")
		# arrived: outside the left file by his gap and half his width, level with the rear rank
		var at := _from_root(rider)
		assert_almost_eq(at.dot(across), float(block["left"]) - (rider._half.x + 2.0 * rider._half.y * gap) * k, 0.01, code + " is outside his left file")
		assert_almost_eq(at.dot(face), float(block["rear"]) - repo.bal("map3d_commander_rear_back") * 2.0 * rider._half.y * k, 0.01,
			code + " is behind his rear rank's line by his share of a length")
		var ahead := -rider.global_basis.z
		assert_almost_eq(Vector2(ahead.x, ahead.z).normalized().dot(face), 1.0, 1e-4, code + " faces the enemy with his unit")
		assert_eq(_clip(rider), "COMMAND")
		assert_eq(rider._anim.speed_scale, 1.0)
		assert_true(rider._anim.active)
		# no group is his, and a click on him there is a click on his unit
		assert_eq(int(piece["figures"]), (piece["groups"] as Array).size())
		assert_lt(Map3DPicker.ray_depth(piece, rider.global_position + Vector3.UP * 500.0, Vector3.DOWN), INF,
			code + ": a ray on him at the left rear meets his unit's piece")
		rider.visible = false
		assert_eq(Map3DPicker.ray_depth(piece, rider.global_position + Vector3.UP * 500.0, Vector3.DOWN), INF, "and nobody else stands there")
		rider.visible = true
		# his unit's figures stepping in and out of their duels (`easing`) never hide him in the fight
		piece["easing"] = true
		rider.stand(0.1)
		assert_true(rider.visible)
		assert_false(rider.riding())
		assert_almost_eq(_from_root(rider).distance_to(at), 0.0, 1e-3)
		piece["easing"] = false
	# the foe's commander is on HIS left, which is the crown's right: the two stand on opposite sides
	var own_block := _block(f["ctx"], layer.built_piece(f["own"]))
	var middle := ((layer.built_piece(f["own"])["node"] as Node3D).global_position + (layer.built_piece(f["foe"])["node"] as Node3D).global_position) * 0.5
	var sides: Array = [f["own"], f["foe"]].map(func(code: String) -> float:
		var p: Vector3 = (riders[code] as Node3D).global_position - middle
		return Vector2(p.x, p.z).dot(own_block["across"]))
	assert_lt(float(sides[0]), 0.0, "the crown's commander on the crown's left")
	assert_gt(float(sides[1]), 0.0, "the foe's on his own left, seen facing the crown")
	assert_eq(SaveLoad.state_hash(state), frozen, "the ride and the command change nothing saved")
	# the fight over (the battle gone, the block still standing): he rides back to the front
	state.battles.clear()
	var rider: Map3DCommanderRider = riders[f["own"]]
	var piece := layer.built_piece(f["own"])
	rider.stand()
	assert_true(rider.riding(), "he rides back")
	var back := _ride_out(rider)
	for p: Vector2 in back:
		assert_true(p.dot(own_block["across"]) <= float(own_block["left"]) - rider._half.x * rider.global_basis.get_scale().x + 0.01
			or p.dot(own_block["face"]) >= float(own_block["front"]) + rider._half.x * rider.global_basis.get_scale().x - 0.01, str(p))
	var lead := rider._half.y * (1.0 + 2.0 * repo.bal("map3d_commander_gap")) * rider.global_basis.get_scale().x
	assert_almost_eq(_from_root(rider).dot(own_block["face"]), _reach(piece, piece["node"], own_block["face"]) + lead, 0.01, "ahead of the first rank again")
	assert_eq(_clip(rider), "STANDBY")


func test_in_the_fight_he_keeps_with_a_block_walking_to_new_points_and_not_with_its_duellists() -> void:
	var f := _field(3000.0)
	var repo: DataRepository = f["repo"]
	(f["state"] as GameState).battles[0]["rounds"] = 1
	var layer := _layer(f["ctx"])
	var piece := layer.built_piece(f["own"])
	var rider := Map3DCommanderRider.of_piece(piece)
	rider.stand(0.1)  # first seen in the fight: at the left rear
	var home := rider.global_position
	var face := WarFront.facing_vector(int(piece["facing_deg"]))
	var along := Vector3(face.x, 0.0, face.y)
	var across := Vector3(-face.y, 0.0, face.x)
	# every figure gone into its duel 30 m to the right: the block is where they STAND, he stays
	for group: Dictionary in piece["groups"]:
		(group["piece"]["anims"][0] as AnimationPlayer).set_meta("duel", true)
		(group["piece"]["node"] as Node3D).global_position += across * 30.0
	for i in 5:
		rider.stand(0.1)
	assert_false(rider.riding(), "duellists out of their places do not move him")
	assert_almost_eq(rider.global_position.distance_to(home), 0.0, 1e-3)
	for group: Dictionary in piece["groups"]:
		(group["piece"]["anims"][0] as AnimationPlayer).remove_meta("duel")
		(group["piece"]["node"] as Node3D).global_position -= across * 30.0
	# the block walks to new points, 2 m a frame ahead for 40 frames: he walks with it, never jumps.
	# 0.1 s of his ride at his scale is the most ground a frame may cover.
	var k := rider.global_basis.get_scale().x
	var top := repo.bal("map3d_commander_ride_pace") * repo.bal("map3d_commander_walk_stride_m") * k / rider._clip_s("MARCH_WALK") * 0.1
	assert_gt(top, 2.0, "he can keep up with a 2 m frame")
	var last := rider.global_position
	for i in 40:
		for group: Dictionary in piece["groups"]:
			(group["piece"]["node"] as Node3D).global_position += along * 2.0
		rider.stand(0.1)
		assert_lt(Vector2(rider.global_position.x - last.x, rider.global_position.z - last.z).length(), top + 0.01, "frame %d" % i)
		last = rider.global_position
	assert_true(rider.riding(), "he is walking with his block")
	assert_eq(_clip(rider), "MARCH_WALK")
	# caught up, he covers the block's 2 m a frame: his hooves at 20 m/s over his walk's own pace
	assert_almost_eq(rider._anim.speed_scale, 20.0 / (repo.bal("map3d_commander_walk_stride_m") * k / rider._clip_s("MARCH_WALK")), 1e-3)
	# the block stands: he is at its left rear again, 80 m on, and commands
	for i in 20:
		rider.stand(0.1)
	assert_false(rider.riding())
	assert_eq(_clip(rider), "COMMAND")
	var moved := rider.global_position - home
	assert_almost_eq(Vector2(moved.x, moved.z).dot(face), 80.0, 0.01)
	assert_almost_eq(Vector2(moved.x, moved.z).dot(Vector2(-face.y, face.x)), 0.0, 0.01)
	# a block creeping on, slower than his walk can play (0.5 m a frame: 5 m/s under 0.3 of his pace):
	# he lets it go and commands, and rides after it once it is a quarter of his length off
	assert_lt(5.0, repo.bal("map3d_unit_anim_min") * repo.bal("map3d_commander_walk_stride_m") * k / rider._clip_s("MARCH_WALK"))
	var rides := 0
	var stands := 0
	for i in 60:
		for group: Dictionary in piece["groups"]:
			(group["piece"]["node"] as Node3D).global_position += (along + across).normalized() * 0.5  # off his facing
		rider.stand(0.1)
		rides += 1 if rider.riding() else 0
		stands += 1 if _clip(rider) == "COMMAND" else 0
	assert_gt(stands, 30, "he commands most of the creep")
	assert_gt(rides, 0, "and catches his block up")
	for i in 20:
		rider.stand(0.1)
	assert_false(rider.riding())
	# the block's root re-anchored (its unit's place moved at a day's end, its figures still where
	# they were): he keeps his own ground, not the root's
	var root: Node3D = piece["node"]
	var was := rider.global_position
	var spots: Array = (piece["groups"] as Array).map(func(group: Dictionary) -> Vector3: return (group["piece"]["node"] as Node3D).global_position)
	root.global_position += Vector3(160.0, 0.0, -290.0)
	for i in spots.size():
		(piece["groups"][i]["piece"]["node"] as Node3D).global_position = spots[i]
	rider.stand(0.1)
	assert_almost_eq(Vector2(rider.global_position.x - was.x, rider.global_position.z - was.z).length(), 0.0, 0.01, "no jump with the root")
	assert_false(rider.riding())
	# a place under a quarter of his length away does not move him
	for group: Dictionary in piece["groups"]:
		(group["piece"]["node"] as Node3D).global_position += along * 0.1 * 2.0 * rider._half.y * k
	var held := rider.global_position
	rider.stand(0.1)
	assert_false(rider.riding())
	assert_almost_eq(rider.global_position.distance_to(held), 0.0, 1e-3, "a shuffle that small is not ridden")


func test_no_ride_after_a_state_swap_or_from_nowhere() -> void:
	# a save loaded mid-fight over a view standing in the stand-off: he is at the left rear at once
	var f := _field(3000.0)
	var layer: Map3DLayerUnits = f["layer"]
	var rider := Map3DCommanderRider.of_piece(layer.built_piece(f["own"]))
	rider.stand()
	assert_true(rider.visible)
	var loaded := Scenario.roundtrip(f["state"])
	loaded.battles[0]["rounds"] = 3
	(f["ctx"] as Map3DContext).state_fn = func() -> GameState: return loaded
	rider.stand(0.1)
	assert_false(rider.riding(), "a loaded save rides nobody")
	assert_eq(_clip(rider), "COMMAND")
	var block := _block(f["ctx"], layer.built_piece(f["own"]))
	assert_almost_eq(_from_root(rider).dot(block["face"]), float(block["rear"]) - _back(rider), 0.01)
	assert_lt(_from_root(rider).dot(block["across"]), float(block["left"]))
	# a unit first seen mid-fight: the same
	f = _field(3000.0)
	(f["state"] as GameState).battles[0]["rounds"] = 2
	layer = _layer(f["ctx"])
	for code: String in [f["own"], f["foe"]]:
		rider = Map3DCommanderRider.of_piece(layer.built_piece(code))
		assert_false(rider.visible, "unseen until he stands")
		rider.stand(0.1)
		assert_true(rider.visible)
		assert_false(rider.riding(), code + " is stood at his place")
		assert_eq(_clip(rider), "COMMAND")
		block = _block(f["ctx"], layer.built_piece(code))
		assert_almost_eq(_from_root(rider).dot(block["face"]), float(block["rear"]) - _back(rider), 0.01)
	# a stand-off too tight to draw him: when the fight starts he appears at the left rear
	f = _field(0.0)
	layer = f["layer"]
	rider = Map3DCommanderRider.of_piece(layer.built_piece(f["own"]))
	# even one handed the place of the marching block's rider (a block gone into its battle): he was
	# not drawn in between, so that place is forgotten
	rider._from = [Vector2(rider.global_position.x, rider.global_position.z) + Vector2(300.0, 0.0), 0.0]
	rider._state = f["state"]
	rider.stand(0.1)
	assert_false(rider.visible, "lines this close leave him no place")
	(f["state"] as GameState).battles[0]["rounds"] = 1
	rider.stand(0.1)
	assert_true(rider.visible)
	assert_false(rider.riding(), "no ride from nowhere")
	block = _block(f["ctx"], layer.built_piece(f["own"]))
	assert_almost_eq(_from_root(rider).dot(block["face"]), float(block["rear"]) - _back(rider), 0.01)
	# hidden with his piece mid-ride (the far zoom's symbols), shown again: stood at his place
	f = _field(3000.0)
	layer = f["layer"]
	rider = Map3DCommanderRider.of_piece(layer.built_piece(f["own"]))
	rider.stand()
	(f["state"] as GameState).battles[0]["rounds"] = 1
	rider.stand(0.1)
	rider.stand(0.1)
	assert_true(rider.riding())
	(layer.built_piece(f["own"])["node"] as Node3D).visible = false
	rider.stand(0.1)
	assert_false(rider._anim.active)
	(layer.built_piece(f["own"])["node"] as Node3D).visible = true
	rider.stand(0.1)
	assert_false(rider.riding())
	assert_eq(_clip(rider), "COMMAND")


func test_out_of_the_battle_he_rides_back_to_the_front_of_the_new_block() -> void:
	var f := _field(3000.0)
	var repo: DataRepository = f["repo"]
	var state: GameState = f["state"]
	var layer: Map3DLayerUnits = f["layer"]
	var own := String(f["own"])
	state.battles[0]["rounds"] = 1
	var old := Map3DCommanderRider.of_piece(layer.built_piece(own))
	old.stand(0.1)  # first seen in the fight: at the left rear
	var stood := old.global_position
	var facing := int(layer.built_piece(own)["facing_deg"])
	# the battle over: the unit stands as an ordinary block again, facing the way it fought
	state.battles.clear()
	state.regiments[own]["facing_deg"] = facing
	var frozen := SaveLoad.state_hash(state)
	layer.refresh()
	var piece := layer.built_piece(own)
	assert_ne(String(piece.get("layout", "")), "physical_groups")
	var rider := Map3DCommanderRider.of_piece(piece)
	assert_ne(rider, old, "the new block's own rider")
	rider.stand()
	assert_true(rider.visible)
	assert_true(rider.riding(), "he rides on from where the battle left him")
	assert_almost_eq(Vector2(rider.global_position.x - stood.x, rider.global_position.z - stood.z).length(), 0.0, 0.01)
	var root: Node3D = piece["node"]
	var k := rider.global_basis.get_scale().x
	var left := INF
	var right := -INF
	var front_z := INF
	for slot: Vector3 in piece["slots"]:
		left = minf(left, slot.x)
		right = maxf(right, slot.x)
		front_z = minf(front_z, slot.z)
	var extent: Vector2 = piece["figure_extent"]
	for i in 3000:
		if not rider.riding():
			break
		rider.stand(0.1)
		# in the block's own frame (front -z): outside its left file or ahead of its first rank
		assert_true(rider.position.x <= left - extent.x + 1e-3 or rider.position.z <= front_z - extent.y - 1e-3 + 2e-3, str(rider.position))
	assert_false(rider.riding(), "he arrives")
	var lengths := 1.0 + 2.0 * repo.bal("map3d_commander_gap")
	assert_almost_eq(rider.position.x, (left + right) * 0.5, 1e-3, "centred on the files")
	assert_almost_eq(rider.position.z, front_z - extent.y - rider._half.y * lengths * k / root.scale.x, 1e-3, "ahead of the first rank")
	assert_almost_eq(rider.rotation.y, 0.0, 1e-4, "facing his unit's way")
	assert_eq(_clip(rider), "STANDBY")
	assert_eq(SaveLoad.state_hash(state), frozen)
	# the same exit under a loaded save: nobody rides
	f = _field(3000.0)
	state = f["state"]
	layer = f["layer"]
	state.battles[0]["rounds"] = 1
	Map3DCommanderRider.of_piece(layer.built_piece(own)).stand(0.1)
	var loaded := Scenario.roundtrip(state)
	loaded.battles.clear()
	(f["ctx"] as Map3DContext).state_fn = func() -> GameState: return loaded
	layer.refresh()
	rider = Map3DCommanderRider.of_piece(layer.built_piece(own))
	assert_ne(String(layer.built_piece(own).get("layout", "")), "physical_groups")
	rider.stand(0.1)
	assert_true(rider.visible)
	assert_false(rider.riding(), "a loaded save stands him at the front at once")
	assert_almost_eq(rider.rotation.y, 0.0, 1e-4)



## The farthest a battle piece's drawn figures reach along `face` from `root` (their far sides).
func _reach(piece: Dictionary, root: Node3D, face: Vector2) -> float:
	var out := -INF
	for group: Dictionary in piece["groups"]:
		var node: Node3D = group["piece"]["node"]
		out = maxf(out, Vector2(node.global_position.x - root.global_position.x,
			node.global_position.z - root.global_position.z).dot(face) + float(group["piece"]["extent"].y) * node.scale.x)
	return out
