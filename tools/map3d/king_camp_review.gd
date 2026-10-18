extends "res://tools/snapshot_screen.gd"
## P3.3 real-window fixture. Uses the normal GameRoot and presentation bridge;
## only the saved scenario is seeded. Pass the usual --hold-line 1 flags.

func _seed_hold_line() -> void:
	super()
	assert(not _war_spread_codes.is_empty(), "--hold-line 1 is required")
	var args := OS.get_cmdline_user_args()
	var case := "flat"
	var phase := "camped"
	var share := 0.0
	for i: int in range(args.size() - 1):
		if args[i] == "--p33-case": case = args[i + 1]
		if args[i] == "--p33-phase": phase = args[i + 1]
		if args[i] == "--p33-share": share = float(args[i + 1])
	var view: Map3DView = _root.current_screen.map3d_view()
	var context: Map3DContext = view._ctx
	view._units.refresh()
	view._units.camp_size_ratio = 0.3
	var code := String(_war_spread_codes[0])
	var entry: Dictionary = Game.state.regiments[code]
	var origin := ArmySystem.metres_to_pack(Game.data, Vector2i(int(entry["x_m"]), int(entry["y_m"])))
	var at := _site(context, origin, case, view, code)
	var metres := ArmySystem.pack_to_metres(Game.data, at)
	entry["x_m"] = metres.x
	entry["y_m"] = metres.y
	entry["dest_x_m"] = metres.x
	entry["dest_y_m"] = metres.y
	entry["camp_town"] = ""
	entry["camp_state"] = {"phase": phase, "idle_days": 3, "build_progress": 1000 if phase != "building" else 0,
		"pack_start_day": Game.state.absolute_day(), "move_not_before_day": Game.state.absolute_day() + 1,
		"last_updated_day": Game.state.absolute_day(), "site": {"x_m": metres.x, "y_m": metres.y}}
	var king_px := at + Vector2(-3, 0)
	var king_at := ArmySystem.pack_to_metres(Game.data, king_px)
	Game.state.king_state = {"x_m": king_at.x, "y_m": king_at.y, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": Game.state.absolute_day() - 1}
	Game.day_progress = share
	view._units._days.clear()
	view._units._shown_xz.clear()
	view._units.refresh()
	_root._refresh_king_map()
	_at3d = at + Vector2(0, 5)
	Game.state_changed.emit()
	print("p33 fixture case=%s phase=%s share=%.2f site=%s king=%s" % [case, phase, share, at, king_at])

func _site(ctx: Map3DContext, origin: Vector2, case: String, view: Map3DView, code: String) -> Vector2:
	var best := origin
	var score := -INF
	var candidates: Array = []
	var sea_test := Map3DLayerRoads.sea_test(ctx)
	var woods := Image.load_from_file(ctx.repo.map3d_dir().path_join("bake/woods.png"))
	var rivers := Map3DRivers.parse(FileAccess.get_file_as_string(ctx.repo.map3d_dir().path_join("rivers.json")), ctx.repo.bal("map3d_river_split_rise_m"))
	for y: int in range(-12, 13):
		for x: int in range(-12, 13):
			var p := origin + Vector2(x, y) * 10.0
			if not MapEconomy.contains_land(ctx.repo, p): continue
			var cell := MapEconomy.cell_at(ctx.repo, p)
			if cell < 0 or MapTerrain.is_water(ctx.repo.cells[cell]): continue
			var near_town := false
			for burg: Dictionary in ctx.repo.burgs.values():
				near_town = near_town or p.distance_to(Vector2(float(burg["x"]), float(burg["y"]))) < 7.0
			if near_town: continue
			var w := ctx.to_world(p)
			if bool(sea_test.call(w)): continue
			var canopy := false
			for delta: Vector2 in [Vector2.ZERO, Vector2(-2, 0), Vector2(0, -2), Vector2(0, 2)]:
				var sample := (ctx.to_world(p + delta) - ctx.bounds.position) / Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL
				canopy = canopy or woods.get_pixel(clampi(int(sample.x),0,woods.get_width()-1),clampi(int(sample.y),0,woods.get_height()-1)).r > 0.0
			if canopy: continue
			var h := ctx.height_at(w)
			var slope := absf(ctx.height_at(w + Vector2(100, 0)) - h) + absf(ctx.height_at(w + Vector2(0, 100)) - h)
			if case == "slope" and slope > 10.0: continue
			var value := slope - p.distance_to(origin) * 0.0001 if case == "slope" else -slope - p.distance_to(origin) * 0.0001
			if case == "water":
				var wet := false
				for d: Vector2 in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
					wet = wet or bool(sea_test.call(ctx.to_world(p + d))) or not MapEconomy.contains_land(ctx.repo, p + d)
				for river: Dictionary in rivers:
					var points: PackedVector3Array = river["pos"]
					for i: int in range(1, points.size()):
						var closest := Geometry2D.get_closest_point_to_segment(w, Vector2(points[i-1].x,points[i-1].z),Vector2(points[i].x,points[i].z))
						wet = wet or w.distance_to(closest) < 400.0
				if not wet: continue
				value = 10000.0 - slope
			candidates.append({"at": p, "score": value})
			if value > score:
				score = value
				best = p
	print("p33 candidates=", candidates.size())
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	if case == "flat" and not candidates.is_empty():
		var ceiling := float(candidates[0]["score"]) - 1.0
		candidates = candidates.filter(func(c: Dictionary) -> bool: return float(c["score"]) >= ceiling)
	var presenter := Map3DUnitCamps.new()
	var piece: Dictionary = view._units._pieces[code]
	var scale_m := (piece["node"] as Node3D).basis.get_scale().x * view._units.camp_size_ratio
	var shown_best := -1
	for candidate: Dictionary in candidates.slice(0, 180):
		var metres := ArmySystem.pack_to_metres(ctx.repo, candidate["at"])
		presenter.apply_snapshot({"absolute_day": Game.state.absolute_day(), "camps": {"review": {"phase": "camped", "build_progress": 1000, "site": {"x_m": metres.x, "y_m": metres.y}}}})
		presenter.sync(view._units,ctx,"review",piece,Vector2.ZERO,0.0,scale_m,view._units.camp_back_m)
		var facilities: Array = (presenter.camps["review"] as Node3D).get_meta("facilities", [])
		var shown := facilities.filter(func(f: Dictionary) -> bool: return bool(f["placed"])).size()
		if shown > shown_best:
			shown_best = shown
			best = candidate["at"]
			score = float(candidate["score"])
		if shown == 6: break
	if presenter.camps.has("review"):
		(presenter.camps["review"] as Node3D).free()
	print("p33 ground score=", score, " facilities=", shown_best, " candidates=", candidates.size())
	return best

func _process(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--p33-animate"):
		Game.day_progress = clampf(float(_frames - 12) / 60.0, 0.0, 1.0)
	super(delta)
	if _frames == 10 and OS.get_cmdline_user_args().has("--p33-before"):
		_root.current_screen.map3d_view().apply_snapshot({})
	if _frames == 20 and OS.get_cmdline_user_args().has("--p33-select"):
		var view: Map3DView = _root.current_screen.map3d_view()
		var at := view.king_rect().get_center()
		_real_click(view, at)
		print("p33 selected=", view.pick_at(at), " selected_armies=", view.component("selection").armies)
		var menu := _root.current_screen.find_child("KingOrders", true, false) as PopupMenu
		print("p33 menu rows=", menu.item_count if menu != null else -1)
	if _frames == 40 and _root != null and _root.current_screen.has_method("map3d_view"):
		var view: Map3DView = _root.current_screen.map3d_view()
		var camps: Dictionary = view._units._camps.camps
		for code: String in camps:
			var camp: Node3D = camps[code]
			for f: Dictionary in camp.get_meta("facilities", []):
				var part: Node3D = f["node"]
				print("p33 part ", part.name, " placed=", f["placed"], " position=", part.global_position, " visible=", part.visible)
		print("p33 king pos=", view._king.position, " global=", view._king.global_position, " box=", view.king_rect(), " camera=", view._ctx.camera.global_position, " target=", view.target(), " size=", view.size)
