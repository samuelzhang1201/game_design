class_name WarIndexChart
extends RefCounted
## The graticule index (owner 2026-10-02, spec 2026-10-02-war-room-v2 §2.3):
## the continent drawn on parchment (owner 2026-10-02: its coast inked, the
## sea washed and lined), every war_sheet_deg cell ruled faint, the land's
## framed in rubric; a click on a land cell lays its
## sheet (after the war marker is tossed onto it). Pure: an Image and a pick
## (the letters and numbers are Label3Ds, WarRoomWall).


static func image(repo: DataRepository, px: int) -> Image:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var ih := int(round(float(px) * h / w))
	var pal: Dictionary = repo.war_palette
	var paper: Color = pal.get("parchment", pal["paper"])
	var img := _parchment(repo, px, ih, paper, pal.get("parchment_age", pal["paper_age"]))
	var k := float(px) / w
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var faint: Color = pal["ink_faint"]
	for col in g.x + 1:
		var x := clampi(int(MapCoords.cell_rect(repo, Vector2i(col, 0), deg).position.x * k), 0, px - 1)
		_blend_rect(img, Rect2i(x, 0, 1, ih), faint)
	for row in g.y + 1:
		var y := clampi(int(MapCoords.cell_rect(repo, Vector2i(0, row), deg).position.y * k), 0, ih - 1)
		_blend_rect(img, Rect2i(0, y, px, 1), faint)
	var rubric: Color = pal["rubric"]
	rubric.a = repo.bal("war_chart_frame_alpha")   # the cells stay second to the coast (the critic, 2026-10-02)
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["cell"]
		var a := Vector2i(r.position * k).clamp(Vector2i.ZERO, Vector2i(px - 1, ih - 1))
		var b := (Vector2i(r.end * k) - Vector2i(1, 1)).clamp(Vector2i.ZERO, Vector2i(px - 1, ih - 1))
		_blend_rect(img, Rect2i(a.x, a.y, b.x - a.x + 1, 1), rubric)
		_blend_rect(img, Rect2i(a.x, b.y, b.x - a.x + 1, 1), rubric)
		_blend_rect(img, Rect2i(a.x, a.y + 1, 1, b.y - a.y - 1), rubric)
		_blend_rect(img, Rect2i(b.x, a.y + 1, 1, b.y - a.y - 1), rubric)
	img.generate_mipmaps()
	return img


## The WALL MAP (spec 2026-10-13-war-room-sunlit-chamber): the same continent
## on parchment with no cells, `px` across, filling a sheet of `aspect` (w / h)
## — a pack of another shape is centred on the parchment, never stretched.
static func wall_image(repo: DataRepository, px: int, aspect: float) -> Image:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var pal: Dictionary = repo.war_palette
	var paper: Color = pal.get("parchment", pal["paper"])
	var age: Color = pal.get("parchment_age", pal["paper_age"])
	var ch := maxi(1, int(round(float(px) / aspect)))
	var mw := px
	var mh := int(round(float(px) * h / w))
	if mh > ch:   # a taller pack: fit its height
		mh = ch
		mw = int(round(float(ch) * w / h))
	var sheet := _parchment(repo, px, ch, paper, age) if mw != px or mh != ch else null
	var map := _parchment(repo, mw, mh, paper, age)
	if sheet != null:
		sheet.blit_rect(map, Rect2i(Vector2i.ZERO, map.get_size()), Vector2i((px - mw) / 2, (ch - mh) / 2))
		map = sheet
	_burn_rim(map, pal["ink"], int(repo.bal("war_wall_map_rim_px")), repo.bal("war_wall_map_rim_alpha"))
	map.generate_mipmaps()
	return map


