class_name Map3DCloudField
extends RefCounted
## Where the 3D map's clouds are (owner 2026-09-18: more than the 2D map's):
## a pure field the view steps every frame and draws. While the clock runs
## the sky fills at once over the view, clouds drift downwind at the clock's
## speed, drop out once well past the view and come in again upwind; when it
## stops they fade and are cleared. Look only: its own seeded generator,
## never the engine's stream. Positions are world XZ metres.

var clouds: Array = []  # {pos: Vector2, size: float, rot: float, life: float}
var fade := 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_in := 0.0


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func step(delta: float, running: bool, clock_speed: int, view: Rect2, p: Dictionary) -> void:
	var fade_s := maxf(float(p["fade_s"]), 0.01)
	if not running:
		fade = maxf(fade - delta / fade_s, 0.0)
		if fade <= 0.0:
			clouds.clear()
			_spawn_in = 0.0
		return
	var first := clouds.is_empty() and fade <= 0.0
	fade = minf(fade + delta / fade_s, 1.0)
	var wind := Vector2.from_angle(deg_to_rad(float(p["wind_deg"])))
	var move := wind * float(p["speed_m_s"]) * float(maxi(clock_speed, 1)) * delta
	var keep: Array = []
	var margin := float(p["size_max"]) * 2.0
	for c: Dictionary in clouds:
		c["pos"] = (c["pos"] as Vector2) + move
		c["life"] = minf(float(c["life"]) + delta / fade_s, 1.0)
		if view.grow(margin).has_point(c["pos"]):
			keep.append(c)
	clouds = keep
	var cap := int(p["max"])
	if first:
		while clouds.size() < cap:
			clouds.append(_cloud(view, p, Vector2.ZERO, _positions()))
		return
	_spawn_in -= delta
	if _spawn_in <= 0.0 and clouds.size() < cap:
		clouds.append(_cloud(view, p, wind, _positions()))
		_spawn_in = float(p["interval_s"]) * _rng.randf_range(0.5, 1.5)


func _positions() -> Array:
	var out: Array = []
	for c: Dictionary in clouds:
		out.append(c["pos"])
	return out


## A cloud over the view, or — with a wind — just off its upwind side. With
## `min_gap_m` in `p` and room in the sky (fix round 1, owner 2026-09-18: the
## shipped sky, gap-blind, read as one fused landmass of shadow at 24 km), it
## is a BEST EFFORT at a few candidates apart from every `existing` cloud,
## keeping the furthest found even when none clears the gap outright. With
## no `min_gap_m` (or an empty sky) this draws exactly ONE candidate, in the
## SAME rng order as before the fix (pos.x, pos.y, size, then rot) — a
## caller that never sets it sees byte-identical positions.
func _cloud(view: Rect2, p: Dictionary, wind: Vector2, existing: Array) -> Dictionary:
	var min_gap := float(p.get("min_gap_m", 0.0))
	# With a `weight_fn` (world XZ -> 0..1, the weather's overcast) the sky
	# favours bad weather: of the candidates, the one under the most overcast
	# wins, a well-spaced one breaking ties (spec 2026-09-29-weather-visuals).
	var weigh: Callable = p.get("weight_fn", Callable())
	var attempts := 6 if (min_gap > 0.0 and not existing.is_empty()) or weigh.is_valid() else 1
	var best_pos := Vector2.ZERO
	var best_size := 0.0
	var best_d := -1.0
	for attempt in attempts:
		var pos := Vector2(_rng.randf_range(view.position.x, view.end.x),
			_rng.randf_range(view.position.y, view.end.y))
		var size := _rng.randf_range(float(p["size_min"]), float(p["size_max"]))
		if wind != Vector2.ZERO:
			pos -= wind * (view.size.length() * 0.5 + size)
		var d := INF
		for e: Vector2 in existing:
			d = minf(d, pos.distance_to(e))
		if weigh.is_valid():
			d = float(weigh.call(pos)) + 0.35 * (minf(d / min_gap, 1.0) if min_gap > 0.0 else 1.0)
		if d > best_d:
			best_pos = pos
			best_size = size
			best_d = d
		if d >= min_gap and not weigh.is_valid():
			break
	return {"pos": best_pos, "size": best_size, "rot": _rng.randf_range(0.0, TAU),
		"life": 1.0 if wind == Vector2.ZERO else 0.0}


## One cloud's shape: a soft simplex-noise puff fading to clear at its edge,
## white with the shape in its alpha — the deck and its shadow twin both
## sample it. Was the 2D map's CloudLayer.cloud_texture; it moved here when
## the 2D map was deleted (2026-09-24).
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
