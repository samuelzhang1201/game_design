# tests/ledger3d/test_ledger_strands.gd
extends GutTest
## Accounts that differ are drawn as STRANDS (spec 2026-09-30-ledger-
## governors-design §4): one thread per account, ledger_strand_gap_m apart,
## each picked as "<link id>#<i>", and a drag re-lays every strand of a
## thread in place.

var repo: DataRepository
var state: GameState
var view: LedgerView3D
var code := ""


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	RealmEconomy.forget()
	state.metrics["strategic"] = 1000000.0
	for c in state.regiments.keys():
		state.regiments[c]["supplies"] = 0
	var m: Character = state.characters[String(state.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = ["venal"]
	m.attributes["integrity"] = 50
	code = String(SupplySystem.plan(repo, state)[0]["code"])
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.size = Vector2(1000, 600)
	view.bind(repo)


func after_each() -> void:
	RealmEconomy.forget()


func _supplies_out(snap: Dictionary) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == "supplies_out":
			return l
	return {}


func _press(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	view._gui_input(mb)


func test_two_accounts_are_two_strands_a_gap_apart() -> void:
	var snap := Ledger.snapshot(repo, state, "war", {"id": "regiment:" + code})
	view.show_snapshot(snap, false)
	var l := _supplies_out(snap)
	assert_eq((l["accounts"] as Array).size(), 2, "a venal marshal's word and the regiment's count")
	var id := String(l["id"])
	assert_false(view._thread_mi.has(id), "no single thread for a split link")
	assert_true(view._thread_mi.has(id + "#0") and view._thread_mi.has(id + "#1"), "two strands")
	var e0: Array = view._thread_ends[id + "#0"]
	var e1: Array = view._thread_ends[id + "#1"]
	var gap := repo.bal("ledger_strand_gap_m")
	assert_almost_eq((e0[0] as Vector3).distance_to(e1[0]), gap, 0.001, "their sources a gap apart")
	assert_almost_eq((e0[1] as Vector3).distance_to(e1[1]), gap, 0.001, "their ends a gap apart")
	var along := ((e0[1] as Vector3) - (e0[0] as Vector3)).normalized()
	assert_almost_eq(((e1[0] as Vector3) - (e0[0] as Vector3)).dot(along), 0.0, 0.001, "side by side, not along")
	var r0 := ((view._thread_mi[id + "#0"] as MeshInstance3D).mesh as CylinderMesh).top_radius
	var r1 := ((view._thread_mi[id + "#1"] as MeshInstance3D).mesh as CylinderMesh).top_radius
	assert_gt(r0, r1, "the claim is wider than what arrived")


func test_a_strand_is_picked_by_its_own_id() -> void:
	var snap := Ledger.snapshot(repo, state, "war", {"id": "regiment:" + code})
	view.show_snapshot(snap, false)
	var id := String(_supplies_out(snap)["id"])
	var ends: Array = view._thread_ends[id + "#1"]
	var mid: Vector3 = ((ends[0] as Vector3) + (ends[1] as Vector3)) * 0.5
	var at := view._camera.unproject_position(mid) / view._window_scale()
	assert_eq(view._pick(at), {"kind": "thread", "id": id + "#1"})


func test_a_drag_moves_every_strand_in_place() -> void:
	var snap := Ledger.snapshot(repo, state, "war", {"id": "regiment:" + code})
	view.show_snapshot(snap, false)
	var id := String(_supplies_out(snap)["id"])
	var end_id := ""
	var at := Vector2.ZERO
	for nid: String in ["regiment:" + code, "supply_line:" + code]:
		var p: Variant = view.screen_pos_of(nid)
		if p != null and view._pick(p as Vector2) == {"kind": "sphere", "id": nid}:
			end_id = nid
			at = p
			break
	assert_ne(end_id, "", "an end of the split thread can be grabbed")
	var nodes := {}
	var before := {}
	for s: String in [id + "#0", id + "#1"]:
		nodes[s] = (view._thread_mi[s] as MeshInstance3D).get_instance_id()
		before[s] = view._thread_ends[s]
	var children := view._threads_root.get_child_count()
	_press(at, true)
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(60, 25)
	mm.relative = Vector2(60, 25)
	view._gui_input(mm)
	_press(mm.position, false)
	for s: String in nodes:
		assert_eq((view._thread_mi[s] as MeshInstance3D).get_instance_id(), nodes[s], "re-laid in place: " + s)
		assert_ne(view._thread_ends[s], before[s], "its ends moved: " + s)
	var e0: Array = view._thread_ends[id + "#0"]
	var e1: Array = view._thread_ends[id + "#1"]
	assert_almost_eq((e0[0] as Vector3).distance_to(e1[0]), repo.bal("ledger_strand_gap_m"), 0.001,
		"still a gap apart")
	assert_eq(view._threads_root.get_child_count(), children, "no thread was made or freed")
