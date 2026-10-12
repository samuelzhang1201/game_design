class_name WarRoomWall
extends RefCounted
## The room's changing-sheets furniture (spec 2026-10-01-war-room-design §2):
## the index chart's picture and its graticule's letters and numbers, the ink arrows at the laid sheet's
## edges, and the picks of both. Built into nodes the authored scene holds
## (%IndexChart, %EdgeArrows); no state of its own.

const SIDES := {"n": "↑", "s": "↓", "e": "→", "w": "←"}


## Dress the chart quad: its size from the map's ratio, the picture, and the
## graticule's column letters along its NEAR (south) edge, the margin nearest the officer, and row
## numbers down its west edge (v2 B: 76 sheet ids crowded the chart unread).
static func build_chart(chart: MeshInstance3D, repo: DataRepository, font: Font) -> void:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var size := Vector2(repo.bal("war_chart_w_m"), repo.bal("war_chart_w_m") * h / w)   # the MAP's size on the chart
	var pad := repo.bal("war_chart_margin_m")   # the parchment margin the letters are printed on
	var quad := chart.mesh.duplicate() as QuadMesh
	quad.size = size + Vector2(pad, pad) * 2.0
	chart.set_meta("margin_m", pad)
	chart.mesh = quad
	var tilt := deg_to_rad(repo.bal("war_chart_tilt_deg"))
	var half := quad.size.y * 0.5
	# R10 (owner-approved 2026-10-12): the chart leans on a reading stand, pivoting about its NEAR
	# (camera-side) edge, which stays on the oak at war_chart_z_m; the far edge rises up the lean
	chart.position = Vector3(0.0, repo.bal("war_chart_y_m") + sin(tilt) * half, repo.bal("war_chart_z_m") - cos(tilt) * half)
	chart.rotation_degrees = Vector3(-(90.0 - repo.bal("war_chart_tilt_deg")), 0.0, 0.0)
	chart.set_meta("foot_y_m", repo.bal("war_chart_y_m"))   # the oak the tray's markers stand on
	var mat := chart.material_override.duplicate() as StandardMaterial3D
	mat.albedo_texture = ImageTexture.create_from_image(WarIndexChart.image_with_margin(repo, int(repo.bal("war_chart_px")),
			int(round(pad / size.x * repo.bal("war_chart_px")))))
	chart.material_override = mat
	for n in chart.get_children():
		chart.remove_child(n)
		n.queue_free()
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var lift := repo.bal("war_chart_numeral_lift_m")
	var margin := repo.bal("war_chart_axis_margin_m")
	var font_px := int(repo.bal("war_chart_numeral_font_px"))
	var pixel_m := repo.bal("war_chart_numeral_pixel_m")
	# a letter every war_chart_label_every columns and rows (the 10° series is
	# 36 x 18: every cell lettered crowds the chart's edges)
	var every := maxi(1, int(repo.bal("war_chart_label_every")))
	for col in range(0, g.x, every):
		var cx := (minf(MapCoords.cell_rect(repo, Vector2i(col, 0), deg).get_center().x, w) / w - 0.5) * size.x
		var letters := WarSheets.column_letters(col)
		var l := _label(letters, font, repo.war_palette["chart_label"],
			Vector3(cx, -(size.y * 0.5 + margin + _extent(font, letters, font_px, pixel_m).y * 0.5), lift), font_px, pixel_m, false)
		l.set_meta("axis", "col")
		l.set_meta("n", col)
		chart.add_child(l)
	for row in range(0, g.y, every):
		var cy := (0.5 - minf(MapCoords.cell_rect(repo, Vector2i(0, row), deg).get_center().y, h) / h) * size.y
		var figure := str(row + 1)
		var l := _label(figure, font, repo.war_palette["chart_label"],
			Vector3(-(size.x * 0.5 + margin + _extent(font, figure, font_px, pixel_m).x * 0.5), cy, lift), font_px, pixel_m, false)
		l.set_meta("axis", "row")
		l.set_meta("n", row)
		chart.add_child(l)


## A label's width and height on the chart, metres: the margin is the gap between the
## map's edge and the label's own near edge, so a wide row figure never overlaps the map.
static func _extent(font: Font, text: String, font_px: int, pixel_m: float) -> Vector2:
	if font == null:
		return Vector2(0.6 * float(text.length()), 1.0) * float(font_px) * pixel_m
	return Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x, font.get_height(font_px)) * pixel_m


