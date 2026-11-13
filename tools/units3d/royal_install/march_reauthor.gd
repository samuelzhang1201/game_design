extends SceneTree
## Re-key the royal MARCH so a planted hoof holds the ground (LOCO-ROY-MARCH, owner ruling R-J
## 2026-11-13). Numeric only (no render), so --headless is safe:
##   Godot --headless --path . -s res://tools/units3d/royal_install/march_reauthor.gd -- --out KEYS.json
## then  python3 tools/units3d/royal_install/march_transplant.py assets/3D/units/royal/royal.glb KEYS.json
##
## Samples the installed MARCH at KEYS intervals and finds each hoof's stance: the run of samples
## whose lowest patch vertex (Map3DRoyalPivot.patches) is within STANCE_M of the seated plane.
## The clip's own stride S is the planted hooves' mean ground speed over the middle of their
## stances (model metres per loop). In stance a hoof is held at ONE frame: the native rotation
## where its patch is flattest, its sole on the seated plane, carried back at exactly S (so it
## stands still on the ground the piece walks over at S per loop). In swing the native path is kept,
## shifted by a correction that eases (smoothstep) from the liftoff error to the next touchdown's.
## Only the hoof chains' rotations change (Map3DCavalryPivot's chain IK); every other bone, every
## origin and scale, and the loop seam (key KEYS = key 0) are the native clip's.

const Provider = preload("res://scripts/map3d/map3d_royal_pivot.gd")
const Shell = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const _Math = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")

