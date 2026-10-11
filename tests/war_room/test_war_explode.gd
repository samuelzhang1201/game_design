extends GutTest
## The exploded kit (spec 2026-10-01-war-room-design §4): each part of an arm's
## static parts model flies straight out from the figure's centre.

var fig: WarInkFigure


func before_each() -> void:
	Game.start_campaign(42)
	var panel: Control = load("res://scenes/war_room/war_folio.tscn").instantiate()
	panel.size = Vector2(1000, 640)
	add_child_autofree(panel)
	fig = panel.get_node("%Figure") as WarInkFigure


## A stand-in parts scene: named boxes where an infantryman's kit would stand.
func _parts_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Parts"
	var spots := {"helmet": Vector3(0, 1.7, 0), "cuirass": Vector3(0, 1.2, 0),
		"shield": Vector3(-0.5, 1.1, 0), "spear": Vector3(0.5, 1.2, 0)}
	for n: String in spots:
		var m := MeshInstance3D.new()
		m.name = n
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.2
		m.mesh = box
		m.position = spots[n]
		root.add_child(m)
		m.owner = root
	var ps := PackedScene.new()
	assert_eq(ps.pack(root), OK)
	root.free()
	return ps


func _part(part_name: String) -> MeshInstance3D:
	return fig.parts_root().find_child(part_name, true, false) as MeshInstance3D


func test_parts_fly_straight_out_from_the_centre() -> void:
	var offs := WarExplode.offsets({"helmet": Vector3(0, 2, 0), "shield": Vector3(-1, 1, 0), "core": Vector3(0, 1, 0)},
		Vector3(0, 1, 0), 0.5)
	assert_almost_eq((offs["helmet"] as Vector3).y, 0.5, 0.0001)
	assert_almost_eq((offs["shield"] as Vector3).x, -0.5, 0.0001)
	assert_almost_eq((offs["core"] as Vector3).y, 0.5, 0.0001, "a part at the centre goes up")


func test_archers_do_not_borrow_the_spearmans_parts() -> void:
	assert_ne(WarExplode.parts_path("archers"), WarExplode.parts_path("infantry"), "Ruling 23")
	assert_false(ResourceLoader.exists(WarExplode.parts_path("archers")), "no take-apart until they have their own model")
	assert_eq(WarExplode.parts_path("infantry"), "res://assets/3D/units/infantry/infantry_parts.glb")


## The owner's Blender export: every installed arm's parts file holds one
## object per war_equipment.csv row of that arm, named exactly by its `part`.
func test_the_real_parts_files_carry_every_kit_row() -> void:
	for arm: String in ["infantry", "cavalry"]:
		var path := WarExplode.parts_path(arm)
		assert_true(ResourceLoader.exists(path), "%s's parts are installed" % arm)
		var root := (load(path) as PackedScene).instantiate() as Node3D
		var names: Array[String] = []
		for m: MeshInstance3D in Map3DUnits.meshes(root):
			names.append(String(m.name))
		var rows := WarFolio.kit_of(Game.data, arm)
		assert_gt(rows.size(), 0)
		for row: Dictionary in rows:
			assert_true(names.has(String(row["part"])), "%s has its %s" % [arm, row["part"]])
		assert_eq(names.size(), rows.size(), "%s: no part the kit does not name (%s)" % [arm, names])
		root.free()


func test_the_real_parts_fly_apart_in_the_figure() -> void:
	for arm: String in ["infantry", "cavalry"]:
		assert_true(fig.show_parts(Game.data, arm), arm)
		assert_eq(fig.part_labels().size(), WarFolio.kit_of(Game.data, arm).size(), "%s: a label per part" % arm)
		var helm := _part("helmet")
		var home := helm.position
		fig.explode(1.0)
		assert_almost_eq((helm.position - home).length(), Game.data.bal("war_explode_m"), 0.0001)
		assert_gt(helm.position.y, home.y, "%s: the helmet flies up" % arm)
		fig.show_drill()


