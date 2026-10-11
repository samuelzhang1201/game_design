class_name Map3DHudManorBars
extends Map3DHudPiece
## MANORS' bars (owner 2026-10-04: 玩家自己省内的每个manor以柱状图显示人口和财富):
## over each manor ManorBars.rows names — every manor of a province the crown
## controls, and another only once a credible spy's report on it has come in —
## two bars standing on its ground: its PEOPLE and its WORTH a month (tax and
## goods in gold), each against its own kind's most among all the rows, so a
## bar compares across the realm. Known figures are solid ink-edged bars; a
## scouted manor's are its report's middle, hatched in the bar's colour inside
## a dashed outline in the intel ink, with a thin whisker over the report's
## range — an estimate, never the truth. A pair steps right of a working
## manor's output badge and out from under the regiments' counters. A key
## bottom-left names the two bars and the hatching. The look is these exports,
## edited on the Hud's ManorBars node in world_map_3d.tscn.

## A bar's width and the gap between the pair, design px.
@export var bar_px := 7.0
@export var gap_px := 2.0
## The tallest bar, design px (the realm's most of each), and the least drawn.
@export var max_h_px := 50.0
@export var min_h_px := 3.0
## People in a deep azure (parted from the crown's teal wash by value, not
## hue), worth in or — the heraldic data set.
@export var people_color := Color("34507a")
@export var worth_color := Color("c9a13a")
## The ink round each bar and along the foot of the pair (overhanging it).
@export var ink := Color("2a1e16")
@export var ink_px := 1.0
@export var foot_overhang_px := 2.0
## The one light's soft shadow, down and right, so a bar holds on any wash.
@export var shadow := Color(0, 0, 0, 0.28)
@export var shadow_offset := Vector2(1.5, 1.5)
## A scouted manor: hatching in the bar's colour at this pitch, a dashed
## outline in the intel ink, the range's whisker and its caps.
@export var hatch_pitch_px := 2.5
@export var hatch_px := 1.2
@export var intel_ink := Color("6a4f8a")
@export var dash_px := 2.0
@export var whisker_px := 1.0
@export var whisker_cap_px := 3.0
## The bars show only while the camera is nearer than this, world metres.
@export var view_m := 90000.0
## How far right of a badge's centre a pair stands when the manor wears one,
## and how far a pair steps right, at most `clear_steps` times, to come out
## from under a regiment's counter.
@export var badge_clear_px := 15.0
@export var clear_step_px := 10.0
@export var clear_steps := 4
## The key, bottom-left (where HEIGHTS keeps its legend): its words' size and
## its inset from the corner, design px.
@export var key_font_px := 14
@export var key_inset := Vector2(14, 16)

var _rows: Array = []
var _rows_key: Array = []
var _scale: Dictionary = {}
var _cut_cache: Array = []
var _cut_key: Array = []


## The rows, read again only when the date, the letters, the holdings or DEV
## MODE change (a row's line is the month's, a report is a letter).
func rows() -> Array:
	var st := ctx.state()
	if st == null:
		return []
	var key := [st.tick, st.next_missive_id, st.manor_owner.size(), st.manor_province.size(),
		Intel.dev_all, ctx.repo]
	if key != _rows_key:
		_rows = ManorBars.rows(ctx.repo, st)
		_scale = ManorBars.scale_of(_rows)
		_rows_key = key
	return _rows


## The pairs on the screen: {cell, at (design px, the pair's foot centre), row}.
## Cut once per camera pose. [] off MANORS or past view_m.
func bars() -> Array:
	if not bound() or view.manor_theme() != "manors" or ctx.distance > view_m:
		return []
	var all := rows()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(), _rows_key,
		view.unit_rects().size(), view.unit_moves()]
	if key == _cut_key:
		return _cut_cache
	var badges: Array = []
	var b := sibling("Badges") as Map3DHudBadges
	if b != null:
		badges = b.badges()
	var counters: Array = []
	var armies := sibling("Armies") as Map3DHudArmies
	if armies != null:
		for m: Dictionary in armies.markers():
			counters.append((m["rect"] as Rect2).grow(2.0))
	for r: Rect2 in view.unit_rects().values():
		counters.append(r)
	var s := ctx.viewport_px_scale()
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(max_h_px)
	var out: Array = []
	for r: Dictionary in all:
		var ground := ctx.cell_ground(int(r["cell"]))
		if ctx.camera.is_position_behind(ground):
			continue
		var at := ctx.camera.unproject_position(ground) / s
		if not frame.has_point(at):
			continue
		for bd: Dictionary in badges:
			if int(bd["cell"]) == int(r["cell"]):
				at.x += badge_clear_px + bar_px
				break
		for i in clear_steps:
			var box := _box(at, r)
			if not counters.any(func(c: Rect2) -> bool: return c.intersects(box)):
				break
			at.x += clear_step_px
		out.append({"cell": int(r["cell"]), "at": at, "row": r})
	_cut_cache = out
	_cut_key = key
	return out


