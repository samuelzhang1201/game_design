class_name Map3DUnits
extends RefCounted
## The maths and the measuring behind MILITARY's 3D pieces (owner
## 2026-09-22) — the pure half of Map3DLayerUnits, as Map3DHouses is of
## Map3DLayerHouses: how big a piece is drawn, which way it faces, and how
## tall the model it was built from actually is.
##
## Nothing here touches a camera pose or the scene tree, so every rule can be
## checked without a 3D view. Never reaches for the Game autoload.


## The world height one piece is drawn at: a constant `map3d_unit_px` of
## SCREEN, clamped in metres at both ends.
##
## A real 1.8 m man is two pixels at the closest zoom the rig allows and a
## rounding error at the farthest, so a piece on this map is a MINIATURE
## standing on a table, never a person at life size — it keeps a constant
## screen height exactly as the flat counter it replaces did. The clamps are
## what stop that rule running away: without the floor it would vanish among
## the houses close in, and without the ceiling the farthest zoom would stand
## a man taller than the mountains he is crossing.
static func height_m(repo: DataRepository, distance_m: float, fov_deg: float,
		view_h_px: float) -> float:
	var mpp := Map3DGeometry.metres_per_pixel(distance_m, fov_deg, view_h_px)
	return clampf(repo.bal("map3d_unit_px") * mpp,
		repo.bal("map3d_unit_min_h_m"), repo.bal("map3d_unit_max_h_m"))


## That height as a scale on the model's own metres.
static func scale_for(repo: DataRepository, distance_m: float, fov_deg: float,
		view_h_px: float, model_h_m: float) -> float:
	if model_h_m <= 0.0:
		return 1.0
	return height_m(repo, distance_m, fov_deg, view_h_px) / model_h_m


## The yaw a piece stands at: the way it MARCHES (a heading in PACK space,
## which is world XZ), or — standing still — square to the camera, because a
## counter on a map is there to be read and a miniature seen edge-on is not.
##
## The models are authored facing +Y in Blender, which the glTF exporter
## turns into -Z here, and -Z turned by a yaw is (-sin, -cos).
static func yaw_for(heading: Vector2, camera_xz: Vector2, at_xz: Vector2) -> float:
	var dir := heading
	if dir == Vector2.ZERO:
		dir = camera_xz - at_xz
	if dir.length() < 0.0001:
		return 0.0
	return atan2(-dir.x, -dir.y)


## World metres a piece WALKS in one real second: the regiment's day's march
## (ArmySystem.day_step_m, in the pack's own metres) turned into the built
## world's metres, over the real seconds a day lasts at this clock speed. The
## engine still moves it a whole day at a time; this is only how the drawing
## gets from one day's spot to the next, so it arrives just as the next day
## does. 0 with the clock stopped.
static func walk_speed(repo: DataRepository, state: GameState, code: String, meta: Dictionary,
		clock_speed: int) -> float:
	if clock_speed <= 0 or state == null:
		return 0.0
	var day_s := maxf(repo.bal("time_day_seconds") / float(clock_speed), 0.001)
	return day_world_m(repo, state, code, meta) / day_s


## A day's march in the built world's metres.
static func day_world_m(repo: DataRepository, state: GameState, code: String,
		meta: Dictionary) -> float:
	if state == null:
		return 0.0
	return float(ArmySystem.day_step_m(repo, state, code)) \
		* float(meta.get("m_per_px", 50.0)) / float(ArmySystem.metres_per_pack_px(repo))


## How far behind the engine a drawn piece may fall before it simply jumps:
## map3d_unit_snap_days days' march. A save loaded, a column that is not
## walking at all, or a clock that ran several days in one frame would
## otherwise leave a piece crawling after its regiment across the map.
static func snap_m(repo: DataRepository, state: GameState, code: String, meta: Dictionary) -> float:
	return day_world_m(repo, state, code, meta) * repo.bal("map3d_unit_snap_days")


