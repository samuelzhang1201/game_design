class_name Map3DCandidateGait
extends RefCounted
## How a v2 candidate figure moves its feet (CF04c, candidate only): only what the arm's
## installed locomotion policy certifies. MARCH starts, stops and holds at the policy's
## admitted phase; a leg walks a whole number of MARCH loops whose stride stays within the
## policy's contact_um of the native stride; a pivot's pose comes from the policy's turn ->
## pose provider (Map3DPivotProvider). Every pose is scrubbed from the committed operation
## time with the player stopped, so there is no crossfade and no frame-delta playback.
## GARRISON/STANDBY are not admitted until certified. Anything missing refuses the unit.

const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const KEYS: Array[String] = ["march_stop_phases", "march_start_phases", "hold_clip", "hold_phases", "stride_m", "contact_um", "provider"]

static var _cache: Dictionary = {}  ## [arm, certificate hash] -> policy(); the certificate is read-only data


## The consumer's slice of the arm's installed policy: {phase, stride_m, contact_um, solve}, or {error}.
## The engine's BodyMotion._loco_policy must admit these fields too (LOCO-POLICY widens it).
static func policy(repo: DataRepository, arm: String) -> Dictionary:
	var raw: Variant = repo.unit_footprints.get(arm, {}).get("locomotion_certificate")
	if not raw is Dictionary: return {"error": "%s has no installed locomotion policy" % arm}
	var key := [arm, raw.hash()]
	if not _cache.has(key): _cache[key] = _policy(arm, raw)
	return _cache[key]

static func _policy(arm: String, raw: Dictionary) -> Dictionary:
	for key: String in KEYS:
		if not raw.has(key): return {"error": "%s locomotion policy lacks %s" % [arm, key]}
	# Only a frozen MARCH hold is admitted here, so hold_phases are MARCH phases too.
	if raw.hold_clip != "MARCH": return {"error": "%s hold clip %s is not admitted" % [arm, raw.hold_clip]}
	var phase := admitted_phase([raw.march_start_phases, raw.march_stop_phases, raw.hold_phases])
	if phase < 0.0: return {"error": "%s has no MARCH phase admitted to start, stop and hold" % arm}
	if not (raw.stride_m is float or raw.stride_m is int) or float(raw.stride_m) <= 0.0 \
		or not BodyMotion._loco_integer(raw.contact_um) or int(raw.contact_um) <= 0:
		return {"error": "%s locomotion policy has an invalid stride or contact bound" % arm}
	var path := String(raw.provider)
	var script: Variant = load(path) if path.begins_with("res://") and path.ends_with(".gd") and ResourceLoader.exists(path) else null
	if not script is GDScript or not (script as GDScript).get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "solve"):
		return {"error": "%s has no turn -> pose provider" % arm}
	return {"phase": phase, "stride_m": float(raw.stride_m), "contact_um": int(raw.contact_um), "solve": Callable(script, "solve")}


## The one MARCH phase every list admits ("*" admits any); -1 when there is none or a list is malformed.
static func admitted_phase(lists: Array) -> float:
	if not lists.all(func(l: Variant) -> bool: return l is Array or (l is String and l == "*")): return -1.0
	var fixed: Array = lists.filter(func(l: Variant) -> bool: return l is Array)
	if fixed.is_empty(): return 0.0
	for p: Variant in fixed[0]:
		if not (p is float or p is int) or float(p) < 0.0 or float(p) >= 1.0: continue
		if fixed.all(func(l: Array) -> bool: return l.has(p)): return float(p)
	return -1.0


## Whole MARCH loops for a leg of `length_m` model metres: the k >= 1 whose stride length/k is
## nearest the native stride; -1 when even that k slides more than contact_um. The bound is
## conservative: a foot's stance lasts at most one loop, so its slide is at most |length/k - stride|.
## It bounds only this stride mismatch; the native clip's own slide is the certificate's to bound.
static func strides(length_m: float, stride_m: float, contact_um: int) -> int:
	var best := -1
	var error := INF
	for k: int in [floori(length_m / stride_m), ceili(length_m / stride_m)]:
		if k >= 1 and absf(length_m / k - stride_m) < error:
			best = k
			error = absf(length_m / k - stride_m)
	return best if error * 1000000.0 <= contact_um else -1


