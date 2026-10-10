class_name ArmyConduct
extends RefCounted
## How the crown's columns conduct themselves on the land (spec
## 2026-10-10-foraging-and-desertion §3.3): when a unit starts and stops living
## off it, the unlawful start's incident (once a unit a month), the grey land's
## hazard and grievance, and Havoc. Integers only, no RNG, code order; every
## number a balance key, every legitimacy move carries a reason.

const LAW := "law"
const DESPERATE := "desperate"
const EVENT_UNLAWFUL := "forage_unlawful"
const EVENT_INCIDENT := "forage_incident"
const EVENT_HAVOC := "forage_havoc"
const HAZARD_KIND := "Raided"
const HAZARD_PREFIX := "forage_"


## The start lines {days, morale, training}: the `_obey` set under obey_command.
static func lines(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var sfx := "_obey" if LawSystem.value(repo, state, "obey_command", code) == "on" else ""
	return {
		"days": int(repo.bal("forage_start_days" + sfx)),
		"morale": int(repo.bal("forage_start_morale" + sfx)),
		"training": int(repo.bal("forage_start_training" + sfx)),
	}


static func _days_of(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code, state)
	var entry: Dictionary = state.regiments.get(code, {})
	return ArmySystem.days_in_hand(int(entry.get("supplies", 0)), ArmySystem.supply_use(repo, reg, state))


## The unit's new `forage` value from its current one on land of `kind`.
static func wants(repo: DataRepository, state: GameState, code: String, kind: String) -> String:
	if kind != Forage.ENEMY and kind != Forage.GREY:
		return ""
	var entry: Dictionary = state.regiments.get(code, {})
	var cur := String(entry.get("forage", ""))
	var plunder := LawSystem.value(repo, state, "plunder", code)
	if kind == Forage.ENEMY and plunder == "allow":
		return LAW
	if cur == LAW:
		cur = ""   # the licence is gone (or the land is not an enemy's): judged as off
	var days := _days_of(repo, state, code)
	var morale := int(entry.get("morale", 0))
	if cur == DESPERATE:
		if days >= int(repo.bal("forage_stop_days")) and morale >= int(repo.bal("forage_stop_morale")):
			return ""
		return DESPERATE
	if kind == Forage.GREY:
		return DESPERATE if days <= 0 else ""
	var l := lines(repo, state, code)
	if days < int(l["days"]) or morale < int(l["morale"]) or int(entry.get("training", 0)) < int(l["training"]):
		return DESPERATE
	return ""


## True the first time `key` is seen this month, false after.
static func mark_once(_repo: DataRepository, state: GameState, key: String) -> bool:
	if state.conduct_marks.has(key) and int(state.conduct_marks[key]) == state.tick:
		return false
	state.conduct_marks[key] = state.tick
	return true


## The "Raided" hazard on a province's manors, once while it stands.
static func lay_hazard(repo: DataRepository, state: GameState, province: String) -> void:
	var id := HAZARD_PREFIX + province
	if state.hazards.has(id):
		return
	var months := int(Hazards.kind_of(repo, HAZARD_KIND).get("months", 0))
	Hazards.add(state, id, HAZARD_KIND, "plundered by the crown's host",
		MapManors.manors_of_province(repo, province, state), state.tick,
		state.tick + months if months > 0 else -1, "forage")


static func _label(repo: DataRepository, state: GameState, code: String) -> String:
	return String(ArmySystem.regiment(repo, code, state).get("label", code))


## Apply `wants` to a unit on land of `kind` in `province`. Returns the events
## filed ({type, regiment, province, kingdom}; a havoc one {type, regiment,
## province}).
## `converted`, when given, collects the codes Havoc turned desperate.
static func switch(repo: DataRepository, state: GameState, code: String, province: String,
		kind: String, converted: Array = []) -> Array:
	var out: Array = []
	var entry: Dictionary = state.regiments.get(code, {})
	if entry.is_empty():
		return out
	var before := String(entry.get("forage", ""))
	var after := wants(repo, state, code, kind)
	entry["forage"] = after
	if after != DESPERATE or before == DESPERATE:
		return out
	var kingdom := MapOwnership.owner_of(repo, state, province)
	if mark_once(repo, state, "incident:" + code):
		var plain := String((repo.provinces.get(province, {}) as Dictionary).get("label", province))
		WorldLedger.apply(repo, state, "metrics.legitimacy", -float(repo.bal("forage_incident_legitimacy")),
			"%s plundered %s against the law" % [_label(repo, state, code), plain], "conduct")
		out.append({"type": EVENT_UNLAWFUL if kind == Forage.ENEMY else EVENT_INCIDENT,
			"regiment": code, "province": province, "kingdom": kingdom})
	if kind == Forage.GREY:
		lay_hazard(repo, state, province)
		if mark_once(repo, state, "grievance:" + kingdom):
			var key := "forage_grievance_month_protected" \
				if LawSystem.value(repo, state, "protect_women", code) == "on" else "forage_grievance_month"
			state.grievance[kingdom] = int(state.grievance.get(kingdom, 0)) + int(repo.bal(key))
	if LawSystem.value(repo, state, "no_havoc", code) != "on":
		var spread := _havoc(repo, state, code, province, converted)
		if spread > 0 and mark_once(repo, state, "havoc:%s:%d" % [province, state.day]):
			out.append({"type": EVENT_HAVOC, "regiment": code, "province": province})
	return out


## Every other crown land unit in `province` that is off goes desperate; returns how many.
static func _havoc(repo: DataRepository, state: GameState, starter: String, province: String,
		converted: Array = []) -> int:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var n := 0
	for c: String in codes:
		if c == starter or state.foes.has(c):
			continue
		var follower: Dictionary = state.regiments[c]
		if String(follower.get("forage", "")) != "":
			continue
		var reg := ArmySystem.regiment(repo, c, state)
		if String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.province_of(repo, state, reg) != province:
			continue
		follower["forage"] = DESPERATE
		converted.append(c)
		n += 1
	return n


## One day's foraging in `province` by `codes` (the units living off it today):
## the day's shares go into their supplies (never past what they may hold), the
## land is stripped by what was taken, and a crossing is acted on. Returns the
## events filed: {type: "stripped_bare", province} when the stripping passes
## forage_bare_permille. Standing at or past forage_hazard_strip_permille (the _protected
## line when any taker keeps protect_church) lays (once) the "Raided" hazard.
static func take_day(repo: DataRepository, state: GameState, province: String, codes: Array) -> Array:
	var out: Array = []
	if codes.is_empty():
		return out
	var sorted: Array = codes.duplicate()
	sorted.sort()
	var before := int(state.forage_stripped.get(province, 0))
	var shares := Forage.shares(repo, state, province, sorted, state.day)
	var protected := false
	for c: String in sorted:
		var entry: Dictionary = state.regiments.get(c, {})
		if entry.is_empty():
			continue
		var reg := ArmySystem.regiment(repo, c, state)
		var cap := ArmySystem.max_units(repo, ArmySystem.supply_use(repo, reg, state))
		var have := int(entry.get("supplies", 0))
		var got := maxi(0, mini(int(shares.get(c, 0)), cap - have))
		entry["supplies"] = have + got
		entry["forage_days"] = int(entry.get("forage_days", 0)) + 1
		Forage.strip(repo, state, province, got)   # per taker, floored each (spec §3.3 step 7)
		if LawSystem.value(repo, state, "protect_church", c) == "on":
			protected = true
	var after := int(state.forage_stripped.get(province, 0))
	var line := int(repo.bal("forage_hazard_strip_permille_protected" if protected else "forage_hazard_strip_permille"))
	if after >= line:
		lay_hazard(repo, state, province)
	var bare := int(repo.bal("forage_bare_permille"))
	if before < bare and bare <= after:
		out.append({"type": "stripped_bare", "province": province})
	return out


## The month's end (day 30) for the columns that lived off the land: morale up,
## training down and the wounded by the days they foraged (d/30 of the month's
## figure, whole), whether or not they are still on that land; then the stripped
## lands recover and the old month's once-marks go.
@warning_ignore("integer_division")
static func settle_month(repo: DataRepository, state: GameState) -> void:
	if state.day != Calendar.DAYS_PER_TICK:
		return
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: String in codes:
		var entry: Dictionary = state.regiments[c]
		var d := int(entry.get("forage_days", 0))
		if d <= 0:
			continue
		entry["morale"] = mini(100, int(entry.get("morale", 0)) + int(repo.bal("forage_morale_month")) * d / Calendar.DAYS_PER_TICK)
		entry["training"] = maxi(0, int(entry.get("training", 0)) - int(repo.bal("forage_training_month")) * d / Calendar.DAYS_PER_TICK)
		var fit := ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, c, state)), entry)
		var hurt := mini(fit, fit * int(repo.bal("forage_harass_permille")) * d / (Calendar.DAYS_PER_TICK * 1000))
		entry["wounded"] = int(entry.get("wounded", 0)) + hurt
		entry["forage_days"] = 0
	var provs: Array = state.forage_stripped.keys()
	provs.sort()
	for p: String in provs:
		var left := clampi(int(state.forage_stripped[p]) - int(repo.bal("forage_recover_permille")), 0, 1000)
		if left <= 0:
			state.forage_stripped.erase(p)
		else:
			state.forage_stripped[p] = left
	var marks: Array = state.conduct_marks.keys()
	for k: String in marks:
		if int(state.conduct_marks[k]) != state.tick:
			state.conduct_marks.erase(k)


