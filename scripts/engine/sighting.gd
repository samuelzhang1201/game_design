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
## standing within player_sight_km (inclusive) of a point of viewers_m, or in
## the scouting sector of a marching unit (`sectors`).
static func seen_foes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	if state == null or state.foes.is_empty():
		return out
	var r := sight_m(repo)
	var viewers := viewers_m(repo, state)
	var fans := sectors(repo, state)
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		if men_of(repo, state, code) <= 0:
			continue
		var e: Dictionary = state.foes[code]
		var at := Vector2i(int(e["x_m"]), int(e["y_m"]))
		var found := false
		for v: Vector2i in viewers:
			var dx := at.x - v.x
			var dy := at.y - v.y
			if dx * dx + dy * dy <= r * r:
				found = true
				break
		if not found:
			for fan: Dictionary in fans:
				if in_sector(at, fan):
					found = true
					break
		if found:
			out.append(code)
	return out


## --- Scouting (spec 2026-10-14-unit-clearance-and-scouting-design §c) ----------

## The sector a crown land unit scouts as it marches: {r_m (whole metres), arc_deg
## (the whole sweep)} from data/army/army_scouting.csv by its chief arm (a royal
## unit reads its own); {} for any unit that scouts none — a standing one, one
## with no man under arms, a fleet, a foe, a unit of another realm.
static func scout_shape(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	if state == null or not state.regiments.has(code):
		return {}
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("kingdom_code", "")) != repo.resolve_realm("player_realm") \
			or String(reg.get("is_naval", "0")) == "1":
		return {}
	if String((state.regiments[code] as Dictionary).get("order", "")) != ArmySystem.ORDER_MARCH \
			or men_of(repo, state, code) <= 0:
		return {}
	var row: Dictionary = repo.army_scouting.get(MapObjects.regiment_arm(repo, reg), {})
	var km := int(row.get("scout_km", 0))
	var arc := int(row.get("arc_deg", 0))
	if km <= 0 or arc <= 0:
		return {}
	return {"r_m": km * 1000, "arc_deg": arc}


## The sectors the crown's marching units sweep now, in code order: {code, at
## (whole metres), heading (a unit vector, ArmySystem.heading_of), r_m, arc_deg}.
## A column with no heading (it stands on its end) sweeps none.
static func sectors(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	if state == null:
		return out
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		var shape := scout_shape(repo, state, code)
		if shape.is_empty():
			continue
		var heading := ArmySystem.heading_of(repo, state, code)
		if heading == Vector2.ZERO:
			continue
		var e: Dictionary = state.regiments[code]
		out.append({"code": code, "at": Vector2i(int(e["x_m"]), int(e["y_m"])), "heading": heading,
			"r_m": int(shape["r_m"]), "arc_deg": int(shape["arc_deg"])})
	return out


## Whether `p` (whole metres) lies in the sector `fan` (one of `sectors`): within
## its radius and within half its arc either side of its heading, both
## inclusive; the apex itself is in it.
static func in_sector(p: Vector2i, fan: Dictionary) -> bool:
	var d: Vector2i = p - (fan["at"] as Vector2i)
	var r := int(fan["r_m"])
	var d2 := d.x * d.x + d.y * d.y
	if d2 > r * r:
		return false
	if d2 == 0:
		return true
	var way := Vector2(d).normalized()
	var half := deg_to_rad(float(fan["arc_deg"]) / 2.0)
	return way.dot(fan["heading"] as Vector2) >= cos(half) - 1.0e-9


## The crown's land units with men under arms: [{code, at}] in code order.
static func _land_units(repo: DataRepository, state: GameState) -> Array:
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
		out.append({"code": code, "at": Vector2i(int(e["x_m"]), int(e["y_m"]))})
	return out


## The foe units in CONTACT — within battle_contact_km of a land unit of the
## crown's with men, marching or standing — each with the first (code order)
## unit of ours that has it so: {foe code -> our unit's code}, foe code order.
static func contacts(repo: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var mine := _land_units(repo, state)
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		if men_of(repo, state, code) <= 0:
			continue
		var e: Dictionary = state.foes[code]
		var at := Vector2i(int(e["x_m"]), int(e["y_m"]))
		for u: Dictionary in mine:
			var d: Vector2i = at - (u["at"] as Vector2i)
			if d.x * d.x + d.y * d.y <= reach * reach:
				out[code] = String(u["code"])
				break
	return out


## The foe units inside a marching unit's sector, not in contact: {foe code -> the
## first (code order) unit whose sector holds it}.
static func scouted(repo: DataRepository, state: GameState, in_contact: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var fans := sectors(repo, state)
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		if in_contact.has(code) or men_of(repo, state, code) <= 0:
			continue
		var e: Dictionary = state.foes[code]
		var at := Vector2i(int(e["x_m"]), int(e["y_m"]))
		for fan: Dictionary in fans:
			if in_sector(at, fan):
				out[code] = String(fan["code"])
				break
	return out


## The day's scouting, once a day after the hosts have moved and before the
## battles (TickEngine._end_day): a foe in CONTACT of a crown land unit gets a
## contact letter (kind `contact`, the truth column) unless one was sent within
## scout_report_gap_days; a foe in a marching unit's SECTOR but not in contact a
## scout letter (kind `scout`, credible) on the same footing. The day of the last
## sight is kept fresh while it lasts, so a foe in view all along is written of
## once, an episode. A foe in contact counts as scouted too (a scout letter is not
## owed after a contact one); a foe gone or with no man under arms is dropped
## from `GameState.scout_log`. At most one
## letter of each kind a day, a fact per newly reported foe, in foe code order.
## No random number.
static func scout_day(repo: DataRepository, state: GameState) -> void:
	if state == null:
		return
	var today := state.absolute_day()
	var gap := int(repo.bal("scout_report_gap_days"))
	for k: Variant in state.scout_log.keys():
		var code := String(k)
		if not state.foes.has(code) or men_of(repo, state, code) <= 0:
			state.scout_log.erase(k)
	var touching := contacts(repo, state)
	var sighted := scouted(repo, state, touching)
	var contact_rows: Array = []
	var scout_rows: Array = []
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		var seen_on: Dictionary = state.scout_log.get(code, {})
		if touching.has(code):
			if not seen_on.has("contact") or today - int(seen_on["contact"]) > gap:
				contact_rows.append({"foe": code, "unit": String(touching[code])})
			seen_on["contact"] = today      # kept fresh while it lasts: one letter an episode
			seen_on["scout"] = today
			state.scout_log[code] = seen_on
		elif sighted.has(code):
			if not seen_on.has("scout") or today - int(seen_on["scout"]) > gap:
				scout_rows.append({"foe": code, "unit": String(sighted[code])})
			seen_on["scout"] = today
			state.scout_log[code] = seen_on
	if not contact_rows.is_empty():
		MissiveLog.add(repo, state, MissiveWriter.contact_report(repo, state, contact_rows))
	if not scout_rows.is_empty():
		MissiveLog.add(repo, state, MissiveWriter.scout_report(repo, state, scout_rows))


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
	@warning_ignore("integer_division")
	var mid := (int(lh[0]) + int(lh[1])) / 2
	@warning_ignore("integer_division")
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
