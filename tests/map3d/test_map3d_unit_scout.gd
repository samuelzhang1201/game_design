extends GutTest
## The scouting fan on the 3D map (spec 2026-10-14-unit-clearance-and-scouting-
## design (d)): a marching crown land unit with men draws a faint sector on the
## ground ahead of its piece (Map3DUnitScout), at the radius the engine sweeps
## (30 km cavalry, 15 km infantry, at 50 m a pack px over 1000 m a pack px),
## across the arc of +-60 degrees about its heading. Never a standing unit's,
## a foe's, a ghost's. Hand-computed: 30000 x 50 / 1000 = 1500, 15000 -> 750.

const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_unit_scout").path_join("test_map3d_unit_scout_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()
	Map3DView.world_override = _fixture


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _crown() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(Game.data, r) > 0:
			out.append(String(r["regiment_code"]))
	return out


func test_world_radius_is_the_engines_metres_over_the_packs_scale() -> void:
	var repo := SuiteData.repo()
	assert_eq(ArmySystem.metres_per_pack_px(repo), 1000, "the pack's measure")
	assert_almost_eq(Map3DUnitScout.world_radius(repo, WORLD, 30000), 1500.0, 0.001, "cavalry")
	assert_almost_eq(Map3DUnitScout.world_radius(repo, WORLD, 15000), 750.0, 0.001, "infantry")
	assert_eq(int((repo.army_scouting["cavalry"] as Dictionary)["scout_km"]), 30)
	assert_eq(int((repo.army_scouting["infantry"] as Dictionary)["scout_km"]), 15)


func test_the_mesh_is_a_polar_grid_from_its_apex_across_the_arc() -> void:
	var flat := func(_xz: Vector2) -> float: return 7.0
	var rings := 6
	var spokes := 24
	var half := deg_to_rad(60.0)
	var yaw := 0.8
	var at := Vector2(1000.0, -500.0)
	var mesh := Map3DUnitScout.mesh_of(flat, at, yaw, 1500.0, half, rings, spokes, 4.0)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(verts.size(), (rings + 1) * (spokes + 1), "(rings+1)(spokes+1) vertices")
	for j in spokes + 1:
		assert_almost_eq(Vector2(verts[j].x, verts[j].z).length(), 0.0, 0.0001, "ring 0 is the apex, at the centre")
		assert_almost_eq(verts[j].y, 11.0, 0.0001, "on the ground plus the lift")
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y))
	var heading := Vector2(-sin(yaw), -cos(yaw))
	var left := xf * verts[rings * (spokes + 1)]
	var right := xf * verts[rings * (spokes + 1) + spokes]
	var mid := xf * verts[rings * (spokes + 1) + spokes / 2]
	for p: Vector3 in [left, right, mid]:
		assert_almost_eq((Vector2(p.x, p.z) - at).length(), 1500.0, 0.01, "the rim is at the radius")
	assert_almost_eq(rad_to_deg(heading.angle_to(Vector2(mid.x, mid.z) - at)), 0.0, 0.01, "the middle spoke is the heading")
	assert_almost_eq(absf(rad_to_deg(heading.angle_to(Vector2(left.x, left.z) - at))), 60.0, 0.01, "the rim spans heading +-60")
	assert_almost_eq(absf(rad_to_deg(heading.angle_to(Vector2(right.x, right.z) - at))), 60.0, 0.01)
	assert_almost_eq(uvs[0].y, 0.0, 0.0001, "v is the radius share")
	assert_almost_eq(uvs[rings * (spokes + 1)].y, 1.0, 0.0001)
	assert_almost_eq(uvs[0].x, -1.0, 0.0001, "u is the arc share")
	assert_almost_eq(uvs[spokes].x, 1.0, 0.0001)


func test_the_mesh_is_draped_on_a_slope() -> void:
	var slope := func(xz: Vector2) -> float: return 0.1 * xz.x
	var at := Vector2(200.0, 0.0)
	var mesh := Map3DUnitScout.mesh_of(slope, at, 0.0, 800.0, deg_to_rad(60.0), 4, 8, 2.0)
	for v: Vector3 in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		assert_almost_eq(v.y, 0.1 * (at.x + v.x) + 2.0, 0.001, "on the slope's own face")


