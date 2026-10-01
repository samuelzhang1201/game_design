class_name WarRoomInk
extends RefCounted
## The laid sheet's ink as a texture, drawn once per ownership signature and
## kept — one entry per sheet, a new key replacing the old texture (spec
## 2026-10-01-war-room-design §2). The view owns one and hands it the ink
## viewport and painter; a headless run reads back nothing, so no texture is
## returned and nothing errors.

## The painter's widths (war_ink_<k>_px) and ratios (war_ink_<k>), by short key.
const INK_PX := ["road", "trail", "river", "coast", "border", "band", "seam", "town", "label", "dash", "gap"]
const INK_RATIOS := ["band_alpha", "town_tier_growth", "town_ring_ratio", "town_dot_ratio", "label_gap_ratio",
	"label_drop_ratio", "peak_label_ratio", "peak_half_w", "peak_drop", "border_dot_ratio"]

var cache: Dictionary = {}   # sheet index -> {key, tex}


## The sheet's ink texture (drawn now if its key changed), null when none is
## to be had. `still_wanted` is asked after the draw's frame: false when the
## view left the tree or laid another sheet meanwhile.
func texture_for(repo: DataRepository, state: GameState, sheet: int, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var key := WarSheetInk.cache_key(state, sheet)
	var held: Dictionary = cache.get(sheet, {})
	if held.get("key", -1) != key:
		var tex_px := int(repo.bal("war_sheet_texture_px"))
		viewport.size = Vector2i(tex_px, tex_px)
		var widths := {}
		for k: String in INK_PX:
			widths[k] = repo.bal("war_ink_%s_px" % k)
		for k: String in INK_RATIOS:
			widths[k] = repo.bal("war_ink_%s" % k)
		painter.paint(WarSheetInk.strokes(repo, state, WarSheets.series(repo)[sheet], tex_px),
			repo.war_palette, widths, font)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not bool(still_wanted.call()):
			return null
		store(sheet, key, viewport.get_texture().get_image())
		held = cache.get(sheet, {})
	return held.get("tex") as Texture2D


func store(sheet: int, key: int, img: Image) -> void:
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	cache[sheet] = {"key": key, "tex": ImageTexture.create_from_image(img)}
