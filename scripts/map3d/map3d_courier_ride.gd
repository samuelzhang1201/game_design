class_name Map3DCourierRide
extends RefCounted
## The pure maths of a courier's drawn ride, read by Map3DLayerCouriers: how
## far along his road the day's share puts him, and his FADE the moment he
## delivers (owner 2026-09-30: 信使送到信息后要立即淡化消失) — as the day ends,
## since he rides evenly to its end (owner 2026-10-02). Pure but for `apply`,
## `ghost` and `fade_ghosts`, which only set his meshes' transparency, pause
## his clip and free a faded piece. Never the Game autoload.


## 1 before he delivered (`elapsed` < 0), falling to 0 over `fade_s` real seconds.
static func alpha(elapsed: float, fade_s: float) -> float:
	if elapsed < 0.0:
		return 1.0
	return clampf(1.0 - elapsed / fade_s, 0.0, 1.0) if fade_s > 0.0 else 0.0


## His meshes see-through by 1 - `a`, set only when it changed.
static func apply(piece: Dictionary, a: float) -> void:
	if is_equal_approx(float(piece.get("alpha", 1.0)), a):
		return
	piece["alpha"] = a
	for m: MeshInstance3D in Map3DUnits.meshes(piece["node"]):
		m.transparency = 1.0 - a


## Whether courier `id`, gone from the state, fades where he delivered — his
## last ride (`ride`) ended on the column and his `piece` is drawn — noting it
## in `ghosts` (id -> real seconds fading, from `faded`): the engine lets him go
## as the day ends (owner 2026-10-02), his piece stays to fade out there.
static func ghost(ghosts: Dictionary, id: int, ride: Dictionary, piece: Dictionary, faded: float) -> bool:
	if ghosts.has(id):
		return true
	if not bool(ride.get("ends", false)) or not (piece["node"] as Node3D).visible:
		return false
	ghosts[id] = faded
	var anim: AnimationPlayer = piece.get("anim")
	if anim != null:
		anim.pause()  # he has arrived: no gallop in place
	return true


## Every ghost a `delta` further faded, freed (from `pieces` too) once gone.
static func fade_ghosts(ghosts: Dictionary, pieces: Dictionary, delta: float, fade_s: float) -> void:
	for id in ghosts.keys():
		ghosts[id] = float(ghosts[id]) + delta
		var a := alpha(float(ghosts[id]), fade_s)
		if pieces.has(id) and a > 0.0:
			apply(pieces[id], a)
			continue
		if pieces.has(id):
			(pieces[id]["node"] as Node3D).queue_free()
			pieces.erase(id)
		ghosts.erase(id)


## `dist` along the points of `queue` from `now`, dropping each point reached.
static func walk_along(now: Vector2, queue: Array, dist: float) -> Vector2:
	var at := now
	var left := dist
	while not queue.is_empty():
		var to: Vector2 = queue[0]
		var d := at.distance_to(to)
		if d > left:
			return at + (to - at) / d * left
		left -= d
		at = to
		queue.pop_front()
	return at


static func length_along(now: Vector2, points: Array) -> float:
	var total := 0.0
	var at := now
	for p: Vector2 in points:
		total += at.distance_to(p)
		at = p
	return total
