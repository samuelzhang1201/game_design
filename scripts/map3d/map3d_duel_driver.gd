class_name Map3DDuelDriver
extends RefCounted
## Plays the front-rank duels (Map3DDuel; spec 2026-11-16-infantry-duel-animation-design.md)
## on the drawn battle groups, once a frame from Map3DLayerUnits.step. A paired
## figure leaves its chain (Map3DClipChain) for its pair's turns: one schedule
## drives both figures, so the strike and the reply meet; the duel's own clock
## stops with the game's and runs in real seconds at any speed. Each figure of a
## pair steps toward the other (`duel_offset`, `duel_yaw` on its group child,
## which Map3DBattleGroups walks it to) — the saved point never moves. Every
## step (in, back out once released, a tail man's up) walks its MARCH paced to
## the ground it covers (`step_rate`), backwards when it backs away.
## Every blow lands (spec 2026-11-21-infantry-melee-scrum-design.md): at the
## turn's contact instant both figures hold a hit-stop, the struck one is
## knocked back (`knock_offset`, Map3DImpact), a pooled burst shows
## (Map3DImpactBursts) and the contact is told (`take_impacts`).

var _pairs: Dictionary = {}  ## "code:slot|code:slot" -> {figs, t, n, turn}
var _bodies: Array = []  ## the fallen: [{child, t, clip_s, key}] (Map3DFall; key: the duel slot it fell from)
var _losses: Dictionary = {}  ## code -> how many losses it has shown
var _stepping: Array = []  ## released figures walking back to their saved point, handed back on arrival
var _waiting: Dictionary = {}  ## key -> figure: front figures left unpaired, guarding toward a foe
var _impacts: Array = []  ## this frame's contacts, [{kind, at, striker, struck}] (take_impacts)
var bursts: Map3DImpactBursts  ## the meeting-point bursts; made by `step` on first use (none in a bare run)
var scrum := Map3DDuelScrum.new()  ## the mixed fight's areas and points (spec 2026-11-21 melee scrum)
var sound := Map3DUnitSound.new()  ## the blows' clash and thud, sounded from `step`


## The contacts of the last frame run, each {"kind": "HIT"|"BLOCK", "at": Vector3,
## "striker": figure, "struck": figure}; drained (the unit sounds play them).
func take_impacts() -> Array:
	var out := _impacts
	_impacts = []
	return out


func is_duelling(anim: AnimationPlayer) -> bool:
	return is_instance_valid(anim) and anim.has_meta("duel")


func scrum_targets(id: int) -> Dictionary: return scrum.targets(id)  ## battle `id`'s figure key -> point (tests, bench)
func scrum_area(id: int) -> Dictionary: return scrum.area_of(id)


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
	var tune := tune_of(ctx.repo)
	if ctx.camera != null:
		tune["eye"] = ctx.camera.global_position
	if bursts == null and not pieces.is_empty():
		var node: Variant = (pieces.values()[0] as Dictionary).get("node")
		if is_instance_valid(node) and (node as Node3D).get_parent() is Node3D:
			bursts = Map3DImpactBursts.new((node as Node3D).get_parent(), GameArt.table(GameArt.IMPACT_BURSTS),
				int(ctx.repo.bal("map3d_impact_burst_max")))
	for code: String in run(gather(ctx, pieces), delta, ctx.clock_speed() > 0, tune):
		if pieces.has(code):
			place.call(code, pieces[code])
	sound.play_impacts(ctx.repo, ctx.camera, take_impacts())


static func tune_of(repo: DataRepository) -> Dictionary:
	var out := {"chain_lo": repo.bal("map3d_unit_chain_rest_min_s"), "chain_hi": repo.bal("map3d_unit_chain_rest_max_s")}
	for key: String in ["steal", "double", "hit", "rest_min_s", "rest_max_s", "open_max_s", "reach_h", "close_h", "step_max_h"]:
		out[key.trim_suffix("_s")] = repo.bal("map3d_duel_" + key)
	out["fall_hold"] = repo.bal("map3d_fall_hold_s")
	out["fall_fade"] = repo.bal("map3d_fall_fade_s")
	out.merge(Map3DImpact.tune_of(repo))
	out["near_m"] = repo.bal("map3d_impact_near_m")
	out["at_h"] = repo.bal("map3d_impact_at_h")
	for key: String in ["depth_h", "space_h", "push_h", "settle_h", "cross", "spread_h", "pair_h"]: out[key] = repo.bal("map3d_melee_" + key)
	return out


