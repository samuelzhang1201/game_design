class_name ArmySystem
extends RefCounted
## The player's regiments as more than a headcount (owner 2026-09-17, spec
## docs/superpowers/specs/2026-09-17-regiment-state-design.md): morale,
## wounded, supplies and a hidden training value, stored in
## GameState.regiments, moved once a month by settle_month. Every number is a
## whole number and every rate is data (balance.csv army_*).

## The pack's row for a regiment, {} when there is none.
static func regiment(repo: DataRepository, code: String) -> Dictionary:
	return repo.world_table("military", "regiments").get(code, {})

## Heads under a regiment's banner, as a whole number.
static func headcount(repo: DataRepository, reg: Dictionary) -> int:
	return int(MapObjects.regiment_size(repo, reg))

## What a regiment starts a campaign with.
static func starting_state(repo: DataRepository, reg: Dictionary) -> Dictionary:
	return {
		"morale": int(repo.bal("army_start_morale")),
		"wounded": 0,
		"supplies": supply_use(repo, reg) * int(repo.bal("army_start_supply_months")),
		"training": int(repo.bal("army_start_training")),
	}

## Seeds every regiment of the player's realm that has no state yet — a new
## campaign, and an old save at its next settlement.
static func ensure(repo: DataRepository, state: GameState) -> void:
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var code := String(reg["regiment_code"])
		if not state.regiments.has(code):
			state.regiments[code] = starting_state(repo, reg)

## A regiment's state for reading: the stored one, else what it would start
## with. Never writes. {} for a regiment that is not the player's.
static func state_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var reg := regiment(repo, code)
	if reg.is_empty() or String(reg["kingdom_code"]) != repo.resolve_realm("player_realm"):
		return {}
	if state != null and state.regiments.has(code):
		return state.regiments[code]
	return starting_state(repo, reg)

## Supplies a regiment uses in a month: the headcount's use times its cell's
## height tier (data/army_height_supply.csv, spec 2026-09-19-map3d-heights
## §2) — a fleet is not scaled.
static func supply_use(repo: DataRepository, reg: Dictionary) -> int:
	var base := headcount(repo, reg) * int(repo.bal("army_supply_per_head_permille")) / 1000
	return base * int(height_tier(repo, reg)["supply_permille"]) / 1000

## Wounded who return to the ranks in a month: a share, at least one while
## any are wounded.
static func wound_recovery(repo: DataRepository, wounded: int) -> int:
	if wounded <= 0:
		return 0
	return maxi(1, wounded * int(repo.bal("army_wound_recovery_permille")) / 1000)

## The month's end for every regiment of the player's realm, in code order:
## wounded return, supplies are spent (nothing resupplies yet), training
## grows by its rate up to 100. Morale does not move yet.
static func settle_month(repo: DataRepository, state: GameState) -> void:
	ensure(repo, state)
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := regiment(repo, code)
		if reg.is_empty():
			continue
		var entry: Dictionary = state.regiments[code]
		var heads := headcount(repo, reg)
		var wounded := clampi(int(entry["wounded"]), 0, heads)
		entry["wounded"] = clampi(wounded - wound_recovery(repo, wounded), 0, heads)
		entry["supplies"] = maxi(0, int(entry["supplies"]) - supply_use(repo, reg))
		entry["training"] = mini(100, int(entry["training"]) + int(repo.bal("army_training_per_month")))

## --- Terrain (spec §4) ---------------------------------------------------

## The ground a regiment stands on: sea for a fleet; mountains and hills by
## the cell's height (the supply tiers' lines, Elevation.tier_of); else its
## biome's terrain.
static func terrain_of(repo: DataRepository, reg: Dictionary) -> String:
	if String(reg.get("is_naval", "0")) == "1":
		return "sea"
	var id := MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))
	if id < 0:
		return "plains"
	var cell: Dictionary = repo.cells[id]
	# The supply tiers' lines (Elevation.tier_of): a peak fights as a mountain.
	match String(Elevation.tier_of(repo, float(cell["height"]))["tier"]):
		"peak", "mountains":
			return "mountains"
		"hills":
			return "hills"
	return String(repo.army_terrain_biomes.get(int(cell["biome_id"]), "plains"))

## Whether walls or a citadel stand in the regiment's cell.
static func is_fortified(repo: DataRepository, reg: Dictionary) -> bool:
	if String(reg.get("is_naval", "0")) == "1":
		return false
	var id := MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))
	if id < 0:
		return false
	var cells := MapEconomy.burg_cells(repo)
	for code: String in cells:
		if int(cells[code]) != id:
			continue
		var feats := String((repo.burgs.get(code, {}) as Dictionary).get("features", "")).split("|")
		if "walls" in feats or "citadel" in feats:
			return true
	return false

