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
	# the coast is the shore's to draw (look route 2026-09-30): the ink, the
	# halo and the band keep to the land borders
	# (without a terrain — a fixture — every point would read as water)
	if repo.bal("map3d_border_skip_coast") > 0.0 and ctx.terrain != null:
		var sea_y := float(ctx.meta.get("sea_y", 0.0))
		var wet := func(xz: Vector2) -> bool: return ctx.height_at(xz) < sea_y + 0.5
		var probe := repo.bal("map3d_border_coast_probe_m")
		rings = Map3DBorders.land_runs(rings, wet, probe)
		var kept_bands: Array = []
		var kept_colours: Array = []
		for bi in bands.size():
			for run: PackedVector2Array in Map3DBorders.land_runs([bands[bi]], wet, probe):
				kept_bands.append(run)
				kept_colours.append(band_colours[bi])
		bands = kept_bands
		band_colours = kept_colours
	# the looks are Map3DLayerLines' line .tres (owner 2026-10-02: the
	# inspector's); each kingdom's band wears its realm's colour per vertex
	lines.set_lines("KingdomBand", bands, Map3DLayerLines.KINGDOM_BAND, Map3DPriority.KINGDOM_BAND,
		band_colours)
	lines.set_lines("KingdomHalo", rings, Map3DLayerLines.KINGDOM_HALO, Map3DPriority.KINGDOM_HALO)
	lines.set_lines("Kingdoms", rings, Map3DLayerLines.KINGDOM_INK, Map3DPriority.KINGDOMS)
	lines.set_lines("Seams", Map3DBorders.seam_lines(repo, st, ctx.meta, step),
		Map3DLayerLines.SEAM, Map3DPriority.SEAMS)


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
	lines.set_lines("Hover", outline, Map3DLayerLines.HOVER, Map3DPriority.HOVER)


func hovered() -> String:
	return _hover
