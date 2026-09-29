class_name Map3DLayerThemes
extends RefCounted
## MANORS and HEIGHTS on the 3D ground (spec 2026-09-20 §1; owner
## 2026-09-19): the patched Terrain3D shader (Map3DGroundTint) with its field
## map, MANORS' LUT of each cell's ManorPalette colour and the cell edges
## (Lines/ManorEdges), HEIGHTS' heat mix. One theme at a time. The theme is
## held from creation, so heat_on() works before the world loads (the tests'
## fixture has no Terrain3D).

## Metres per texel of the bake's field map: tools/map3d/bake_world.py
## FIELD_MAP_STEP (2) vertices of VERTEX_M (20 m).
const FIELD_MAP_M_PER_TEXEL := 40.0

var ctx: Map3DContext
var lines: Map3DLayerLines
## The theme: "", "manors" or "heights" — GameRoot hands it down.
var _theme := ""
## HEIGHTS' heat mix (owner 2026-09-19, spec 2026-09-19-map3d-heights): a
## plain bool set with the theme, so heat_on() works before any load.
var _heat := false
## The LUT of each cell's ManorPalette colour the patched terrain shader reads
## (Map3DGroundTint), rebuilt when the theme or an owner turns; the terrain
## material carrying the patch (null without a Terrain3D or when the addon's
## code would not patch); whether the cell edges have been laid.
var _theme_sig := 0
var _cell_lut: ImageTexture
var _lut_image: Image
var _tint_mat: Resource
var _edges_built := false


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines) -> void:
	ctx = p_ctx
	lines = p_lines


## Patch the world's Terrain3D shader for the manor tint (Map3DGroundTint).
## Without a Terrain3D (the tests' fixture) or when the addon's code no longer
## carries the line the patch rewrites, the ground simply stays plain.
func prepare(scene_path: String) -> void:
	var terrains := ctx.world.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return
	var mat: Resource = terrains[0].get("material")
	if mat == null:
		return
	mat.set("shader_override_enabled", true)
	var shader: Shader = mat.get("shader_override")
	var patched := "" if shader == null else Map3DGroundTint.patch(shader.code)
	if patched == "":
		mat.set("shader_override_enabled", false)
		push_warning("Map3DView: Terrain3D's shader has no line to tint — the themes leave the ground plain")
		return
	# A kept world (Map3DWorldCache) arrives already patched: its material is
	# this view's own, so the shader is left as it is — no second rewrite.
	if not Map3DGroundTint.is_patched(shader.code):
		shader.code = patched
	_tint_mat = mat
	var repo := ctx.repo
	var origin: Array = ctx.meta.get("pack_origin", [0.0, 0.0])
	mat.call("set_shader_param", "pack_origin", Vector2(float(origin[0]), float(origin[1])))
	mat.call("set_shader_param", "m_per_px", float(ctx.meta.get("m_per_px", 50.0)))
	if repo.cell_texture_path != "" and ResourceLoader.exists(repo.cell_texture_path):
		mat.call("set_shader_param", "cell_index", load(repo.cell_texture_path))
	mat.call("set_shader_param", "tint_mix", 0.0)
	# HEIGHTS (owner 2026-09-19): the ground's world height ramped through
	# terrain_palette heat_1..6, over 0..elevation_m_per_unit x
	# (100 - elevation_sea_level) metres.
	mat.call("set_shader_param", "heat_mix", 0.0)
	mat.call("set_shader_param", "heat_sea_y", float(ctx.meta.get("sea_y", 0.0)))
	mat.call("set_shader_param", "heat_top_m",
		repo.bal("elevation_m_per_unit") * (100.0 - repo.bal("elevation_sea_level")))
	for i in 6:
		mat.call("set_shader_param", "heat_c%d" % i,
			MapTerrain.palette_color(repo, "heat_%d" % (i + 1), MapTerrain.FALLBACK))
	# the bake's field map (owner 2026-09-19): furrows up close, the crops'
	# colour eased back far out; without it both stay off
	var fields := load_field_map(scene_path)
	if fields == null:
		Map3DWorldLoader.warn_once("fields:" + scene_path,
			"Map3DView: no bake/fields.png beside %s — no furrows (rebuild: tools/map3d/build_pack.sh)" % scene_path)
	else:
		mat.call("set_shader_param", "field_map", fields)
		mat.call("set_shader_param", "field_m_per_texel", FIELD_MAP_M_PER_TEXEL)
		mat.call("set_shader_param", "furrow_m", repo.bal("map3d_furrow_m"))
		mat.call("set_shader_param", "furrow_depth", repo.bal("map3d_furrow_depth"))
		mat.call("set_shader_param", "field_fade", repo.bal("map3d_field_fade"))
		mat.call("set_shader_param", "field_fade_near_m", repo.bal("map3d_field_fade_near_m"))
		mat.call("set_shader_param", "field_fade_far_m", repo.bal("map3d_field_fade_far_m"))