## An arm's modifier on a terrain, per mille (1000 when the table has no
## row); walls multiply onto it for the defender only.
static func terrain_factor(repo: DataRepository, terrain: String, arm: String, stance: String, fortified: bool) -> int:
	var f := int((repo.army_terrain.get("%s|%s" % [terrain, arm], {}) as Dictionary).get(stance, 1000))
	if fortified and stance == "defend":
		f = f * int((repo.army_terrain.get("fortified|%s" % arm, {}) as Dictionary).get("defend", 1000)) / 1000
	return f

## "Hills", or "Hills (fortified)".
static func terrain_label(repo: DataRepository, reg: Dictionary) -> String:
	var text := terrain_of(repo, reg).capitalize()
	return text + " (fortified)" if is_fortified(repo, reg) else text

## --- Height (spec 2026-09-19-map3d-heights §2) ---------------------------

## The cell under a regiment, -1 for a fleet or off the land.
static func _cell_of(repo: DataRepository, reg: Dictionary) -> int:
	if String(reg.get("is_naval", "0")) == "1":
		return -1
	return MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))

## Whole metres the regiment stands at; 0 for a fleet or off the land.
static func elevation_of(repo: DataRepository, reg: Dictionary) -> int:
	return Elevation.metres_of_cell(repo, _cell_of(repo, reg))

## {tier, supply_permille} of the regiment's cell; plains / 1000 for a fleet.
static func height_tier(repo: DataRepository, reg: Dictionary) -> Dictionary:
	var id := _cell_of(repo, reg)
	if id < 0:
		return {"tier": "plains", "supply_permille": 1000}
	return Elevation.tier_of(repo, float(repo.cells[id]["height"]))

## Per mille on a side's power for standing delta_m above (or, negative,
## below) the other: army_height_bonus_permille_per_100m, capped either way.
static func height_factor(repo: DataRepository, delta_m: int) -> int:
	var cap := int(repo.bal("army_height_bonus_cap_permille"))
	return 1000 + clampi(delta_m * int(repo.bal("army_height_bonus_permille_per_100m")) / 100, -cap, cap)

## --- Hidden strength (spec §5) ------------------------------------------

## A regiment's hidden value against an arm floats round its base, month by
## month: a hash of (regiment, arm, tick), never a draw from the engine's
## RNG stream, so it is deterministic and moves no other seeded roll.
static func float_factor(repo: DataRepository, code: String, vs_arm: String, tick: int) -> int:
	var spread := int(repo.bal("army_float_permille"))
	return 1000 - spread + posmod(("%s|%s|%d" % [code, vs_arm, tick]).hash(), spread * 2 + 1)

## An arm's base, per mille: the mean over its matchups of (attack +
## defense) / 2, each scaled by the month's float.
static func _arm_base(repo: DataRepository, code: String, arm: String, tick: int) -> int:
	var rows: Array = repo.army_matchups.get(arm, [])
	if rows.is_empty():
		return 1000
	var sum := 0
	for m: Dictionary in rows:
		sum += (int(m["attack"]) + int(m["defense"])) / 2 * float_factor(repo, code, String(m["vs"]), tick) / 1000
	return sum / rows.size()