func test_a_missing_parts_file_shows_nothing() -> void:
	assert_false(fig.show_parts(Game.data, "artillery"))
	assert_null(fig.parts_root())


func test_the_parts_sit_assembled_then_fly_apart_and_come_back() -> void:
	assert_true(fig.show_parts_from(Game.data, "infantry", _parts_scene()))
	var home := _part("shield").position
	assert_eq(home, Vector3(-0.5, 1.1, 0), "assembled: every part where the kit stands")
	fig.explode(1.0)
	var moved := _part("shield").position - home
	assert_almost_eq(moved.length(), Game.data.bal("war_explode_m"), 0.0001, "a full explosion is war_explode_m")
	assert_lt(moved.x, 0.0, "the shield flies out to the side it stood on")
	assert_gt((_part("helmet").position - Vector3(0, 1.7, 0)).y, 0.0, "the helmet flies up")
	fig.explode(0.5)
	assert_almost_eq((_part("shield").position - home).length(), Game.data.bal("war_explode_m") * 0.5, 0.0001)
	fig.explode(0.0)
	assert_eq(_part("shield").position, home)


func test_each_kit_row_that_names_a_part_gets_its_label() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	var texts: Array[String] = []
	for l: Label3D in fig.part_labels():
		texts.append(l.text)
	for row: Dictionary in WarFolio.kit_of(Game.data, "infantry"):
		var present := _part(String(row["part"])) != null
		assert_eq(texts.has(String(row["label"])), present, "%s labelled iff its part exists" % row["part"])
	assert_eq(texts.size(), 4, "helmet, cuirass, shield and spear of the stand-in")


func test_the_labels_appear_as_the_parts_fly_out() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	for l: Label3D in fig.part_labels():
		assert_eq(l.modulate.a, 0.0, "no label on the assembled kit")
	fig.explode(1.0)
	for l: Label3D in fig.part_labels():
		assert_eq(l.modulate.a, 1.0)


func test_the_parts_are_drawn_in_ink() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	assert_true(_part("helmet").material_override is ShaderMaterial)


func test_the_drill_comes_back_and_the_parts_go() -> void:
	fig.show_arm(Game.data, "infantry")
	var cam := fig.get_node("%FigCamera") as Camera3D
	var before := cam.transform
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	assert_ne(cam.transform, before, "the camera frames the kit")
	fig.show_drill()
	assert_null(fig.parts_root())
	assert_eq(cam.transform, before, "the camera is back on the figure")
	assert_true(fig.model_visible())


func _to_root(m: Node3D) -> Vector3:
	return (fig.parts_root().global_transform.affine_inverse() * m.global_transform).origin


func test_each_labelled_part_has_a_leader_line_from_its_centre_to_its_label() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	fig.explode(1.0)
	for row: Dictionary in WarFolio.kit_of(Game.data, "infantry"):
		var part := String(row["part"])
		if _part(part) == null:
			continue
		var ends := fig.leader_ends(part)
		assert_eq(ends.size(), 2, "%s has a line" % part)
		var label := fig.parts_root().find_child("Label_" + part, true, false) as Label3D
		assert_almost_eq(ends[0].distance_to(_part(part).position), 0.0, 0.0001, "starts at the part's centre (a box about its origin)")
		assert_almost_eq(ends[1].distance_to(label.position), 0.0, 0.0001, "ends at its label")
		var line := fig.parts_root().find_child("Leader_" + part, true, false) as MeshInstance3D
		assert_not_null(line)
		assert_eq(((line.mesh as ImmediateMesh).get_surface_count()), 1, "and it is drawn")
		var mat := line.material_override as StandardMaterial3D
		assert_true(mat.no_depth_test)
		assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(fig.leader_ends("nothing").size(), 0)


func test_the_line_follows_the_flight() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	fig.explode(0.5)
	var half := fig.leader_ends("shield")
	fig.explode(1.0)
	var full := fig.leader_ends("shield")
	assert_gt(full[0].distance_to(full[1]) + 0.0001, 0.0)
	assert_ne(half[0], full[0])