## One frame's walk from `now` toward `want`, `step` metres at most; straight
## onto `want` when it is closer than that or farther than `snap`.
static func walk(now: Vector2, want: Vector2, step: float, snap: float) -> Vector2:
	var left := now.distance_to(want)
	if left <= step or left > snap:
		return want
	return now + (want - now) / left * step


## Where a piece's BASE samples the ground (owner 2026-09-24: 斜面上兵人的一
## 部分会被地图盖住): its centre, an inner ring and the base's own outline —
## an ellipse of the base's half extents, so a cavalry base's long axis is
## sampled where it actually reaches — turned by the piece's yaw and scaled to
## the size it is drawn at. Offsets in world XZ from the piece's centre.
static func footprint(half_extents: Vector2, yaw: float, k: float, ring: int) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2.ZERO])
	for share: float in [0.5, 1.0]:
		for i in ring:
			var t := TAU * float(i) / float(ring)
			var local := Vector2(half_extents.x * cos(t), half_extents.y * sin(t)) * share * k
			# Node3D yaw about +Y turns local (x, z) to (x cos + z sin, -x sin + z cos).
			out.append(Vector2(local.x * cos(yaw) + local.y * sin(yaw),
				-local.x * sin(yaw) + local.y * cos(yaw)))
	return out


## How a piece SITS on the ground its footprint sampled — a miniature on a
## sloping table tilts with the table rather than half sinking into it:
## the plane h = a*x + b*z + c fitted through the samples (least squares),
## its slope held to `max_tilt_deg` so a man on a cliff does not lie down,
## then raised until no sample stands above it. Returns {"y": the base's
## centre height, "normal": the plane's up}. `offsets` are XZ from the
## centre, `heights` the ground at each.
static func seat(offsets: PackedVector2Array, heights: PackedFloat32Array,
		max_tilt_deg: float) -> Dictionary:
	var n := offsets.size()
	var sx := 0.0; var sz := 0.0; var sh := 0.0
	var sxx := 0.0; var szz := 0.0; var sxz := 0.0; var sxh := 0.0; var szh := 0.0
	for i in n:
		var o := offsets[i]
		var h := heights[i]
		sx += o.x; sz += o.y; sh += h
		sxx += o.x * o.x; szz += o.y * o.y; sxz += o.x * o.y
		sxh += o.x * h; szh += o.y * h
	var a := 0.0
	var b := 0.0
	if n >= 3:
		# Centred normal equations for the two slopes.
		var fn := float(n)
		var cxx := sxx - sx * sx / fn
		var czz := szz - sz * sz / fn
		var cxz := sxz - sx * sz / fn
		var cxh := sxh - sx * sh / fn
		var czh := szh - sz * sh / fn
		var det := cxx * czz - cxz * cxz
		if absf(det) > 1e-9:
			a = (cxh * czz - czh * cxz) / det
			b = (czh * cxx - cxh * cxz) / det
	var grade := sqrt(a * a + b * b)
	var cap := tan(deg_to_rad(max_tilt_deg))
	if grade > cap:
		a *= cap / grade
		b *= cap / grade
	var y := -INF
	for i in n:
		y = maxf(y, heights[i] - a * offsets[i].x - b * offsets[i].y)
	return {"y": y if n > 0 else 0.0, "normal": Vector3(-a, 1.0, -b).normalized()}


## seat() on the ground `height_at` (world XZ -> metres) gives under a
## piece's footprint at `xz`, sampled per balance map3d_unit_seat_ring.
static func seat_at(repo: DataRepository, height_at: Callable, xz: Vector2,
		base: Vector2, yaw: float, k: float) -> Dictionary:
	var offsets := footprint(base, yaw, k, int(repo.bal("map3d_unit_seat_ring")))
	var heights := PackedFloat32Array()
	for o in offsets:
		heights.append(float(height_at.call(xz + o)))
	return seat(offsets, heights, repo.bal("map3d_unit_tilt_max_deg"))


