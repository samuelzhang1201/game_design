class_name Sighting
extends RefCounted
## The crown's SIGHT of the enemy and its GHOSTS (spec docs/superpowers/specs/
## 2026-10-10-player-sight-and-ghosts-design.md; the fog: spec
## 2026-10-07-enemy-ai-and-battle §2). A foe unit is SEEN while it stands within
## player_sight_km of a land unit of the crown's with men under arms or of a
## town the crown holds (seen_foes) — the map draws it then, at its true place.
## What the crown last knew of the enemy — a unit seen, a spy's count, the
## border rumour of a host — is a GHOST in GameState.sightings, kept
## ghost_keep_days. A unit's ghost is keyed by its unit code (a sight and a spy
## name units); the rumour names no unit, so its ghost is the HOST's, keyed
## HOST_KEY + the host code, and gives way to the first ghost of one of its
## units. Pure: whole metres, squared distances in whole numbers, no random
## number; never a foe's exact men (an estimate, `about`).

const SEEN := "seen"
const SPY := "spy"
const RUMOUR := "rumour"
const KIND_UNIT := "unit"
const KIND_HOST := "host"
## A host ghost's key: HOST_KEY + the host code.
const HOST_KEY := "host:"
## A map pick of a ghost's piece names GHOST_CODE + its key (Map3DLayerUnits);
## MapObjects.army_card hands such a code to ghost_card.
const GHOST_CODE := "ghost:"
## Which source wins the same day: a sight over a spy over the rumour.
const _RANK := {RUMOUR: 0, SPY: 1, SEEN: 2}


## The sight's reach in whole metres (player_sight_km).
static func sight_m(repo: DataRepository) -> int:
	return int(round(repo.bal("player_sight_km") * 1000.0))


## A unit's men under arms: its pack headcount less its dead, never below 0.
static func men_of(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty():
		return 0
	return maxi(0, ArmySystem.headcount(repo, reg) - int(ArmySystem.state_of(repo, state, code).get("dead", 0)))


## The points the crown sees from, whole metres: each land unit of the
## player's realm with men under arms (code order; a fleet sees nothing), then
## each town the crown holds (TownStores.realm_towns, an occupied one not:
## ArmyGround.holds).
static func viewers_m(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var realm := repo.resolve_realm("player_realm")
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("kingdom_code", "")) != realm or String(reg.get("is_naval", "0")) == "1":
			continue
		if men_of(repo, state, code) <= 0:
			continue
		var e: Dictionary = state.regiments[code]
		out.append(Vector2i(int(e["x_m"]), int(e["y_m"])) if e.has("x_m")
			else ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, reg)))
	for t: String in TownStores.realm_towns(repo, state):
		if ArmyGround.holds(repo, state, realm, t):
			out.append(ArmyGround.town_point_m(repo, t))
	return out


## The foe units the crown SEES now, in code order: each with men under arms
## standing within player_sight_km (inclusive) of a point of viewers_m.
static func seen_foes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	if state == null or state.foes.is_empty():
		return out
	var r := sight_m(repo)
	var viewers := viewers_m(repo, state)
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		if men_of(repo, state, code) <= 0:
			continue
		var e: Dictionary = state.foes[code]
		var x := int(e["x_m"])
		var y := int(e["y_m"])
		for v: Vector2i in viewers:
			var dx := x - v.x
			var dy := y - v.y
			if dx * dx + dy * dy <= r * r:
				out.append(code)
				break
	return out


## "About how many": the middle of SpySystem.estimate's span for `v` at
## quality `q` and `bias`, rounded to intel_facts.csv foe_troops (half up),
## never under one step for a unit with men; 0 for none. Never `v` itself
## unless the rounding happens to land on it.
@warning_ignore("integer_division")  # whole men
static func about(repo: DataRepository, v: int, q: int, bias: int) -> int:
	if v <= 0:
		return 0
	var r := maxi(1, int((repo.intel_facts.get("foe_troops", {}) as Dictionary).get("round_to", 1)))
	var lh := SpySystem.estimate(repo, v, q, bias, r)
	var mid := (int(lh[0]) + int(lh[1])) / 2
	return maxi(r, (mid + r / 2) / r * r)


## Puts `entry` under `key` unless a ghost there is newer, or as new and of a
## better source (seen > spy > rumour). A unit's ghost takes its host's rumour
## ghost away.
static func record(state: GameState, key: String, entry: Dictionary) -> void:
	var old: Dictionary = state.sightings.get(key, {})
	if not old.is_empty():
		var od := int(old["day"])
		var nd := int(entry["day"])
		if nd < od or (nd == od and int(_RANK.get(String(entry["source"]), 0)) < int(_RANK.get(String(old["source"]), 0))):
			return
	state.sightings[key] = entry
	if String(entry["kind"]) == KIND_UNIT:
		var host := String((state.foes.get(String(entry["code"]), {}) as Dictionary).get("host", ""))
		if host != "":
			state.sightings.erase(HOST_KEY + host)


