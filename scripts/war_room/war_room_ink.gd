class_name WarRoomInk
extends RefCounted
## The laid sheet's ink as a texture, drawn once per ownership signature and
## kept (spec 2026-10-01-war-room-design §2). The cache is BOUNDED: the laid
## sheet and at most one other (the one laid before it, so a step back is
## free) — each texture is ~tex_px² × 4 bytes and its mipmaps. The ink
## viewport is 2×2 (the smallest a viewport takes) at rest: it is sized to the sheet only for the frame it
## draws in, then given back. The view owns one and hands it the ink
## viewport and painter; a headless run reads back nothing, so no texture is
## returned and nothing errors.

## The painter's widths (war_ink_<k>_px) and ratios (war_ink_<k>), by short key.
const INK_PX := ["road", "trail", "river", "coast", "border", "band", "seam", "town", "label", "dash", "gap",
	"wood", "manor", "manor_label", "manor_dash", "manor_gap", "river_label", "bridge", "trade", "works", "market",
	"river_feather", "label_halo"]
const INK_RATIOS := ["band_alpha", "town_tier_growth", "town_ring_ratio", "town_dot_ratio", "town_halo_ratio", "town_pip_ratio", "town_outer_gap_ratio", "label_gap_ratio",
	"label_drop_ratio", "peak_label_ratio", "peak_half_w", "peak_drop", "border_dot_ratio", "wall_ratio", "anchor_ratio", "char_w",
	"river_label_lift"]
## The intelligence layer's widths (war_intel_<k>_px) and ratios (war_intel_<k>).
const INTEL_PX := ["supply", "supply_dash", "supply_gap", "courier", "weather", "label", "spy_ring", "hazard", "hazard_label"]
const INTEL_RATIOS := ["hazard_alpha"]
## The fine print's widths (war_fine_<k>_px), by short key.
const FINE_PX := ["note", "route", "mark", "figure"]
## How many sheets' ink are kept: the laid one and one more.
const KEEP := 2
## The ink viewport's size at rest (the smallest a viewport takes).
const REST := Vector2i(2, 2)

## Every cache is keyed by the laid sheet's `key` (WarSheets.union: "12", or
## "12+13" for a sheet laid over two cells).
var cache: Dictionary = {}   # sheet key -> {key, tex}
var intel: Dictionary = {}   # the laid sheet's intelligence layer: {sheet, key, tex}
var plan: Dictionary = {}    # the laid sheet's plan layer (WarPlanInk): {sheet, key, tex}
var fine: Dictionary = {}    # sheet key -> {key, tex}: the fine print (WarFinePrint)
var _order: Array = []       # cached sheet keys, least recently laid first
## The frame the draw is read back after (a headless run never draws, so a
## test hands in the tree's process_frame).
var frame_done: Signal = RenderingServer.frame_post_draw
var _gen := 0                # the latest draw; an older one awaiting its frame leaves the viewport alone


## The ink texture's size for a sheet: war_sheet_texture_px across, its
## height at the same scale (not square: the sheet is wider than it is deep).
static func tex_size(repo: DataRepository, rect: Rect2) -> Vector2i:
	return fit_size(int(repo.bal("war_sheet_texture_px")), rect)


## `px` across a sheet's LONGER side, the other at the same scale: one cell
## (wider than deep) is `px` wide as ever; a union deeper than wide (1 x 3,
## 1 x 4; R11) is `px` deep, so no texture outgrows one cell's.
static func fit_size(px: int, rect: Rect2) -> Vector2i:
	if rect.size.y > rect.size.x:
		return Vector2i(maxi(1, floori(px * rect.size.x / rect.size.y)), px)   # floored: the sheet's rows never pass px
	return Vector2i(px, maxi(1, ceili(px * rect.size.y / rect.size.x)))


## The share of the texture's height the sheet's own height fills (the
## shader's tex_aspect): 1 but for the rounding up of the texture's rows.
static func used_share(repo: DataRepository, rect: Rect2) -> float:
	var s := tex_size(repo, rect)
	return float(s.x) * rect.size.y / rect.size.x / float(s.y)