func test_only_a_marching_crown_unit_gets_a_fan() -> void:
	var v := _view()
	v.set_military(true)
	var units := v._units as Map3DLayerUnits
	var codes := _crown()
	assert_gt(codes.size(), 1)
	var code: String = codes[0]
	var r := ArmySystem.regiment(Game.data, code, Game.state)
	v.look_at_pack(Vector2(float(r["x"]), float(r["y"])), Map3DGeometry.distance_for_bar(Game.data, v._ctx.meta, Game.data.bal("map3d_unit_symbol_leave_scale") * 0.5, v._ctx.view_size.y))
	Game.state.regiments[code]["order"] = ArmySystem.ORDER_STANDBY
	units.step(0.0)
	assert_eq(units.scout_codes(), [], "a standing crown unit sweeps nothing")
	var here := ArmySystem.pack_to_metres(Game.data, Vector2(float(r["x"]), float(r["y"])))
	ArmySystem.set_march_m(Game.data, Game.state, code, here + Vector2i(40000, 0))
	units.step(0.0)
	assert_eq(units.scout_codes(), [code], "a marching one has its fan, and only it")
	var fan := units.get_node_or_null(Map3DUnitScout.PREFIX + code.replace(":", "_")) as MeshInstance3D
	assert_not_null(fan, "a sibling of the pieces under the Units node")
	assert_eq(fan.material_override, Map3DUnitScout.MATERIAL, "its look is the .tres")
	assert_null(fan.owner, "never saved")
	assert_almost_eq(float(fan.get_instance_shader_parameter("half_arc")), deg_to_rad(60.0), 0.0001)
	assert_eq(float(fan.get_instance_shader_parameter("phase")), Map3DUnitScout.phase_of(code), "phase hashed from the code")
	Game.state.regiments[code]["order"] = ArmySystem.ORDER_STANDBY
	units.step(0.0)
	assert_eq(units.scout_codes(), [], "it stops, the fan goes")
	ArmySystem.set_march_m(Game.data, Game.state, code, here + Vector2i(40000, 0))
	units.step(0.0)
	units.set_shown(false)
	assert_eq(units.scout_codes(), [], "a put-away view stands no fan")


func test_a_seen_foe_gets_no_fan() -> void:
	var v := _view()
	v.set_military(true)
	var units := v._units as Map3DLayerUnits
	var crown := _crown()
	var r := ArmySystem.regiment(Game.data, crown[0], Game.state)
	v.look_at_pack(Vector2(float(r["x"]), float(r["y"])), 2500.0)
	for code: Variant in Game.state.foes:
		(Game.state.foes[code] as Dictionary)["order"] = ArmySystem.ORDER_MARCH
	units.step(0.0)
	for code: String in units.scout_codes():
		assert_false(Game.state.foes.has(code), "%s is a foe" % code)
	assert_eq(Sighting.scout_shape(Game.data, Game.state, String(Game.state.foes.keys()[0]) if not Game.state.foes.is_empty() else "x"), {})


func test_the_fan_is_redraped_only_past_a_move_or_a_turn() -> void:
	var repo := SuiteData.repo()
	var host := Node3D.new()
	add_child_autofree(host)
	var flat := func(_xz: Vector2) -> float: return 0.0
	var s := Map3DUnitScout.new()
	var want := {"A": {"at": Vector2(0, 0), "yaw": 0.0, "r_m": 15000, "arc_deg": 120}}
	s.sync(host, flat, repo, WORLD, want, 6, 24, 4.0, 150.0, 3.0)
	var node := s.fan_node("A")
	var mesh := node.mesh
	want["A"]["at"] = Vector2(100, 0)
	s.sync(host, flat, repo, WORLD, want, 6, 24, 4.0, 150.0, 3.0)
	assert_same(node.mesh, mesh, "100 m is under the redrape distance")
	want["A"]["at"] = Vector2(200, 0)
	s.sync(host, flat, repo, WORLD, want, 6, 24, 4.0, 150.0, 3.0)
	assert_not_same(node.mesh, mesh, "200 m is past it")
	mesh = node.mesh
	want["A"]["yaw"] = deg_to_rad(5.0)
	s.sync(host, flat, repo, WORLD, want, 6, 24, 4.0, 150.0, 3.0)
	assert_not_same(node.mesh, mesh, "5 degrees is past the redrape angle")
	s.sync(host, flat, repo, WORLD, {}, 6, 24, 4.0, 150.0, 3.0)
	assert_eq(s.codes(), [], "a unit no longer wanted loses its fan")
