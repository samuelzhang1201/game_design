class_name Map3DUnits
extends RefCounted
## The maths and the measuring behind MILITARY's 3D pieces (owner
## 2026-09-22) — the pure half of Map3DLayerUnits, as Map3DHouses is of
## Map3DLayerHouses: how big a piece is drawn, which way it faces, and how
## tall the model it was built from actually is.
##
## Nothing here touches a camera pose or the scene tree, so every rule can be
## checked without a 3D view. Never reaches for the Game autoload.


## The world height one piece is drawn at: `map3d_unit_ref_px` of SCREEN as
## seen from `ref_m` — the opening view's distance — and from there ONE world
## height at every zoom, so a piece grows and shrinks with the camera exactly
## as the ground and the houses do (owner 2026-09-30: 兵人模型的比例缩放需要和游戏
## 视角缩放一致). It is drawn at every zoom, with no mark over it (owner
## 2026-10-10). px x metres-per-px: the window's height cancels, since ref_m
## grows with it.
static func height_m(repo: DataRepository, fov_deg: float, view_h_px: float, ref_m: float) -> float:
	return repo.bal("map3d_unit_ref_px") * Map3DGeometry.metres_per_pixel(maxf(ref_m, 1.0), fov_deg, view_h_px)


## A piece ({node, anims}) shown or hidden; its AnimationPlayers run only while
## it is shown (perf 2026-10-02; under the LEDGER or the WAR ROOM the view stops).
static func show_piece(piece: Dictionary, on: bool) -> void:
	(piece["node"] as Node3D).visible = on
	if bool(piece.get("running", true)) == on:
		return
	piece["running"] = on
	for anim: AnimationPlayer in piece["anims"]:
		anim.active = on


## Whether the camera is far enough out that a COURIER is its flat mark
## instead of a rider (Map3DLayerCouriers): once a piece, one world size at
## every zoom (height_m), would be drawn under `map3d_unit_mark_px` design px
## at the camera's target. Its px there: ref_px x ref_m / distance.
static func as_counters(repo: DataRepository, meta: Dictionary, camera_distance_m: float,
		view_h_px: float) -> bool:
	var ref_m := Map3DGeometry.distance_for_bar(repo, meta, repo.bal("map3d_zoom_start_scale"), view_h_px)
	return repo.bal("map3d_unit_ref_px") * ref_m < repo.bal("map3d_unit_mark_px") * maxf(camera_distance_m, 1.0)


## That height as a scale on the model's own metres, times `size`
## (data/army_art.csv): one arm may stand bigger than the rest (all 1 since
## the owner's 2026-09-27 "1.5倍不合适").
static func scale_for(repo: DataRepository, fov_deg: float, view_h_px: float, ref_m: float,
		model_h_m: float, size: float = 1.0) -> float:
	if model_h_m <= 0.0:
		return 1.0
	return height_m(repo, fov_deg, view_h_px, ref_m) / model_h_m * size


## The way a piece faces when it has never advanced and has no march: toward
## where the opening camera stands (it looks north, so south, +Z) — a fixed
## world heading, never the camera's live pose, so a pan turns no piece.
const REST := Vector2(0.0, 1.0)
## How far, world metres, the DRAWN piece must go from where its heading was last taken before it
## turns (sub-metre creep or a halt keeps it; owner 2026-10-10: 应当固定向他们之前前进的方向).
const TRACK_MIN_M := 0.5


## The yaw a figure stands at: the way it MARCHES (a heading in PACK space,
## which is world XZ), or — with none — toward `camera_xz` (a courier on the
## 3D map, a WAR ROOM piece toward the table's near edge), turned `stand_deg`
## (data/army_art.csv) further, since a horse square to the view is nose-on,
## the narrowest thing it can show (owner 2026-09-27). The models are authored
## facing +Y in Blender, which the glTF exporter turns into -Z here, and -Z
## turned by a yaw is (-sin, -cos).
static func yaw_for(heading: Vector2, camera_xz: Vector2, at_xz: Vector2,
		stand_deg: float = 0.0) -> float:
	var dir := heading
	var off := 0.0
	if dir == Vector2.ZERO:
		dir = camera_xz - at_xz
		off = deg_to_rad(stand_deg)
	if dir.length() < 0.0001:
		return off
	return atan2(-dir.x, -dir.y) + off


## A regiment PIECE's yaw on the 3D map: `heading` (the way it last advanced, kept by track()),
## else at REST — never the live camera, so a pan or a halt turns no piece (owner 2026-10-10).
static func facing_yaw(heading: Vector2, stand_deg: float = 0.0) -> float:
	return yaw_for(heading, REST, Vector2.ZERO, stand_deg)