static var KEYS: int = 64  # 120 fps import (royal.glb.import): the native-jets proof needs keys >= 5.12 ms apart; --keys N for a study
const STANCE_M: float = 0.006  # a hoof whose sole is this close to the seated plane (or under it) stands
const HULL_SHARE: float = 0.5  # a vertex is the hoof's when the hoof bone carries over half its weight
const SETTLE: int = 3  # swing keys at each end that blend from the planted hoof (zero ground speed)
const MIDDLE: float = 0.6  # the share of a stance its ground speed is read over
const FORWARD: Vector3 = Vector3(0.0, 0.0, 1.0)  # skeleton space; the model's forward is -Z, skeleton_to_model flips X and Z


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var user: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = user[user.find("--out") + 1] if user.has("--out") else ""
	if user.has("--keys"):
		KEYS = int(user[user.find("--keys") + 1])
	if out_path == "":
		push_error("usage: -- --out KEYS.json")
		quit(2)
		return
	var model: Node3D = load("res://scenes/models/units/royal.tscn").instantiate()
	root.add_child(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var bound: Dictionary = Provider.bind(player, sk)
	var rest: Dictionary = bound.rest
	var patches: Dictionary = bound.patches
	# A hoof's hull: every vertex carrying most of its weight on the hoof bone (wall and rim, not only
	# the sole patch), what the certifier's penetration and planting read. It seats the hoof.
	var hull_profile: Dictionary = Provider.plan().duplicate()
	hull_profile.patch_share = HULL_SHARE
	hull_profile.patch_band_m = 10.0
	var hulls: Dictionary = Provider.patches(sk.find_children("*", "MeshInstance3D", true, false)[0], hull_profile)
	var length: float = player.get_animation("MARCH").length
	var native: Array[Dictionary] = []
	var globals: Array[Dictionary] = []
	for i: int in KEYS:
		native.append(Shell.locals(player, sk, "MARCH", length * float(i) / float(KEYS), rest.bones))
		globals.append(_Math._fk(rest.bones, native[i]))

	# Stances and the clip's own stride.
	var runs: Dictionary = {}
	var speeds: Array[float] = []
	for hoof: String in Provider.HOOVES:
		var down: Array[bool] = []
		for i: int in KEYS:
			down.append(Provider.lowest(globals[i], patches[hoof]) <= STANCE_M)
		var run_of: Array[int] = _one_run(down)
		if run_of.is_empty():
			push_error("%s has no single stance" % hoof)
			quit(1)
			return
		runs[hoof] = run_of
	# A hoof's flattest stance key, and the clip's stride S: the least-squares ground speed of the
	# planted soles (their patch centroids) over every stance key of every hoof, one intercept a hoof.
	var flats: Dictionary = {}
	var along: Dictionary = {}
	var landing: Dictionary = {}
	var entry_key: int = int(round(float(Provider.plan().march_phase) * float(KEYS)))
	var num: float = 0.0
	var den: float = 0.0
	for hoof: String in Provider.HOOVES:
		var run_of: Array[int] = runs[hoof]
		var spread: float = INF
		for k: int in run_of.size():
			var s: float = _spread(globals[run_of[k]], patches[hoof])
			if s < spread:
				spread = s
				flats[hoof] = k
		# The stance ends where the breaking-over toe is deepest: past it the native toe rises (lifts off).
		var deepest: int = run_of.size() - 1
		var low: float = INF
		for k: int in range(int(flats[hoof]), run_of.size()):
			var y: float = Provider.lowest(globals[run_of[k]], patches[hoof])
			if y < low:
				low = y
				deepest = k
		run_of = run_of.slice(0, deepest + 1)
		# A hoof landing exactly at the pivots' admitted MARCH phase (Map3DRoyalPivot's march_phase,
		# their entry and exit pose) keeps its native pose there and stands from the next key: the
		# pivots were certified and reviewed from that pose, and the R-B skin rule measures against it.
		if run_of[0] == entry_key:
			run_of = run_of.slice(1)
			landing[hoof] = entry_key
			flats[hoof] = maxi(0, int(flats[hoof]) - 1)
		runs[hoof] = run_of
		var zs: Array[float] = []
		for k: int in run_of.size():
			zs.append(_centroid(globals[run_of[k]], patches[hoof]).dot(-FORWARD))
		along[hoof] = zs
		var n: float = float(run_of.size())
		var t_mean: float = (n - 1.0) * 0.5 / float(KEYS)
		var z_mean: float = 0.0
		for z: float in zs:
			z_mean += z / n
		for k: int in run_of.size():
			var t: float = float(k) / float(KEYS) - t_mean
			num += t * (zs[k] - z_mean)
			den += t * t
	var stride: float = num / den
	for hoof: String in Provider.HOOVES:
		var zs: Array[float] = along[hoof]
		speeds.append((zs[-1] - zs[0]) / (float(zs.size() - 1) / float(KEYS)))

	# Per-key hoof targets.
	var targets: Array[Dictionary] = []
	for i: int in KEYS:
		targets.append({})
	var report: Dictionary = {"stride_m": stride, "speeds": speeds, "hooves": {}}
	var seats: Dictionary = {}  # hoof -> the height its stance soles are settled to (default the plane)
	for hoof: String in Provider.HOOVES:
		var run_of: Array[int] = runs[hoof]
		var kf: int = flats[hoof]
		var flat: int = run_of[kf]
		var basis: Basis = globals[flat][hoof].basis
		# The flat frame, carried back at S: held(k) = anchor - FORWARD * S * (k - kf) / KEYS, seated,
		# placed along the track so its sole centroid fits the native soles' (least squares).
		var zs: Array[float] = along[hoof]
		var shift: float = 0.0
		for k: int in run_of.size():
			shift += (zs[k] - (zs[kf] + stride * float(k - kf) / float(KEYS))) / float(run_of.size())
		var anchor: Vector3 = globals[flat][hoof].origin - FORWARD * shift
		anchor.y -= _lowest_rigid(globals[flat], Transform3D(basis, anchor), hoof, hulls[hoof])
		# Planted across the pivots' admitted phase (their entry and exit pose, against which the R-B
		# skin rule measures): the track is placed so the hoof IS the native hoof there, and the stance
		# is seated at that native sole's height (under the 0.5 mm planting band).
		var at_entry: int = run_of.find(entry_key)
		if at_entry >= 0:
			var native_at: Transform3D = globals[entry_key][hoof]
			var roll_at: Basis = native_at.basis * basis.inverse()
			var probe: Transform3D = Transform3D(basis, anchor)
			var contact: Vector3 = probe.affine_inverse() * _contact(globals[entry_key], probe, roll_at, hoof, hulls[hoof])
			var held_at: Vector3 = native_at.origin + roll_at * (basis * contact) - basis * contact
			anchor = held_at + FORWARD * stride * float(at_entry - kf) / float(KEYS)
			seats[hoof] = Provider.lowest(globals[entry_key], hulls[hoof])
		var worst: float = 0.0
		# The planted hoof at key i, k keys from its stance's first: the held frame carried back at S,
		# rolled as the native hoof rolls about the hull vertex that roll brings lowest (the heel
		# landing, the toe breaking over), which stays where the held hoof put it.
		var planted: Callable = func(i: int, k: int) -> Transform3D:
			var held: Transform3D = Transform3D(basis, anchor - FORWARD * stride * float(k - kf) / float(KEYS))
			var roll: Basis = globals[i][hoof].basis * basis.inverse()
			var pivot: Vector3 = _contact(globals[i], held, roll, hoof, hulls[hoof])
			return Transform3D(roll, pivot - roll * pivot) * held
		for k: int in run_of.size():
			var i: int = run_of[k]
			targets[i][hoof] = planted.call(i, k)
			worst = maxf(worst, targets[i][hoof].origin.distance_to(globals[i][hoof].origin))
		# Swing: the native path plus a correction easing from liftoff's error to touchdown's. Its first
		# and last SETTLE keys blend from the planted motion carried on, so a hoof leaves and meets the
		# ground at zero ground speed instead of sliding off at the native swing's.
		var lift: int = run_of[-1]
		var touch: int = run_of[0]
		var gap: int = posmod(touch - lift, KEYS)
		var lift_err: Transform3D = targets[lift][hoof] * globals[lift][hoof].affine_inverse()
		var touch_err: Transform3D = targets[touch][hoof] * globals[touch][hoof].affine_inverse()
		var settle: int = mini(SETTLE, (gap - 1) / 2)
		var lift_q: Quaternion = lift_err.basis.get_rotation_quaternion()
		var touch_q: Quaternion = touch_err.basis.get_rotation_quaternion()
		var lift_pos: Vector3 = targets[lift][hoof].origin - globals[lift][hoof].origin
		var touch_pos: Vector3 = targets[touch][hoof].origin - globals[touch][hoof].origin
		# In the air at the pivots' admitted phase: the correction passes through nothing there.
		var through: int = posmod(entry_key - lift, KEYS)
		if through <= 0 or through >= gap or landing.has(hoof):
			through = -1
		for k: int in range(1, gap):
			var i: int = (lift + k) % KEYS
			var q: Quaternion
			var pos: Vector3
			if through < 0:
				var u: float = float(k) / float(gap)
				var s: float = u * u * (3.0 - 2.0 * u)
				q = lift_q.slerp(touch_q, s)
				pos = lift_pos.lerp(touch_pos, s)
			elif k <= through:
				var u: float = float(k) / float(through)
				var s: float = u * u * (3.0 - 2.0 * u)
				q = lift_q.slerp(Quaternion.IDENTITY, s)
				pos = lift_pos.lerp(Vector3.ZERO, s)
			else:
				var u: float = float(k - through) / float(gap - through)
				var s: float = u * u * (3.0 - 2.0 * u)
				q = Quaternion.IDENTITY.slerp(touch_q, s)
				pos = touch_pos * s
			var native_frame: Transform3D = globals[i][hoof]
			var swing: Transform3D = Transform3D(Basis(q) * native_frame.basis, native_frame.origin + pos)
			if k <= settle:
				var w: float = float(k) / float(settle + 1)
				swing = planted.call(i, run_of.size() - 1 + k).interpolate_with(swing, w * w * (3.0 - 2.0 * w))
			elif gap - k <= settle:
				var w: float = float(gap - k) / float(settle + 1)
				swing = planted.call(i, k - gap).interpolate_with(swing, w * w * (3.0 - 2.0 * w))
			targets[i][hoof] = swing
			worst = maxf(worst, swing.origin.distance_to(native_frame.origin))
		if landing.has(hoof):
			targets[landing[hoof]][hoof] = globals[landing[hoof]][hoof]
		report.hooves[hoof] = {"stance": [float(touch) / KEYS, float(lift) / KEYS], "flat_phase": float(run_of[kf]) / KEYS,
			"largest_move_m": worst}

	# Solve every key, then settle the stance soles exactly on the plane (cannon-weighted rim).
	var keyed: Array[Dictionary] = []
	var scaled: Array = []
	var residual: float = 0.0
	for i: int in KEYS:
		var locals: Dictionary = native[i].duplicate()
		for hoof: String in Provider.HOOVES:
			var target: Transform3D = targets[i][hoof]
			var stance: bool = runs[hoof].has(i)
			# A swinging leg already at full reach cannot take the whole correction: scale it back.
			var shares: Array = [1.0] if stance else [1.0, 0.75, 0.5, 0.25, 0.0]
			var solved: bool = false
			for share: float in shares:
				var trial: Dictionary = locals.duplicate()
				var aim: Transform3D = globals[i][hoof].interpolate_with(target, share)
				var why: String = ""
				for pass_index: int in 3:
					why = _solve_hoof(rest, trial, hoof, aim)
					if why != "" or not stance:
						break
					var drop: float = Provider.lowest(_Math._fk(rest.bones, trial), hulls[hoof]) - float(seats.get(hoof, 0.0))
					if absf(drop) < 1e-6:
						break
					aim.origin.y -= drop
				if why == "":
					locals = trial
					solved = true
					if share < 1.0:
						scaled.append({"hoof": hoof, "phase": float(i) / KEYS, "share": share})
					break
			if not solved:
				push_error("IK failed: %s at key %d (stance %s)" % [hoof, i, str(stance)])
				quit(1)
				return
		for hoof: String in Provider.HOOVES:
			if runs[hoof].has(i):
				residual = maxf(residual, absf(Provider.lowest(_Math._fk(rest.bones, locals), hulls[hoof]) - float(seats.get(hoof, 0.0))))
		keyed.append(locals)
	report["stance_sole_residual_m"] = residual
	report["swing_corrections_scaled"] = scaled
	report["seats_m"] = seats
	var entry_same: bool = true
	for name: String in native[entry_key]:
		entry_same = entry_same and keyed[entry_key][name] == native[entry_key][name]
	report["admitted_phase_pose_native"] = entry_same

	var bones: Dictionary = {}
	var chain_bones: Array[String] = []
	for hoof: String in Provider.HOOVES:
		for name: String in rest.chains[hoof].bones:
			chain_bones.append(name)
	for name: String in chain_bones:
		bones[name] = {"rotation": _quats(keyed, name), "native": _quats(native, name)}
	var times: Array = []
	for i: int in KEYS + 1:
		times.append(length * float(i) / float(KEYS))
	report["length_s"] = length
	report["keys"] = KEYS
	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"report": report, "times": times, "bones": bones}, " ", true, true))
	file.close()
	print(JSON.stringify(report))
	model.free()
	quit(0)


