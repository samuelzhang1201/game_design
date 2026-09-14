class_name CloudLayer
extends Node2D
## Clouds drifting over the DEFAULT map while time runs (owner 2026-09-14):
## now and then a very faint cloud floats across the sheet; pause the clock
## and they fade away; under a theme or the military layer there are none.
##
## A child of WorldMapView drawn OVER the map's own drawing (not behind it),
## in native map px — the view sets this node's position and scale to its
## offset and zoom, as it does for the sea — so a cloud pans and zooms with
## the land it passes over. Purely a look: its random numbers come from its
## own generator seeded from balance.csv (map_cloud_seed), never the engine's
## stream, and nothing it does touches game state.

## Asked every frame whether clouds belong on the map right now.
var is_active: Callable = func() -> bool: return false
## The native-px rect the view currently shows.
var visible_native: Callable = func() -> Rect2: return Rect2()

var _rng := RandomNumberGenerator.new()
var _clouds: Array = []  # {pos, variant, size: Vector2, life}
var _spawn_in := 0.0
var _fade := 0.0  # 0 gone .. 1 fully present, the pause fade
var _textures: Array = []

func setup() -> void:
	_rng.seed = int(Game.data.bal("map_cloud_seed"))
	_spawn_in = 0.0

func _process(delta: float) -> void:
	var repo := Game.data
	if repo == null:
		return
	var active := bool(is_active.call())
	var fade_s := maxf(repo.bal("map_cloud_fade_s"), 0.01)
	if active:
		_fade = minf(_fade + delta / fade_s, 1.0)
		_spawn_in -= delta
		if _spawn_in <= 0.0 and _clouds.size() < int(repo.bal("map_cloud_max")):
			_spawn(_clouds.is_empty())
			_spawn_in = _rng.randf_range(repo.bal("map_cloud_interval_min_s"),
				repo.bal("map_cloud_interval_max_s"))
		var wind := Vector2.from_angle(deg_to_rad(repo.bal("map_cloud_wind_deg")))
		var speed := repo.bal("map_cloud_speed_px") * float(maxi(Game.clock_speed, 1))
		var view := visible_native.call() as Rect2
		var keep: Array = []
		for c: Dictionary in _clouds:
			c["pos"] = (c["pos"] as Vector2) + wind * speed * delta
			c["life"] = minf(float(c["life"]) + delta / fade_s, 1.0)
			# Gone once it has drifted well past the far side of the view.
			var reach := (c["size"] as Vector2).length()
			if view.grow(reach * 2.0).has_point(c["pos"]):
				keep.append(c)
		_clouds = keep
		queue_redraw()
	elif _fade > 0.0:
		_fade = maxf(_fade - delta / fade_s, 0.0)
		if _fade <= 0.0:
			_clouds.clear()
			_spawn_in = 0.0
		queue_redraw()

## A new cloud at the upwind edge of the view — or, for the first one after
## the clock starts, somewhere over the view itself, so play shows a cloud
## without a wait.
func _spawn(inside: bool) -> void:
	var repo := Game.data
	var view := visible_native.call() as Rect2
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	var w := repo.bal("map_cloud_size_px") * _rng.randf_range(0.7, 1.3)
	var size := Vector2(w, w * _rng.randf_range(0.45, 0.65))
	var wind := Vector2.from_angle(deg_to_rad(repo.bal("map_cloud_wind_deg")))
	var pos := Vector2(_rng.randf_range(view.position.x, view.end.x),
		_rng.randf_range(view.position.y, view.end.y))
	if not inside:
		# Step back against the wind until the cloud starts just off the view.
		pos -= wind * (view.size.length() * 0.5 + size.x)
		pos += wind * view.size.length() * 0.5 * _rng.randf_range(-0.2, 0.2)
	_clouds.append({"pos": pos, "variant": _rng.randi_range(0, 2), "size": size, "life": 0.0})

func _draw() -> void:
	if _clouds.is_empty() or _fade <= 0.0:
		return
	var alpha := Game.data.bal("map_cloud_alpha")
	for c: Dictionary in _clouds:
		var tex := _texture(int(c["variant"]))
		var s: Vector2 = c["size"]
		draw_texture_rect(tex, Rect2((c["pos"] as Vector2) - s * 0.5, s), false,
			Color(1.0, 1.0, 1.0, alpha * _fade * float(c["life"])))

## Soft white puffs: fractal noise under an elliptical falloff, built once.
func _texture(variant: int) -> Texture2D:
	if _textures.is_empty():
		for v in 3:
			_textures.append(cloud_texture(int(Game.data.bal("map_cloud_seed")) + v * 101))
	return _textures[clampi(variant, 0, _textures.size() - 1)]

const TEX_W := 192
const TEX_H := 112

static func cloud_texture(seed_value: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.03
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	for y in TEX_H:
		for x in TEX_W:
			var u := (float(x) / float(TEX_W - 1)) * 2.0 - 1.0
			var v := (float(y) / float(TEX_H - 1)) * 2.0 - 1.0
			var fall := clampf(1.0 - (u * u + v * v), 0.0, 1.0)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := clampf((n * 1.5 - 0.3) * sqrt(fall) * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a)))
	return ImageTexture.create_from_image(img)

## Test seams.
func cloud_count() -> int:
	return _clouds.size()

func presence() -> float:
	return _fade