## A unit's ghost where it stands now, today.
static func _unit_entry(state: GameState, code: String, source: String, men: int) -> Dictionary:
	var e: Dictionary = state.foes[code]
	return {"kind": KIND_UNIT, "code": code, "x_m": int(e["x_m"]), "y_m": int(e["y_m"]),
		"day": state.absolute_day(), "source": source, "men": men}


## The day's sight, once a day at its end (TickEngine._end_day, after the
## battles): the border rumour's host ghost on the rumour's day (at the host's
## assembly point, men unknown; none once a unit of it has a ghost), every SEEN
## unit's ghost refreshed to its place today, then `forget`.
static func update(repo: DataRepository, state: GameState) -> void:
	if state == null:
		return
	var host := EnemyAi.rumoured_host(repo, state)
	if host != "" and not _host_has_unit_ghost(state, host):
		var at := EnemyAi.home_m(repo, host)
		record(state, HOST_KEY + host, {"kind": KIND_HOST, "code": host, "x_m": at.x, "y_m": at.y,
			"day": state.absolute_day(), "source": RUMOUR, "men": 0})
	var q := int(repo.bal("player_sight_estimate_quality"))
	for c: String in seen_foes(repo, state):
		record(state, c, _unit_entry(state, c, SEEN, about(repo, men_of(repo, state, c), q, 0)))
	forget(repo, state)


static func _host_has_unit_ghost(state: GameState, host: String) -> bool:
	for k: Variant in state.sightings:
		var g: Dictionary = state.sightings[k]
		if String(g["kind"]) == KIND_UNIT \
				and String((state.foes.get(String(g["code"]), {}) as Dictionary).get("host", "")) == host:
			return true
	return false


## A spy's report has come in from `at` (PACK px) at quality `q` and `bias`
## (SpySystem.observe): a ghost for each foe column he counted
## (SpySystem.foe_codes_near) at its TRUE place now, with HIS estimate of its men.
static func on_spy(repo: DataRepository, state: GameState, at: Vector2, q: int, bias: int) -> void:
	for c: String in SpySystem.foe_codes_near(repo, state, at):
		record(state, c, _unit_entry(state, c, SPY, about(repo, men_of(repo, state, c), q, bias)))


## Whether a ghost is forgotten: older than ghost_keep_days, a unit no longer in
## the field or with no man under arms (its battles destroyed it), a host the
## campaign no longer has.
static func _gone(repo: DataRepository, state: GameState, g: Dictionary) -> bool:
	if state.absolute_day() - int(g["day"]) > int(repo.bal("ghost_keep_days")):
		return true
	var code := String(g["code"])
	if String(g["kind"]) == KIND_HOST:
		return not state.ai_hosts.has(code)
	return not state.foes.has(code) or men_of(repo, state, code) <= 0


## Drops every ghost `_gone` says is gone.
static func forget(repo: DataRepository, state: GameState) -> void:
	var keys: Array = state.sightings.keys()
	keys.sort()
	for k: Variant in keys:
		if _gone(repo, state, state.sightings[k]):
			state.sightings.erase(k)


