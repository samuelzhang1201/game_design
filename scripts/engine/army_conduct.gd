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
static func switch(repo: DataRepository, state: GameState, code: String, province: String,
		kind: String) -> Array:
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
		var spread := _havoc(repo, state, code, province)
		if spread > 0 and mark_once(repo, state, "havoc:%s:%d" % [province, state.day]):
			out.append({"type": EVENT_HAVOC, "regiment": code, "province": province})
	return out


## Every other crown land unit in `province` that is off goes desperate; returns how many.
static func _havoc(repo: DataRepository, state: GameState, starter: String, province: String) -> int:
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
		n += 1
	return n
