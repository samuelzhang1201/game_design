class_name ArmyCounters
extends RefCounted
## The MILITARY layer's counters (owner 2026-09-13 on the 2D map, 2026-09-19
## on the 3D map): each of the player's regiments as a square — its painted
## piece (data/army_art.csv), else a glyph: swords, a crown for the royal
## regiment, waves for a fleet — joined to a box in the realm's hue stating
## the headcount. Shared by both maps: each map gathers its regiments' screen
## points and the settlement marks to keep clear of, and hands them here.
## Every colour and size is political_palette.csv army_* / balance.csv
## map_army_*.


## The counters for `points` ([{reg, pos}], pos in the map's screen px) at
## height `h`: {code, pos, size, text, font_px, rect, icon, count, glyph,
## piece, color, naval, royal}. Sorted top to bottom; a counter meeting a
## settlement mark or an earlier counter drops to just under it, so no
## counter ever covers a town or another counter.
static func layout(repo: DataRepository, points: Array, h: float, obstacles: Array) -> Array:
	var mine := repo.resolve_realm("player_realm")
	var royal := MapObjects.royal_regiment(repo, mine)
	var pad := repo.bal("map_army_count_pad_px")
	var gap := repo.bal("map_army_stack_gap_px")
	var font_px := maxi(int(round(h * repo.bal("map_army_font_frac"))), 1)
	var font := UiPalette.body_font()
	var color := count_color(repo, mine)
	var out: Array = []
	for p: Dictionary in points:
		var r: Dictionary = p["reg"]
		var sp: Vector2 = p["pos"]
		var code := String(r["regiment_code"])
		var strength := MapObjects.regiment_size(repo, r)
		var naval := String(r.get("is_naval", "0")) == "1"
		var text := str(int(strength))
		var count_w := maxf(h, ManorBadges.text_width(font, text, font_px) + pad * 2.0)
		var w := h + count_w
		out.append({"code": code, "pos": sp, "size": strength, "text": text,
			"font_px": font_px, "rect": Rect2(sp - Vector2(w, h) / 2.0, Vector2(w, h)),
			"glyph": "waves" if naval else ("crown" if code == royal else "swords"),
			"piece": MapObjects.army_piece(repo, r),
			"color": color, "naval": naval, "royal": code == royal})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := (a["pos"] as Vector2).y
		var by := (b["pos"] as Vector2).y
		return String(a["code"]) < String(b["code"]) if ay == by else ay < by)
	# The settlements are obstacles from the start: counters only ever move
	# down, so a counter meeting a town drops to just under its mark.
	var placed: Array = obstacles.duplicate()
	for m: Dictionary in out:
		var rect: Rect2 = m["rect"]
		# Each push can land on another obstacle, so go round again until the
		# rect is clear; every pass moves it strictly down, so this ends.
		var moved := true
		while moved:
			moved = false
			for other: Rect2 in placed:
				if rect.intersects(other.grow(gap * 0.5)):
					rect.position.y = other.end.y + gap
					moved = true
		placed.append(rect)
		m["rect"] = rect
		m["icon"] = Rect2(rect.position, Vector2(h, h))
		m["count"] = Rect2(rect.position + Vector2(h, 0.0), Vector2(rect.size.x - h, h))
	return out


## The colour of a realm's headcount box: the realm's own hue, pushed to at
## least map_army_count_sat and set at map_army_count_val, so the box reads as
## a solid counter over that realm's pale wash rather than disappearing into it.
static func count_color(repo: DataRepository, kingdom_code: String) -> Color:
	var c := MapPalette.color_of(repo, kingdom_code)
	return Color.from_hsv(c.h, maxf(c.s, repo.bal("map_army_count_sat")),
		repo.bal("map_army_count_val"))


## Draw `markers` (from layout) on `ci`; the counter coded `selected`, if any,
## is outlined in gold.
static func draw(ci: CanvasItem, repo: DataRepository, markers: Array, selected := "") -> void:
	if markers.is_empty():
		return
	var outline := MapPalette.named(repo, "army_outline")
	var icon_bg := MapPalette.named(repo, "army_icon_bg")
	var glyph_ink := MapPalette.named(repo, "army_glyph")
	var count_ink := MapPalette.named(repo, "army_count_ink")
	var line := repo.bal("map_army_outline_px")
	var glyph_frac := repo.bal("map_army_glyph_frac")
	var font := UiPalette.body_font()
	for m: Dictionary in markers:
		var rect: Rect2 = m["rect"]
		var icon: Rect2 = m["icon"]
		var count: Rect2 = m["count"]
		# The painted 3D piece (owner 2026-09-15, data/army_art.csv) stands in the
		# counter's square on its own base; the glyph square only without art.
		var art := UiPalette.load_art(String((repo.army_art.get(String(m["piece"]), {}) as Dictionary).get("texture", "")))
		if art != null:
			ci.draw_rect(count.grow(line), outline)
			ci.draw_rect(count, m["color"])
			# Fitted to the square's HEIGHT: a piece is wider than tall, and fitted
			# to its width it read as a flat disc; the overhang is a few px.
			var ts := art.get_size()
			var drawn := ts * (icon.size.y / ts.y)
			ci.draw_texture_rect(art, Rect2(icon.position + (icon.size - drawn) * Vector2(0.5, 1.0), drawn), false)
		else:
			ci.draw_rect(rect.grow(line), outline)
			ci.draw_rect(icon, icon_bg)
			ci.draw_rect(count, m["color"])
			ci.draw_line(Vector2(icon.end.x, rect.position.y), Vector2(icon.end.x, rect.end.y),
				outline, line)
			ResourceIcon.draw_glyph(ci, String(m["glyph"]), icon.get_center(),
				icon.size.y * glyph_frac, glyph_ink)
		ManorBadges.draw_centered_text(ci, font, count, String(m["text"]), int(m["font_px"]), count_ink)
		if String(m["code"]) == selected and selected != "":
			ci.draw_rect(rect.grow(repo.bal("map_army_outline_px") + 1.5), UiPalette.GOLD, false, 2.0)