## A hung map is darkest at its rim (handled, smoked, damp): `reach` px of
## ink laid on every edge, strongest at the edge and fading inward.
static func _burn_rim(img: Image, ink: Color, reach: int, alpha: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for k in reach:
		var t := 1.0 - float(k) / float(reach)
		var c := Color(ink.r, ink.g, ink.b, alpha * t * t)
		_blend_rect(img, Rect2i(0, k, w, 1), c)
		_blend_rect(img, Rect2i(0, h - 1 - k, w, 1), c)
		_blend_rect(img, Rect2i(k, 0, 1, h), c)
		_blend_rect(img, Rect2i(w - 1 - k, 0, 1, h), c)


## The chart's ground (owner 2026-10-02: 选择地图的格子那个纸也换成羊皮纸，然后画
## 上整个大陆地图的形状): parchment blotched toward its aged colour and darker at
## the rim, the sea washed in sea ink with two water lines following the
## shore, the coast inked — the land read from the pack's relief bitmap at its
## waterline. Without the bitmap, the bare parchment.
static func _parchment(repo: DataRepository, px: int, ih: int, paper: Color, age: Color) -> Image:
	var pal: Dictionary = repo.war_palette
	var sea_ink: Color = pal["sea_ink"]
	var ink: Color = pal["ink"]
	var noise := FastNoiseLite.new()
	noise.seed = 1201
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = repo.bal("war_chart_blotch_freq") / float(px)
	var blotch := noise.get_image(px, ih).get_data()   # L8, normalised
	var land := PackedByteArray()
	var near := PackedByteArray()
	var far := PackedByteArray()
	var relief := _relief(repo)
	var sea_byte := repo.bal("elevation_sea_level") * 255.0 / 100.0
	if relief != null:
		# the land mask at the bitmap's own size, shrunk to the chart smoothly
		# (an even, antialiased coast), then blurred at two reaches for the
		# shore's two water lines
		var mask := _mask(relief, sea_byte)
		mask.resize(px, ih, Image.INTERPOLATE_LANCZOS)
		land = mask.get_data()
		near = _blurred(mask, repo.bal("war_chart_water_near_px"))
		far = _blurred(mask, repo.bal("war_chart_water_far_px"))
	var mottle := repo.bal("war_parchment_mottle")
	var wash := repo.bal("war_chart_sea_wash")
	var lift := repo.bal("war_chart_land_lift")
	var line_a := repo.bal("war_chart_water_line_alpha")
	var coast_a := repo.bal("war_chart_coast_alpha")
	var out := PackedByteArray()
	out.resize(px * ih * 4)
	for y in ih:
		for x in px:
			var i := y * px + x
			var c := paper.lerp(age, smoothstep(0.45, 0.85, float(blotch[i]) / 255.0) * mottle)
			var edge := maxf(absf(float(x) / float(px) - 0.5), absf(float(y) / float(ih) - 0.5)) * 2.0
			c = c.lerp(age, smoothstep(0.85, 1.0, edge) * 0.6)
			if not land.is_empty():
				var v := float(land[i])
				var on_land := v / 255.0
				c = c.lerp(sea_ink, (1.0 - on_land) * wash).lerp(paper.lightened(lift), on_land * 0.6)
				# the water lines: where each blurred mask crosses its middle, offshore only
				var n1 := 1.0 - clampf(absf(float(near[i]) - 64.0) / 18.0, 0.0, 1.0)
				var n2 := 1.0 - clampf(absf(float(far[i]) - 64.0) / 18.0, 0.0, 1.0)
				c = c.lerp(sea_ink, maxf(n1, n2 * 0.7) * line_a * (1.0 - on_land))
				var coast := 1.0 - clampf(absf(v - 128.0) / 110.0, 0.0, 1.0)
				c = c.lerp(ink.darkened(0.3), coast * coast_a)
			out[i * 4] = int(c.r8)
			out[i * 4 + 1] = int(c.g8)
			out[i * 4 + 2] = int(c.b8)
			out[i * 4 + 3] = 255
	return Image.create_from_data(px, ih, false, Image.FORMAT_RGBA8, out)


## The chart's picture with a parchment margin of `margin_px` round the map's
## own image, the letters and numbers printed on it: the map's pixels sit at
## (margin_px, margin_px), the sheet picks (`sheet_at_uv`) stay in the map's UV.
static func image_with_margin(repo: DataRepository, px: int, margin_px: int) -> Image:
	var map := image(repo, px)
	if margin_px <= 0:
		return map
	map.clear_mipmaps()
	var pal: Dictionary = repo.war_palette
	var paper: Color = pal.get("parchment", pal["paper"])
	var age: Color = pal.get("parchment_age", pal["paper_age"])
	var out := Image.create(px + 2 * margin_px, map.get_height() + 2 * margin_px, false, Image.FORMAT_RGBA8)
	out.fill(paper.lerp(age, 0.35))
	out.blit_rect(map, Rect2i(Vector2i.ZERO, map.get_size()), Vector2i(margin_px, margin_px))
	var faint: Color = pal["ink_faint"]
	var f := Rect2i(margin_px - 1, margin_px - 1, px + 2, map.get_height() + 2)
	_blend_rect(out, Rect2i(f.position.x, f.position.y, f.size.x, 1), faint)
	_blend_rect(out, Rect2i(f.position.x, f.end.y - 1, f.size.x, 1), faint)
	_blend_rect(out, Rect2i(f.position.x, f.position.y + 1, 1, f.size.y - 2), faint)
	_blend_rect(out, Rect2i(f.end.x - 1, f.position.y + 1, 1, f.size.y - 2), faint)
	out.generate_mipmaps()
	return out


static func _relief(repo: DataRepository) -> Image:
	if repo.relief_path.is_empty() or not ResourceLoader.exists(repo.relief_path):
		return null
	var tex := load(repo.relief_path) as Texture2D
	var img := tex.get_image() if tex != null else null
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()   # get_data() must be the one level the loops index
	img.convert(Image.FORMAT_L8)
	return img


## The land mask: 255 above the waterline, 0 below.
static func _mask(relief: Image, sea_byte: float) -> Image:
	var src := relief.get_data()
	var mask := PackedByteArray()
	mask.resize(src.size())
	for i in src.size():
		mask[i] = 255 if float(src[i]) > sea_byte else 0
	return Image.create_from_data(relief.get_width(), relief.get_height(), false, Image.FORMAT_L8, mask)


## A mask blurred by about `reach` px: shrunk and grown back, so its middle
## value runs a little offshore.
static func _blurred(mask: Image, reach: float) -> PackedByteArray:
	var m := mask.duplicate() as Image
	var w := m.get_width()
	var h := m.get_height()
	var f := maxf(reach, 1.0)
	m.resize(maxi(1, int(float(w) / f)), maxi(1, int(float(h) / f)), Image.INTERPOLATE_BILINEAR)
	m.resize(w, h, Image.INTERPOLATE_CUBIC)
	return m.get_data()


static func _blend_rect(img: Image, r: Rect2i, c: Color) -> void:
	var cut := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(cut.position.y, cut.end.y):
		for x in range(cut.position.x, cut.end.x):
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## The sheet whose cell holds a chart UV (0..1 across the map), -1 on a sea
## cell or off the map.
static func sheet_at_uv(repo: DataRepository, uv: Vector2) -> int:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return -1
	var p := uv * Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var at := MapCoords.cell_of(repo, p, repo.bal("war_sheet_deg"))
	for s: Dictionary in WarSheets.series(repo):
		if int(s["col"]) == at.x and int(s["row"]) == at.y:
			return int(s["index"])
	return -1


## A sheet's cell over the map, in chart UV.
static func uv_of_cell(repo: DataRepository, sheet: Dictionary) -> Rect2:
	var size := Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var c: Rect2 = sheet["cell"]
	return Rect2(c.position / size, c.size / size)
