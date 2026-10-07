extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The supposed pieces on the table (spec 2026-10-07-war-room-annotations-and-
## planning-pieces §1.3): the arm's carved piece in boxwood on the side's
## lacquer, a pencilled tag, built and freed with the plans, carried by a drag.

var repo: DataRepository
var state: GameState
var view: WarRoomView
var plans: WarPlanPieces


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()
	view = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 600)
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)
	plans = view.get_node_or_null("%PlanPieces")
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)


## A land point on the laid sheet, near our first piece.
func _land() -> Vector2:
	return WarRoom.pieces(repo, state)[0]["at"] + Vector2(6, 4)


func _foreign() -> String:
	return String(WarPlans.sides(repo)[0])


func test_the_view_holds_a_plan_pieces_node() -> void:
	assert_not_null(plans, "%PlanPieces in the war room scene")


func test_a_supposed_piece_is_boxwood_on_its_sides_lacquer_with_a_pencilled_tag() -> void:
	var id := WarPlans.place(repo, state, "cavalry", 2000, _foreign(), _land(), 0)
	plans.update(state)
	var node := plans.piece(id)
	assert_not_null(node)
	var figure := node.get_node("Piece") as Node3D
	assert_not_null(figure, "the arm's carved piece")
	var mesh: MeshInstance3D = Map3DUnits.meshes(figure)[0]
	assert_eq(float(mesh.get_instance_shader_parameter("blank")), repo.bal("war_plan_blank"))
	assert_eq(mesh.get_instance_shader_parameter("lacquer"),
		MapPalette.color_of(repo, _foreign()).darkened(repo.bal("war_base_darken")))
	var tag := node.get_node("Tag") as Label3D
	assert_eq(tag.text, "supposed · 2,000 horse")
	assert_eq(tag.modulate, repo.war_palette["pencil"])
	assert_almost_eq((Vector2(node.position.x, node.position.z)).distance_to(
		Vector2(view.table_point(_land()).x, view.table_point(_land()).z)), 0.0, 0.0001, "stood where it was set")


func test_unknown_wears_sable() -> void:
	var id := WarPlans.place(repo, state, "infantry", 1000, WarPlans.UNKNOWN, _land(), 0)
	plans.update(state)
	var mesh: MeshInstance3D = Map3DUnits.meshes(plans.piece(id).get_node("Piece"))[0]
	assert_eq(mesh.get_instance_shader_parameter("lacquer"), repo.war_palette["plan_unknown"])


func test_built_and_freed_with_the_plans_and_rebuilt_for_a_new_side() -> void:
	var id := WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land(), 0)
	plans.update(state)
	var first := plans.piece(id)
	WarPlans.edit_piece(repo, state, id, "infantry", 1500, _foreign())
	plans.update(state)
	assert_eq(plans.piece(id), first, "heads only: the same piece, retagged")
	assert_eq((first.get_node("Tag") as Label3D).text, "supposed · 1,500 foot")
	WarPlans.edit_piece(repo, state, id, "infantry", 1500, WarPlans.UNKNOWN)
	plans.update(state)
	await wait_process_frames(1)
	assert_ne(plans.piece(id), first, "a new side: rebuilt")
	WarPlans.remove(state, id)
	plans.update(state)
	await wait_process_frames(1)
	assert_null(plans.piece(id))


func test_follow_carries_it_and_a_pick_finds_it() -> void:
	var id := WarPlans.place(repo, state, "archers", 1000, _foreign(), _land(), 0)
	plans.update(state)
	var to := _land() + Vector2(3, 0)
	plans.follow(id, to, 90)
	var node := plans.piece(id)
	assert_almost_eq(node.position.x, view.table_point(to).x, 0.0001)
	var cam := view.get_node("%Camera") as Camera3D
	var at := cam.unproject_position(node.global_position) / view.window_scale()
	assert_eq(plans.pick(cam, view.window_scale(), at, repo.bal("war_pick_px")), id)


func test_facing_of_a_heading() -> void:
	assert_eq(WarPlanPieces.facing_of(Vector2.RIGHT), 0)
	assert_eq(WarPlanPieces.facing_of(Vector2.DOWN), 90)
	assert_eq(WarPlanPieces.facing_of(Vector2.LEFT), 180)
	assert_eq(WarPlanPieces.facing_of(Vector2.UP), 270)
