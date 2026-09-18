class_name BiomeLayer
extends Node2D
## THE BIOMES LAYER — an EXPERIMENT (owner 2026-09-14). The land of the
## default map wears the biome ground tiles (library §5 T- tiles, colour
## pencil; data/biome_art.csv says which tile a biome wears), and every
## pixel is a MIX of the tiles around it: the pack carries
## world_biome_weights_N.png, each biome's share of the land within
## map_biome_blur_px of the point (baked by MapIndex.bake_biome_weights,
## tools/bake_biome_weights.gd), so one biome fades into the next over a
## couple of cells and no cell edge is left to see (owner: the tiles must
## sink into the map with no shape showing). biome_tiles.gdshader does the
## mixing on the GPU over the LAND MESH (MapTerrain.shared_mesh) — the shore
## is the mesh's own edge — from a Texture2DArray with one layer per biome
## id 1..12. Drawn behind WorldMapView's own _draw (show_behind_parent),
## above the sea and the ground (terrain and wash) — the view orders its
## children so — and below the water, the roads, the woods and the towns.
## The view sets this node's position and scale to its offset and zoom.
##
## TO REMOVE THE EXPERIMENT: delete this file, biome_tiles.gdshader,
## GroundLayer (and give the terrain and the wash back to the view's own
## _draw), tools/bake_biome_weights.gd and MapIndex.bake_biome_weights,
## assets/maps/<id>/world_biome_weights_*.png and maps.csv biome_weights,
## data/biome_art.csv, assets/biomes/, assets/flux/biome_art.csv and
## install_biomes, the map_biome_* rows of balance.csv, and the blocks marked
## BIOMES LAYER in DataRepository, WorldMapView, the view test and
## tools/snapshot_map.gd.

const SHADER_PATH := "res://scripts/ui/biome_tiles.gdshader"
## One layer per biome id 1..LAYERS; the shader mixes sixteen. 13, 14 and
## 15 are not Azgaar biomes — MapIndex.raise_high_ground rewrites high land
## to them (hill, mountain, peak) so the high ground blends in like any
## other ground (owner 2026-09-17).
const LAYERS := 16
const WEIGHT_IMAGES := 4

var _mesh: ArrayMesh = null
var _size := Vector2.ZERO
var _tile_count := 0
var _weight_count := 0

## Native size of the field — the map's own canvas. Test seam.
func field_size() -> Vector2:
	return _size

## How many biomes brought a tile. Test seam.
func tile_count() -> int:
	return _tile_count

func has_tiles() -> bool:
	return _tile_count > 0

## Whether the pack's baked weight maps loaded (all of them). Test seam.
func has_weights() -> bool:
	return _weight_count == WEIGHT_IMAGES