## The map's own size on the chart: the quad less its parchment margin.
static func map_size(chart: MeshInstance3D) -> Vector2:
	return (chart.mesh as QuadMesh).size - Vector2.ONE * 2.0 * float(chart.get_meta("margin_m", 0.0))


## The sheet under a screen px on the chart, -1 off it. `screen_px` is already
## in the viewport's own px (the view multiplies its window scale in).
## The chart UV (0..1 across the map, v down) under a screen px, (-1, -1) off
## its plane or behind the camera.
static func chart_uv(chart: MeshInstance3D, camera: Camera3D, screen_px: Vector2) -> Vector2:
	var inv := chart.global_transform.affine_inverse()
	var lo := inv * camera.project_ray_origin(screen_px)
	var ld := (inv.basis * camera.project_ray_normal(screen_px)).normalized()
	if absf(ld.z) < 0.00001:
		return Vector2(-1, -1)
	var t := -lo.z / ld.z
	if t < 0.0:
		return Vector2(-1, -1)
	var hit := lo + ld * t
	var size := map_size(chart)
	return Vector2(hit.x / size.x + 0.5, 0.5 - hit.y / size.y)


static func pick_chart(chart: MeshInstance3D, camera: Camera3D, repo: DataRepository, screen_px: Vector2) -> int:
	var uv := chart_uv(chart, camera, screen_px)
	return -1 if uv.x < 0.0 else WarIndexChart.sheet_at_uv(repo, uv)


## A chart UV as a world point on the chart's face (the war marker lands here).
static func chart_point(chart: MeshInstance3D, uv: Vector2) -> Vector3:
	var size := map_size(chart)
	return chart.global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0.0)


## The unit normal of the chart's face (toward the camera): a marker laid on the
## chart stands along it, not along the world's up.
static func chart_normal(chart: MeshInstance3D) -> Vector3:
	return chart.global_transform.basis.z.normalized()


## Where resting war marker `slot` stands: a column beside the chart's east
## edge, `gap` apart and `off` off it (the tray; owner 2026-10-12, item 7). The column runs down the
## lean's footprint, and the markers stand on the OAK (the chart's foot height), not in
## the air along the leaning plane.
static func tray_point(chart: MeshInstance3D, slot: int, gap: float, off := -1.0) -> Vector3:
	var size := map_size(chart)
	var pad := float(chart.get_meta("margin_m", 0.0))
	var p := chart.global_transform * Vector3(size.x * 0.5 + pad + (gap if off < 0.0 else off), size.y * 0.5 - gap * float(slot), 0.0)
	p.y = float(chart.get_meta("foot_y_m", p.y))
	return p


## Replace the arrows: one at each side the markers can all move toward
## (WarTray.can_shift: every held cell has a sheet beside it there; one marker,
## each side with a neighbour), labelled with the sheet that move lays and
## carrying, as `sheet`, the neighbour of `lead` on that side.
static func lay_arrows(parent: Node3D, repo: DataRepository, tray: WarTray, lead: int, table_w: float, depth: float,
		font: Font) -> void:
	for n in parent.get_children():
		parent.remove_child(n)
		n.queue_free()
	var gap := repo.bal("war_arrow_gap_m")
	var y := repo.bal("war_arrow_y_m")
	# the north arrow keeps its own gap: beyond the north edge stands the leaning index chart and its column letters
	var places := {"n": Vector3(0.0, y, -depth * 0.5 - repo.bal("war_arrow_gap_n_m")), "s": Vector3(0.0, y, depth * 0.5 + gap),
		"e": Vector3(table_w * 0.5 + gap, y, 0.0), "w": Vector3(-table_w * 0.5 - gap, y, 0.0)}
	var near := WarSheets.neighbours(repo, lead)
	for side: String in near:
		var to := int(near[side])
		var moved := tray.shifted(tray.cell_of(to) - tray.cell_of(lead))
		if moved.is_empty():
			continue
		var a := _label("%s %s" % [SIDES[side], WarSheets.union(repo, moved)["id"]], font, repo.war_palette["ink"],
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