## A bone's local rotation at every key and once more at the end (key KEYS = key 0), sign-continuous.
static func _quats(poses: Array[Dictionary], name: String) -> Array:
	var rows: Array = []
	var previous: Quaternion = Quaternion.IDENTITY
	for i: int in KEYS + 1:
		var q: Quaternion = (poses[i % KEYS][name] as Transform3D).basis.get_rotation_quaternion()
		if i > 0 and previous.dot(q) < 0.0:
			q = -q
		previous = q
		rows.append([q.x, q.y, q.z, q.w])
	return rows


## The one circular run of true values, in time order; [] when there is not exactly one.
static func _one_run(down: Array[bool]) -> Array[int]:
	var n: int = down.size()
	var starts: Array[int] = []
	for i: int in n:
		if down[i] and not down[posmod(i - 1, n)]:
			starts.append(i)
	if starts.size() != 1:
		return []
	var out: Array[int] = []
	var i: int = starts[0]
	while down[i] and out.size() < n:
		out.append(i)
		i = (i + 1) % n
	return out


## How far a patch is from lying flat: its highest vertex less its lowest.
static func _spread(globals: Dictionary, patch: Array) -> float:
	var low: float = INF
	var high: float = -INF
	for row: Dictionary in patch:
		var at: Vector3 = Vector3.ZERO
		for k: int in row.bones.size():
			at += (globals[row.bones[k]] * row.binds[k] * row.v) * float(row.weights[k])
		low = minf(low, at.y)
		high = maxf(high, at.y)
	return high - low