## Which figures fall for `code`'s `removed` slots (Map3DFall.plan over its duellists in `kept`).
func plan_falls(code: String, removed: Array, kept: Array) -> Array:
	var n := int(_losses.get(code, 0))
	_losses[code] = n + 1
	return Map3DFall.plan(code, removed, paired_slots(code), kept, n)


## A body (a group child taken out by Map3DBattleGroups.fall_swap) plays one of
## its arm's DEATH clips, then holds, fades and is freed; no DEATH clip: freed now.
## The tail man walking up into its slot waits until it lies (`_wait_for_bodies`).
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
	var key := ""
	for p: Dictionary in _pairs.values():
		for f: Dictionary in p["figs"]:
			if is_same(f["child"], child):
				key = String(f["key"])
	_bodies.append({"child": child, "t": 0.0, "clip_s": anim.get_animation(clip).length, "key": key})


## Each battle's figures that can duel, by side ("a" = its attacking side), in battle id order:
## under the scrum (`map3d_melee_scrum`) both ranks, else the front.
static func gather(ctx: Map3DContext, pieces: Dictionary) -> Array:
	var by_id: Dictionary = {}
	var scrum := ctx.repo.bal("map3d_melee_scrum") > 0.0
	for code: String in pieces:
		var piece: Dictionary = pieces[code]
		if piece.get("layout", "") != "physical_groups" or code.begins_with(Sighting.GHOST_CODE):
			continue
		var battle := BattleSystem.battle_of(ctx.state(), code)
		if battle.is_empty() or int(battle.get("rounds", 0)) <= 0:
			continue
		var id := int(battle.get("id", 0))  # a hand-built battle may carry none
		if not by_id.has(id):
			by_id[id] = {"id": id, "rounds": int(battle["rounds"]), "across": Vector2.ZERO, "across_code": "", "a": [], "b": [], "scrum": scrum}
		if code in battle["att"] and (by_id[id]["across_code"] == "" or code < by_id[id]["across_code"]):
			var heading := WarFront.facing_vector(int(piece.get("facing_deg", 0)))  # the attackers' front, whatever the pieces' order
			by_id[id]["across"] = Vector2(-heading.y, heading.x)
			by_id[id]["across_code"] = code
		var art: Dictionary = ctx.repo.army_art.get(String(piece.get("model", "")), {})
		for group: Dictionary in piece["groups"]:
			var child: Dictionary = group["piece"]
			if (not scrum and String(group["role"]) != "front") or (child["anims"] as Array).is_empty() \
					or not can_duel(child, art, child["anims"][0]):
				continue
			by_id[id]["a" if code in battle["att"] else "b"].append({"key": "%s:%d" % [code, int(group["slot"])],
				"code": code, "slot": int(group["slot"]), "anim": child["anims"][0], "child": child, "art": art, "piece": piece,
				"rank": String(group["role"]),
				"xz": Map3DBattleGroups.stand_xz(ctx, piece, group),
				"h": float(child["height_m"]) * (child["node"] as Node3D).global_basis.get_scale().y})
	var ids := by_id.keys()
	ids.sort()
	return ids.map(func(id: int) -> Dictionary: return by_id[id])


