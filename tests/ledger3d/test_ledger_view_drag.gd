# tests/ledger3d/test_ledger_view_drag.gd
extends GutTest
## Dragging a LEDGER sphere re-lays only its own threads, in place (spec
## §6.2): every other thread keeps its node, and none is rebuilt per motion.
## Headless instancing is fine: the dummy renderer draws nothing but the
## scene, its nodes and its maths are all there.

func _press(view: LedgerView3D, at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	view._gui_input(mb)


func test_a_drag_moves_only_the_dragged_spheres_threads_in_place() -> void:
	var repo := DataRepository.load_all("res://data")
	var state := GameState.new_campaign(repo, 42)
	var view: LedgerView3D = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.bind(repo)
	var snap := Ledger.snapshot(repo, state, "court", {})
	view.show_snapshot(snap, true)
	# A sphere the pointer can grab (its own screen spot picks it) with both
	# threads of its own and threads that are not its.
	var id := ""
	var at := Vector2.ZERO
	for n: Dictionary in snap["nodes"]:
		var nid := String(n["id"])
		var p: Variant = view.screen_pos_of(nid)
		if p == null or view._pick(p as Vector2) != {"kind": "sphere", "id": nid}:
			continue
		var touching: Array = (snap["links"] as Array).filter(func(l: Dictionary) -> bool:
			return String(l["from"]) == nid or String(l["to"]) == nid)
		if not touching.is_empty() and touching.size() < (snap["links"] as Array).size():
			id = nid
			at = p
			break
	assert_ne(id, "", "some court sphere can be grabbed")
	var own := {}
	var others := {}
	var ends_before := {}
	for l: Dictionary in snap["links"]:
		var tid := String(l["id"])
		if not view._thread_mi.has(tid):
			continue
		var node_id: int = (view._thread_mi[tid] as MeshInstance3D).get_instance_id()
		if String(l["from"]) == id or String(l["to"]) == id:
			own[tid] = node_id
			ends_before[tid] = view._thread_ends[tid]
		else:
			others[tid] = node_id
	var children_before := view._threads_root.get_child_count()
	_press(view, at, true)
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(60, 25)
	mm.relative = Vector2(60, 25)
	view._gui_input(mm)
	_press(view, mm.position, false)
	assert_ne(view._pos[id], LedgerLayout.positions(repo, snap)[id], "the sphere moved")
	for tid: String in others:
		assert_eq((view._thread_mi[tid] as MeshInstance3D).get_instance_id(), others[tid], "untouched: " + tid)
	for tid: String in own:
		assert_eq((view._thread_mi[tid] as MeshInstance3D).get_instance_id(), own[tid], "re-laid in place: " + tid)
		assert_ne(view._thread_ends[tid], ends_before[tid], "its ends moved: " + tid)
	assert_eq(view._threads_root.get_child_count(), children_before, "no thread was made or freed")