## A move op's length in the figure's model metres (sim metres -> built world -> model).
static func model_length(ctx: Map3DContext, piece: Dictionary, child: Dictionary, op: Dictionary) -> float:
	var dx := BodyMotion._difference(int(op.b[0]), int(op.a[0]))
	var dy := BodyMotion._difference(int(op.b[1]), int(op.a[1]))
	var world := sqrt(dx * dx + dy * dy) * float(ctx.meta["m_per_px"]) / float(ArmySystem.metres_per_pack_px(ctx.repo))
	var repo := ctx.repo
	var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference, child["reference_height_m"], child["size"])
	return world / (k * float(child.get("statures", [1.0])[0]))


## Why this v2 row cannot be shown honestly ("" when it can).
static func refusal(ctx: Map3DContext, piece: Dictionary, child: Dictionary, row: Dictionary) -> String:
	var arm := String(piece.get("model", "arm"))
	var rule := policy(ctx.repo, arm)
	if rule.has("error"): return rule.error
	if child["anims"].is_empty(): return "%s has no animation player" % arm
	for anim: AnimationPlayer in child["anims"]:
		if _skeleton(anim) == null: return "%s has no skeleton under its animation player" % arm
	for op: Dictionary in row.move.ops:
		if op.kind == "pivot":
			var clip := "PIVOT_RIGHT" if int(op.turn_udeg) > 0 else "PIVOT_LEFT"
			for anim: AnimationPlayer in child["anims"]:
				if Map3DUnits.clip_named(anim, clip).is_empty(): return "%s has no %s clip: transverse leg refused" % [arm, clip]
		elif op.kind == "move":
			var length := model_length(ctx, piece, child, op)
			if strides(length, rule.stride_m, rule.contact_um) < 0:
				return "%s leg of %.3f model m fits no whole MARCH stride within %d um: refused" % [arm, length, rule.contact_um]
	for anim: AnimationPlayer in child["anims"]:
		if Map3DUnits.clip_named(anim, "MARCH").is_empty(): return "%s has no MARCH clip" % arm
	return ""


## Poses one v2 figure at `time_q`; returns the clip it shows.
static func pose(ctx: Map3DContext, piece: Dictionary, child: Dictionary, row: Dictionary, time_q: int) -> String:
	var rule := policy(ctx.repo, String(piece.get("model", "")))
	var op := Map3DCandidateBodies._locomotion_op(row.move, time_q)
	var phase := clampf(float(time_q - int(op.t0_q)) / float(int(op.t1_q) - int(op.t0_q)), 0.0, 1.0)
	var clip := "MARCH"
	var march: float = rule.phase
	if op.kind == "pivot":
		clip = "PIVOT_RIGHT" if int(op.turn_udeg) > 0 else "PIVOT_LEFT"
	elif op.kind == "move":
		march = fposmod(rule.phase + strides(model_length(ctx, piece, child, op), rule.stride_m, rule.contact_um) * phase, 1.0)
	for anim: AnimationPlayer in child["anims"]:
		var skeleton := _skeleton(anim)
		if skeleton == null: continue
		var name := Map3DUnits.clip_named(anim, clip)
		Map3DClipChain.stop(anim)
		anim.speed_scale = 0.0
		if op.kind == "pivot":
			Provider.apply(rule.solve, anim, skeleton, {"clip": name, "time_s": null, "phase": phase, "turn_udeg": int(op.turn_udeg)})
		else:
			Provider.seek(anim, skeleton, name, march * anim.get_animation(name).length)
	return "v2:" + clip  # never equal to an ordinary action, so leaving v2 always replays


static func _skeleton(anim: AnimationPlayer) -> Skeleton3D:
	var root := anim.get_node_or_null(anim.root_node)
	if root == null: return null
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null
