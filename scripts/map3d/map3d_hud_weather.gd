class_name Map3DHudWeather
extends Map3DHudPiece
## The weather marks (spec 2026-09-27-courier-core §2): each province whose
## weather is not clear today shows its weather's icon at its centre — only
## within map3d_weather_view_m of the camera, inside the view, and clear of
## one another (the first in province order keeps its place). The icon is
## resource_icons.csv's art once installed (sub-project D), its glyph till then.


func _draw() -> void:
	if not bound() or ctx.state() == null or ctx.distance > ctx.repo.bal("map3d_weather_view_m"):
		return
	var repo := ctx.repo
	var st := ctx.state()
	var px := repo.bal("map3d_weather_icon_px")
	var marks: Array = []
	var codes := repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var kind := Weather.of(repo, st, code, st.absolute_day())
		if kind == Weather.CLEAR:
			continue
		var prov: Dictionary = repo.provinces[code]
		var p := ctx.ground_of_pack(Vector2(float(prov["center_x"]), float(prov["center_y"])))
		if ctx.camera.is_position_behind(p):
			continue
		marks.append({"at": ctx.camera.unproject_position(p) / ctx.viewport_px_scale(), "kind": kind})
	for m: Dictionary in thin(marks, px * 1.5, Rect2(Vector2.ZERO, size)):
		_draw_icon(String(m["kind"]), m["at"], px)


## The marks inside `bounds`, each at least `min_px` from every mark kept before it.
static func thin(marks: Array, min_px: float, bounds: Rect2) -> Array:
	var out: Array = []
	for m: Dictionary in marks:
		var at: Vector2 = m["at"]
		if not bounds.has_point(at):
			continue
		var clear := true
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
	draw_circle(at, px * 0.62, MapPalette.named(ctx.repo, "weather_mark_bg"))
	ResourceIcon.draw_glyph(self, String(row.get("icon", "sun")), at, px,
		MapPalette.named(ctx.repo, "army_glyph"))