## One frame of every duel; the codes whose pieces must be placed again (a figure stepped in or out).
func run(battles: Array, delta: float, running: bool, tune: Dictionary) -> Array:
	var placed: Dictionary = {}
	var wanted: Dictionary = {}
	var waiting: Dictionary = {}  ## key -> {f, foes}: this frame's front figures left unpaired
	_impacts.clear()
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
		if battle.get("scrum", false):
			scrum.pair(battle, figs, _pairs, wanted, taken, tune, h)
		for key: String in ([] if battle.get("scrum", false) else _pairs):  # a pair whose two figures still stand within reach keeps its exchange
			var ka := String(_pairs[key]["figs"][0]["key"])
			var kb := String(_pairs[key]["figs"][1]["key"])
			if figs.has(ka) and figs.has(kb) and not taken.has(ka) and not taken.has(kb) \
					and (figs[ka]["xz"] as Vector2).distance_to(figs[kb]["xz"]) <= reach:
				wanted[key] = [figs[ka], figs[kb]]
				taken[ka] = true
				taken[kb] = true
		var free := func(side: Array) -> Array: return side.filter(func(f: Dictionary) -> bool: return not taken.has(f["key"]))
		for p: Dictionary in ([] if battle.get("scrum", false) else Map3DDuel.pairs(free.call(battle["a"]), free.call(battle["b"]), battle["across"], reach)):
			wanted["%s|%s" % [p["a"], p["b"]]] = [figs[p["a"]], figs[p["b"]]]
			taken[p["a"]] = true
			taken[p["b"]] = true
		for side: String in ["a", "b"]:  # no one fights air: the front left over guards toward a foe
			var foes: Array = battle["b" if side == "a" else "a"]
			if foes.is_empty():
				continue
			for f: Dictionary in battle[side]:
				if not taken.has(f["key"]):
					waiting[f["key"]] = {"f": f, "foes": foes}
	for key: String in _pairs.keys():
		if not wanted.has(key):
			for f: Dictionary in _pairs[key]["figs"]:
				if waiting.has(f["key"]) and is_instance_valid(f["anim"]) and (f["anim"] as AnimationPlayer).has_meta("duel"):
					if f.has("scrum"): (f["child"] as Dictionary).erase("knock_offset")  # in the scrum it waits where it stands
					else: Map3DDuelMelee.unstep(f)  # its partner gone: it steps back and waits
					placed[f["code"]] = true
				elif _release(f):
					placed[f["code"]] = true
					_stepping.append(f)
			_pairs.erase(key)
	var kept := func(f: Dictionary) -> bool:  # by its figure, not its key (a fall swap gives it another row)
		return waiting.values().any(func(w: Dictionary) -> bool: return is_same(w["f"]["anim"], f["anim"])) \
			or wanted.values().any(func(pair: Array) -> bool: return pair.any(func(g: Dictionary) -> bool: return is_same(g["anim"], f["anim"])))
	for key: String in _waiting:
		var f: Dictionary = _waiting[key]
		if not kept.call(f) and _release(f):
			placed[f["code"]] = true
			_stepping.append(f)
	_waiting = {}
	for key: String in waiting:
		var f: Dictionary = waiting[key]["f"]
		_waiting[key] = f
		var was_stepping := _stepping.any(func(w: Dictionary) -> bool: return is_same(w["anim"], f["anim"]))
		if was_stepping or not (f["anim"] as AnimationPlayer).has_meta("duel"):
			_stepping = _stepping.filter(func(w: Dictionary) -> bool: return not is_same(w["anim"], f["anim"]))
			_claim(f)
		if scrum.aim(f, waiting[key]["foes"], tune) if f.has("scrum") else Map3DDuelMelee.face(f, waiting[key]["foes"]):
			placed[f["code"]] = true
		if not _pace(f, delta, running):  # it turns (or steps back) paced; standing, it keeps the clock
			(f["anim"] as AnimationPlayer).speed_scale = 1.0 if running else 0.0
	for key: String in wanted:
		var figs: Array = wanted[key]
		if not _pairs.has(key):
			# each pair opens after its own hashed guard, so a front never strikes in unison
			_pairs[key] = {"figs": figs, "t": -Map3DMarchLag.unit(key + "|open") * float(tune["open_max"]), "n": 0}
			for f: Dictionary in figs:
				_claim(f)
			_begin(_pairs[key], key, tune)
		for f: Dictionary in figs:  # a paired figure never walks back on its own
			_stepping = _stepping.filter(func(w: Dictionary) -> bool: return not is_same(w["anim"], f["anim"]))
		var was: Array = _pairs[key]["figs"]
		_pairs[key]["figs"] = figs
		if figs.any(func(f: Dictionary) -> bool: return not (f["anim"] as AnimationPlayer).has_meta("duel")) \
				or not is_same(was[0]["anim"], figs[0]["anim"]) or not is_same(was[1]["anim"], figs[1]["anim"]):
			for f: Dictionary in figs:  # a figure built again, or another in its row (a fall): claimed, the turn restarted on it
				_claim(f)
				(f["child"] as Dictionary).erase("knock_offset")
			_pairs[key]["t"] = 0.0
			_pairs[key].erase("hold")
			_pairs[key].erase("impact")
			_begin(_pairs[key], key, tune)
		_wait_for_bodies(figs, tune)
		if scrum.aim_pair(figs, tune) if figs[0].has("scrum") else _aim(figs, tune):
			placed[figs[0]["code"]] = true
			placed[figs[1]["code"]] = true
	for key: String in _pairs:
		var knocked := _advance(_pairs[key], key, delta, running, tune)
		if knocked != "":
			placed[knocked] = true
	for f: Dictionary in _stepping.duplicate():
		if not is_instance_valid(f["anim"]):
			_stepping.erase(f)  # freed with its piece
		elif not _pace(f, delta, running):
			_stepping.erase(f)
			_hand_back(f, tune)
	_fade(delta, running, tune)
	scrum.keep(battles.map(func(b: Dictionary) -> int: return int(b["id"])))
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
		var a := Map3DFall.alpha(float(body["t"]) - float(body["clip_s"]), float(tune["fall_hold"]), float(tune["fall_fade"]))
		Map3DCourierRide.apply(child, a)
		if a <= 0.0:
			(child["node"] as Node3D).queue_free()
			_bodies.erase(body)


