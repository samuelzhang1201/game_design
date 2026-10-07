class_name Map3DSelection
extends RefCounted
## What the player clicked on the 3D map (spec 2026-09-20 §1): a settlement
## (its gold ring), a province or — under MANORS — a manor (its gold outline),
## a regiment or a landmark, and the signals the 2D map sends for each. The
## view re-emits them under its own names, so the screens change nothing.

signal object_selected(entry: Dictionary)
signal province_selected(province_code: String)

var ctx: Map3DContext
var lines: Map3DLayerLines
var markers: Map3DLayerSettlements
var view: Map3DView
var province := ""
var burg := ""
## The manor cell clicked under a theme, -1 for none.
var manor := -1
var army := ""
## The units selected together (spec §5.6); [army] after a plain click.
var armies: Array = []


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_markers: Map3DLayerSettlements,
		p_view: Map3DView) -> void:
	ctx = p_ctx
	lines = p_lines
	markers = p_markers
	view = p_view


## A left click. On one of the player's regiments it selects him AND opens
## his orders (owner 2026-09-24: 左键点击兵人，会出现行动清单 — GARRISON, or
## MARCH, which is then aimed with a ruler and confirmed by the next left
## click); anywhere else it selects what it hit. `pos` is design px.
func click(picked: Dictionary, pos: Vector2) -> void:
	if String(picked.get("kind", "")) == "route":
		view.route_clicked.emit(String(picked["code"]), pos)
		return
	select(picked)
	if String(picked.get("kind", "")) == "army":
		view.army_menu_requested.emit(String(picked["code"]), pos)


## The click: a settlement opens its card, land names its province (its
## manor under a theme), the sea clears — exactly the signals WorldMapView
## sends.
func select(picked: Dictionary) -> void:
	match String(picked.get("kind", "")):
		"burg":
			var code := String(picked["code"])
			army = ""
			armies = []
			_set_province("")
			burg = code
			_show_ring(code)
			object_selected.emit({"title": String(ctx.repo.burgs[code].get("label", code)),
				"obj": {"kind": "burg", "code": code}})
		"province":
			burg = ""
			army = ""
			armies = []
			_show_ring("")
			_set_province(String(picked["code"]))
			province_selected.emit(province)
		"army":
			var code := String(picked["code"])
			burg = ""
			_show_ring("")
			_set_province("")
			army = code
			armies = [code]
			_refresh_hud()
			object_selected.emit({"title": MapObjects.label_of(ctx.repo, picked),
				"obj": {"kind": "army", "code": code}})
		"manor":
			var cell := int(picked["cell"])
			army = ""
			armies = []
			burg = ""
			_show_ring("")
			province = ""
			manor = cell
			redraw()
			object_selected.emit({"title": MapManors.label_of(ctx.repo, cell),
				"obj": {"kind": "manor", "cell": cell}})
		"courier":
			var id := int(picked["id"])
			burg = ""
			army = ""
			armies = []
			_show_ring("")
			_set_province("")
			_refresh_hud()
			object_selected.emit({"title": CourierCard.title(ctx.repo, ctx.state(), id),
				"obj": {"kind": "courier", "id": id}})
		"landmark":
			var cell := int(picked["cell"])
			if army != "":
				army = ""
				armies = []
				_refresh_hud()
			burg = ""
			_show_ring("")
			_set_province("")
			var m := Elevation.landmark_at(ctx.repo, cell)
			object_selected.emit({"title": String(m.get("name", "")),
				"lines": MapObjects.landmark_lines(ctx.repo, ctx.state(), cell),
				"ask": "", "obj": {"kind": "landmark", "cell": cell}})
		_:
			clear()


## Forget the selection (the card was closed, or the sea clicked).
func clear() -> void:
	var had := burg != "" or province != "" or manor >= 0 or army != ""
	if army != "":
		army = ""
		armies = []
		_refresh_hud()
	burg = ""
	_show_ring("")
	_set_province("")
	if had:
		object_selected.emit({})


## Leaving MANORS forgets the clicked manor and its gold outline.
func forget_manor() -> void:
	if manor >= 0:
		manor = -1
		if ctx != null:
			redraw()


## The clicked province's outline — its own seam EMPHASISED: the same dark
## dashes at full ink and heavier (owner 2026-09-27: "黄色实心线…不需要这个，
## 它本身就是一个黑色的虚线，你highlight那个黑色虚线即可"); under a theme the
## clicked manor's stays solid gold over the borders.
func redraw() -> void:
	var repo := ctx.repo
	var ls: Array = []
	if manor >= 0 and repo.cells.has(manor):
		var pts := PackedVector2Array()
		for vid in (repo.cells[manor]["vertex_ids"] as PackedInt32Array):
			pts.append(Map3DGeometry.pack_to_world(ctx.meta, repo.vertices[vid] as Vector2))
		if pts.size() >= 3:
			pts.append(pts[0])
			ls.append(Map3DGeometry.resample(pts, ctx.line_step()))
	elif province != "":
		var steps := int(repo.bal("map_border_smoothing_steps"))
		for loop: PackedVector2Array in MapOwnership.province_loops(repo, ctx.state(), province):
			if loop.size() < 3:
				continue
			var pts := PackedVector2Array()
			for p in MapGeometry.smooth_closed_through(loop, steps):
				pts.append(Map3DGeometry.pack_to_world(ctx.meta, p))
			pts.append(pts[0])
			ls.append(Map3DGeometry.resample(pts, ctx.line_step()))
	# a clicked manor in gold, a clicked province by its own seam emphasised
	lines.set_lines("Selection", ls, Map3DLayerLines.SELECTION_MANOR if manor >= 0
		else Map3DLayerLines.SELECTION_PROVINCE, Map3DPriority.SELECTION)


func _set_province(code: String) -> void:
	if code == province and manor < 0:
		return
	province = code
	manor = -1
	if ctx != null:
		redraw()


func _show_ring(code: String) -> void:
	if markers != null:
		markers.show_selected(code)


func _refresh_hud() -> void:
	if view != null:
		view.refresh_hud()