## The ghosts to draw, in key order: every one not gone, but none of a unit
## SEEN now (its piece stands there) or of a host one of whose units is seen.
## Each {key, kind, code, x_m, y_m, day, age, source, men, label, line} — data only.
static func ghosts(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	if state == null or state.sightings.is_empty():
		return out
	var seen: Dictionary = {}
	var seen_hosts: Dictionary = {}
	for c: String in seen_foes(repo, state):
		seen[c] = true
		seen_hosts[String((state.foes[c] as Dictionary).get("host", ""))] = true
	var keys: Array = state.sightings.keys()
	keys.sort()
	for k: Variant in keys:
		var g: Dictionary = state.sightings[k]
		var code := String(g["code"])
		if _gone(repo, state, g) or (String(g["kind"]) == KIND_UNIT and seen.has(code)) \
				or (String(g["kind"]) == KIND_HOST and seen_hosts.has(code)):
			continue
		out.append({"key": String(k), "kind": String(g["kind"]), "code": code,
			"x_m": int(g["x_m"]), "y_m": int(g["y_m"]), "day": int(g["day"]),
			"age": state.absolute_day() - int(g["day"]), "source": String(g["source"]),
			"men": int(g["men"]), "label": label_of(repo, state, g), "line": line_of(repo, state, g)})
	return out


## The unit a ghost is pictured by: its own, or a host's first column (code
## order); "" for a host with none.
static func model_unit(state: GameState, g: Dictionary) -> String:
	if String(g["kind"]) != KIND_HOST:
		return String(g["code"])
	var cols := EnemyAi.regiments_of(state, String(g["code"]))
	return String(cols[0]) if not cols.is_empty() else ""


## A ghost's name: its unit's roster label, or "<raider realm>'s host".
static func label_of(repo: DataRepository, state: GameState, g: Dictionary) -> String:
	if String(g["kind"]) == KIND_HOST:
		return MissiveWriter.battle_words(repo, "sighting_host", {}, 0)
	return String(ArmySystem.regiment(repo, String(g["code"]), state).get("label", g["code"]))


## The sighting line of a ghost (templates.csv sighting_*): "Seen today",
## "Last seen N days ago", "Spy report, N days ago", "Rumoured at the border,
## N days ago", with "— about N men" where the men are known (an estimate).
static func line_of(repo: DataRepository, state: GameState, g: Dictionary) -> String:
	var age := maxi(0, state.absolute_day() - int(g["day"]))
	var ago := MissiveWriter.battle_words(repo, "sighting_ago_today", {}, 0) if age == 0 \
		else (MissiveWriter.battle_words(repo, "sighting_ago_one", {}, 0) if age == 1
			else MissiveWriter.battle_words(repo, "sighting_ago", {"days": age}, 0))
	var key := "sighting_rumour"
	match String(g["source"]):
		SEEN:
			key = "sighting_seen_today" if age == 0 else "sighting_seen"
		SPY:
			key = "sighting_spy"
	var line := MissiveWriter.battle_words(repo, key, {"ago": ago}, 0)
	if int(g.get("men", 0)) > 0:
		line = MissiveWriter.battle_words(repo, "sighting_with_men", {"line": line, "men": Intel.num(int(g["men"]))}, 0)
	return line


## The sighting line on a foe unit's card: "Seen today" (with the seers'
## estimate) while it is SEEN, else its ghost's line, else "".
static func card_line(repo: DataRepository, state: GameState, code: String) -> String:
	if state == null or not ArmySystem.is_foe(state, code):
		return ""
	if code in seen_foes(repo, state):
		var q := int(repo.bal("player_sight_estimate_quality"))
		return line_of(repo, state, _unit_entry(state, code, SEEN, about(repo, men_of(repo, state, code), q, 0)))
	var g: Dictionary = state.sightings.get(code, {})
	return "" if g.is_empty() or _gone(repo, state, g) else line_of(repo, state, g)


## A ghost's card (a pick of GHOST_CODE + key): only what the crown knows — the
## name, whose men they are, where they were last known, the sighting line
## and the men as an estimate (or the word for none) — at the GHOST's place,
## never the unit's true one. {} for no such ghost.
static func ghost_card(repo: DataRepository, state: GameState, key: String) -> Dictionary:
	var g: Dictionary = state.sightings.get(key, {}) if state != null else {}
	if g.is_empty():
		return {}
	var at := ArmySystem.metres_to_pack(repo, Vector2i(int(g["x_m"]), int(g["y_m"])))
	var reg := ArmySystem.regiment(repo, model_unit(state, g), state)
	var kingdom := String(reg.get("kingdom_code", repo.resolve_realm("raider_realm")))
	var piece := MapObjects.army_piece(repo, reg) if not reg.is_empty() else ""
	var label := label_of(repo, state, g)
	var men := int(g.get("men", 0))
	var men_text := ("about " + Intel.num(men)) if men > 0 else Intel.UNCLEAR
	return {
		"kind": "army", "code": GHOST_CODE + key, "title": label,
		"subtitle": "%s of %s" % ["Host" if String(g["kind"]) == KIND_HOST else "Regiment",
			String((repo.kingdoms.get(kingdom, {}) as Dictionary).get("label", kingdom))],
		"kingdom_code": kingdom, "initial": label.substr(0, 1), "piece": piece,
		"painting": GameArt.path(GameArt.ARMY_PAINTINGS, piece) if piece != "" else "",
		"stats": [{"key": "army_total", "text": men_text, "tooltip": "Headcount — %s (an estimate)" % men_text}],
		"rates": [], "features": [], "production": [], "actions": [],
		"fields": [["Under arms", men_text], ["Last known near", Intel.place_label(repo, state, at)],
			["Sighted", line_of(repo, state, g)]],
		"known": "army", "center": at, "ask": "", "stat_columns": 2,
	}
