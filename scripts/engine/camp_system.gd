class_name CampSystem
extends RefCounted

const NONE := "none"
const BUILDING := "building"
const CAMPED := "camped"
const PACKING := "packing"

static func _table(state: GameState, code: String) -> Dictionary:
	return state.regiments if state.regiments.has(code) else state.foes

static func _camp(state: GameState, code: String) -> Dictionary:
	var table := _table(state, code)
	if not table.has(code):
		return {}
	var entry: Dictionary = table[code]
	if not entry.has("camp_state"):
		entry["camp_state"] = {"phase": NONE, "idle_days": 0, "build_progress": 0,
			"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1,
			"site": {"x_m": int(entry.get("x_m", 0)), "y_m": int(entry.get("y_m", 0))}}
	return entry["camp_state"]

static func request_departure(state: GameState, code: String, effective_day: int, march_already_done: bool) -> void:
	var camp := _camp(state, code)
	if camp.is_empty() or String(camp.get("phase", NONE)) in [NONE, PACKING]:
		return
	var start := effective_day + (1 if march_already_done else 0)
	camp["phase"] = PACKING
	camp["pack_start_day"] = start
	camp["move_not_before_day"] = start + 1

static func ensure_legacy(repo: DataRepository, state: GameState, code: String) -> void:
	var table := _table(state, code)
	if not table.has(code) or table[code].has("camp_state"):
		return
	if not state.regiments.has(code):
		return
	var entry: Dictionary = table[code]
	var cap := int(repo.bal("camp_after_days"))
	if cap <= 0 or int(entry.get("hold_days", 0)) < cap \
			or String(entry.get("order", "")) == ArmySystem.ORDER_MARCH \
			or not BattleSystem.battle_of(state, code).is_empty() \
			or ArmyGround.garrison_town(repo, state, code) != "":
		return
	entry["camp_state"] = {"phase": CAMPED, "idle_days": int(repo.bal("camp_after_days")),
		"build_progress": 1000, "pack_start_day": -1, "move_not_before_day": -1,
		"last_updated_day": -1, "site": {"x_m": int(entry.get("x_m", 0)), "y_m": int(entry.get("y_m", 0))}}

static func can_march(state: GameState, code: String, day: int) -> bool:
	var table := _table(state, code)
	if not table.has(code):
		return true
	var camp: Dictionary = table[code].get("camp_state", {})
	var phase := String(camp.get("phase", NONE))
	if phase == PACKING:
		return day >= int(camp.get("move_not_before_day", 2147483647))
	return phase not in [BUILDING, CAMPED]

static func departure_started(state: GameState, code: String) -> void:
	var camp := _camp(state, code)
	if camp.is_empty():
		return
	camp["phase"] = NONE
	camp["idle_days"] = 0
	camp["build_progress"] = 0
	camp["pack_start_day"] = -1
	camp["move_not_before_day"] = -1
	var e: Dictionary = _table(state, code)[code]
	camp["site"] = {"x_m": int(e.get("x_m", 0)), "y_m": int(e.get("y_m", 0))}

static func defence_factor(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = _table(state, code).get(code, {})
	var camp: Dictionary = entry.get("camp_state", {})
	if camp.is_empty():
		return 1000
	var site: Dictionary = camp.get("site", {})
	if int(entry.get("x_m", -1)) != int(site.get("x_m", -2)) or int(entry.get("y_m", -1)) != int(site.get("y_m", -2)):
		return 1000
	var phase := String(camp.get("phase", NONE))
	var bonus := 0
	match phase:
		BUILDING:
			@warning_ignore("integer_division")
			bonus = int(repo.bal("army_camp_defence_permille")) * int(camp.get("build_progress", 0)) / 1000
		CAMPED:
			bonus = int(repo.bal("army_camp_defence_permille"))
		PACKING:
			bonus = int(repo.bal("army_camp_pack_defence_permille"))
	return 1000 + bonus

static func reduced_supply_loss(repo: DataRepository, state: GameState, code: String, loss: int) -> int:
	var entry: Dictionary = state.regiments.get(code, {})
	var camp: Dictionary = entry.get("camp_state", {})
	if String(camp.get("phase", NONE)) != CAMPED:
		return loss
	var site: Dictionary = camp.get("site", {})
	if int(entry.get("x_m", -1)) != int(site.get("x_m", -2)) or int(entry.get("y_m", -1)) != int(site.get("y_m", -2)):
		return loss
	return maxi(0, loss - int(repo.bal("army_camp_supply_loss_reduction_permille")))

static func finish_day(repo: DataRepository, state: GameState, day: int) -> void:
	for table: Dictionary in [state.regiments, state.foes]:
		for key: Variant in table:
			var code := String(key)
			var entry: Dictionary = table[code]
			ensure_legacy(repo, state, code)
			var camp := _camp(state, code)
			if int(camp.get("last_updated_day", -1)) == day:
				continue
			camp["last_updated_day"] = day
			var phase := String(camp.get("phase", NONE))
			if phase == PACKING:
				continue
			if phase == NONE:
				camp["site"] = {"x_m": int(entry.get("x_m", 0)), "y_m": int(entry.get("y_m", 0))}
			if int(entry.get("moved_day", -1)) == day:
				if phase == NONE:
					camp["idle_days"] = 0
				continue
			if String(ArmySystem.regiment(repo, code, state).get("is_naval", "0")) == "1":
				continue
			var in_battle := not BattleSystem.battle_of(state, code).is_empty()
			var marching := String(entry.get("order", "")) == ArmySystem.ORDER_MARCH
			if in_battle or marching:
				if phase == NONE:
					camp["idle_days"] = 0
				continue
			if state.regiments.has(code) and ArmyGround.garrison_town(repo, state, code) != "":
				if phase == NONE:
					camp["idle_days"] = 0
				continue
			if state.foes.has(code):
				var at_town := false
				for town: String in repo.burgs:
					if SiegeSystem.at_town(repo, state, code, town):
						at_town = true
						break
				if at_town:
					if phase == NONE:
						camp["idle_days"] = 0
					continue
			if phase == BUILDING:
				var build_days := maxi(1, int(repo.bal("army_camp_build_days")))
				@warning_ignore("integer_division")
				var progress_step := 1000 / build_days
				camp["build_progress"] = mini(1000, int(camp.get("build_progress", 0)) + progress_step)
				if int(camp["build_progress"]) >= 1000:
					camp["phase"] = CAMPED
			elif phase == CAMPED:
				continue
			else:
				camp["idle_days"] = int(camp.get("idle_days", 0)) + 1
				if int(camp["idle_days"]) >= maxi(1, int(repo.bal("army_camp_idle_days"))):
					camp["phase"] = BUILDING
					camp["build_progress"] = 0
