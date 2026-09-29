class_name Map3DWeatherField
extends RefCounted
## The weather as the 3D map draws it (spec 2026-09-29-weather-visuals): a
## low-resolution FIELD over the pack, one texel per map3d_weather_field_step_px
## pack px, each land texel the look of its cell's province's weather that
## spell (data/weather.csv's overcast, wet, mud, snow, rainfall, snowfall),
## blurred over land only (map3d_weather_field_blur_halvings halvings) — the sea
## by a coast takes the coast's weather — so a front, not a province outline,
## is what the ground shows. Pure and look-only: Weather.of is read, nothing is written.
##
## `ground` is RGBA8 (wet, mud, snow, overcast), `fall` RGB8 (rainfall,
## snowfall, gust — the wind that drives a blizzard's snow sideways); a texel (i, j) covers pack px [i, i + 1) × step, sampled at its
## centre.

var step_px := 16
var size := Vector2i.ONE
## Texel → cell id (-1 water), row-major; cut once per pack.
var _cells := PackedInt32Array()
## Texel → ordinal in _prov_codes, cut again when a manor changes province,
## and how much of its province's weather it wears (the CELL, below).
var _texel_prov := PackedInt32Array()
var _texel_cell := PackedFloat32Array()
var _prov_codes: Array = []
var _prov_key := -1


func _init(repo: DataRepository) -> void:
	step_px = maxi(1, int(repo.bal("map3d_weather_field_step_px")))
	var img := _cell_index(repo)
	if img == null:
		return
	@warning_ignore("integer_division")  # whole texels over the pack
	size = Vector2i(maxi(1, (img.get_width() + step_px - 1) / step_px),
		maxi(1, (img.get_height() + step_px - 1) / step_px))
	_cells.resize(size.x * size.y)
	@warning_ignore("integer_division")  # the texel's centre pixel
	var half := step_px / 2
	for j in size.y:
		for i in size.x:
			var x := mini(i * step_px + half, img.get_width() - 1)
			var y := mini(j * step_px + half, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			var id := int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256
			_cells[j * size.x + i] = id if repo.cells.has(id) else -1


## The pack's world_cell_index.png read as a file (it is data: R + G × 256,
## white water), or null.
static func _cell_index(repo: DataRepository) -> Image:
	if repo.cell_texture_path == "":
		return null
	var tex := load(repo.cell_texture_path) as Texture2D if ResourceLoader.exists(repo.cell_texture_path) else null
	if tex != null:
		return tex.get_image()
	var path := ProjectSettings.globalize_path(repo.cell_texture_path)
	return Image.load_from_file(path) if FileAccess.file_exists(path) else null


## A kind's ground look: (wet, mud, snow, overcast).
static func channels(repo: DataRepository, kind: String) -> Color:
	var k: Dictionary = repo.weather_kinds.get(kind, {})
	return Color(float(k.get("wet", 0.0)), float(k.get("mud", 0.0)),
		float(k.get("snow", 0.0)), float(k.get("overcast", 0.0)))


## A kind's falling weather: (rainfall, snowfall, gust).
static func fall(repo: DataRepository, kind: String) -> Vector3:
	var k: Dictionary = repo.weather_kinds.get(kind, {})
	return Vector3(float(k.get("rainfall", 0.0)), float(k.get("snowfall", 0.0)), float(k.get("gust", 0.0)))


## The first absolute day of a spell.
static func first_day_of(repo: DataRepository, spell: int) -> int:
	return spell * maxi(1, int(repo.bal("weather_spell_days"))) + 1


## {spell, t}: the spell a moment falls in and how far its field has turned to
## the NEXT spell's — 0 until the last map3d_weather_blend_days of the spell,
## then eased to 1 at its end (a front arriving, not a switch).
static func blend_of(repo: DataRepository, abs_day: int, day_share: float) -> Dictionary:
	var days := maxi(1, int(repo.bal("weather_spell_days")))
	var spell := Weather.spell_of(repo, abs_day)
	var pos := float(maxi(abs_day, 1) - 1 - spell * days) + clampf(day_share, 0.0, 1.0)
	var span := clampf(repo.bal("map3d_weather_blend_days"), 0.0, float(days))
	var t := 0.0 if span <= 0.0 else smoothstep(float(days) - span, float(days), pos)
	return {"spell": spell, "t": t}


## The field for a spell: {ground: Image, fall: Image, kinds: {province: kind}}.
## `kind_of` (province -> kind) stands in for Weather.of — a tool's forced sky.
func build(repo: DataRepository, state: GameState, spell: int, kind_of: Callable = Callable()) -> Dictionary:
	var day := first_day_of(repo, spell)
	_index_provinces(repo, state)
	# each province's look as bytes: premultiplied by land, so the blur below is
	# a land-weighted one — RGBA (wet, mud, snow, overcast) and RGBA (rainfall,
	# snowfall, gust, land); every texel takes its share of its province's cell
	var kinds: Dictionary = {}
	var g_look := PackedByteArray()
	var f_look := PackedByteArray()
	g_look.resize(_prov_codes.size() * 4)
	f_look.resize(_prov_codes.size() * 4)
	for p in _prov_codes.size():
		var code: String = _prov_codes[p]
		var kind := String(kind_of.call(code)) if kind_of.is_valid() else Weather.of(repo, state, code, day)
		kinds[code] = kind
		g_look.encode_u32(p * 4, channels(repo, kind).to_abgr32())
		var f := fall(repo, kind)
		f_look.encode_u32(p * 4, Color(f.x, f.y, f.z, 0.0).to_abgr32())
	var n := size.x * size.y
	var g := PackedByteArray()
	g.resize(n * 4)
	var fb := PackedByteArray()
	fb.resize(n * 4)
	for t in n:
		var p := _texel_prov[t]
		if p < 0:
			continue
		var k := _texel_cell[t]
		for c in 4:
			g[t * 4 + c] = int(float(g_look[p * 4 + c]) * k + 0.5)
		for c in 3:
			fb[t * 4 + c] = int(float(f_look[p * 4 + c]) * k + 0.5)
		fb[t * 4 + 3] = 255
	var ground := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, g)
	var falls := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, fb)
	var halvings := int(repo.bal("map3d_weather_field_blur_halvings"))
	_blur(ground, halvings)
	_blur(falls, halvings)
	# un-premultiply; a texel's look fades with the land in its reach, so the
	# sea by a coast keeps the coast's weather and open sea stays clear
	g = ground.get_data()
	fb = falls.get_data()
	var out_f := PackedByteArray()
	out_f.resize(n * 3)
	for t in n:
		var land := fb[t * 4 + 3]
		if land < 2:
			for c in 4:
				g[t * 4 + c] = 0
			continue
		var k := minf(2.0, 255.0 / float(land))  # full weather from half land in reach
		for c in 4:
			g[t * 4 + c] = mini(255, int(float(g[t * 4 + c]) * k + 0.5))
		for c in 3:
			out_f[t * 3 + c] = mini(255, int(float(fb[t * 4 + c]) * k + 0.5))
	return {"ground": Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, g),
		"fall": Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, out_f), "kinds": kinds}