func setup(repo: DataRepository, biome_index: Image) -> void:
	show_behind_parent = true
	_size = Vector2(float(repo.map_info.get("width", "0")), float(repo.map_info.get("height", "0")))
	_mesh = MapTerrain.shared_mesh(repo)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	if biome_index != null:
		mat.set_shader_parameter("biome_index", ImageTexture.create_from_image(biome_index))
	_weight_count = 0
	if repo.biome_weights_path != "":
		for i in WEIGHT_IMAGES:
			var tex := UiPalette.load_art("%s_%d.png" % [repo.biome_weights_path, i])
			if tex != null:
				mat.set_shader_parameter("weights_%d" % i, tex)
				_weight_count += 1
	mat.set_shader_parameter("tiles", _build_tiles(repo))
	mat.set_shader_parameter("field_px", _size)
	mat.set_shader_parameter("tile_px", maxf(repo.bal("map_biome_tile_px"), 1.0))
	# TILE LOD (owner 2026-09-17): one tile size cannot be both sharp up close
	# and free of a visible repeat at world zoom, so the shader crossfades two
	# densities by the view's own zoom. set_view_zoom keeps it current.
	mat.set_shader_parameter("tile_px_far", maxf(repo.bal("map_biome_tile_px_far"), 1.0))
	mat.set_shader_parameter("lod_near_zoom", repo.bal("map_biome_lod_near_zoom"))
	mat.set_shader_parameter("lod_far_zoom", repo.bal("map_biome_lod_far_zoom"))
	mat.set_shader_parameter("alpha", repo.bal("map_biome_alpha"))
	# Relief (owner 2026-09-17, choice B): the photograph is lit by the slope
	# of the pack's baked height field, from the map's own light.
	var relief := UiPalette.load_art(repo.relief_path) if repo.relief_path != "" else null
	if relief != null:
		mat.set_shader_parameter("relief", relief)
		mat.set_shader_parameter("shade", repo.bal("map_relief_shade"))
	else:
		mat.set_shader_parameter("shade", 0.0)
	mat.set_shader_parameter("shade_px", repo.bal("map_relief_shade_px"))
	mat.set_shader_parameter("gain", repo.bal("map_relief_gain"))
	mat.set_shader_parameter("light", Vector2(repo.bal("map_light_x"), repo.bal("map_light_y")))
	# SETTLEMENT EARTH HALO (owner 2026-09-17): the ground fades to bare earth
	# near a town, so its art rises out of worked land. Absent field or rows
	# leave the shader's own 0 strength, i.e. unchanged.
	var settle := UiPalette.load_art(repo.settlement_path) if repo.settlement_path != "" else null
	if settle != null:
		mat.set_shader_parameter("settlement", settle)
		mat.set_shader_parameter("town_fade_px", float(repo.balance.get("map_town_halo_fade_px", 0.0)))
		mat.set_shader_parameter("town_earth_strength", float(repo.balance.get("map_town_earth_strength", 0.0)))
		var earth := MapTerrain.palette_color(repo, "town_earth", Color(0.68, 0.60, 0.49))
		mat.set_shader_parameter("town_earth", Vector3(earth.r, earth.g, earth.b))
	# SURFACE FOLLOWS THE LAND (owner 2026-09-17): slope and height bias which
	# tile shows, so the cover is a result of the topography and not of the biome
	# id alone. bal() asserts on a missing key, so read the dict directly: a pack
	# without these rows leaves the shader's own 0 strengths, i.e. unchanged.
	for key: String in ["map_biome_rock_slope_lo", "map_biome_rock_slope_hi",
			"map_biome_rock_strength", "map_biome_snow_height",
			"map_biome_snow_soft", "map_biome_snow_strength",
			"map_biome_rock_height_lo", "map_biome_rock_height_hi"]:
		if repo.balance.has(key):
			mat.set_shader_parameter(key.trim_prefix("map_biome_"), float(repo.balance[key]))
	material = mat
	queue_redraw()

## biome_id -> texture path, first row per biome; rows without a texture
## are skipped.
static func art_of(repo: DataRepository) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in repo.biome_art:
		var id := int(row.get("biome_id", -1))
		var texture := String(row.get("texture", ""))
		if id >= 1 and id <= LAYERS and texture != "" and not out.has(id):
			out[id] = texture
	return out

## One square RGBA layer per biome id, every one the size of the first tile
## that loads (a Texture2DArray wants them alike), mipmapped; a biome
## without a tile is a clear layer, which the shader mixes as nothing.
func _build_tiles(repo: DataRepository) -> Texture2DArray:
	var art := art_of(repo)
	var side := 0
	var loaded: Dictionary = {}
	for id in art:
		var tex := UiPalette.load_art(String(art[id]))
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		loaded[id] = img
		if side == 0:
			side = maxi(img.get_width(), img.get_height())
	if side == 0:
		side = 4
	var images: Array[Image] = []
	for id in range(1, LAYERS + 1):
		var img: Image = null
		if loaded.has(id):
			img = (loaded[id] as Image).duplicate()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != side or img.get_height() != side:
				img.resize(side, side, Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			_tile_count += 1
		else:
			img = Image.create_empty(side, side, true, Image.FORMAT_RGBA8)
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr

## The view's zoom in screen px per native px, for the tile LOD. Cheap, so
## the view may call it every frame; the material only stores a float.
func set_view_zoom(zoom: float) -> void:
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("view_zoom", maxf(zoom, 0.0001))


func _draw() -> void:
	if _mesh != null and _size.x > 0.0 and _size.y > 0.0:
		draw_mesh(_mesh, null, Transform2D())
