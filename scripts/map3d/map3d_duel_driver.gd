class_name Map3DDuelDriver
extends RefCounted
## Plays the front-rank duels (Map3DDuel; spec 2026-11-16-infantry-duel-animation-design.md)
## on the drawn battle groups, once a frame from Map3DLayerUnits.step. A paired
## figure leaves its chain (Map3DClipChain) for its pair's turns: one schedule
## drives both figures, so the strike and the reply meet; the duel's own clock
## stops with the game's and runs in real seconds at any speed. Each figure of a
## pair steps toward the other (`duel_offset`, `duel_yaw` on its group child,
## which Map3DBattleGroups walks it to) — the saved point never moves.

var _pairs: Dictionary = {}  ## "code:slot|code:slot" -> {figs, t, n, turn}
var _bodies: Array = []  ## the fallen: [{child, t}] (Map3DFall)
var _losses: Dictionary = {}  ## code -> how many losses it has shown


func is_duelling(anim: AnimationPlayer) -> bool:
	return is_instance_valid(anim) and anim.has_meta("duel")


func pair_time(key: String) -> float:
	return float(_pairs.get(key, {}).get("t", 0.0))


## The slots of `code` now in a duel.
func paired_slots(code: String) -> Array[int]:
	var out: Array[int] = []
	for p: Dictionary in _pairs.values():
		for f: Dictionary in p["figs"]:
			if String(f["code"]) == code:
				out.append(int(f["slot"]))
	return out


func step(ctx: Map3DContext, pieces: Dictionary, delta: float, place: Callable) -> void:
	if ctx == null or ctx.state() == null:
		return
	for code: String in run(gather(ctx, pieces), delta, ctx.clock_speed() > 0, tune_of(ctx.repo)):
		if pieces.has(code):
			place.call(code, pieces[code])


static func tune_of(repo: DataRepository) -> Dictionary:
	var out := {"chain_lo": repo.bal("map3d_unit_chain_rest_min_s"), "chain_hi": repo.bal("map3d_unit_chain_rest_max_s")}
	for key: String in ["steal", "double", "hit", "rest_min_s", "rest_max_s", "open_max_s", "reach_h", "close_h", "step_max_h"]:
		out[key.trim_suffix("_s")] = repo.bal("map3d_duel_" + key)
	out["fall_hold"] = repo.bal("map3d_fall_hold_s")
	out["fall_fade"] = repo.bal("map3d_fall_fade_s")
	return out


## Which figures fall for `code`'s `removed` slots (Map3DFall.plan over its duellists in `kept`).
func plan_falls(code: String, removed: Array, kept: Array) -> Array:
	var n := int(_losses.get(code, 0))
	_losses[code] = n + 1
	return Map3DFall.plan(code, removed, paired_slots(code), kept, n)


## A body (a group child taken out by Map3DBattleGroups.fall_swap) plays one of
## its arm's DEATH clips, holds, fades and is freed; no DEATH clip: freed now.
func fall(child: Dictionary, art: Dictionary, _tune: Dictionary) -> void:
	var anim: AnimationPlayer = (child["anims"] as Array)[0] if not (child["anims"] as Array).is_empty() else null
	var deaths: Array = Map3DClipChain.of_column(art, "duel").get("DEATH", [])
	var clip := ""
	if is_instance_valid(anim) and not deaths.is_empty():
		var pick := mini(int(Map3DMarchLag.unit("%d|death" % anim.get_instance_id()) * deaths.size()), deaths.size() - 1)
		clip = Map3DUnits.clip_named(anim, String(deaths[pick]))
	if clip == "":
		(child["node"] as Node3D).queue_free()
		return
	anim.set_meta("duel", true)  # nothing else plays a body
	anim.set_meta("fallen", true)  # nor does a release give it back its piece's action
	Map3DClipChain.stop(anim)
	anim.speed_scale = 1.0
	anim.play(clip, 0.1)
	anim.seek(0.0, true)
	_bodies.append({"child": child, "t": 0.0})


