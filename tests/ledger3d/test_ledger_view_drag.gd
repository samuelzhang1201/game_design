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


func test_the_court_stands_on_one_disc_and_is_framed_whole() -> void:
	var repo := DataRepository.load_all("res://data")
	var state := GameState.new_campaign(repo, 42)
	var view: LedgerView3D = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.size = Vector2(1000, 600)
	view.bind(repo)
	view.show_snapshot(Ledger.snapshot(repo, state, "court", {}), false)
	assert_true(view.disc_of("people").visible, "the court's disc")
	assert_false(view.disc_of("things").visible, "no empty THINGS disc")
	assert_false(view.disc_of("know").visible, "no empty KNOW disc")
	assert_ne(view.orbit().distance, repo.bal("ledger_camera_distance"), "framed, not the fixed distance")
	view.show_snapshot(Ledger.snapshot(repo, state, "economy", {}), false)
	for layer: String in Ledger.LAYERS:
		assert_true(view.disc_of(layer).visible, "economy draws the %s disc" % layer)


## A sphere the pointer can grab: [id, its screen spot], or ["", _].
func _grabbable(view: LedgerView3D, snap: Dictionary) -> Array:
	for n: Dictionary in snap["nodes"]:
		var nid := String(n["id"])
		var p: Variant = view.screen_pos_of(nid)
		if p != null and view._pick(p as Vector2) == {"kind": "sphere", "id": nid}:
			return [nid, p]
	return ["", Vector2.ZERO]


func _court_view() -> Array:
	var repo := DataRepository.load_all("res://data")
	var state := GameState.new_campaign(repo, 42)
	var view: LedgerView3D = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.bind(repo)
	return [repo, state, view]


func _motion(view: LedgerView3D, to: Vector2, rel: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = to
	mm.relative = rel
	view._gui_input(mm)


## Final fix I2: a state change redraws the same lens without undoing what
## the player moved; a new lens or focus forgets it.
func test_a_dragged_sphere_keeps_its_place_across_a_redraw() -> void:
	var made := _court_view()
	var repo: DataRepository = made[0]
	var state: GameState = made[1]
	var view: LedgerView3D = made[2]
	var snap := Ledger.snapshot(repo, state, "court", {})
	view.show_snapshot(snap, true)
	var grab := _grabbable(view, snap)
	var id := String(grab[0])
	assert_ne(id, "", "some court sphere can be grabbed")
	_press(view, grab[1], true)
	_motion(view, (grab[1] as Vector2) + Vector2(60, 25), Vector2(60, 25))
	_press(view, (grab[1] as Vector2) + Vector2(60, 25), false)
	var dragged: Vector3 = view._pos[id]
	assert_ne(dragged, LedgerLayout.positions(repo, snap)[id], "the sphere moved")
	view.show_snapshot(Ledger.snapshot(repo, state, "court", {}), true)
	assert_eq(view._pos[id], dragged, "still where the player put it")
	assert_eq((view._sphere_mi[id] as MeshInstance3D).position, dragged, "and drawn there")
	view.show_snapshot(Ledger.snapshot(repo, state, "economy", {}), true)
	view.show_snapshot(snap, true)
	assert_eq(view._pos[id], LedgerLayout.positions(repo, snap)[id], "another lens forgot the drag")


## Final fix I2: the sphere under a drag vanishes from the next snapshot
## (its focus went, a courier arrived): the drag ends quietly.
func test_a_drag_survives_its_sphere_vanishing() -> void:
	var made := _court_view()
	var repo: DataRepository = made[0]
	var state: GameState = made[1]
	var view: LedgerView3D = made[2]
	var snap := Ledger.snapshot(repo, state, "court", {})
	view.show_snapshot(snap, true)
	var grab := _grabbable(view, snap)
	var id := String(grab[0])
	assert_ne(id, "", "some court sphere can be grabbed")
	var at: Vector2 = grab[1]
	_press(view, at, true)
	_motion(view, at + Vector2(40, 10), Vector2(40, 10))
	var without := snap.duplicate(true)
	without["nodes"] = (snap["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["id"]) != id)
	without["links"] = (snap["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["from"]) != id and String(l["to"]) != id)
	view.show_snapshot(without, true)
	var pose := view.orbit().pose()
	_motion(view, at + Vector2(90, 30), Vector2(50, 20))
	_press(view, at + Vector2(90, 30), false)
	assert_false(view._pos.has(id), "the sphere is gone")
	assert_eq(view.orbit().pose(), pose, "the rest of the gesture neither pans nor turns")
	assert_eq(view._drag_id, "", "the drag ended")
