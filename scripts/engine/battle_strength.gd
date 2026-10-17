class_name BattleStrength
extends RefCounted

const CATEGORIES: Array[String] = ["training", "morale", "discipline", "supply", "formation_terrain", "action"]

## Add deviations within a category before one clamp and one whole-power truncation.
static func combine(base: int, factors: Array[Dictionary]) -> Dictionary:
	if base < 0:
		return {"error": "Battle strength base cannot be negative"}
	var seen: Dictionary = {}
	var groups: Dictionary = {}
	var ordered: Array[Dictionary] = factors.duplicate(true)
	for factor: Dictionary in ordered:
		var source := String(factor.get("source", ""))
		var category := String(factor.get("category", ""))
		if source.strip_edges().is_empty() or seen.has(source):
			return {"error": "Battle strength source is empty or repeated: " + source}
		if not CATEGORIES.has(category) or String(factor.get("reason", "")).strip_edges().is_empty():
			return {"error": "Battle strength needs a known category and a reason: " + source}
		for key: String in ["permille", "min_permille", "max_permille"]:
			if not factor.get(key) is int:
				return {"error": "Battle strength needs integer " + key + ": " + source}
		var lower := int(factor["min_permille"])
		var upper := int(factor["max_permille"])
		if lower < 0 or upper < lower:
			return {"error": "Battle strength bounds are invalid: " + source}
		if not groups.has(category):
			groups[category] = {"permille": 1000, "min_permille": lower, "max_permille": upper}
		var group: Dictionary = groups[category]
		if int(group["min_permille"]) != lower or int(group["max_permille"]) != upper:
			return {"error": "Battle strength category bounds disagree: " + category}
		group["permille"] += int(factor["permille"]) - 1000
		seen[source] = true
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := CATEGORIES.find(String(a["category"]))
		var right := CATEGORIES.find(String(b["category"]))
		return String(a["source"]) < String(b["source"]) if left == right else left < right)
	var power := base
	var steps: Array[Dictionary] = []
	for category: String in CATEGORIES:
		if not groups.has(category):
			continue
		var group: Dictionary = groups[category]
		var permille := clampi(int(group["permille"]), int(group["min_permille"]), int(group["max_permille"]))
		var before := power
		@warning_ignore("integer_division")
		power = power * permille / 1000
		steps.append({"category": category, "permille": permille, "before": before, "power": power})
	return {"base": base, "power": power, "factors": ordered, "steps": steps}

## Battle-only equipment pipeline: old ArmySystem.power already applies several of these factors.
static func unit(repo: DataRepository, state: GameState, code: String,
		attacking: bool, extra_factors: Array[Dictionary] = []) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code, state)
	var entry := ArmySystem.state_of(repo, state, code)
	if reg.is_empty() or entry.is_empty():
		return {"error": "Unknown battle unit: " + code}
	var capacity := ArmySystem.personnel_capacity(repo, reg)
	var fit := ArmySystem.fit_count(repo, state, code)
	var quality := MilitaryQuality.profile(repo, state, code)
	var development := DevelopmentSystem.arm_permille(repo, state, ArmySystem.realm_of(repo, code, state))
	var equipment := 0
	var terrain_weight := 0
	var terrain := ArmySystem.terrain_of(repo, reg, state)
	var works := ArmySystem.works_of(repo, reg, state)
	var stance := "attack" if attacking else "defend"
	if capacity > 0:
		for arm: String in repo.world_table("military", "unit_types"):
			var count := int(float(reg.get(arm, 0)))
			if count <= 0:
				continue
			@warning_ignore("integer_division")
			var milli := count * fit * 1000 / capacity
			@warning_ignore("integer_division")
			milli = milli * ArmySystem._arm_base(repo, code, arm, state.tick) / 1000
			var dev := maxi(0, int(development.get(arm, 1000)))
			@warning_ignore("integer_division")
			var power := (milli * dev + 999999) / 1000000
			equipment += power
			terrain_weight += power * ArmySystem.terrain_factor(repo, terrain, arm, stance, works)
	@warning_ignore("integer_division")
	var base := equipment * int(quality["power_permille"]) / 1000
	@warning_ignore("integer_division")
	var terrain_permille := terrain_weight / equipment if equipment > 0 else 1000
	var support := KingSystem.morale_support(repo, state, code) if not ArmySystem.is_foe(state, code) else 0
	var morale := clampi(int(entry["morale"]) + support, 0, 100)
	var factors: Array[Dictionary] = [
		{"category": "training", "source": "unit:training", "permille": int(repo.bal("army_training_base_permille"))
			+ int(entry["training"]) * int(repo.bal("army_training_step_permille")), "reason": "Training of fit personnel"},
		{"category": "morale", "source": "unit:morale", "permille": int(repo.bal("army_morale_base_permille"))
			+ morale * int(repo.bal("army_morale_step_permille")), "reason": "Current morale including nearby royal support"},
		{"category": "discipline", "source": "unit:discipline", "permille": int(quality["discipline_permille"]),
			"reason": "Discipline of active fit personnel by identity"},
		{"category": "supply", "source": "unit:supply", "permille": ArmySystem.supply_score(repo,
			int(entry["supplies"]), ArmySystem.supply_use(repo, reg, state)), "reason": "Food in hand against living personnel demand"},
		{"category": "formation_terrain", "source": "unit:terrain", "permille": terrain_permille,
			"reason": "Equipment-weighted terrain and defensive works"}]
	factors.append_array(extra_factors.duplicate(true))
	for factor: Dictionary in factors:
		factor["min_permille"] = int(repo.bal("battle_strength_factor_min_permille"))
		factor["max_permille"] = int(repo.bal("battle_strength_factor_max_permille"))
	return combine(base, factors)
