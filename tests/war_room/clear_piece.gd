extends RefCounted
## A land piece a test can click (tests/war_room and tests/ui): the units
## camped round one town are spread plinth to plinth on the table
## (WarPieces._spread), so a spread piece stands off its engine point and a
## neighbour in front may stand its figures over its base. Whatever the
## camp's pitch (army/balance.csv army_slot_spacing_m), this finds a piece whose
## OWN drawn point the view's real pick (WarRoomView.piece_under) takes up,
## the few px round it included (a click may drift under war_rake_min_px);
## with none, the first land piece is stood apart from every other first.
## Returns the piece's WarRoom.on_sheet entry plus `press`, the screen point
## (design px) to click, and `drawn`, the pack point the piece stands on.

## The drift a click may make before it is a drag, probed round the point.
const PROBE := [Vector2.ZERO, Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]


static func find(view: WarRoomView, repo: DataRepository, state: GameState) -> Dictionary:
	var p := _first_clear(view, repo, state)
	if not p.is_empty():
		return p
	var first := ""
	for q: Dictionary in WarRoom.on_sheet(repo, state, view.sheet_index()):
		if not bool(q["naval"]):
			first = String(q["code"])
			break
	if first == "":
		return {}
	stand_alone(view, repo, state, first)
	p = _first_clear(view, repo, state)
	if not p.is_empty():
		return p
	# nothing pickable yet (a sheet laid this very frame): the piece, at its point
	for q: Dictionary in WarRoom.on_sheet(repo, state, view.sheet_index()):
		if String(q["code"]) == first:
			var out := q.duplicate()
			out["press"] = view.screen_pos_of_px(q["at"])
			out["drawn"] = q["at"]
			return out
	return {}


static func _first_clear(view: WarRoomView, repo: DataRepository, state: GameState) -> Dictionary:
	var drawn := view.piece_pack_positions()
	for q: Dictionary in WarRoom.on_sheet(repo, state, view.sheet_index()):
		var code := String(q["code"])
		if bool(q["naval"]) or not drawn.has(code):
			continue
		var at: Variant = view.screen_pos_of_px(drawn[code])
		if at == null:
			continue
		var mine := true
		for d: Vector2 in PROBE:
			if view.piece_under((at as Vector2) + d) != code:
				mine = false
				break
		if mine:
			var out := q.duplicate()
			out["press"] = at
			out["drawn"] = drawn[code]
			return out
	return {}


## Stand `code` on the laid sheet's point farthest from every other piece and
## lay the pieces again.
static func stand_alone(view: WarRoomView, repo: DataRepository, state: GameState, code: String) -> void:
	var rect: Rect2 = WarSheets.series(repo)[view.sheet_index()]["rect"]
	var others: Array = []
	for p: Dictionary in WarRoom.on_sheet(repo, state, view.sheet_index()):
		if String(p["code"]) != code:
			others.append(p["at"])
	var best := rect.get_center()
	var best_d := -1.0
	for i in range(1, 8):
		for j in range(1, 8):
			var at := rect.position + rect.size * Vector2(i / 8.0, j / 8.0)
			var d := INF
			for o: Vector2 in others:
				d = minf(d, at.distance_to(o))
			if d > best_d:
				best_d = d
				best = at
	ArmySystem.ensure(repo, state)
	var m := ArmySystem.pack_to_metres(repo, best)
	state.regiments[code]["x_m"] = m.x
	state.regiments[code]["y_m"] = m.y
	view.refresh()
	(view.get_node("%Pieces") as WarPieces).settle()
