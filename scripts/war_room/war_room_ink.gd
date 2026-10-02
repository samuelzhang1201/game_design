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
	"wood", "manor", "manor_label", "manor_dash", "manor_gap", "river_label", "bridge"]
const INK_RATIOS := ["band_alpha", "town_tier_growth", "town_ring_ratio", "town_dot_ratio", "label_gap_ratio",
	"label_drop_ratio", "peak_label_ratio", "peak_half_w", "peak_drop", "border_dot_ratio", "wall_ratio", "anchor_ratio"]
## How many sheets' ink are kept: the laid one and one more.
const KEEP := 2
## The ink viewport's size at rest (the smallest a viewport takes).
const REST := Vector2i(2, 2)

var cache: Dictionary = {}   # sheet index -> {key, tex}
var _order: Array[int] = []  # cached sheets, least recently laid first
## The frame the draw is read back after (a headless run never draws, so a
## test hands in the tree's process_frame).
var frame_done: Signal = RenderingServer.frame_post_draw
var _gen := 0                # the latest draw; an older one awaiting its frame leaves the viewport alone


## The ink texture's size for a sheet: war_sheet_texture_px across, its
## height at the same scale (not square: the sheet is wider than it is deep).
static func tex_size(repo: DataRepository, rect: Rect2) -> Vector2i:
	var w := int(repo.bal("war_sheet_texture_px"))
	return Vector2i(w, maxi(1, ceili(w * rect.size.y / rect.size.x)))


## The share of the texture's height the sheet's own height fills (the
## shader's tex_aspect): 1 but for the rounding up of the texture's rows.
static func used_share(repo: DataRepository, rect: Rect2) -> float:
	var s := tex_size(repo, rect)
	return float(s.x) * rect.size.y / rect.size.x / float(s.y)


## The sheet's ink texture (drawn now if its key changed), null when none is
## to be had. `still_wanted` is asked after the draw's frame: false when the
## view left the tree or laid another sheet meanwhile.
func texture_for(repo: DataRepository, state: GameState, sheet: int, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var key := WarSheetInk.cache_key(state, sheet)
	var held: Dictionary = cache.get(sheet, {})
	if held.get("key", -1) != key:
		var row: Dictionary = WarSheets.series(repo)[sheet]
		var size := tex_size(repo, row["rect"])
		_gen += 1
		var gen := _gen
		viewport.size = size
		var widths := {}
		for k: String in INK_PX:
			widths[k] = repo.bal("war_ink_%s_px" % k)
		for k: String in INK_RATIOS:
			widths[k] = repo.bal("war_ink_%s" % k)
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


func store(sheet: int, key: int, img: Image) -> void:
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	cache[sheet] = {"key": key, "tex": ImageTexture.create_from_image(img)}
	_touch(sheet)


## `sheet` becomes the most recent; the oldest beyond KEEP are let go.
func _touch(sheet: int) -> void:
	if not cache.has(sheet):
		return
	_order.erase(sheet)
	_order.append(sheet)
	while _order.size() > KEEP:
		cache.erase(_order.pop_front())