## One day of the crown's columns on the land (spec 2026-10-10-foraging-and-
## desertion §3.3): pass 1 per land unit in code order (home land: stop living
## off it and desert; other land: switch), pass 2 the day's take per province
## (provinces and codes sorted), pass 3 the month's settlement (day 30 only).
## Fleets, foes and units that eat nothing are skipped. Returns the events in
## the order made; mutates nothing but `state`.
static func day_step(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	var places: Dictionary = {}   # code -> province, for the units on land that is not home
	var converted: Array = []     # the codes Havoc turned desperate today: they keep it today
	for c: String in codes:
		if state.foes.has(c):
			continue
		var entry: Dictionary = state.regiments[c]
		var reg := ArmySystem.regiment(repo, c, state)
		if entry.is_empty() or reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.supply_use(repo, reg, state) <= 0:
			continue
		var province := ArmySystem.province_of(repo, state, reg)
		var kind := Forage.land_kind(repo, state, province)
		if kind == Forage.HOME:
			entry["forage"] = ""
			var was := int(entry.get("deserted", 0))
			var lost := Desertion.daily_loss(repo, state, c)
			if lost > 0 and mark_once(repo, state, "desert_news:" + c):
				out.append({"type": "deserting", "regiment": c, "lost": lost})
			var line := int(repo.bal("desert_news_cumulative_permille")) * ArmySystem.headcount(repo, reg)
			if was * 1000 <= line and line < int(entry.get("deserted", 0)) * 1000:
				out.append({"type": "deserting_big", "regiment": c})
			continue
		places[c] = province
		if c in converted:
			continue
		out.append_array(switch(repo, state, c, province, kind, converted))
	var foragers: Dictionary = {}   # province -> [codes]
	for c: String in codes:
		if places.has(c) and String((state.regiments[c] as Dictionary).get("forage", "")) != "":
			var p := String(places[c])
			if not foragers.has(p):
				foragers[p] = []
			(foragers[p] as Array).append(c)
	var provs: Array = foragers.keys()
	provs.sort()
	for p: String in provs:
		out.append_array(take_day(repo, state, p, foragers[p]))
	settle_month(repo, state)
	return out
