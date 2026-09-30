class_name MapRuler
extends RefCounted
## The MEASUREMENT tab's ruler (owner 2026-09-18), one per map view. A left
## click drops the anchor, the pointer stretches the ruler, a second click
## fixes it (a click after that starts a new one) and a right click puts it
## away. The points are in the view's own measuring space — the 2D map's
## native px, the 3D map's world XZ metres — and both views read a length
## in the pack's own measure (map_info.csv distance_scale, distance_unit),
## so the same two towns read the same on either map (owner 2026-09-18).
##
## draw() is the one look both views share: an ink dashed line on a pale
## halo, a dot and a crossbar at each end, a one-sided tick at every 1-2-5
## step, the reading at the middle (political_palette ruler_*, balance map_ruler_*).

enum Phase { IDLE, STRETCHING, FIXED }

var phase := Phase.IDLE
var start := Vector2.ZERO
var end := Vector2.ZERO


## A left click (not a drag) at `p`.
func click(p: Vector2) -> void:
	if phase == Phase.STRETCHING:
		end = p
		phase = Phase.FIXED
	else:
		start = p
		end = p
		phase = Phase.STRETCHING


## The pointer at `p`; true when the ruler changed and wants a redraw.
func move(p: Vector2) -> bool:
	if phase != Phase.STRETCHING or p == end:
		return false
	end = p
	return true


## A right click: puts the ruler away. True when there was one to put away.
func cancel() -> bool:
	var had := active()
	phase = Phase.IDLE
	return had


func active() -> bool:
	return phase != Phase.IDLE


## The ruler's length in its measuring space.
func length() -> float:
	return start.distance_to(end)


## A length in the pack's unit: whole from 10 up, one decimal under it.
static func reading(dist: float, unit: String) -> String:
	var num := ScaleBar.trim_zeros(snappedf(dist, 0.1)) if dist < 10.0 \
		else str(int(roundf(dist)))
	return "%s %s" % [num, unit] if unit != "" else num


## The tick step: the 1-2-5 step nearest above `min_px` screen px, given
## how many measuring units one screen px spans.
static func tick_step(units_per_px: float, min_px: float) -> float:
	return MapGeometry.nice_step(units_per_px * min_px)


