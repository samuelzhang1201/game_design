class_name Map3DDuel
extends RefCounted
## Front-rank infantry duels (spec 2026-11-16-infantry-duel-animation-design.md;
## owner: 主要是要临场感，可以做成好看但和数字无关的表演). Pure: which figures pair,
## and each pair's hashed turns (Map3DMarchLag.unit), so a replay looks the same.
## View-only: the engine never sees it.


## `art`'s `contact`: clip -> the share of its length where the blade meets
## (a strike), the shield is fully up (BLOCK) or the jolt lands (HIT).
static func contact_of(art: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for part: String in String(art.get("contact", "")).split(";", false):
		var kv := part.split(":", false)
		if kv.size() == 2 and kv[1].strip_edges().is_valid_float():
			out[kv[0].strip_edges()] = float(kv[1])
	return out


## Whether an arm duels: its `duel` names STRIKE, BLOCK and HIT clips, every one
## installed on `anim` with its `contact` share (DEATH is the fall's, not the duel's).
static func duels(art: Dictionary, anim: AnimationPlayer) -> bool:
	var kinds := Map3DClipChain.of_column(art, "duel")
	var contact := contact_of(art)
	for kind: String in ["STRIKE", "BLOCK", "HIT"]:
		if not kinds.has(kind) or anim == null:
			return false
		for clip: String in kinds[kind]:
			if not contact.has(clip) or Map3DUnits.clip_named(anim, clip) == "":
				return false
	return true


## The front figures of the two sides paired along the front (`across`), never
## crossing: each side sorted along it, the shorter laid against the longer at
## the offset closest along the front (ties: the smallest), a pair farther apart
## than `reach_m` dropped. `a`, `b`: [{key, xz}]; returns [{a, b}] (keys).
static func pairs(a: Array, b: Array, across: Vector2, reach_m: float) -> Array:
	var along := func(rows: Array) -> Array:
		var sorted := rows.duplicate()
		sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return (p["xz"] as Vector2).dot(across) < (q["xz"] as Vector2).dot(across))
		return sorted
	var sa: Array = along.call(a)
	var sb: Array = along.call(b)
	var short_a := sa.size() <= sb.size()
	var s: Array = sa if short_a else sb
	var l: Array = sb if short_a else sa
	var best := 0
	var best_sum := INF
	for o in l.size() - s.size() + 1:
		var sum := 0.0
		for i in s.size():
			sum += absf((s[i]["xz"] as Vector2).dot(across) - (l[i + o]["xz"] as Vector2).dot(across))
		if sum < best_sum:
			best_sum = sum
			best = o
	var out: Array = []
	for i in s.size():
		var pa: Dictionary = s[i] if short_a else l[i + best]
		var pb: Dictionary = l[i + best] if short_a else s[i]
		if (pa["xz"] as Vector2).distance_to(pb["xz"]) <= reach_m:
			out.append({"a": pa["key"], "b": pb["key"]})
	return out


## Turn `n` of pair `pair_key`: who strikes ("a" is the battle's attacking side),
## which of `strikes` strike clips, BLOCK or HIT and which of `variants` of it,
## and the guard pause after (`rest_u`, 0..1 of the balance range). Turn 0 is
## a's; each later turn the other's, unless `double` gives the same striker again;
## a b turn is taken by a by `steal`. `hit` is the share of HIT replies.
static func turn(pair_key: String, n: int, strikes: int, variants: int, steal: float, double: float,
		hit: float) -> Dictionary:
	var u := func(k: int, field: String) -> float: return Map3DMarchLag.unit("%s|duel|%d|%s" % [pair_key, k, field])
	var striker := "a"
	for k in range(1, n + 1):
		if u.call(k, "who") >= double:
			striker = "b" if striker == "a" else "a"
		if striker == "b" and u.call(k, "steal") < steal:
			striker = "a"
	return {"striker": striker, "strike": mini(int(u.call(n, "strike") * strikes), strikes - 1),
		"reply": "HIT" if u.call(n, "reply") < hit else "BLOCK",
		"reply_variant": mini(int(u.call(n, "variant") * variants), variants - 1), "rest_u": u.call(n, "rest")}


## When, from a turn's start, the strike and the reply begin so the blade's
## contact (`strike_share` of `strike_len`) meets the reply's (`reply_share` of
## `reply_len`): the earlier starts at 0; `end` is when the later clip ends.
static func timing(strike_len: float, strike_share: float, reply_len: float, reply_share: float) -> Dictionary:
	var gap := strike_len * strike_share - reply_len * reply_share  # how much later the reply starts
	var strike_at := maxf(-gap, 0.0)
	var reply_at := maxf(gap, 0.0)
	return {"strike_at": strike_at, "reply_at": reply_at, "end": maxf(strike_at + strike_len, reply_at + reply_len)}