## The half extents (x, z) of a piece's BASE mesh in its own metres — what
## its footprint is sampled on. The widest extent of the whole model when no
## "_base" mesh is found.
static func base_extent(node: Node3D) -> Vector2:
	for m: MeshInstance3D in meshes(node):
		if m.mesh != null and String(m.mesh.resource_name).ends_with("_base"):
			var box := m.mesh.get_aabb()
			return Vector2(maxf(absf(box.position.x), absf(box.end.x)),
				maxf(absf(box.position.z), absf(box.end.z)))
	var w := model_size(node).x
	return Vector2(w, w)


## A model's own (half width, height) in metres, measured off its meshes
## rather than read from a table — a .glb rebuilt at another size needs
## nothing changed anywhere.
static func model_size(node: Node3D) -> Vector2:
	var top := -INF
	var bottom := INF
	var wide := 0.0
	for m: MeshInstance3D in meshes(node):
		if m.mesh == null:
			continue
		var box := m.mesh.get_aabb()
		var at := node.transform.affine_inverse() * m.transform
		for i in 8:
			var p: Vector3 = at * box.get_endpoint(i)
			top = maxf(top, p.y)
			bottom = minf(bottom, p.y)
			wide = maxf(wide, maxf(absf(p.x), absf(p.z)))
	if top <= -INF:
		return Vector2(0.5, 1.0)
	return Vector2(maxf(wide, 0.0001), maxf(top - bottom, 0.0001))


## The box a piece covers on screen, design px: its standing volume's eight
## corners projected, not the two centre points between its feet and its
## head — at a low camera the piece leans right across the screen and a box
## drawn between those two misses most of it. Rect2() when it is behind the
## camera.
static func screen_box(camera: Camera3D, ground: Vector3, high: float, wide: float,
		px_scale: float) -> Rect2:
	var top := ground + Vector3.UP * high
	if camera.is_position_behind(top):
		return Rect2()
	var box := Rect2(camera.unproject_position(top) / px_scale, Vector2.ZERO)
	for dx in [-wide, wide]:
		for dz in [-wide, wide]:
			for dy in [0.0, high]:
				var corner := ground + Vector3(dx, dy, dz)
				if camera.is_position_behind(corner):
					continue
				box = box.expand(camera.unproject_position(corner) / px_scale)
	return box


## The clip on `anim` whose name ends in `action` ("GARRISON", "MARCH",
## "ATTACK"); "" when it has none. The glTF importer may prefix a library
## name, so the match is on the tail, not the whole name.
static func clip_named(anim: AnimationPlayer, action: String) -> String:
	for n: String in anim.get_animation_list():
		if n.to_upper().ends_with(action):
			return n
	return ""


## The base's colour: the REALM's own hue, deepened.
##
## A grey disc was the first review's worst finding — a hard-edged tray that
## says nothing, in a neutral that exists nowhere else on this map. Painting
## it the realm's colour is what a real wargame base is FOR: it tells you
## whose piece it is at a glance, which is the one thing a counter must do,
## and it puts the disc in the map's own palette instead of outside it. Deep,
## not bright: the figure standing on it has to stay the brighter thing.
static func base_color(repo: DataRepository, kingdom_code: String) -> Color:
	var c := MapPalette.color_of(repo, kingdom_code)
	return Color.from_hsv(c.h, maxf(c.s, repo.bal("map3d_unit_base_sat")),
		repo.bal("map3d_unit_base_val"))


## Paint every surface of the piece's BASE (and nothing else) in `color`.
## The base is its own mesh in the .glb — make_units.py keeps it separate so
## it cannot deform with the animation — and it is named after the unit with
## "_base" on the end.
static func paint_base(node: Node3D, color: Color) -> void:
	for m: MeshInstance3D in meshes(node):
		if not String(m.mesh.resource_name if m.mesh != null else "").ends_with("_base"):
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.85
		mat.metallic = 0.0
		# Surface 0 only: surface 1 is the gold trim, which keeps its own.
		m.set_surface_override_material(0, mat)


static func meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(meshes(c))
	return out


static func find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var a := find_anim(c)
		if a != null:
			return a
	return null