func test_a_label_carries_its_note_in_a_smaller_line_under_the_name() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	fig.explode(1.0)
	var notes := fig.note_labels()
	assert_eq(notes.size(), 4)
	var shield_note := fig.parts_root().find_child("Note_shield", true, false) as Label3D
	var name_label := fig.parts_root().find_child("Label_shield", true, false) as Label3D
	var want := ""
	for row: Dictionary in WarFolio.kit_of(Game.data, "infantry"):
		if String(row["part"]) == "shield":
			want = String(row["note"])
	assert_ne(want, "")
	assert_eq(shield_note.text, want)
	assert_lt(shield_note.font_size, name_label.font_size, "smaller")
	assert_lt(shield_note.position.y, name_label.position.y, "under the name")


func test_nested_parts_are_measured_and_flown_in_the_roots_space() -> void:
	var root := Node3D.new()
	var group := Node3D.new()
	group.name = "Group"
	group.position = Vector3(0, 1, 0)
	group.scale = Vector3.ONE * 2.0
	root.add_child(group)
	group.owner = root
	var ps := PackedScene.new()
	for spot: Array in [["helmet", Vector3(0, 0.5, 0)], ["shield", Vector3(-0.5, 0, 0)]]:
		var m := MeshInstance3D.new()
		m.name = spot[0]
		m.mesh = BoxMesh.new()
		m.position = spot[1]
		group.add_child(m)
		m.owner = root
	ps.pack(root)
	root.free()
	assert_true(fig.show_parts_from(Game.data, "infantry", ps))
	var home := _to_root(_part("shield"))
	fig.explode(1.0)
	var moved := _to_root(_part("shield")) - home
	assert_almost_eq(moved.length(), Game.data.bal("war_explode_m"), 0.0001, "the flight is war_explode_m in the root's space, not the group's doubled one")
	assert_lt(moved.x, 0.0)


func test_a_resize_re_pitches_the_kits_hatching_and_the_frame_matches_the_drill() -> void:
	fig.show_parts_from(Game.data, "infantry", _parts_scene())
	var mat: ShaderMaterial = fig._parts_mat
	var before := float(mat.get_shader_parameter("stroke_px"))
	assert_almost_eq(before, Game.data.bal("war_figure_stroke_px") * fig.window_scale(), 0.0001)
	fig._stroke_px = 11.0
	fig._fit_viewport()
	assert_almost_eq(float(mat.get_shader_parameter("stroke_px")), 11.0 * fig.window_scale(), 0.0001)
	assert_almost_eq((fig.get_node("%FigCamera") as Camera3D).fov, Game.data.bal("war_figure_fov"), 0.0001)


## The names stand in two columns beside the flown-apart kit as the camera
## sees it, never over it, and no two in a column overlap.
func test_the_names_flank_the_kit_and_never_overlap() -> void:
	assert_true(fig.show_parts(Game.data, "infantry"))
	fig.explode(1.0)
	var cam := fig.get_node("%FigCamera") as Camera3D
	var right := cam.global_transform.basis.x
	var lo := INF
	var hi := -INF
	for m: MeshInstance3D in Map3DUnits.meshes(fig.parts_root()):
		if String(m.name).begins_with("Leader_"):
			continue
		var a := m.global_transform * m.get_aabb()
		for i in 8:
			lo = minf(lo, a.get_endpoint(i).dot(right))
			hi = maxf(hi, a.get_endpoint(i).dot(right))
	var ys := {}
	for l: Label3D in fig.part_labels():
		var x := l.global_position.dot(right)
		assert_true(x >= hi or x <= lo, "%s stands beside the kit (%.3f, kit %.3f..%.3f)" % [l.text, x, lo, hi])
		var side := 1 if x >= hi else -1
		for y: float in ys.get(side, []):
			assert_gt(absf(y - l.global_position.y), Game.data.bal("war_explode_label_px") * Game.data.bal("war_explode_label_pixel_m"),
				"%s keeps clear of its neighbour" % l.text)
		ys[side] = (ys.get(side, []) as Array) + [l.global_position.y]