## The tail man walking up into a slot whose body is still falling holds back
## (his walk kept at its start, so the pair's turn waits): he sets off once it
## lies, and no sooner than arrives as it is gone (its hold + fade after the
## clip, less his paced walk's seconds).
func _wait_for_bodies(figs: Array, tune: Dictionary) -> void:
	for f: Dictionary in figs:
		var child: Dictionary = f["child"]
		if not child.get("step_up", false) or not child.has("walk"):
			continue
		var walk_s := float(child["walk"].get("s", 0.0))
		for body: Dictionary in _bodies:
			var clip_s := float(body["clip_s"])
			if String(body["key"]) == String(f["key"]) and float(body["t"]) \
					< maxf(clip_s, clip_s + float(tune["fall_hold"]) + float(tune["fall_fade"]) - walk_s):
				child["walk"]["t0"] = float((f["piece"] as Dictionary).get("clock", 0.0))


static func _claim(f: Dictionary) -> void:
	var anim: AnimationPlayer = f["anim"]
	anim.set_meta("duel", true)
	Map3DClipChain.stop(anim)
	_start(anim, "GARRISON", 0.0)


## Back to its saved spot and facing, walking backwards (`_stepping`, `_pace`);
## false for a figure freed with its piece (e.g. a refresh under the pause menu), or a body falling.
static func _release(f: Dictionary) -> bool:
	var child: Dictionary = f["child"]
	child.erase("knock_offset")  # no figure stays knocked (nor held: `_pace` / `_hand_back` set its speed)
	child.erase("duel_offset")
	child.erase("duel_yaw")
	if child.has("scrum_far"):
		child.erase("step_facing")  # from the scrum it walks back turned into its way
	child["step_up" if child.has("scrum_far") else "step_facing"] = true  # else it steps back facing its foe
	child.erase("scrum_far")
	if not is_instance_valid(f["anim"]) or (f["anim"] as AnimationPlayer).has_meta("fallen"):
		return false
	child["walking"] = true  # its walk back starts when its piece is placed
	return true


## Arrived: back to the piece's own action (its chain, if it chains).
static func _hand_back(f: Dictionary, tune: Dictionary) -> void:
	var anim: AnimationPlayer = f["anim"]
	anim.remove_meta("duel")
	anim.speed_scale = 1.0
	var action := String((f["piece"] as Dictionary).get("action", ""))
	if action == "":
		_start(anim, "GARRISON", 0.0)
		return
	var clips: Array = ((f["piece"] as Dictionary).get("chains", {}) as Dictionary).get(action, [])
	Map3DUnitRig.play([anim], action, 0.2, String(f["key"]),
		{} if clips.is_empty() else {"clips": clips, "lo": tune["chain_lo"], "hi": tune["chain_hi"]})


## A stepping figure's MARCH rate: its drawn step `moved` (world XZ) this frame
## along the way it faces (`yaw`), in its model's metres (scale `k`), over what
## a `clip_s` loop walks (`stride_m`): 1 at its own pace, below 0 backing away.
static func step_rate(moved: Vector2, yaw: float, dt: float, k: float, clip_s: float, stride_m: float) -> float:
	if dt <= 0.0 or k <= 0.0 or stride_m <= 0.0:
		return 0.0
	return moved.dot(Vector2(-sin(yaw), -cos(yaw))) / dt / k * clip_s / stride_m