## Distances from the anchor of every tick strictly inside a ruler of
## `length`, `step` apart.
static func ticks(length_units: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if step <= 0.0:
		return out
	var d := step
	while d < length_units - step * 1e-4:
		out.append(d)
		d += step
	return out


## The ruler on `ci` in its own px: `a` the anchor, `b` the other end, `tick_pts`
## the ticks' screen points along it, `text` the reading. `px` scales every
## balance px value (1 for a Control drawn in design px). `ink_over` (alpha
## > 0) replaces the ink, and `arrow` ends the rule at `b` in an arrowhead
## instead of a crossbar — the MARCH aim's ruler (owner 2026-09-24: 像那个
## measurement的标尺类似，但是颜色是玩家国家颜色). `path` (a..b, at least two
## points) lays the rule along it instead of the straight line — the aim's,
## draped on the ground the column will walk (owner 2026-09-30: 瞄准测距尺也改成贴地).
static func draw(ci: CanvasItem, a: Vector2, b: Vector2, tick_pts: PackedVector2Array,
		text: String, px: float = 1.0, ink_over := Color(0, 0, 0, 0), arrow := false,
		path := PackedVector2Array()) -> void:
	var data := Game.data
	var ink := ink_over if ink_over.a > 0.0 else MapPalette.named(data, "ruler_ink")
	var halo := MapPalette.named(data, "ruler_halo")
	halo.a = data.bal("map_ruler_halo_alpha")
	var w := data.bal("map_ruler_width_px") * px
	var hw := w + 2.0 * data.bal("map_ruler_halo_px") * px
	var anchor_r := data.bal("map_ruler_anchor_px") * px
	var tick_len := data.bal("map_ruler_tick_px") * px
	var line := path if path.size() >= 2 else PackedVector2Array([a, b])
	var dir := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	# each end is square to the line where it ends, which a draped rule bends
	var side_a := _normal(line[1] - line[0], side)
	var side_b := _normal(line[line.size() - 1] - line[line.size() - 2], side)
	var dir_b := Vector2(side_b.y, -side_b.x)
	# Ticks stand on ONE side, off the line's edge (the side away from the
	# reading), so a tick never crosses a dash into a "+" or a gap into a
	# "T"; each end is a crossbar over a dot, the way a rule ends — nothing
	# a settlement ring or a border could be mistaken for.
	var up := side if side.y < 0.0 else -side
	var down := -up
	var foot := w * 0.5
	var tick_segs: Array = []
	for t in tick_pts:
		tick_segs.append([t + down * foot, t + down * (foot + tick_len)])
	var caps: Array = [[a - side_a * tick_len * 1.6, a + side_a * tick_len * 1.6]]
	if not arrow:
		caps.append([b - side_b * tick_len * 1.6, b + side_b * tick_len * 1.6])
	var head := PackedVector2Array()
	if arrow:
		var hl := data.bal("map_ruler_arrow_px") * px
		head = PackedVector2Array([b, b - dir_b * hl + side_b * hl * 0.55, b - dir_b * hl - side_b * hl * 0.55])
	# Halo first — the line, every tick, both ends — so the ink above reads
	# over snow, sea and grass alike.
	if a.distance_to(b) > 0.001:
		ci.draw_polyline(line, halo, hw, true)
	for seg in tick_segs + caps:
		ci.draw_line(seg[0], seg[1], halo, hw, true)
	ci.draw_circle(a, anchor_r + hw * 0.5, halo)
	if arrow:
		ci.draw_polyline(head + PackedVector2Array([b]), halo, hw, true)
	else:
		ci.draw_circle(b, anchor_r + hw * 0.5, halo)
	if a.distance_to(b) > 0.001:
		dashed_path(ci, line, ink, w, data.bal("map_ruler_dash_px") * px)
	for seg in tick_segs + caps:
		ci.draw_line(seg[0], seg[1], ink, w, true)
	ci.draw_circle(a, anchor_r, ink)
	if arrow:
		ci.draw_colored_polygon(head, ink)
	else:
		ci.draw_circle(b, anchor_r, ink)
	var font := UiPalette.display_font()
	if font == null or text == "":
		return
	var font_px := int(data.bal("map_ruler_font_px") * px)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px)
	# The reading sits off the line's middle on the side that points up the
	# screen, so it never lies across the dashes or the ticks.
	var centre := line[int(line.size() * 0.5)] if line.size() > 2 else (a + b) * 0.5
	centre += up * (data.bal("map_ruler_label_offset_px") * px + size.y * 0.5)
	var pos := centre + Vector2(-size.x * 0.5, size.y * 0.25)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px,
		int(data.bal("map_ruler_label_outline_px") * px), halo)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)


## `v`'s left normal, or `fallback` for a segment too short to have one.
static func _normal(v: Vector2, fallback: Vector2) -> Vector2:
	return Vector2(-v.y, v.x).normalized() if v.length() > 0.001 else fallback


## A dashed polyline whose dashes run on across its joints (draw_dashed_line
## per segment would restart the pattern at every sample) — the draped rule
## and a march's road ahead.
static func dashed_path(ci: CanvasItem, pts: PackedVector2Array, ink: Color, w: float,
		dash: float) -> void:
	if dash <= 0.0:
		ci.draw_polyline(pts, ink, w, true)
		return
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var at := 0.0
		while at < seg:
			var run := minf(left, seg - at)
			if on:
				ci.draw_line(a.lerp(b, at / seg), a.lerp(b, (at + run) / seg), ink, w, true)
			at += run
			left -= run
			if left <= 0.0:
				on = not on
				left = dash
