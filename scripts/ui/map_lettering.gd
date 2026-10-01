class_name MapLettering
extends RefCounted
## Kingdom names set like printed map lettering — shared by the 2D map
## (WorldMapView) and the 3D map's HUD (Map3DHudLabels), so the two
## letter a realm the same way: blackletter in the name's own case
## (UiPalette.map_label_font), map_label_tracking between the glyphs, in the
## coast ink at map_label_alpha.


## Ink, not gold (owner 2026-09-12, after docs/references/mapSample.jpg:
## realm names are set in dark serif capitals over the wash).
static func ink(repo: DataRepository) -> Color:
	if MapPalette.war_table(repo) and repo.terrain_palette.has("map_label_ink_table"):
		return MapTerrain.palette_color(repo, "map_label_ink_table", MapTerrain.FALLBACK)
	var color := MapTerrain.palette_color(repo, "coast_line", MapTerrain.FALLBACK)
	color.a = repo.bal("map_label_alpha")
	return color


## A faint parchment halo under the ink (2026-09-24, look route Phase 4):
## under Forward+ and the new grade the ground went darker and the dark ink
## sank into it; the ink stays ink (the owner's 2026-09-12 ruling) and the
## halo lifts it — terrain_palette map_label_halo at map_label_halo_alpha.
static func halo(repo: DataRepository) -> Color:
	if MapPalette.war_table(repo) and repo.terrain_palette.has("map_label_halo_table"):
		# its alpha is the row's own (#rrggbbaa)
		return Color(String(repo.terrain_palette["map_label_halo_table"]))
	var color := MapTerrain.palette_color(repo, "map_label_halo", Color(0.94, 0.9, 0.82))
	color.a = repo.bal("map_label_halo_alpha")
	return color


## draw_string has no letter-spacing, and tracking is most of what makes a
## label read as engraved rather than typed — so the glyphs are placed one at
## a time with the extra advance added between them.
static func draw_tracked(ci: CanvasItem, font: Font, text: String, origin: Vector2,
		font_px: int, tracking: float, color: Color, halo_color := Color(0, 0, 0, 0),
		halo_px := 0) -> void:
	var pen := origin
	for i in text.length():
		var ch := text.substr(i, 1)
		if halo_color.a > 0.0 and halo_px > 0:
			font.draw_string_outline(ci.get_canvas_item(), pen, ch, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_px, halo_px, halo_color)
		font.draw_string(ci.get_canvas_item(), pen, ch, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_px, color)
		pen.x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x \
			+ tracking


static func tracked_width(font: Font, text: String, font_px: int, tracking: float) -> float:
	if text.is_empty():
		return 0.0
	var w := 0.0
	for i in text.length():
		w += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_px).x + tracking
	return w - tracking


## Letter `text` centred on `at` (its x the word's middle, its y the anchor)
## at `px`, unless its box misses `frame`. Returns whether it was drawn.
static func draw_centred(ci: CanvasItem, repo: DataRepository, font: Font, text: String,
		at: Vector2, px: float, frame: Rect2) -> bool:
	var font_px := int(px)
	var tracking := px * repo.bal("map_label_tracking")
	var box := box_centred(repo, font, text, at, px)
	if not frame.intersects(box):
		return false
	draw_tracked(ci, font, text, box.position + Vector2(0, px), font_px, tracking, ink(repo), halo(repo),
		int(round(px * repo.bal("map_label_halo_frac"))))
	return true


## The box draw_centred letters `text` in: its width, from a cap height above
## the baseline to below the descenders.
static func box_centred(repo: DataRepository, font: Font, text: String, at: Vector2, px: float) -> Rect2:
	var width := tracked_width(font, text, int(px), px * repo.bal("map_label_tracking"))
	var origin := at - Vector2(width * 0.5, -px * 0.35)
	return Rect2(origin - Vector2(0, px), Vector2(width, px * 1.4))