## Each battle's front figures that can duel, by side ("a" = its attacking side), in battle id order.
static func gather(ctx: Map3DContext, pieces: Dictionary) -> Array:
	var by_id: Dictionary = {}
	for code: String in pieces:
		var piece: Dictionary = pieces[code]
		if piece.get("layout", "") != "physical_groups" or code.begins_with(Sighting.GHOST_CODE):
			continue
		var battle := BattleSystem.battle_of(ctx.state(), code)
		if battle.is_empty() or int(battle.get("rounds", 0)) <= 0:
			continue
		var id := int(battle.get("id", 0))  # a hand-built battle may carry none
		if not by_id.has(id):
			by_id[id] = {"id": id, "rounds": int(battle["rounds"]), "across": Vector2.ZERO, "across_code": "", "a": [], "b": []}
		if code in battle["att"] and (by_id[id]["across_code"] == "" or code < by_id[id]["across_code"]):
			var heading := WarFront.facing_vector(int(piece.get("facing_deg", 0)))  # the attackers' front, whatever the pieces' order
			by_id[id]["across"] = Vector2(-heading.y, heading.x)
			by_id[id]["across_code"] = code
		var art: Dictionary = ctx.repo.army_art.get(String(piece.get("model", "")), {})
		for group: Dictionary in piece["groups"]:
			var child: Dictionary = group["piece"]
			if String(group["role"]) != "front" or (child["anims"] as Array).is_empty() \
					or not can_duel(child, art, child["anims"][0]):
				continue
			by_id[id]["a" if code in battle["att"] else "b"].append({"key": "%s:%d" % [code, int(group["slot"])],
				"code": code, "slot": int(group["slot"]), "anim": child["anims"][0], "child": child, "art": art, "piece": piece,
				"xz": Map3DBattleGroups.saved_xz(ctx, piece, group),
				"h": float(child["height_m"]) * (child["node"] as Node3D).global_basis.get_scale().y})
	var ids := by_id.keys()
	ids.sort()
	return ids.map(func(id: int) -> Dictionary: return by_id[id])


## One frame of every duel; the codes whose pieces must be placed again (a figure stepped in or out).
func run(battles: Array, delta: float, running: bool, tune: Dictionary) -> Array:
	var placed: Dictionary = {}
	var wanted: Dictionary = {}
	for battle: Dictionary in battles:
		if int(battle["rounds"]) <= 0:
			continue
		var figs: Dictionary = {}
		var h := 0.0
		for f: Dictionary in battle["a"] + battle["b"]:
			figs[f["key"]] = f
			h = maxf(h, float(f["h"]))
		var reach := float(tune["reach_h"]) * h
		var taken: Dictionary = {}
		for key: String in _pairs:  # a pair whose two figures still stand within reach keeps its exchange
			var ka := String(_pairs[key]["figs"][0]["key"])
			var kb := String(_pairs[key]["figs"][1]["key"])
			if figs.has(ka) and figs.has(kb) and not taken.has(ka) and not taken.has(kb) \
					and (figs[ka]["xz"] as Vector2).distance_to(figs[kb]["xz"]) <= reach:
				wanted[key] = [figs[ka], figs[kb]]
				taken[ka] = true
				taken[kb] = true
		var free := func(side: Array) -> Array: return side.filter(func(f: Dictionary) -> bool: return not taken.has(f["key"]))
		for p: Dictionary in Map3DDuel.pairs(free.call(battle["a"]), free.call(battle["b"]), battle["across"], reach):
			wanted["%s|%s" % [p["a"], p["b"]]] = [figs[p["a"]], figs[p["b"]]]
	for key: String in _pairs.keys():
		if not wanted.has(key):
			for f: Dictionary in _pairs[key]["figs"]:
				if _release(f, tune):
					placed[f["code"]] = true
			_pairs.erase(key)
	for key: String in wanted:
		var figs: Array = wanted[key]
		if not _pairs.has(key):
			# each pair opens after its own hashed guard, so a front never strikes in unison
			_pairs[key] = {"figs": figs, "t": -Map3DMarchLag.unit(key + "|open") * float(tune["open_max"]), "n": 0}
			for f: Dictionary in figs:
				_claim(f)
			_begin(_pairs[key], key, tune)
		_pairs[key]["figs"] = figs
		if figs.any(func(f: Dictionary) -> bool: return not (f["anim"] as AnimationPlayer).has_meta("duel")):
			for f: Dictionary in figs:  # a figure built again (its piece rebuilt): claimed, the turn restarted on it
				_claim(f)
			_pairs[key]["t"] = 0.0
			_begin(_pairs[key], key, tune)
		if _aim(figs, tune):
			placed[figs[0]["code"]] = true
			placed[figs[1]["code"]] = true
	for key: String in _pairs:
		_advance(_pairs[key], key, delta, running, tune)
	_fade(delta, running, tune)
	return placed.keys()