## The patch's lowest vertex with the hoof bone (and its weighted share) moved to `frame`, the other
## bones as they are: the first guess of the seated height; the solve then settles the rest.
## The hull vertex (held position) that `roll` about the hull's centre brings lowest.
static func _contact(globals: Dictionary, held: Transform3D, roll: Basis, hoof: String, hull: Array) -> Vector3:
	var moved: Dictionary = globals.duplicate()
	moved[hoof] = held
	var points: Array[Vector3] = _points(moved, hull)
	var best: Vector3 = points[0]
	var low: float = INF
	for p: Vector3 in points:
		var y: float = (roll * p).y
		if y < low:
			low = y
			best = p
	return best


static func _points(globals: Dictionary, patch: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row: Dictionary in patch:
		var at: Vector3 = Vector3.ZERO
		for k: int in row.bones.size():
			at += (globals[row.bones[k]] * row.binds[k] * row.v) * float(row.weights[k])
		out.append(at)
	return out


static func _centroid(globals: Dictionary, patch: Array) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var points: Array[Vector3] = _points(globals, patch)
	for p: Vector3 in points:
		sum += p
	return sum / float(points.size())


static func _lowest_rigid(globals: Dictionary, frame: Transform3D, hoof: String, patch: Array) -> float:
	var moved: Dictionary = globals.duplicate()
	moved[hoof] = frame
	return Provider.lowest(moved, patch)


static func _solve_hoof(rest: Dictionary, locals: Dictionary, hoof: String, target: Transform3D) -> String:
	var chain: Dictionary = rest.chains[hoof]
	var parent: String = _Math._bone(rest.bones, chain.bones[0]).parent
	var globals: Dictionary = _Math._fk(rest.bones, locals)
	var solved: Dictionary = _Math._solve(rest, chain, locals, target, globals[parent], Transform3D.IDENTITY, Transform3D.IDENTITY)
	if not solved.ok:
		return solved.reason
	for name: String in chain.bones:
		locals[name] = solved.locals[name]
	return ""