## The bake's field map beside a built scene (bake/fields.png — the bake dir
## is .gdignored, so it is read as a file, not imported), or null.
static func load_field_map(scene_path: String) -> Texture2D:
	var path := ProjectSettings.globalize_path(scene_path.get_base_dir().path_join("bake/fields.png"))
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return null if img == null else ImageTexture.create_from_image(img)


## Store the theme: "manors", "heights", or "" for none. refresh() puts it
## on the ground.
func set_theme(theme_name: String) -> void:
	_theme = theme_name
	_heat = theme_name == "heights"


func theme() -> String:
	return _theme


## Whether the HEIGHTS heat is on the ground.
func heat_on() -> bool:
	return _heat


## The theme on the ground: MANORS' LUT (rebuilt when an owner turns), its
## tint and cell edges; HEIGHTS' heat mix. Nothing until bound.
func refresh() -> void:
	if ctx == null:
		return
	var manors := _theme == "manors"
	if manors:
		var st := ctx.state()
		var sig := hash([_theme, 0 if st == null else st.province_owner.hash(),
			0 if st == null else st.manor_owner.hash(),
			0 if st == null else st.manor_province.hash()])
		if sig != _theme_sig or _cell_lut == null:
			_theme_sig = sig
			_build_lut()
		if not _edges_built:
			_build_manor_edges()
	if _tint_mat != null:
		_tint_mat.call("set_shader_param", "tint_mix",
			ctx.repo.bal("map3d_manor_tint") if manors else 0.0)
		_tint_mat.call("set_shader_param", "heat_mix",
			ctx.repo.bal("map3d_heat_tint") if _heat else 0.0)
	var edges := lines.get_node_or_null("ManorEdges") as MeshInstance3D
	if edges != null:
		edges.visible = manors


## Each land cell's ManorPalette colour for the theme at texel (id % w, id / w).
func _build_lut() -> void:
	var repo := ctx.repo
	var max_id := 0
	for id: int in repo.cells:
		max_id = maxi(max_id, id)
	var lut := Map3DGroundTint.lut_size(max_id)
	var img := Image.create(lut.x, lut.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := ctx.state()
	for id: int in repo.cells:
		@warning_ignore("integer_division")  # the LUT row this cell id falls in
		img.set_pixel(id % lut.x, id / lut.x, ManorPalette.theme_color(repo, st, id, _theme))
	_lut_image = img
	if _cell_lut != null and _cell_lut.get_size() == Vector2(lut):
		_cell_lut.update(img)
	else:
		_cell_lut = ImageTexture.create_from_image(img)
	if _tint_mat != null:
		_tint_mat.call("set_shader_param", "cell_lut", _cell_lut)
		_tint_mat.call("set_shader_param", "lut_size", lut)


## The cell edges (ManorPalette.edges, the 2D map's own) as constant-width
## ribbons on the relief, in the 2D map's manor_line ink, alpha and width.
## Geometry: laid on the first theme and kept.
func _build_manor_edges() -> void:
	_edges_built = true
	var repo := ctx.repo
	var step := ctx.line_step()
	var pairs := ManorPalette.edges(repo)
	var pairs_lines: Array = []
	for i in range(0, pairs.size() - 1, 2):
		var seg := PackedVector2Array([Map3DGeometry.pack_to_world(ctx.meta, pairs[i]),
			Map3DGeometry.pack_to_world(ctx.meta, pairs[i + 1])])
		pairs_lines.append(Map3DGeometry.resample(seg, step))
	var ink := MapPalette.named(repo, "manor_line")
	ink.a = repo.bal("map_manor_line_alpha")
	lines.set_lines("ManorEdges", pairs_lines,
		Map3DLineStyle.solid(ink, "map_manor_line_width", Map3DPriority.MANOR_EDGES))


## The terrain material carrying the patch (null without a Terrain3D, or when
## the addon's code would not patch) — the weather's uniforms go on it too.
func tint_material() -> Resource:
	return _tint_mat


## The LUT the terrain shader reads (null before the first theme).
func cell_lut() -> ImageTexture:
	return _cell_lut


## The colour the LUT holds for cell `id` (clear before a theme).
func lut_color(id: int) -> Color:
	if _lut_image == null:
		return Color(0, 0, 0, 0)
	var w := _lut_image.get_width()
	@warning_ignore("integer_division")  # the LUT row this cell id falls in
	return _lut_image.get_pixel(id % w, id / w)
