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


func _part(name: String) -> MeshInstance3D:
	return fig.parts_root().find_child(name, true, false) as MeshInstance3D


func test_parts_fly_straight_out_from_the_centre() -> void:
	var offs := WarExplode.offsets({"helmet": Vector3(0, 2, 0), "shield": Vector3(-1, 1, 0), "core": Vector3(0, 1, 0)},
		Vector3(0, 1, 0), 0.5)
	assert_almost_eq((offs["helmet"] as Vector3).y, 0.5, 0.0001)
	assert_almost_eq((offs["shield"] as Vector3).x, -0.5, 0.0001)
	assert_almost_eq((offs["core"] as Vector3).y, 0.5, 0.0001, "a part at the centre goes up")


func test_archers_take_the_spearmans_parts() -> void:
	assert_eq(WarExplode.parts_path("archers"), WarExplode.parts_path("infantry"))
	assert_eq(WarExplode.parts_path("infantry"), "res://assets/3D/units/infantry/infantry_parts.glb")


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