func _fade(delta: float, running: bool, tune: Dictionary) -> void:
	for body: Dictionary in _bodies.duplicate():
		var child: Dictionary = body["child"]
		if not is_instance_valid(child["node"]):
			_bodies.erase(body)  # freed with its piece
			continue
		(child["anims"][0] as AnimationPlayer).speed_scale = 1.0 if running else 0.0
		if not running:
			continue
		body["t"] = float(body["t"]) + delta
		var a := Map3DFall.alpha(float(body["t"]), float(tune["fall_hold"]), float(tune["fall_fade"]))
		Map3DCourierRide.apply(child, a)
		if a <= 0.0:
			(child["node"] as Node3D).queue_free()
			_bodies.erase(body)


static func _claim(f: Dictionary) -> void:
	var anim: AnimationPlayer = f["anim"]
	anim.set_meta("duel", true)
	Map3DClipChain.stop(anim)
	_start(anim, "GARRISON", 0.0)


## Back to the piece's own action (its chain, if it chains), its saved spot and facing.
static func _release(f: Dictionary, tune: Dictionary) -> bool:
	(f["child"] as Dictionary).erase("duel_offset")
	(f["child"] as Dictionary).erase("duel_yaw")
	(f["child"] as Dictionary)["step_facing"] = true  # it steps back facing its foe
	if not is_instance_valid(f["anim"]) or (f["anim"] as AnimationPlayer).has_meta("fallen"):
		return false  # freed with its piece (e.g. a refresh under the pause menu), or a body falling
	var anim: AnimationPlayer = f["anim"]
	anim.remove_meta("duel")
	anim.speed_scale = 1.0
	var action := String((f["piece"] as Dictionary).get("action", ""))
	if action == "":
		_start(anim, "GARRISON", 0.0)
		return true
	var clips: Array = ((f["piece"] as Dictionary).get("chains", {}) as Dictionary).get(action, [])
	Map3DUnitRig.play([anim], action, 0.2, String(f["key"]),
		{} if clips.is_empty() else {"clips": clips, "lo": tune["chain_lo"], "hi": tune["chain_hi"]})
	return true


## Each figure steps toward the other until `close_h` heights apart, at most `step_max_h`, and faces it.
static func _aim(figs: Array, tune: Dictionary) -> bool:
	var d: Vector2 = (figs[1]["xz"] as Vector2) - (figs[0]["xz"] as Vector2)
	var h := maxf(float(figs[0]["h"]), float(figs[1]["h"]))
	var gap := d.length()
	var step := clampf((gap - float(tune["close_h"]) * h) / 2.0, 0.0, float(tune["step_max_h"]) * h)
	var dir := d / gap if gap > 0.0 else Vector2.ZERO
	var changed := false
	for i in 2:
		var child: Dictionary = figs[i]["child"]
		var sign := 1.0 if i == 0 else -1.0
		var offset := dir * step * sign
		var yaw := Map3DUnits.facing_yaw(d * sign, float(child.get("stand_deg", 0.0)))
		if not child.has("duel_offset") or not (child["duel_offset"] as Vector2).is_equal_approx(offset) \
				or not is_equal_approx(float(child["duel_yaw"]), yaw):
			child["duel_offset"] = offset
			child["duel_yaw"] = yaw
			if not child.get("step_up", false):  # a figure walking up from the tail turns into its way
				child["step_facing"] = true  # it steps in facing its foe, never turned to its way
			changed = true
	return changed


