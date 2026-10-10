class_name ArmyCounters
extends RefCounted
## The flat counter of a unit that has NO 3D piece on the map — a fleet
## (owner 2026-09-13 on the 2D map, 2026-09-19 on the 3D map): a glyph square
## (waves for a fleet; swords, or a crown for the household — the roster's
## `is_royal` — for a land unit with no model) joined to a box in the realm's
## hue stating its headcount. A land unit is its 3D piece alone, with no
## counter, chip, bar or number over it (owner 2026-10-10). Nothing is merged
## into one counter (spec 2026-10-07-army-split-and-ground §5.1).
## Every colour and size is political_palette.csv army_* / balance.csv
## map_army_*.


## The counters for `points` ([{reg, pos}], pos in the map's screen px) at
## height `h`: {code, pos, size, text, font_px, rect, icon, count, glyph,
## piece, color, naval, royal}, one a unit. Spread by Map3DDeclutter (spec
## 2026-10-07-army-split-and-ground §5.2) in priority order — `first` (the
## selected codes), the royal household, then by men, then by code — so no
## counter covers an obstacle (a settlement mark, a 3D piece) or another: the
## first never moves, each other takes the nearest clear place out to
## map3d_declutter_max_px, else the clearest it found (never hidden). Two
## counters stand at least map_army_stack_gap_px apart, rim to rim: each box is
## grown by its drawn rim (outline_px) and half the gap for the spreading.
static func layout(repo: DataRepository, points: Array, h: float, obstacles: Array,
		first: Array = []) -> Array:
	var mine := repo.resolve_realm("player_realm")
	var pad := repo.bal("map_army_count_pad_px")
	var font := UiPalette.body_font()
	var out: Array = []
	var colors: Dictionary = {}  # kingdom -> count_color, once a layout (perf 2026-10-02)
	for p: Dictionary in points:
		var r: Dictionary = p["reg"]
		var sp: Vector2 = p["pos"]
		var code := String(r["regiment_code"])
		var strength := MapObjects.regiment_size(repo, r)
		var naval := String(r.get("is_naval", "0")) == "1"
		var royal := String(r.get("is_royal", "0")) == "1"
		var text := str(int(strength))
		var font_px := maxi(int(round(h * repo.bal("map_army_font_frac"))), 1)
		var count_w := maxf(h, ManorBadges.text_width(font, text, font_px) + pad * 2.0)
		var w := h + count_w
		var kingdom := String(r.get("kingdom_code", mine))
		if not colors.has(kingdom):
			colors[kingdom] = count_color(repo, kingdom)
		out.append({"code": code, "pos": sp, "size": strength, "text": text, "font_px": font_px,
			"rect": Rect2(sp - Vector2(w, h) / 2.0, Vector2(w, h)),
			"glyph": "waves" if naval else ("crown" if royal else "swords"),
			"piece": MapObjects.army_piece(repo, r),
			"color": colors[kingdom],
			"naval": naval, "royal": royal})
	# Priority (spec §5.2): the selected, the royal household, then by men, then code.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := first.has(a["code"])
		var sb := first.has(b["code"])
		if sa != sb:
			return sa
		if bool(a["royal"]) != bool(b["royal"]):
			return bool(a["royal"])
		if float(a["size"]) != float(b["size"]):
			return float(a["size"]) > float(b["size"])
		return String(a["code"]) < String(b["code"]))
	var room := outline_px(repo) + repo.bal("map_army_stack_gap_px") * 0.5
	var boxes: Array = out.map(func(m: Dictionary) -> Rect2: return (m["rect"] as Rect2).grow(room))
	var hide: Array = out.map(func(_m: Dictionary) -> bool: return false)
	var offs := Map3DDeclutter.place(boxes, hide, obstacles, repo.bal("map3d_declutter_step_px"),
		repo.bal("map3d_declutter_max_px"))
	var kept: Array = []
	for i in out.size():
		if offs[i] == null:
			continue
		var m: Dictionary = out[i]
		var rect := Rect2((m["rect"] as Rect2).position + (offs[i] as Vector2), (m["rect"] as Rect2).size)
		m["rect"] = rect
		m["pos"] = (m["pos"] as Vector2) + (offs[i] as Vector2)
		m["icon"] = Rect2(rect.position, Vector2(h, h))
		m["count"] = Rect2(rect.position + Vector2(h, 0.0), Vector2(rect.size.x - h, h))
		kept.append(m)
	return kept


## The colour of a realm's headcount box: the realm's own hue, its saturation
## held between map_army_count_sat and map_army_count_sat_max and set at
## map_army_count_val, so the box reads as a solid counter over that realm's
## pale wash rather than disappearing into it — and never as a sign-board
## (owner 2026-09-28: the cyan box read as a web badge).
static func count_color(repo: DataRepository, kingdom_code: String) -> Color:
	var c := MapPalette.color_of(repo, kingdom_code)
	var top := repo.bal("map_army_count_sat_max") if repo.balance.has("map_army_count_sat_max") else 1.0
	return Color.from_hsv(c.h, clampf(c.s, repo.bal("map_army_count_sat"), top),
		repo.bal("map_army_count_val"))


## How far a counter's drawn rim stands outside its rect, design px: its
## outline (on the war table the realm-hued ring, if wider).
static func outline_px(repo: DataRepository) -> float:
	var line := repo.bal("map_army_outline_px")
	if MapPalette.war_table(repo) and repo.balance.has("map_army_outline_px_table"):
		line = maxf(line, repo.bal("map_army_outline_px_table"))
	return line


## Draw `markers` (from layout) on `ci`; each counter whose code is in
## `selected` is outlined in gold.
static func draw(ci: CanvasItem, repo: DataRepository, markers: Array, selected: Array = []) -> void:
	if markers.is_empty():
		return
	var outline := MapPalette.named(repo, "army_outline")
	var icon_bg := MapPalette.named(repo, "army_icon_bg")
	var glyph_ink := MapPalette.named(repo, "army_glyph")
	var count_ink := MapPalette.named(repo, "army_count_ink")
	# THE WAR TABLE: a dark token printed on the sheet, ringed in its realm's hue
	# (the realm still tells the counters apart) rather than a box OF that hue
	var table := MapPalette.war_table(repo)
	var token := MapPalette.named(repo, "army_count_box")
	var line := outline_px(repo)
	var glyph_frac := repo.bal("map_army_glyph_frac")
	var font := UiPalette.body_font()
	for m: Dictionary in markers:
		var rect: Rect2 = m["rect"]
		var icon: Rect2 = m["icon"]
		var count: Rect2 = m["count"]
		ci.draw_rect(icon.merge(count).grow(line), m["color"] if table else outline)
		ci.draw_rect(icon, icon_bg)
		ci.draw_rect(count, token if table else m["color"])
		ci.draw_line(Vector2(icon.end.x, icon.position.y), Vector2(icon.end.x, icon.end.y),
			outline, line)
		ResourceIcon.draw_glyph(ci, String(m["glyph"]), icon.get_center(),
			icon.size.y * glyph_frac, glyph_ink)
		ManorBadges.draw_centered_text(ci, font, count, String(m["text"]), int(m["font_px"]), count_ink)
		if selected.has(String(m["code"])):
			ci.draw_rect(rect.grow(repo.bal("map_army_outline_px") + 1.5), UiPalette.GOLD, false, 2.0)