## Texel → province ordinal (-1 water) under the state's holdings: annexed
## manors carry their new province's weather, as Weather.at does.
func _index_provinces(repo: DataRepository, state: GameState) -> void:
	var key := 0 if state == null else state.manor_province.hash()
	if key == _prov_key and not _texel_prov.is_empty():
		return
	_prov_key = key
	var ordinal: Dictionary = {}
	_prov_codes = []
	var prov_of_cell: Dictionary = {}
	_texel_prov = PackedInt32Array()
	_texel_prov.resize(_cells.size())
	for t in _cells.size():
		var cell := _cells[t]
		if cell < 0:
			_texel_prov[t] = -1
			continue
		if not prov_of_cell.has(cell):
			var code := MapManors.province_of(repo, cell, state)
			if code != "" and not ordinal.has(code):
				ordinal[code] = _prov_codes.size()
				_prov_codes.append(code)
			prov_of_cell[cell] = int(ordinal.get(code, -1))
		_texel_prov[t] = int(prov_of_cell[cell])
	_cut_cells(repo)


## A province's weather is a CELL round its centre, not a blanket over it
## (owner 2026-09-29: 天气效果不用铺满整个省份，再小一点): whole out to
## map3d_weather_cell_core of the province's own radius (its area's), gone by
## map3d_weather_cell_edge (the core never under map3d_weather_cell_min_px, or
## the blur ate a small province's weather), the rim wobbled by map3d_weather_cell_wobble with
## the angle so no cell is a circle — well inside the province, clear of its
## neighbours. The whole province still slows a march: the look is smaller
## than the rule, and the HUD mark at the centre names it.
func _cut_cells(repo: DataRepository) -> void:
	var count := PackedInt32Array()
	count.resize(_prov_codes.size())
	for t in _texel_prov.size():
		if _texel_prov[t] >= 0:
			count[_texel_prov[t]] += 1
	var centre: Array = []
	var radius := PackedFloat32Array()
	var phase := PackedFloat32Array()
	for p in _prov_codes.size():
		var row: Dictionary = repo.provinces.get(_prov_codes[p], {})
		centre.append(Vector2(float(row.get("center_x", 0.0)), float(row.get("center_y", 0.0))))
		radius.append(sqrt(float(count[p]) * step_px * step_px / PI))
		phase.append(float(posmod(String(_prov_codes[p]).hash(), 6283)) / 1000.0)
	var core := repo.bal("map3d_weather_cell_core")
	var edge := maxf(repo.bal("map3d_weather_cell_edge"), core + 0.01)
	var wobble := repo.bal("map3d_weather_cell_wobble")
	var min_px := repo.bal("map3d_weather_cell_min_px")
	_texel_cell = PackedFloat32Array()
	_texel_cell.resize(_texel_prov.size())
	for j in size.y:
		for i in size.x:
			var t := j * size.x + i
			var p := _texel_prov[t]
			if p < 0:
				continue
			var off := (Vector2(i + 0.5, j + 0.5) * step_px) - (centre[p] as Vector2)
			var a := off.angle()
			var w := 1.0 + wobble * (0.6 * sin(3.0 * a + phase[p]) + 0.4 * sin(5.0 * a + 2.0 * phase[p]))
			var core_px := maxf(core * radius[p], min_px)
			_texel_cell[t] = 1.0 - smoothstep(core_px, maxf(edge * radius[p], core_px * 1.8),
				off.length() / w)


## Softens `img` over about `halvings` octaves: halved that many times (each a
## 2x2 mean) and grown back by a cubic — native Image work, a few ms.
static func _blur(img: Image, halvings: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for i in halvings:
		@warning_ignore("integer_division")  # whole texels
		img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	if halvings > 0:
		img.resize(w, h, Image.INTERPOLATE_CUBIC)


## The ground look (wet, mud, snow, overcast) of `ground` at a pack point
## (nearest texel), for the clouds to read on the CPU.
func sample(ground: Image, pack_px: Vector2) -> Color:
	if ground == null:
		return Color(0, 0, 0, 0)
	var i := clampi(int(floor(pack_px.x / float(step_px))), 0, size.x - 1)
	var j := clampi(int(floor(pack_px.y / float(step_px))), 0, size.y - 1)
	return ground.get_pixel(i, j)
