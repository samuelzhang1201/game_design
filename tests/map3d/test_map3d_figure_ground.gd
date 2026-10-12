extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Every figure of a piece stands on ITS OWN ground (owner 2026-10-12: 走在斜坡上
## 飘, 不同模型所处的高度是不同的). The piece is one tilted plane raised over the
## highest ground under its footprint, so on a slope the lower figures hovered;
## the lag spring's offset, taken in the tilted frame, also lifted a figure off
## the plane. Map3DUnitRig.plant puts each figure's foot on the ground under it.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


## A hillside rising 0.3 per metre east and 0.1 per metre south, 40 m up.
func _hill(xz: Vector2) -> float:
	return 40.0 + 0.3 * xz.x + 0.1 * xz.y


## A 3x3 piece, figures 3 model-metres apart, seated on the hill by the real
## seat() at scale 2 and a yaw.
func _piece(yaw: float) -> Dictionary:
	var node := Node3D.new()
	var figs: Array = []
	var slots: Array = []
	for r in 3:
		for c in 3:
			var f := Node3D.new()
			f.position = Vector3((c - 1) * 3.0, 0.0, (r - 1) * 3.0)
			node.add_child(f)
			figs.append(f)
			slots.append(f.position)
	var piece := {"node": node, "figs": figs, "slots": slots, "height_m": 1.8, "extent": Vector2(4.5, 4.5)}
	Map3DUnitRig.seat(repo, _hill, piece, Vector2(100.0, 50.0), yaw, 2.0)
	return piece


func _feet_over_ground(piece: Dictionary) -> Array:
	var node: Node3D = piece["node"]
	var out: Array = []
	for f: Node3D in piece["figs"]:
		var w := node.transform * f.position
		out.append(w.y - _hill(Vector2(w.x, w.z)))
	return out


func test_without_planting_the_low_figures_hover() -> void:
	var piece := _piece(0.7)
	var worst := 0.0
	for gap: float in _feet_over_ground(piece):
		worst = maxf(worst, gap)
	assert_gt(worst, 0.5, "the rigid plane leaves a figure metres over the slope (the bug)")
	(piece["node"] as Node3D).free()


func test_planted_every_foot_is_on_its_own_ground() -> void:
	var clear := 1.8 * 2.0 * repo.bal("map3d_unit_seat_clear") - repo.bal("map3d_unit_sink_m")
	for yaw: float in [0.0, 0.7, 2.4]:
		var piece := _piece(yaw)
		Map3DUnitRig.plant(repo, _hill, piece)
		for gap: float in _feet_over_ground(piece):
			assert_almost_eq(gap, clear, 0.002, "foot = ground + the seat's clearance, yaw %s" % yaw)
		(piece["node"] as Node3D).free()


func test_planted_after_a_lag_offset_still_on_the_ground() -> void:
	# a figure trailing its slot (x, z in the tilted frame) is replanted where it IS
	var piece := _piece(0.7)
	var clear := 1.8 * 2.0 * repo.bal("map3d_unit_seat_clear") - repo.bal("map3d_unit_sink_m")
	var figs: Array = piece["figs"]
	for i in figs.size():
		(figs[i] as Node3D).position += Vector3(-0.4, 0.0, 0.25)
	Map3DUnitRig.plant(repo, _hill, piece)
	for gap: float in _feet_over_ground(piece):
		assert_almost_eq(gap, clear, 0.002)
	(piece["node"] as Node3D).free()


func test_lag_never_lifts_a_figure_off_its_plane() -> void:
	# a tilted piece walking uphill: the world velocity has a component along the
	# piece's own up axis; the lag spring must stay in the plane (y untouched)
	var piece := _piece(0.0)
	var node: Node3D = piece["node"]
	assert_gt(absf(node.transform.basis.y.x), 0.01, "the piece is tilted")
	piece["lag_cap"] = 0.5
	for _i in 30:
		Map3DUnitRig.lag(repo, piece, "reg_a", Vector2(30.0, 0.0), 0.05)
	for f: Node3D in piece["figs"]:
		assert_eq(f.position.y, 0.0, "the lag offset is in-plane")
	node.free()