## A piece's facing kept as it is drawn from `from` to `at` (world XZ): `kept` {heading, trail} -> the
## new one, turned only once it stands TRACK_MIN_M past `trail` (where it was last taken; `from` the
## first time), so a halt, a stopped clock or a camera move never turns it.
static func track(kept: Dictionary, from: Vector2, at: Vector2) -> Dictionary:
	var trail: Vector2 = kept.get("trail", from)
	var heading: Vector2 = kept.get("heading", Vector2.ZERO)
	if at.distance_to(trail) > TRACK_MIN_M:
		return {"heading": (at - trail).normalized(), "trail": at}
	return {"heading": heading, "trail": trail}


## Where a piece is DRAWN on its day's march (owner 2026-09-28): `day` is
## {from, to, s0} (Map3DUnits.day_march), walked by `share`, the day's share
## now. A stopped clock holds the share, so the piece holds too.
static func along_day(day: Dictionary, share: float) -> Vector2:
	var s0 := float(day["s0"])
	var f := clampf((share - s0) / maxf(1.0 - s0, 0.001), 0.0, 1.0)
	if (day.get("via", PackedVector2Array()) as PackedVector2Array).is_empty():
		return (day["from"] as Vector2).lerp(day["to"], f)
	# along the route's corners it passes today, never across them (a scarp)
	var pts := PackedVector2Array([day["from"]]) + (day["via"] as PackedVector2Array) + PackedVector2Array([day["to"]])
	return MarchRoute.along(pts, f)


## Whether a piece WALKS its day's march at the day's `share`: it has somewhere
## to go and its start (s0) has come — not "it moved this frame".
static func walking(day: Dictionary, share: float) -> bool:
	# a few world metres: the last frame of a day lands just short of its end
	return (day["from"] as Vector2).distance_to(day["to"]) > 0.5 and share >= float(day["s0"])


## A piece's day's march for along_day, reckoned at the day's `share`: from where it is `drawn`
## (or `here`, past the snap) to where the engine's next day leaves it, by its route's corners.
static func day_march(repo: DataRepository, state: GameState, code: String, meta: Dictionary,
		here: Vector2, drawn: Vector2, share: float) -> Dictionary:
	if state == null:
		return {"from": here, "to": here, "s0": 0.0}
	var from := here if drawn.distance_to(here) > snap_m(repo, state, code, meta) else drawn
	var via := PackedVector2Array()
	for p: Vector2i in CourierSystem.day_path_of(repo, state, code):
		via.append(Map3DGeometry.pack_to_world(meta, ArmySystem.metres_to_pack(repo, p)))
	return {"from": from, "s0": share, "to": via[via.size() - 1], "via": via.slice(0, via.size() - 1)}


## A day's march in the built world's metres.
static func day_world_m(repo: DataRepository, state: GameState, code: String,
		meta: Dictionary) -> float:
	if state == null:
		return 0.0
	return float(ArmySystem.day_march_m(repo, state, code)) \
		* float(meta.get("m_per_px", 50.0)) / float(ArmySystem.metres_per_pack_px(repo))


## How far from the engine's spot a drawn piece may stand when its day turns
## before it jumps there: map3d_unit_snap_days days' march.
static func snap_m(repo: DataRepository, state: GameState, code: String, meta: Dictionary) -> float:
	return day_world_m(repo, state, code, meta) * repo.bal("map3d_unit_snap_days")


## Where a piece samples the ground (owner 2026-09-24: 斜面上兵人的一
## 部分会被地图盖住): its centre, an inner ring and its own outline — an
## ellipse of its half extents (stand_extent), so a horse's long axis is
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
## then raised until no sample stands above it. Returns {"y": the piece's
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
		extent: Vector2, yaw: float, k: float) -> Dictionary:
	var offsets := footprint(extent, yaw, k, int(repo.bal("map3d_unit_seat_ring")))
	var heights := PackedFloat32Array()
	for o in offsets:
		heights.append(float(height_at.call(xz + o)))
	return seat(offsets, heights, repo.bal("map3d_unit_tilt_max_deg"))


## The half extents (x, z) a piece stands on, in its own metres — what its
## footprint is sampled on. Measured off the whole model: the pieces have no
## base (owner 2026-09-27: 撤除所有底座), so a horse's is long and narrow.
static func stand_extent(node: Node3D) -> Vector2:
	var half := Vector2.ZERO
	for m: MeshInstance3D in meshes(node):
		if m.mesh == null:
			continue
		var box := m.mesh.get_aabb()
		var at := node.transform.affine_inverse() * m.transform
		for i in 8:
			var p: Vector3 = at * box.get_endpoint(i)
			half = Vector2(maxf(half.x, absf(p.x)), maxf(half.y, absf(p.z)))
	return half if half != Vector2.ZERO else Vector2(0.5, 0.5)


## A model's own (half width, height) in metres, measured off its meshes.
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
## corners projected (a low camera leans it across the screen). Rect2() behind.
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
	# a model with no STANDBY clip stands by in its GARRISON (owner 2026-09-29)
	return clip_named(anim, "GARRISON") if action == "STANDBY" else ""


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
