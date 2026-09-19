class_name Map3DLayerBorders
extends RefCounted
## The kingdom borders, the province seams and the hovered kingdom's outline
## (spec 2026-09-20 §1), drawn as ribbons through Map3DLayerLines
## (Lines/KingdomBand, KingdomHalo, Kingdoms, Seams, Hover) from the live
## MapOwnership outlines, and rebuilt only when ownership moves — the same
## signature WorldMapView keys its rings on.

var ctx: Map3DContext
var lines: Map3DLayerLines
var _sig := 0
## The hovered kingdom ("" none) and each kingdom's outline lines, kept until
## ownership turns.
var _hover := ""
var _hover_lines: Dictionary = {}


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines) -> void:
	ctx = p_ctx
	lines = p_lines


## Rebuild the realm band, the halo, the ink and the seams if ownership moved
## since they were built (the signature WorldMapView keys its rings on).
func refresh() -> bool:
	var st := ctx.state()
	var sig := 0 if st == null else hash([st.province_owner.hash(), st.manor_province.hash()])
	if sig == _sig and lines.line_mesh("Kingdoms") != null:
		return false
	_sig = sig
	_hover_lines.clear()
	draw_hover(_hover)
	_build(st)
	return true


func _build(st: GameState) -> void:
	var repo := ctx.repo
	var step := ctx.line_step()
	# The kingdom border (owner 2026-09-19, spec 2026-09-19-map3d-border-look,
	# replacing the thin solid black line of 2026-09-18): a band in the realm's
	# own colour inside each outline, fading inward — ONE mesh, the colour per
	# vertex; where two kingdoms meet each draws its band on its own side — a
	# pale halo, and the warm ink line over both.
	var rings: Array = []
	var bands: Array = []
	var band_colours: Array = []
	for code: String in repo.kingdoms:
		var own := Map3DBorders.kingdom_lines(repo, st, ctx.meta, code, step)
		rings.append_array(own)
		var c := MapPalette.color_of(repo, code)
		for r: PackedVector2Array in Map3DBorders.inward_rings(own):
			bands.append(r)
			band_colours.append(c)
	var band := Color(1, 1, 1, repo.bal("map3d_border_band_alpha"))
	var band_style := Map3DLineStyle.solid(band, "map3d_border_band_px", Map3DPriority.KINGDOM_BAND)
	band_style.one_sided = true
	band_style.colours = band_colours
	band_style.fade_across = 1.0
	band_style.fade_power_key = "map3d_border_band_fade_power"
	lines.set_lines("KingdomBand", bands, band_style)
	var halo := MapPalette.named(repo, "map3d_border_halo")
	halo.a = repo.bal("map3d_border_halo_alpha")
	var halo_style := Map3DLineStyle.solid(halo, "map3d_border_halo_px", Map3DPriority.KINGDOM_HALO)
	halo_style.edge_soft = repo.bal("map3d_border_halo_soft")
	lines.set_lines("KingdomHalo", rings, halo_style)
	var ink := MapPalette.named(repo, "map3d_border")
	lines.set_lines("Kingdoms", rings,
		Map3DLineStyle.solid(ink, "map3d_border_width_px", Map3DPriority.KINGDOMS))
	var seam := MapPalette.named(repo, "map3d_seam")
	seam.a = repo.bal("map3d_seam_alpha")
	lines.set_lines("Seams", Map3DBorders.seam_lines(repo, st, ctx.meta, step),
		Map3DLineStyle.dashed(seam, Color(seam, 0.0), "map3d_seam_width_px",
			"map3d_seam_dash_px", "map3d_seam_gap_px", Map3DPriority.SEAMS))


## The hovered kingdom's live outline in the border's own ink, wider — the
## 2D map's hover ribbon (map3d_hover_border_width_px); "" clears it.
func draw_hover(kingdom: String) -> void:
	_hover = kingdom
	var outline: Array = []
	if kingdom != "":
		if not _hover_lines.has(kingdom):
			_hover_lines[kingdom] = Map3DBorders.kingdom_lines(ctx.repo, ctx.state(), ctx.meta,
				kingdom, ctx.line_step())
		outline = _hover_lines[kingdom]
	var ink := MapPalette.named(ctx.repo, "map3d_border")
	lines.set_lines("Hover", outline,
		Map3DLineStyle.solid(ink, "map3d_hover_border_width_px", Map3DPriority.HOVER))


func hovered() -> String:
	return _hover