## The sheet's ink texture (drawn now if its key changed), null when none is
## to be had. `still_wanted` is asked after the draw's frame: false when the
## view left the tree or laid another sheet meanwhile.
func texture_for(repo: DataRepository, state: GameState, row: Dictionary, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var sheet := String(row["key"])
	var key := WarSheetInk.cache_key(state, sheet)
	var held: Dictionary = cache.get(sheet, {})
	if held.get("key", -1) != key:
		var size := tex_size(repo, row["rect"])
		_gen += 1
		var gen := _gen
		viewport.size = size
		var widths := {}
		for k: String in INK_PX:
			widths[k] = repo.bal("war_ink_%s_px" % k)
		for k: String in INK_RATIOS:
			widths[k] = repo.bal("war_ink_%s" % k)
		widths["mark"] = repo.bal("war_mark_px")
		widths["mark_reach_alpha"] = repo.bal("war_mark_reach_alpha")
		widths["mark_reach"] = repo.bal("war_mark_reach_px")
		painter.paint(WarSheetInk.strokes(repo, state, row, size.x, WarBake.of(repo)), repo.war_palette, widths, font)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await frame_done
		if gen != _gen:
			return null   # a later draw took the viewport over
		var img: Image = viewport.get_texture().get_image() if bool(still_wanted.call()) else null
		if is_instance_valid(viewport):
			viewport.size = REST   # the render target is given back at once
		if img == null:
			return null
		store(sheet, key, img)
		held = cache.get(sheet, {})
	_touch(sheet)
	return held.get("tex") as Texture2D


func store(sheet: Variant, key: int, img: Image) -> void:
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	cache[sheet] = {"key": key, "tex": ImageTexture.create_from_image(img)}
	_touch(sheet)


## `sheet` becomes the most recent; the oldest beyond KEEP are let go.
func _touch(sheet: Variant) -> void:
	if not cache.has(sheet):
		return
	_order.erase(sheet)
	_order.append(sheet)
	trim(KEEP)


## Keeps only the `count` most recently laid sheets' ink (the room shut keeps
## the laid one alone, perf 2026-10-02: each is ~62 MB of video memory).
func trim(count: int) -> void:
	while _order.size() > count:
		cache.erase(_order.pop_front())
	for s: Variant in fine.keys():
		if not cache.has(s):
			fine.erase(s)


## The sheet's fine print as a texture, the ink's size, drawn when the same
## key turns as the ink's; null headless or when a later draw took over.
func fine_for(repo: DataRepository, state: GameState, row: Dictionary, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var sheet := String(row["key"])
	var key := WarSheetInk.cache_key(state, sheet)
	var held: Dictionary = fine.get(sheet, {})
	if held.get("key", -1) == key:
		return held.get("tex") as Texture2D
	var size := tex_size(repo, row["rect"])
	_gen += 1
	var gen := _gen
	viewport.size = size
	var widths := {}
	for k: String in FINE_PX:
		widths[k] = repo.bal("war_fine_%s_px" % k)
	widths["mark"] = repo.bal("war_fine_mark_px")
	painter.paint(WarFinePrint.strokes(repo, state, row, size.x, WarBake.of(repo)), repo.war_palette, widths, font, false, true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await frame_done
	if gen != _gen:
		return null
	var img: Image = viewport.get_texture().get_image() if bool(still_wanted.call()) else null
	if is_instance_valid(viewport):
		viewport.size = REST
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	fine[sheet] = {"key": key, "tex": ImageTexture.create_from_image(img)}
	return fine[sheet]["tex"]


## The laid sheet's intelligence layer (WarIntelInk), redrawn when its key
## turns (a new day, a courier moved, a report came in); null when none is to
## be had (headless) or a later draw took the viewport over.
func intel_for(repo: DataRepository, state: GameState, row: Dictionary, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var sheet := String(row["key"])
	var key := WarIntelInk.cache_key(state, sheet)
	if int(intel.get("key", -1)) == key and String(intel.get("sheet", "")) == sheet:
		return intel.get("tex") as Texture2D
	var size := fit_size(int(repo.bal("war_intel_texture_px")), row["rect"])
	_gen += 1
	var gen := _gen
	viewport.size = size
	var widths := {}
	for k: String in INTEL_PX:
		widths[k if k != "label" else "intel_label"] = repo.bal("war_intel_%s_px" % k)
	for k: String in INTEL_RATIOS:
		widths[k] = repo.bal("war_intel_%s" % k)
	painter.paint(WarIntelInk.strokes(repo, state, row, size.x), repo.war_palette, widths, font, true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await frame_done
	if gen != _gen:
		return null
	var img: Image = viewport.get_texture().get_image() if bool(still_wanted.call()) else null
	if is_instance_valid(viewport):
		viewport.size = REST
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	intel = {"sheet": sheet, "key": key, "tex": ImageTexture.create_from_image(img)}
	return intel["tex"]


## The laid sheet's plan layer (WarPlanInk: the staff's strokes, spec
## 2026-10-07-war-room-annotations-and-planning-pieces §2.5), redrawn when the
## plans' revision turns; null when none is to be had (headless) or a later
## draw took the viewport over. An empty layer is still drawn (it clears).
## The stroke `hidden` (being dragged) is left out.
func plan_for(repo: DataRepository, state: GameState, row: Dictionary, viewport: SubViewport,
		painter: WarInkPainter, font: Font, caps: Font, still_wanted: Callable, hidden := "") -> Texture2D:
	var sheet := String(row["key"])
	var key := WarPlanInk.cache_key(state, sheet)
	if int(plan.get("key", -1)) == key and String(plan.get("sheet", "")) == sheet and String(plan.get("hidden", "")) == hidden:
		return plan.get("tex") as Texture2D
	var rect: Rect2 = row["rect"]
	var size := fit_size(int(repo.bal("war_plan_texture_px")), rect)
	_gen += 1
	var gen := _gen
	viewport.size = size
	var table_w := WarRoomTable.width_for(repo, row)
	var mm := float(size.x) / (table_w * 1000.0)
	painter.paint_plan(WarPlanInk.strokes(repo, state, row, size.x, table_w, hidden), plan_look(repo, tooth(), mm, font, caps))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await frame_done
	if gen != _gen:
		return null
	var img: Image = viewport.get_texture().get_image() if bool(still_wanted.call()) else null
	if is_instance_valid(viewport):
		viewport.size = REST
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	plan = {"sheet": sheet, "key": key, "hidden": hidden, "tex": ImageTexture.create_from_image(img)}
	return plan["tex"]


## The wax crayon's tooth (GameArt.WAR_PLAN_ART "wax_tooth"): a seamless
## noise whose alpha is where the wax took; null draws the crayon flat.
static func tooth() -> Texture2D:
	return GameArt.table(GameArt.WAR_PLAN_ART).of("wax_tooth") as Texture2D


## WarPlanDraw's look at `mm` px a table millimetre.
static func plan_look(repo: DataRepository, tooth_tex: Texture2D, mm: float, font: Font, caps: Font) -> Dictionary:
	var pal := repo.war_palette
	var cells := float(tooth_tex.get_width()) if tooth_tex != null else 1.0
	return {"colours": {"blue": pal["plan_blue"], "red": pal["plan_red"], "ink": pal["ink"],
			"blue_draft": pal.get("plan_blue_draft", pal["plan_blue"])},
		"edges": {"blue_draft": pal.get("pencil", Color.GRAY)},
		"tooth": tooth_tex, "tooth_uv": repo.bal("war_plan_tooth_scale") / maxf(mm, 0.0001) / cells,
		"edge_dark": repo.bal("war_plan_edge_dark"), "edge_px": maxf(repo.bal("war_plan_edge_mm") * mm, 1.0),
		"font": font, "caps": caps, "halo": pal.get("parchment", Color.WHITE)}