## A regiment's power where it stands, in the given stance ("defend" or
## "attack"): each arm's heads less its share of the wounded, times the arm's
## base, the training and morale factors and the terrain. 0 for a regiment
## without state.
static func power(repo: DataRepository, state: GameState, code: String, stance: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	var fit := heads - clampi(int(st["wounded"]), 0, heads)
	var tick := 0 if state == null else state.tick
	var training_f := int(repo.bal("army_training_base_permille")) + int(st["training"]) * int(repo.bal("army_training_step_permille"))
	var morale_f := int(repo.bal("army_morale_base_permille")) + int(st["morale"]) * int(repo.bal("army_morale_step_permille"))
	var terrain := terrain_of(repo, reg)
	var walls := is_fortified(repo, reg)
	var total := 0
	for arm: String in repo.world_table("military", "unit_types"):
		var n := int(float(reg.get(arm, 0)))
		if n <= 0:
			continue
		# Carry precision through the chain (owner 2026-09-17 review): the
		# naive n * fit / heads truncated to 0 whenever an arm's fit heads
		# were a small share of the regiment (a 1-ship fleet, a 1-gun
		# artillery train), which then zeroed every factor after it. Scale
		# the head-fraction up to milli-heads before applying the per-mille
		# factors, so each /1000 below loses at most a thousandth instead of
		# the whole value, and take the CEILING (not the floor) of the
		# division that removes the extra digit at the end, so any arm that
		# truly contributes something — even a lone ship at low training —
		# never rounds all the way down to 0 (every intermediate stays far
		# inside int64: heads <= ~4564, factors <= ~1500 each).
		var p := n * fit * 1000 / heads
		p = p * _arm_base(repo, code, arm, tick) / 1000
		p = p * training_f / 1000
		p = p * morale_f / 1000
		p = p * terrain_factor(repo, terrain, arm, stance, walls) / 1000
		total += (p + 999) / 1000
	return total

## The training grade a hidden training value shows as.
static func training_grade(repo: DataRepository, training: int) -> String:
	for g: Dictionary in repo.army_training_grades:
		if training > int(g["above"]):
			return String(g["label"])
	return "" if repo.army_training_grades.is_empty() else String(repo.army_training_grades.back()["label"])

## Strong, Average or Weak: the regiment's defending power over the mean of
## the player's regiments of the same kind (land or fleet). A kind of one is
## Average.
static func strength_grade(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := regiment(repo, code)
	if reg.is_empty():
		return ""
	var naval := String(reg.get("is_naval", "0")) == "1"
	var sum := 0
	var n := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if (String(r.get("is_naval", "0")) == "1") != naval:
			continue
		sum += power(repo, state, String(r["regiment_code"]), "defend")
		n += 1
	if n <= 1 or sum <= 0:
		return "Average"
	var ratio := power(repo, state, code, "defend") * 1000 * n / sum
	if ratio >= int(repo.bal("army_strong_ratio_permille")):
		return "Strong"
	if ratio <= int(repo.bal("army_weak_ratio_permille")):
		return "Weak"
	return "Average"

# --- the march (owner 2026-09-19) ----------------------------------------------

## The km a day a regiment's SLOWEST arm marches (data/army_speed.csv): horse
## waits for foot, and everyone waits for the guns. 0 for an empty banner.
static func base_pace_km(repo: DataRepository, reg: Dictionary) -> int:
	var slowest := 0
	for arm: String in repo.army_speed:
		if int(float(reg.get(arm, 0))) <= 0:
			continue
		var km := int(repo.army_speed[arm])
		if slowest == 0 or km < slowest:
			slowest = km
	return slowest


## Supplies as a score, per mille: the months in hand over
## army_speed_supply_full_months, capped at 1000. A banner that uses nothing
## never runs short.
static func supply_score(repo: DataRepository, supplies: int, use_per_month: int) -> int:
	if use_per_month <= 0:
		return 1000
	var full := maxi(1, int(repo.bal("army_speed_supply_full_months")))
	return clampi(maxi(supplies, 0) * 1000 / (use_per_month * full), 0, 1000)


## Readiness per mille: the weighted mean (balance army_speed_w_*) of the arm
## (always 1000), supplies (a supply_score), morale x 10 and training x 10.
static func readiness_permille(repo: DataRepository, supply_permille: int, morale: int,
		training: int) -> int:
	var wa := int(repo.bal("army_speed_w_arm"))
	var ws := int(repo.bal("army_speed_w_supply"))
	var wm := int(repo.bal("army_speed_w_morale"))
	var wt := int(repo.bal("army_speed_w_training"))
	var total := wa + ws + wm + wt
	if total <= 0:
		return 1000
	return (wa * 1000 + ws * clampi(supply_permille, 0, 1000)
		+ wm * clampi(morale, 0, 100) * 10 + wt * clampi(training, 0, 100) * 10) / total


## The march in TENTHS of a km a day: base_km x 10 x readiness / 1000.
static func pace_tenths(repo: DataRepository, base_km: int, supply_permille: int, morale: int,
		training: int) -> int:
	return base_km * 10 * readiness_permille(repo, supply_permille, morale, training) / 1000


## A regiment's march in km a day, from its arms and its state; 0 for a
## regiment that is not the player's (no state) or has no one under arms.
static func speed_km_per_day(repo: DataRepository, state: GameState, code: String) -> float:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0.0
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg)),
		int(st["morale"]), int(st["training"])) / 10.0


## PLACEHOLDER (owner 2026-09-17: the battle formula is not decided). The
## attacker's power in the attack stance over both sides' powers, each on its
## own ground. Called by nothing but its test; replace it whole when the
## owner settles the formula. Height is its first settled factor (spec
## 2026-09-19-map3d-heights §2): the higher side's power is scaled up and the
## lower side's down by the same height_factor.
static func battle_odds(repo: DataRepository, state: GameState, attacker_code: String, defender_code: String) -> float:
	var delta := elevation_of(repo, regiment(repo, attacker_code)) \
		- elevation_of(repo, regiment(repo, defender_code))
	var a := power(repo, state, attacker_code, "attack") * height_factor(repo, delta) / 1000
	var d := power(repo, state, defender_code, "defend") * height_factor(repo, -delta) / 1000
	if a + d <= 0:
		return 0.5
	return float(a) / float(a + d)
