class_name ArmyCounters
extends RefCounted
## The MILITARY layer's counters (owner 2026-09-13 on the 2D map, 2026-09-19
## on the 3D map): each of the player's units as a square of its own — its
## painted piece (data/army_art.csv), else a glyph: swords, a crown for the
## household (the roster's `is_royal`), waves for a fleet — joined to a box in
## the realm's hue stating its headcount. Nothing is merged into one counter
## (spec 2026-10-07-army-split-and-ground §5.1). Shared by both maps: each map
## gathers its regiments' screen points and the settlement marks to keep clear
## of, and hands them here.
## Every colour and size is political_palette.csv army_* / balance.csv
## map_army_*.


## The counters for `points` ([{reg, pos, bars?}], pos in the map's screen px)
## at height `h`: {code, pos, size, text, font_px, rect, icon, count, bars,
## glyph, piece, color, naval, royal}, one a unit. `bars` is ArmySystem.bars_of's
## Vector2i (readiness, supply per mille): two thin bars, red over yellow,
## stand on the counter inside its `rect` (owner 2026-09-27). Spread by
## Map3DDeclutter (spec 2026-10-07-army-split-and-ground §5.2) in priority
## order — `first` (the selected codes), the royal household, then by men,
## then by code — so no counter or chip covers a settlement mark or another:
## the first never moves, each other takes the nearest clear place out to
## map3d_declutter_max_px. A counter with no clear place takes the clearest
## it found (never hidden); a chip with none is left out until the camera
## comes closer.
## `with_piece` names the regiments that already have a 3D PIECE standing on
## the map (Map3DLayerUnits). Those keep only their headcount box (a chip):
## the model IS the counter's square now, and drawing the flat piece beside it
## put the same regiment on the map twice.
## Two counters stand at least map_army_stack_gap_px apart: each box is grown
## by half of it for the spreading, the marker keeps the box itself.
static func layout(repo: DataRepository, points: Array, h: float, obstacles: Array,
		with_piece: Dictionary = {}, first: Array = []) -> Array:
	var mine := repo.resolve_realm("player_realm")
	var pad := repo.bal("map_army_count_pad_px")
	var font := UiPalette.body_font()
	var bars_h := bars_height(repo)
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
		var solo := with_piece.has(code)
		# a chip over a 3D piece is its tag, never bigger than the soldier
		var ph: float = minf(h, float(p.get("h", h)))
		var font_px := maxi(int(round(ph * repo.bal("map_army_font_frac"))), 1)
		var count_w := maxf(ph, ManorBadges.text_width(font, text, font_px) + pad * 2.0)
		var w := count_w if solo else ph + count_w
		var kingdom := String(r.get("kingdom_code", mine))
		if not colors.has(kingdom):
			colors[kingdom] = count_color(repo, kingdom)
		out.append({"code": code, "pos": sp, "size": strength, "text": text, "solo": solo,
			"font_px": font_px,
			"h": ph,
			"rect": Rect2(sp - Vector2(w, ph) / 2.0 - Vector2(0.0, bars_h), Vector2(w, ph + bars_h)),
			"bars": p.get("bars", Vector2i(-1, -1)),
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
	var half_gap := repo.bal("map_army_stack_gap_px") * 0.5
	var boxes: Array = out.map(func(m: Dictionary) -> Rect2: return (m["rect"] as Rect2).grow(half_gap))
	var hide: Array = out.map(func(m: Dictionary) -> bool: return bool(m["solo"]))
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
		var mh := float(m["h"])
		var square := 0.0 if bool(m["solo"]) else mh
		var top := rect.position + Vector2(0.0, bars_h)
		m["icon"] = Rect2(top, Vector2(square, mh))
		m["count"] = Rect2(top + Vector2(square, 0.0), Vector2(rect.size.x - square, mh))
		kept.append(m)
	return kept


## The two bars and their gaps, screen px (0 while map_army_bar_px is 0).
static func bars_height(repo: DataRepository) -> float:
	var bar := repo.bal("map_army_bar_px")
	return 0.0 if bar <= 0.0 else (bar + repo.bal("map_army_bar_gap_px")) * 2.0


## Red (readiness) over yellow (supply), each as wide as the counter and
## filled by its per mille, on a dark track — the top of `rect`.
static func _draw_bars(ci: CanvasItem, repo: DataRepository, m: Dictionary) -> void:
	var v: Vector2i = m.get("bars", Vector2i(-1, -1))
	var bar := repo.bal("map_army_bar_px")
	if v.x < 0 or bar <= 0.0:
		return
	var gap := repo.bal("map_army_bar_gap_px")
	var rect: Rect2 = m["rect"]
	var track := MapPalette.named(repo, "army_bar_track")
	var y := rect.position.y
	for row: Array in [[v.x, "army_bar_ready"], [v.y, "army_bar_supply"]]:
		var full := Rect2(rect.position.x, y, rect.size.x, bar + gap)
		ci.draw_rect(full, track)
		var inner := Rect2(full.position + Vector2(gap, gap), Vector2(full.size.x - gap * 2.0, bar))
		inner.size.x *= clampf(float(row[0]) / 1000.0, 0.0, 1.0)
		ci.draw_rect(inner, MapPalette.named(repo, String(row[1])))
		y += bar + gap


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


## Draw `markers` (from layout) on `ci`; each counter whose code is in
## `selected` is outlined in gold.
static func draw(ci: CanvasItem, repo: DataRepository, markers: Array, selected: Array = []) -> void:
	if markers.is_empty():
		return
	var outline := MapPalette.named(repo, "army_outline")
	var icon_bg := MapPalette.named(repo, "army_icon_bg")
	var glyph_ink := MapPalette.named(repo, "army_glyph")
	var count_ink := MapPalette.named(repo, "army_count_ink")
	var line := repo.bal("map_army_outline_px")
	# THE WAR TABLE: a dark token printed on the sheet, ringed in its realm's hue
	# (the realm still tells the counters apart) rather than a box OF that hue
	var table := MapPalette.war_table(repo)
	var token := MapPalette.named(repo, "army_count_box")
	if table:
		line = maxf(line, repo.bal("map_army_outline_px_table") if repo.balance.has("map_army_outline_px_table") else line)
	var glyph_frac := repo.bal("map_army_glyph_frac")
	var font := UiPalette.body_font()
	for m: Dictionary in markers:
		var rect: Rect2 = m["rect"]
		var icon: Rect2 = m["icon"]
		var count: Rect2 = m["count"]
		_draw_bars(ci, repo, m)
		if bool(m.get("solo", false)):
			# The 3D piece is the counter; this is only its headcount.
			ci.draw_rect(count.grow(line), m["color"] if table else outline)
			ci.draw_rect(count, token if table else m["color"])
			ManorBadges.draw_centered_text(ci, font, count, String(m["text"]),
				int(m["font_px"]), count_ink)
			if selected.has(String(m["code"])):
				ci.draw_rect(rect.grow(line + 1.5), UiPalette.GOLD, false, 2.0)
			continue
		# the glyph square (the 2D counter art went 2026-09-29, Hunyuan's licence)
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
