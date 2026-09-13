class_name SeaLayer
extends Node2D
## The sea under the land (owner 2026-09-13, after the reference chart): four
## flat bands by distance from the shore — near, nearer, far, deep — each
## edge a soft fade, over a fixed wave grain. Nothing is drawn per cell: the
## pack carries world_sea_distance.png (every pixel its distance to land in
## native px, baked by MapIndex.bake_sea_distance in the importer), and
## sea_bands.gdshader maps that distance to the band colours and lays the
## grain over it, so the whole sea is ONE textured quad a frame and the bands
## are as smooth as the field. Drawn behind WorldMapView's own _draw
## (show_behind_parent), which paints the land mesh over it: the shore is the
## land's own edge. The view sets this node's position and scale to its
## offset and zoom, so the sea pans and zooms with the map.
##
## Colours are terrain_palette.csv sea_near / sea_nearer / sea_far /
## sea_deep; the band edges and the grain are balance.csv map_sea_band_* and
## map_sea_wave_*. The grain is part of the drawing (native px), not the
## paper: it zooms with the map, and its seed is data, so it is the same sea
## every run — a look, never simulation.

const SHADER_PATH := "res://scripts/ui/sea_bands.gdshader"
const GRAIN_TILE_PX := 256

var _field: Texture2D = null
var _size := Vector2.ZERO
var _grain: NoiseTexture2D = null

## Native size of the field — the map's own canvas. Test seam.
func field_size() -> Vector2:
	return _size

func has_field() -> bool:
	return _field != null

func setup(repo: DataRepository) -> void:
	show_behind_parent = true
	_size = Vector2(float(repo.map_info.get("width", "0")), float(repo.map_info.get("height", "0")))
	_field = UiPalette.load_art(repo.sea_texture_path) if repo.sea_texture_path != "" else null
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	for band: String in ["near", "nearer", "far", "deep"]:
		mat.set_shader_parameter("sea_" + band,
			MapTerrain.palette_color(repo, "sea_" + band, MapTerrain.FALLBACK))
	mat.set_shader_parameter("band_near", repo.bal("map_sea_band_near_px"))
	mat.set_shader_parameter("band_nearer", repo.bal("map_sea_band_nearer_px"))
	mat.set_shader_parameter("band_far", repo.bal("map_sea_band_far_px"))
	mat.set_shader_parameter("soft", repo.bal("map_sea_band_soft_px"))
	var tile := maxf(repo.bal("map_sea_wave_tile_px"), 1.0)
	mat.set_shader_parameter("wave_scale",
		Vector2(tile * maxf(repo.bal("map_sea_wave_stretch"), 1.0), tile))
	mat.set_shader_parameter("wave_alpha", repo.bal("map_sea_wave_alpha"))
	mat.set_shader_parameter("wave_cut", repo.bal("map_sea_wave_cut"))
	mat.set_shader_parameter("field_px", _size)
	_grain = _make_grain(int(repo.bal("map_sea_wave_seed")))
	mat.set_shader_parameter("waves", _grain)
	material = mat
	queue_redraw()

## A seamless simplex tile; the shader stretches it sideways into streaks.
func _make_grain(seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value
	noise.frequency = 1.0 / 24.0
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = GRAIN_TILE_PX
	tex.height = GRAIN_TILE_PX
	tex.seamless = true
	tex.noise = noise
	return tex

func _draw() -> void:
	if _size.x <= 0.0 or _size.y <= 0.0:
		return
	# Beyond the field is open sea: a plain quad, which the shader reads as
	# the deep band (no texture samples as white, distance 255). Nine times
	# the map, so it fills the frame at the zoom-out floor.
	draw_rect(Rect2(-_size * 4.0, _size * 9.0), Color.WHITE)
	if _field != null:
		draw_texture_rect(_field, Rect2(Vector2.ZERO, _size), false)