## Turn `n`'s clips and when each starts (Map3DDuel.turn / timing).
static func _begin(p: Dictionary, key: String, tune: Dictionary) -> void:
	var figs: Array = p["figs"]
	var kinds := Map3DClipChain.of_column(figs[0]["art"], "duel")
	var reply_n := maxi((kinds["BLOCK"] as Array).size(), (kinds["HIT"] as Array).size())
	var turn := Map3DDuel.turn(key, int(p["n"]), (kinds["STRIKE"] as Array).size(), reply_n,
		float(tune["steal"]), float(tune["double"]), float(tune["hit"]))
	var s: Dictionary = figs[0] if turn["striker"] == "a" else figs[1]
	var d: Dictionary = figs[1] if turn["striker"] == "a" else figs[0]
	var strikes: Array = Map3DClipChain.of_column(s["art"], "duel")["STRIKE"]
	var replies: Array = Map3DClipChain.of_column(d["art"], "duel")[turn["reply"]]
	var strike := String(strikes[int(turn["strike"]) % strikes.size()])
	var reply := String(replies[int(turn["reply_variant"]) % replies.size()])
	var timing := Map3DDuel.timing(_length(s["anim"], strike), float(Map3DDuel.contact_of(s["art"])[strike]),
		_length(d["anim"], reply), float(Map3DDuel.contact_of(d["art"])[reply]))
	var rest := lerpf(float(tune["rest_min"]), float(tune["rest_max"]), float(turn["rest_u"]))
	p["turn"] = {"s": s["anim"], "d": d["anim"], "strike": strike, "reply": reply, "strike_at": timing["strike_at"],
		"reply_at": timing["reply_at"], "end": timing["end"], "total": maxf(float(timing["end"]) + rest, 0.05),
		"struck": false, "replied": false, "guarded": false}


static func _advance(p: Dictionary, key: String, delta: float, running: bool, tune: Dictionary) -> void:
	var anims: Array = (p["figs"] as Array).map(func(f: Dictionary) -> AnimationPlayer: return f["anim"])
	for anim: AnimationPlayer in anims:
		if is_instance_valid(anim):
			anim.speed_scale = 1.0 if running else 0.0
	if not running or (p["figs"] as Array).any(func(f: Dictionary) -> bool: return bool((f["child"] as Dictionary).get("walking", false))):
		return  # paused, or still stepping in: the turn waits
	p["t"] = float(p["t"]) + delta
	while true:
		var tt: Dictionary = p["turn"]
		var t := float(p["t"])
		if not tt["struck"] and t >= float(tt["strike_at"]):
			tt["struck"] = true
			_start(tt["s"], tt["strike"], t - float(tt["strike_at"]))
		if not tt["replied"] and t >= float(tt["reply_at"]):
			tt["replied"] = true
			_start(tt["d"], tt["reply"], t - float(tt["reply_at"]))
		if not tt["guarded"] and t >= float(tt["end"]):
			tt["guarded"] = true
			for anim: AnimationPlayer in anims:
				_start(anim, "GARRISON", 0.0)
		if t < float(tt["total"]):
			return
		p["t"] = t - float(tt["total"])
		p["n"] = int(p["n"]) + 1
		_begin(p, key, tune)


static func _length(anim: AnimationPlayer, clip: String) -> float:
	return anim.get_animation(Map3DUnits.clip_named(anim, clip)).length


static func _start(anim: AnimationPlayer, clip: String, at: float) -> void:
	var name := Map3DUnits.clip_named(anim, clip) if is_instance_valid(anim) else ""
	if name == "" or clip == "GARRISON" and anim.current_animation == name:
		return  # a guard already held is not restarted
	anim.play(name, 0.15)
	anim.seek(at, true)


## Whether a figure can duel, worked out once per AnimationPlayer and kept on its group child.
static func can_duel(child: Dictionary, art: Dictionary, anim: AnimationPlayer) -> bool:
	if int(child.get("duels_for", 0)) != anim.get_instance_id():
		child["duels_for"] = anim.get_instance_id()
		child["duels"] = Map3DDuel.duels(art, anim)
	return bool(child["duels"])
