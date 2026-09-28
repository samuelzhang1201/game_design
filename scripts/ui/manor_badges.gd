class_name ManorBadges
extends RefCounted
## The MANORS view's output badges (owner 2026-09-13 on the 2D map as
## ECONOMY's; 2026-09-19 on the 3D map, and ECONOMY folded into MANORS): a
## working manor's chief good as its icon in a disc ringed in the good's
## CATEGORY colour, over a chip with its units. Shared by both maps so
## they place and draw a badge the same way: each map gathers its working
## manors in screen space ({cell, burg, good, units, center}, biggest producer
## first) and hands them here. Every colour and size is political_palette.csv
## manor_* / balance.csv map_manor_*.

## Loaded goods art by path (UiPalette.load_art), kept for the session.
static var _textures: Dictionary = {}


## The badges to draw for `manors`: {cell, burg, good, units, text, badge,
## label, ring, texture, glyph, rect}, `badge` the icon disc's square and
## `label` the number chip (null without `with_label`). A badge that would
## overlap a bigger producer's is left off.
static func place(repo: DataRepository, manors: Array, with_label: bool) -> Array:
	var px := repo.bal("map_manor_badge_px")
	var font := UiPalette.body_font()
	var font_px := int(repo.bal("map_manor_label_font_px"))
	var placed: Array = []
	var out: Array = []
	for m: Dictionary in manors:
		var center: Vector2 = m["center"]
		var badge := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
		var whole := badge
		var text := ScaleBar.trim_zeros(float(m["units"]))
		var label := Rect2()
		if with_label:
			var w := text_width(font, text, font_px) + repo.bal("map_manor_label_pad_px") * 2.0
			var h := float(font_px) + 4.0
			label = Rect2(center.x - w * 0.5, badge.end.y - h * 0.3, w, h)
			whole = badge.merge(label)
		var clear := true
		for other: Rect2 in placed:
			if whole.intersects(other):
				clear = false
				break
		if not clear:
			continue
		placed.append(whole)
		var tex: Texture2D = null
		var path := String(repo.goods_art.get(String(m["good"]), ""))
		if path != "":
			if not _textures.has(path):
				_textures[path] = UiPalette.load_art(path)
			tex = _textures[path]
		var tag := MapEconomy.good_tag(repo, String(m["good"]))
		# Not every good has a drawing yet (data/goods_art.csv); those wear
		# their category's glyph from data/resource_icons.csv instead.
		var glyph := String((repo.resource_icons.get("tag_" + tag, {}) as Dictionary).get("icon", ""))
		var entry := m.duplicate()
		entry.merge({"text": text, "badge": badge, "label": null,
			"texture": tex, "glyph": glyph, "rect": whole,
			"ring": tag_color(repo, tag)})
		if with_label:
			entry["label"] = label
		out.append(entry)
	return out


## Draw `badges` (from place) on `ci`.
static func draw(ci: CanvasItem, repo: DataRepository, badges: Array) -> void:
	if badges.is_empty():
		return
	var disc := MapPalette.named(repo, "manor_badge")
	var chip := MapPalette.named(repo, "manor_label_bg")
	var ink := MapPalette.named(repo, "manor_label_ink")
	# The chip's number: its own key (owner 2026-09-28: a dark chip with light
	# figures), the outline ink when a palette has none.
	var text_ink := MapPalette.named(repo, "manor_label_text") if repo.palette.has("manor_label_text") else ink
	# A good with no art draws its category glyph on the disc: its own key, so a
	# dark chip never takes the glyph dark with it.
	var glyph_ink := MapPalette.named(repo, "manor_badge_glyph") if repo.palette.has("manor_badge_glyph") else chip
	var ring_w := repo.bal("map_manor_ring_px")
	var icon_frac := repo.bal("map_manor_icon_frac")
	var font := UiPalette.body_font()
	var font_px := int(repo.bal("map_manor_label_font_px"))
	for b: Dictionary in badges:
		var r: Rect2 = b["badge"]
		var c := r.get_center()
		var rad := r.size.x * 0.5
		ci.draw_circle(c, rad + ring_w, ink)
		ci.draw_circle(c, rad, b["ring"])
		ci.draw_circle(c, rad - ring_w, disc)
		var tex: Texture2D = b["texture"]
		var side := r.size.x * icon_frac
		if tex != null:
			var w := side * float(tex.get_width()) / float(tex.get_height())
			ci.draw_texture_rect(tex, Rect2(c - Vector2(w, side) * 0.5, Vector2(w, side)), false)
		elif String(b["glyph"]) != "":
			ResourceIcon.draw_glyph(ci, String(b["glyph"]), c, side * 0.8, glyph_ink)
		if b["label"] != null:
			var label: Rect2 = b["label"]
			ci.draw_rect(label.grow(1.0), ink)
			ci.draw_rect(label, chip)
			draw_centered_text(ci, font, label, String(b["text"]), font_px, text_ink)


## The colour a good's category wears (data/goods_palette.csv) — the badge's
## ring, and the manor card's output icons.
static func tag_color(data: DataRepository, tag: String) -> Color:
	var hex := String(data.goods_palette.get(tag, ""))
	return Color(hex) if hex != "" else UiPalette.TEXT_MUTED


static func text_width(font: Font, text: String, font_px: int) -> float:
	if font == null:
		return float(text.length() * font_px) * 0.6
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x


## Text centred in a rect, on the font's own ascent and descent so digits sit
## in the middle of the box rather than on its floor.
static func draw_centered_text(ci: CanvasItem, font: Font, rect: Rect2, text: String,
		font_px: int, color: Color) -> void:
	if font == null:
		return
	var asc := font.get_ascent(font_px)
	var desc := font.get_descent(font_px)
	var base := Vector2(rect.position.x + (rect.size.x - text_width(font, text, font_px)) * 0.5,
		rect.position.y + (rect.size.y - asc - desc) * 0.5 + asc)
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px, color)
