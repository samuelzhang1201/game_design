class_name BattleStrength
extends RefCounted

const CATEGORIES: Array[String] = ["training", "morale", "discipline", "supply", "formation_terrain", "contact", "action"]

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
## CF06 candidate outgoing power passes the source's union of eligible melee (`melee`, M) and
## direct-fire (`firing`, J) personnel: every arm uses E = M (ranged/machinery E = M + J) in
## m0 = trunc(N * E * H * 1000 / (C * F)), one per-arm rounding chain, H = F - guards. With
## E = F this is the original full-personnel chain; `melee` < 0 keeps that original path.
static func unit(repo: DataRepository, state: GameState, code: String,
		attacking: bool, extra_factors: Array[Dictionary] = [], melee := -1, firing := 0) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code, state)
	var entry := ArmySystem.state_of(repo, state, code)
	if reg.is_empty() or entry.is_empty():
		return {"error": "Unknown battle unit: " + code}
	var capacity := ArmySystem.personnel_capacity(repo, reg)
	var all_fit := ArmySystem.fit_count(repo, state, code)
	var guards := PrisonerBurden.guard_count(repo, state, code)
	var candidate := melee >= 0
	if candidate and (guards < 0 or guards > all_fit): return {"error": "Guards exceed fit personnel: " + code}
	if candidate and (firing < 0 or melee + firing > all_fit):
		return {"error": "Eligible melee and fire exceed fit personnel: " + code}
	var fit := all_fit - guards
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
			var dev := maxi(0, int(development.get(arm, 1000)))
			var power := 0
			if candidate:
				var ranged: bool = String(repo.world_table("military", "unit_types")[arm]["type"]) in ["ranged", "machinery"]
				var eligible := melee + firing if ranged else melee
				if eligible <= 0 or all_fit <= 0: continue
				power = arm_power(count, eligible, fit, all_fit, capacity, ArmySystem._arm_base(repo, code, arm, state.tick), dev)[2]
			else:
				@warning_ignore("integer_division")
				var milli := count * fit * 1000 / capacity
				@warning_ignore("integer_division")
				milli = milli * ArmySystem._arm_base(repo, code, arm, state.tick) / 1000
				@warning_ignore("integer_division")
				power = (milli * dev + 999999) / 1000000
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


## One arm's candidate rounding chain, [m0, m1, p]: m0 = trunc(N*E*H*1000/(C*F)),
## m1 = trunc(m0*base/1000), p = ceil(m1*max(0,dev)/1000000). Exactly one rounding each.
static func arm_power(n: int, e: int, h: int, fit: int, capacity: int, base: int, dev: int) -> Array:
	if fit <= 0 or capacity <= 0: return [0, 0, 0]
	@warning_ignore("integer_division")
	var m0 := n * e * h * 1000 / (capacity * fit)
	@warning_ignore("integer_division")
	var m1 := m0 * base / 1000
	@warning_ignore("integer_division")
	return [m0, m1, (m1 * maxi(0, dev) + 999999) / 1000000]


## CF06 simultaneous incoming exposure of one target over its admitted lawful sources I(t):
## trunc(sum(1000 * M_t + R * J_t) / sum(F)), each row `{fit, ranged_share, melee, firing}`.
## Empty I(t) is 0, never 1000; R is the truncated `BattleRanged.share`, applied once.
static func exposure(sources: Array) -> Dictionary:
	var weighted := 0
	var fit := 0
	for raw: Variant in sources:
		if not raw is Dictionary: return {"error": "Invalid exposure source"}
		var row: Dictionary = raw
		for key: String in ["fit", "ranged_share", "melee", "firing"]:
			if not row.get(key) is int or int(row[key]) < 0: return {"error": "Exposure needs nonnegative integer " + key}
		if int(row.ranged_share) > 1000 or int(row.melee) + int(row.firing) > int(row.fit) or int(row.fit) <= 0:
			return {"error": "Exposure source counts disagree with its fit"}
		weighted += 1000 * int(row.melee) + int(row.ranged_share) * int(row.firing)
		fit += int(row.fit)
	@warning_ignore("integer_division")
	return {"exposure": weighted / fit if fit > 0 else 0}


## The frozen per-unit loss rate: trunc(tier loss * target context / 1000).
static func loss_rate(tier_loss_permille: int, context_permille: int) -> int:
	@warning_ignore("integer_division")
	return tier_loss_permille * context_permille / 1000
