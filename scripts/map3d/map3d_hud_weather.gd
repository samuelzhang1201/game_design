class_name Map3DHudWeather
extends Map3DHudPiece
## The weather marks (spec 2026-09-27-courier-core §2): each province whose
## weather is not clear today shows its weather's icon at its centre — only
## within `view_m` of the camera, inside the view, off the
## settlement dots, the regiments' counters and the couriers, and clear of
## one another (the first in province order keeps its place). The icon is
## resource_icons.csv's art once installed (sub-project D), its glyph till then.

## The marks show only while the camera is nearer than this (world metres).
@export var view_m := 60000.0
## A mark's size, design px.
@export var icon_px := 13.0

## The settlement dots' rects, cut once per camera pose (~1.5 ms a call).
var _dots: Array = []
var _dots_key: Array = []
## Today's marks on the ground, cut once per day (final review: Weather.of and
## a ground sample for every province were paid on every redraw) ...
var _day_marks: Array = []
var _day_key: Array = []
## ... and on the screen, cut once per camera pose.
var _screen_marks: Array = []
var _screen_key: Array = []


func _draw() -> void:
	if not bound() or ctx.state() == null or ctx.distance > view_m:
		return
	var px := icon_px
	# Whole inside the view, never cut by its edge (critic 2026-09-28).
	var inside := Rect2(Vector2.ZERO, size).grow(-px)
	for m: Dictionary in thin(screen_marks(), px * 1.5, inside, taken(), px):
		_draw_icon(String(m["kind"]), m["at"], px)


## {kind, ground: Vector3} for each province whose weather is not clear
## today, in province order; the same Array until the day, the campaign's
## seed or the pack changes.
func day_marks() -> Array:
	var repo := ctx.repo
	var st := ctx.state()
	var key := [repo.map_id, st.rng.seed_value() if st.rng != null else 0, st.absolute_day()]
	if key == _day_key:
		return _day_marks
	_day_marks = []
	var codes := repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var kind := Weather.of(repo, st, code, st.absolute_day())
		if kind == Weather.CLEAR:
			continue
		var prov: Dictionary = repo.provinces[code]
		_day_marks.append({"kind": kind,
			"ground": ctx.ground_of_pack(Vector2(float(prov["center_x"]), float(prov["center_y"])))})
	_day_key = key
	return _day_marks


## day_marks() projected, {kind, at} in design px, those behind the camera
## left out; cut once per camera pose.
func screen_marks() -> Array:
	var ground := day_marks()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(), _day_key]
	if key == _screen_key:
		return _screen_marks
	_screen_marks = []
	for m: Dictionary in ground:
		var p: Vector3 = m["ground"]
		if not ctx.camera.is_position_behind(p):
			_screen_marks.append({"at": ctx.camera.unproject_position(p) / ctx.viewport_px_scale(),
				"kind": m["kind"]})
	_screen_key = key
	return _screen_marks


## Everything a weather mark keeps off, as design-px rects: the settlement
## dots and the kingdom names (cut once per camera pose), the MANORS badges, the regiments'
## counters with their bars, their pieces and march end rings, the couriers
## and their pending orders' envelope rings (read live: they walk).
func taken() -> Array:
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(),
		ctx.state().absolute_day() if ctx.state() != null else 0]
	if key != _dots_key:
		_dots = ctx.settlement_rects()
		var labels := sibling("Labels") as Map3DHudLabels
		if labels != null:
			_dots.append_array(labels.rects())
		_dots_key = key
	var out := _dots.duplicate()
	# The MANORS output badges too (critic 2026-09-28: a mark sat on "5").
	var badges := sibling("Badges") as Map3DHudBadges
	if badges != null:
		for b: Dictionary in badges.badges():
			out.append(b["rect"])
	var armies := sibling("Armies") as Map3DHudArmies
	if armies != null:
		for a: Dictionary in armies.markers():
			out.append(a["rect"])
		var couriers := sibling("Couriers") as Map3DHudCouriers
		var ring := (couriers.ring_px() if couriers != null else 8.0) + armies.route_px
		for e: Dictionary in armies.route_ends():
			out.append(Rect2((e["pos"] as Vector2) - Vector2(ring, ring), Vector2(ring, ring) * 2.0))
	for r: Rect2 in (view.unit_rects() as Dictionary).values():
		out.append(r)
	for r: Dictionary in (view.courier_rects() as Dictionary).values():
		out.append(r["rect"])
	var couriers := sibling("Couriers") as Map3DHudCouriers
	if couriers != null:
		out.append_array(couriers.pending_rects())
	return out


## The marks inside `bounds`, each at least `min_px` from every mark kept
## before it, and — `box_px` square about its point — over none of `occupied`.
static func thin(marks: Array, min_px: float, bounds: Rect2, occupied: Array = [], box_px: float = 0.0) -> Array:
	var out: Array = []
	for m: Dictionary in marks:
		var at: Vector2 = m["at"]
		if not bounds.has_point(at):
			continue
		var box := Rect2(at - Vector2(box_px, box_px) * 0.5, Vector2(box_px, box_px))
		var clear := true
		for r: Rect2 in occupied:
			if box.intersects(r):
				clear = false
				break
		for k: Dictionary in out:
			if (k["at"] as Vector2).distance_to(at) < min_px:
				clear = false
				break
		if clear:
			out.append(m)
	return out


func _draw_icon(kind: String, at: Vector2, px: float) -> void:
	var row: Dictionary = ctx.repo.resource_icons.get(String((ctx.repo.weather_kinds.get(kind, {}) as Dictionary).get("icon", "")), {})
	var path := String(row.get("texture", ""))
	var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	if tex != null:
		ResourceIcon.draw_icon_texture(self, tex, at, px)
		return
	# No disc (owner 2026-09-28, second critique: a black disc with a white
	# glyph was the last web-bright sticker on the map, and a gold-rimmed
	# one was still a tray): the bare glyph in dimmed parchment over a soft
	# dark shadow, like ink on the map rather than a badge on it.
	var glyph := String(row.get("icon", "sun"))
	var shade := MapPalette.named(ctx.repo, "weather_mark_bg")
	for off: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(0, 1.5)]:
		ResourceIcon.draw_glyph(self, glyph, at + off, px, Color(shade, 0.45))
	ResourceIcon.draw_glyph(self, glyph, at, px, MapPalette.named(ctx.repo, "weather_mark_glyph"))
