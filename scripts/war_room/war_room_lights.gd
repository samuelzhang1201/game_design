class_name WarRoomLights
extends RefCounted
## The candles on the oak table (fix round 1 ruling): ONE key candle — a
## stronger, raking, shadow-casting light that models the sheet's relief — and
## the other candlesticks short warm accents with no shadow, so the slopes are
## lit from one side and read. Every energy, range and offset is a screens/war_room/balance.csv
## `war_candle_*` key; how many candles cast a shadow (the key first) and how
## is the graphics tier's (`graphics_quality.csv` `war_candle_shadows`,
## `war_candle_shadow_cube`).


## The candlesticks' lights in the scene's order (Candlestick1..N under `room`).
static func candles(room: Node3D) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	var sticks := room.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Candlestick"))
	sticks.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for s: Node in sticks:
		var l := s.get_node_or_null("Light") as OmniLight3D
		if l != null:
			out.append(l)
	return out


## The key candle's index into `candles` (war_candle_key counts from 1).
static func key_index(repo: DataRepository, count: int) -> int:
	return clampi(int(repo.bal("war_candle_key")) - 1, 0, maxi(0, count - 1))


## The candles in shadow order: the key first, then the rest as the scene has them.
static func shadow_order(repo: DataRepository, lights: Array[OmniLight3D]) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	if lights.is_empty():
		return out
	var k := key_index(repo, lights.size())
	out.append(lights[k])
	for i in lights.size():
		if i != k:
			out.append(lights[i])
	return out


## Set each candle as the key or an accent. The key stands `war_candle_key_y_m`
## over its candlestick's foot and `war_candle_key_out_m` further out from the
## table's middle (a raking light from outside the corner), the accents at the
## candles' own flames.
static func bind(repo: DataRepository, lights: Array[OmniLight3D]) -> void:
	var k := key_index(repo, lights.size())
	for i in lights.size():
		var l := lights[i]
		var stick := l.get_parent() as Node3D
		var key := i == k
		var out := Vector3(stick.position.x, 0.0, stick.position.z)
		out = out.normalized() * repo.bal("war_candle_key_out_m") if key and out.length() > 0.0001 else Vector3.ZERO
		var at := stick.position + out + Vector3(0.0, repo.bal("war_candle_key_y_m" if key else "war_candle_accent_y_m"), 0.0)
		l.position = stick.transform.affine_inverse() * at
		l.light_color = repo.war_palette["candle"]
		l.light_energy = repo.bal("war_candle_key_energy" if key else "war_candle_accent_energy")
		l.omni_range = repo.bal("war_candle_key_range_m" if key else "war_candle_accent_range_m")
		l.omni_attenuation = repo.bal("war_candle_key_attenuation" if key else "war_candle_accent_attenuation")


## The tier's shadows: the first `war_candle_shadows` candles in shadow order
## cast one, as cube maps when `war_candle_shadow_cube` is 1, else the cheaper
## dual paraboloid.
static func apply_tier(repo: DataRepository, lights: Array[OmniLight3D], row: Dictionary) -> void:
	var n := int(Map3DQuality.num(row, "war_candle_shadows", 1.0))
	var cube := Map3DQuality.num(row, "war_candle_shadow_cube", 0.0) >= 1.0
	var order := shadow_order(repo, lights)
	for i in order.size():
		order[i].shadow_enabled = i < n
		order[i].omni_shadow_mode = OmniLight3D.SHADOW_CUBE if cube else OmniLight3D.SHADOW_DUAL_PARABOLOID
