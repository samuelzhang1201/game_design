class_name WarTrayNodes
extends RefCounted
## The war markers' NODES (owner 2026-10-12, items 6-7; R11): one authored
## Node3D a WarTray slot (WarRoomView.tray_markers, else the scene's %Marker),
## each scaled to fit one index-chart cell (war_marker_fit), resting beside the
## chart (war_tray_gap_m) while its slot is free, standing on its cell while
## held, and tossed FROM its tray slot onto a cell (WarToss). Holds no game
## state; nothing is saved.

var markers: Array[Node3D] = []
var _repo: DataRepository
var _chart: MeshInstance3D
var _placed: Array = []   # slot -> the sheet its node stands on, -1 resting
var _toss: Dictionary = {}
var _toss_t := 0.0
var _toss_to := -1
var _toss_slot := -1
var _toss_n := 0


func setup(repo: DataRepository, chart: MeshInstance3D, nodes: Array[Node3D]) -> void:
	_repo = repo
	_chart = chart
	markers = nodes
	_placed.resize(markers.size())
	_placed.fill(-2)   # never placed: the first sync places every node


func marker(slot: int) -> Node3D:
	return markers[slot] if slot >= 0 and slot < markers.size() else null


func tossing() -> bool:
	return not _toss.is_empty()


## The chart is dressed (WarRoomWall.build_chart): only then do points on it mean anything.
func _chart_dressed() -> bool:
	return _chart != null and _chart.has_meta("margin_m")


## Every node where the tray says: a held slot's node on its cell's centre
## (left where it landed when it stands there already), a free one resting in
## its place beside the chart; the node in flight is left to the toss.
func sync(tray: WarTray) -> void:
	if not _chart_dressed():
		return
	for slot in markers.size():
		if tossing() and slot == _toss_slot:
			continue
		var sheet := tray.sheet_in(slot)
		if sheet == int(_placed[slot]):
			continue
		_placed[slot] = sheet
		if sheet < 0:
			_pose(slot, Transform3D(Basis.IDENTITY, rest_point(slot)))
		else:
			var uv := WarIndexChart.uv_of_cell(_repo, WarSheets.series(_repo)[sheet]).get_center()
			_pose(slot, Transform3D(Basis(WarToss.lay(WarRoomWall.chart_normal(_chart))), WarRoomWall.chart_point(_chart, uv)))


## Where slot `slot`'s marker rests beside the chart's east edge.
func rest_point(slot: int) -> Vector3:
	return WarRoomWall.tray_point(_chart, slot, _repo.bal("war_tray_gap_m"), _repo.bal("war_tray_off_m"))


## Toss slot `slot`'s marker from its tray place onto sheet `index`'s cell (a
## spot inside it, seeded by the sheet and the toss count: presentation only).
func toss(slot: int, index: int) -> void:
	if not _chart_dressed() or slot < 0 or slot >= markers.size():
		return
	_toss_n += 1
	var uv := WarToss.landing(WarIndexChart.uv_of_cell(_repo, WarSheets.series(_repo)[index]),
		hash([index, _toss_n]), _repo.bal("war_toss_margin"))
	_toss = WarToss.plan(rest_point(slot), WarRoomWall.chart_point(_chart, uv), hash([index, _toss_n, "toss"]),
		WarToss.rules(_repo), WarRoomWall.chart_normal(_chart))
	_toss_t = 0.0
	_toss_to = index
	_toss_slot = slot
	_placed[slot] = index
	_pose(slot, WarToss.pose(_toss, 0.0))


## Advance the toss by `delta`: the sheet it landed on the step it lands, else -1.
func step(delta: float) -> int:
	if not tossing():
		return -1
	_toss_t += delta
	_pose(_toss_slot, WarToss.pose(_toss, _toss_t))
	if _toss_t < float(_toss["duration"]):
		return -1
	_toss = {}
	return _toss_to


## A marker's pose, scaled so its base fits inside one chart cell.
func _pose(slot: int, t: Transform3D) -> void:
	var m := markers[slot]
	m.visible = true
	t.basis = t.basis.scaled(Vector3.ONE * scale_k())
	m.global_transform = t


## The markers' scale: the base's diameter is war_marker_fit of one chart
## cell's narrower side (never enlarged; 1 with no base to measure).
func scale_k() -> float:
	if not _chart_dressed() or markers.is_empty():
		return 1.0
	var base := markers[0].get_node_or_null("Base") as MeshInstance3D
	var cyl := base.mesh as CylinderMesh if base != null else null
	if cyl == null:
		return 1.0
	var cell := MapCoords.cell_rect(_repo, Vector2i.ZERO, _repo.bal("war_sheet_deg")).size
	var map_px := Vector2(float(_repo.map_info.get("width", "1")), float(_repo.map_info.get("height", "1")))
	var size := WarRoomWall.map_size(_chart)
	var cell_m := Vector2(cell.x / map_px.x * size.x, cell.y / map_px.y * size.y)
	var diameter := maxf(cyl.bottom_radius, cyl.top_radius) * 2.0
	return minf(1.0, _repo.bal("war_marker_fit") * minf(cell_m.x, cell_m.y) / maxf(diameter, 0.0001))
