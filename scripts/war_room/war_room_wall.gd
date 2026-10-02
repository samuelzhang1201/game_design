class_name WarRoomWall
extends RefCounted
## The room's changing-sheets furniture (spec 2026-10-01-war-room-design §2):
## the index chart's picture and numerals, the ink arrows at the laid sheet's
## edges, and the picks of both. Built into nodes the authored scene holds
## (%IndexChart, %EdgeArrows); no state of its own.

const SIDES := {"n": "↑", "s": "↓", "e": "→", "w": "←"}


## Dress the chart quad: its size from the map's ratio, the picture, and one
## numeral lying on it at each sheet's centre.
static func build_chart(chart: MeshInstance3D, repo: DataRepository, font: Font) -> void:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var size := Vector2(repo.bal("war_chart_w_m"), repo.bal("war_chart_w_m") * h / w)
	var quad := chart.mesh.duplicate() as QuadMesh
	quad.size = size
	chart.mesh = quad
	chart.position = Vector3(0.0, repo.bal("war_chart_y_m"), repo.bal("war_chart_z_m"))
	chart.rotation_degrees = Vector3(-(90.0 - repo.bal("war_chart_tilt_deg")), 0.0, 0.0)
	var mat := chart.material_override.duplicate() as StandardMaterial3D
	mat.albedo_texture = ImageTexture.create_from_image(WarIndexChart.image(repo, int(repo.bal("war_chart_px"))))
	chart.material_override = mat
	for n in chart.get_children():
		chart.remove_child(n)
		n.queue_free()
	for s: Dictionary in WarSheets.series(repo):
		var c: Vector2 = (s["rect"] as Rect2).get_center()
		var at := Vector3((c.x / w - 0.5) * size.x, (0.5 - c.y / h) * size.y, repo.bal("war_chart_numeral_lift_m"))
		chart.add_child(_label(String(s["id"]), font, repo.war_palette["rubric"], at,
			int(repo.bal("war_chart_numeral_font_px")), repo.bal("war_chart_numeral_pixel_m"), false))


## The sheet under a screen px on the chart, -1 off it. `screen_px` is already
## in the viewport's own px (the view multiplies its window scale in).
static func pick_chart(chart: MeshInstance3D, camera: Camera3D, repo: DataRepository, screen_px: Vector2) -> int:
	var inv := chart.global_transform.affine_inverse()
	var lo := inv * camera.project_ray_origin(screen_px)
	var ld := (inv.basis * camera.project_ray_normal(screen_px)).normalized()
	if absf(ld.z) < 0.00001:
		return -1
	var t := -lo.z / ld.z
	if t < 0.0:
		return -1
	var hit := lo + ld * t
	var size := (chart.mesh as QuadMesh).size
	return WarIndexChart.sheet_at_uv(repo, Vector2(hit.x / size.x + 0.5, 0.5 - hit.y / size.y))


## Replace the arrows: one at each side of the laid sheet that has a neighbour.
static func lay_arrows(parent: Node3D, repo: DataRepository, sheet: int, table_w: float, depth: float, font: Font) -> void:
	for n in parent.get_children():
		parent.remove_child(n)
		n.queue_free()
	var series := WarSheets.series(repo)
	var gap := repo.bal("war_arrow_gap_m")
	var y := repo.bal("war_arrow_y_m")
	var places := {"n": Vector3(0.0, y, -depth * 0.5 - gap), "s": Vector3(0.0, y, depth * 0.5 + gap),
		"e": Vector3(table_w * 0.5 + gap, y, 0.0), "w": Vector3(-table_w * 0.5 - gap, y, 0.0)}
	var near := WarSheets.neighbours(repo, sheet)
	for side: String in near:
		var to := int(near[side])
		var a := _label("%s %s" % [SIDES[side], series[to]["id"]], font, repo.war_palette["ink"],
			places[side], int(repo.bal("war_arrow_font_px")), repo.bal("war_arrow_pixel_m"), true)
		a.set_meta("sheet", to)
		parent.add_child(a)


## The sheet whose arrow stands within `reach_px` of a screen px, -1 none: both in
## the Control's own px, so the camera's viewport px are divided by `scale`.
static func pick_arrow(parent: Node3D, camera: Camera3D, screen_px: Vector2, scale: float, reach_px: float) -> int:
	for a: Node in parent.get_children():
		var p := (a as Node3D).global_position
		if camera.is_position_behind(p):
			continue
		if (camera.unproject_position(p) / scale).distance_to(screen_px) <= reach_px:
			return int(a.get_meta("sheet"))
	return -1


static func _label(text: String, font: Font, color: Color, at: Vector3, font_px: int, pixel_m: float, billboard: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.font = font
	l.font_size = font_px
	l.pixel_size = pixel_m
	l.modulate = color
	l.double_sided = true
	l.no_depth_test = billboard
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l