## One frame of a figure's step: while its group child walks it plays MARCH at
## `step_rate` (its guard while it stands held), paused it stands still (its
## walk held); arrived, back to its guard. False once it no longer walks.
static func _pace(f: Dictionary, delta: float, running: bool) -> bool:
	var child: Dictionary = f["child"]
	var anim: AnimationPlayer = f["anim"]
	var march := Map3DUnits.clip_named(anim, "MARCH")
	if not child.get("walking", false):
		child.erase("paced_at")
		if march != "" and anim.current_animation == march:
			_start(anim, "GARRISON", 0.0)
		return false
	if not running:
		anim.speed_scale = 0.0
		if child.has("walk"):
			child["walk"]["t0"] = float(child["walk"]["t0"]) + delta  # its step waits with the clock
		return true
	var at: Dictionary = child.get("at", {})
	var xz: Vector2 = at.get("xz", Vector2.ZERO)
	var was: Vector2 = child.get("paced_at", xz)
	child["paced_at"] = xz
	var k := float(f["h"]) / float(child["height_m"]) if float(child.get("height_m", 0.0)) > 0.0 else 0.0
	var rate := step_rate(xz - was, float(at.get("yaw", 0.0)), delta, k, float(child.get("clip_s", 0.0)),
		float(child.get("stride_m", 0.0)))
	if march == "" or absf(rate) < 0.05:
		anim.speed_scale = 1.0
		_start(anim, "GARRISON", 0.0)  # held back (or no MARCH): it stands its guard
		return true
	if anim.current_animation != march:
		anim.play(march, 0.15)
	anim.speed_scale = rate
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
			# a figure standing on its point steps in facing its foe, never turned to its way; one
			# still walking (up from the tail, or in from its block) turns into its way, so it never crabs
			if not child.get("step_up", false) and not child.get("walking", false):
				child["step_facing"] = true
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
		"reply_at": timing["reply_at"], "contact_at": timing["contact_at"], "kind": turn["reply"],
		"sf": s, "df": d, "end": timing["end"], "total": maxf(float(timing["end"]) + rest, 0.05),
		"struck": false, "replied": false, "contacted": false, "guarded": false}


## One frame of a pair's turn; the code of a piece whose figure the knock-back
## moved (to be placed again), else "".
func _advance(p: Dictionary, key: String, delta: float, running: bool, tune: Dictionary) -> String:
	var anims: Array = (p["figs"] as Array).map(func(f: Dictionary) -> AnimationPlayer: return f["anim"])
	var hold := float(p.get("hold", 0.0))
	var stepping := false
	for f: Dictionary in p["figs"]:
		if is_instance_valid(f["anim"]) and _pace(f, delta, running):
			stepping = true
		elif is_instance_valid(f["anim"]):
			(f["anim"] as AnimationPlayer).speed_scale = 1.0 if running else 0.0
	if not running:
		return ""  # paused: the turn, the hold and the knock stand
	var knocked := Map3DDuelMelee.knock(p, delta, tune)
	if stepping:
		return knocked  # still stepping in: the turn waits
	var use := minf(hold, delta)  # a hit-stop's remainder first: the turn clock stands through it
	hold -= use
	p["t"] = float(p["t"]) + delta - use
	while true:
		var tt: Dictionary = p["turn"]
		var t := float(p["t"])
		if not tt["contacted"] and t >= float(tt["contact_at"]):
			tt["contacted"] = true  # the blow meets: the hit-stop holds from here, the overshoot spent on it
			var over := t - float(tt["contact_at"])
			Map3DDuelMelee.contact(p, tt, over, tune, _impacts, bursts)
			hold = float(tune.get("hitstop", 0.0))
			use = minf(hold, over)
			hold -= use
			t -= use
			p["t"] = t
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
			break
		p["t"] = t - float(tt["total"])
		p["n"] = int(p["n"]) + 1
		_begin(p, key, tune)
	p["hold"] = hold
	Map3DDuelMelee.speed(anims, 0.0 if hold > 0.0 else 1.0)
	return knocked if knocked != "" else String(p.get("impact", {}).get("code", ""))


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