## A pair's footprint at `at`, design px.
func _box(at: Vector2, r: Dictionary) -> Rect2:
	var tall := maxf(_h(r, "people"), _h(r, "worth") if int(r["worth"]) >= 0 else 0.0)
	var x0 := at.x - bar_px - gap_px * 0.5 - foot_overhang_px
	return Rect2(x0, at.y - tall - whisker_cap_px, bar_px * 2.0 + gap_px + foot_overhang_px * 2.0,
		tall + whisker_cap_px + ink_px)


func _draw() -> void:
	var pairs := bars()
	for p: Dictionary in pairs:
		var r: Dictionary = p["row"]
		var at: Vector2 = p["at"]
		var x0 := at.x - bar_px - gap_px * 0.5
		var x1 := at.x + gap_px * 0.5
		_bar(x0, at.y, r, "people", people_color)
		if int(r["worth"]) >= 0:
			_bar(x1, at.y, r, "worth", worth_color)
		var foot_ink := ink if not bool(r["estimate"]) else intel_ink
		draw_line(Vector2(x0 - foot_overhang_px, at.y), Vector2(x1 + bar_px + foot_overhang_px, at.y),
			foot_ink, ink_px, true)
	if not pairs.is_empty():
		_draw_key()


## A bar's drawn height, design px: an estimate stands at its middle.
func _h(r: Dictionary, kind: String) -> float:
	return maxf(min_h_px, max_h_px * float(r[kind]) / float(_scale.get(kind, 1)))


## One bar standing on `foot_y` at `x`, its shadow first.
func _bar(x: float, foot_y: float, r: Dictionary, kind: String, col: Color) -> void:
	var h := _h(r, kind)
	var box := Rect2(x, foot_y - h, bar_px, h)
	draw_rect(Rect2(box.position + shadow_offset, box.size), shadow)
	if not bool(r["estimate"]):
		draw_rect(box, col)
		draw_rect(box, ink, false, ink_px)
		return
	# an estimate: the paper shows through the hatching, a dashed edge, and
	# the report's range as a whisker standing proud of the bar
	draw_rect(box, Color(1, 1, 1, 0.18))
	_hatch(box, col)
	_dashed_rect(box, intel_ink)
	var most := float(_scale.get(kind, 1))
	var lo := foot_y - maxf(min_h_px, max_h_px * float(r[kind + "_lo"]) / most)
	var hi := foot_y - maxf(min_h_px, max_h_px * float(r[kind + "_hi"]) / most)
	var cx := x + bar_px * 0.5
	draw_line(Vector2(cx, lo), Vector2(cx, hi), intel_ink, whisker_px, true)
	for y in [lo, hi]:
		draw_line(Vector2(cx - whisker_cap_px * 0.5, y), Vector2(cx + whisker_cap_px * 0.5, y),
			intel_ink, whisker_px, true)


## 45° hatching inside `box` in `col`.
func _hatch(box: Rect2, col: Color) -> void:
	var w := box.size.x
	var h := box.size.y
	var t := -w
	while t < h:
		# the line y = x + t (box space), clipped to the box
		var a := Vector2(maxf(0.0, -t), maxf(0.0, t))
		var b := Vector2(minf(w, h - t), minf(h, w + t))
		if b.x > a.x:
			draw_line(box.position + a, box.position + b, col, hatch_px, true)
		t += hatch_pitch_px


func _dashed_rect(box: Rect2, col: Color) -> void:
	var c := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		draw_dashed_line(c[i], c[(i + 1) % 4], col, ink_px, dash_px, true, true)


## The key, bottom-left: a solid azure bar "People", a solid or bar "Gold a
## month", and — once a scouted manor stands on the map — a hatched bar "A spy's
## estimate". HEIGHTS' legend has the corner only under HEIGHTS.
func _draw_key() -> void:
	var font := UiPalette.display_font()
	if font == null:
		return
	var rows_: Array = [["People", people_color, false], ["Gold a month", worth_color, false]]
	if _rows.any(func(r: Dictionary) -> bool: return bool(r["estimate"])):
		rows_.append(["A spy's estimate", worth_color, true])
	var line_h := float(key_font_px) + 6.0
	var y := size.y - key_inset.y - line_h * float(rows_.size())
	var halo := Color((get_parent() as Map3DHud).halo_color, 0.85) if get_parent() is Map3DHud \
		else Color(0.95, 0.93, 0.87, 0.85)
	for row: Array in rows_:
		var box := Rect2(key_inset.x, y + 2.0, bar_px, line_h - 6.0)
		draw_rect(Rect2(box.position + shadow_offset, box.size), shadow)
		if bool(row[2]):
			draw_rect(box, Color(1, 1, 1, 0.18))
			_hatch(box, row[1])
			_dashed_rect(box, intel_ink)
		else:
			draw_rect(box, row[1])
			draw_rect(box, ink, false, ink_px)
		var at := Vector2(box.end.x + 6.0, y + float(key_font_px))
		var text := String(row[0])
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, at + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, key_font_px, halo)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, key_font_px, ink)
		y += line_h
