class_name ArmySystem
extends RefCounted
const Quality := preload("res://scripts/engine/military_quality.gd")
## The player's regiments as more than a headcount (owner 2026-09-17, spec
## docs/superpowers/specs/2026-09-17-regiment-state-design.md): morale,
## wounded, supplies and a hidden training value, stored in
## GameState.regiments, moved once a month by settle_month — but for the
## supplies, eaten a DAY at a time by eat_day (owner 2026-09-30: 军事单位的补给
## 要每天都在以一定速率减少). Every number is a whole number and every rate is
## data (army/balance.csv army_*).

## The army as it stands (spec 2026-10-07-army-split-and-ground §2.4): the
## campaign's roster, else — no state, or a state with none — the pack's split.
static func roster(repo: DataRepository, state: GameState = null) -> Dictionary:
	if state != null and not state.army_roster.is_empty():
		return state.army_roster
	return ArmySplit.roster_of(repo)

## A unit's row, {} when there is none.
static func regiment(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
	return roster(repo, state).get(code, {})

## Units in the order the lists show them (spec 2026-10-07-army-split-and-
## ground §5.5): the royal household, the royal train, then each regiment's
## units together (by the regiment's code) in arm order, then the rest (the
## fleets) by code.
static func ordered(repo: DataRepository, state: GameState, codes: Array) -> Array:
	var arm_at: Dictionary = {}
	for i in repo.army_split.size():
		arm_at[String(repo.army_split[i]["arm"])] = i
	var key := func(c: String) -> String:
		var r := regiment(repo, c, state)
		var rank := 3
		if String(r.get("is_royal", "0")) == "1":
			rank = 0
		elif String(r.get("parent_code", "")) == "" and String(r.get("is_naval", "0")) == "0":
			rank = 1
		elif String(r.get("parent_code", "")) != "":
			rank = 2
		return "%d|%s|%02d|%s" % [rank, r.get("parent_code", ""),
			int(arm_at.get(MapObjects.regiment_arm(repo, r), 99)), c]
	var out := codes.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool: return key.call(a) < key.call(b))
	return out

## Equipment capacity is a preview, never the current personnel balance.
static func personnel_capacity(repo: DataRepository, reg: Dictionary) -> int:
	return MilitaryRoster.personnel_capacity(repo, reg)

static func headcount(repo: DataRepository, reg: Dictionary) -> int:
	return personnel_capacity(repo, reg)

## Null state explicitly previews full equipment capacity. A real state with
## no personnel record has no available troops; legacy counters cannot refill it.
static func fit_count(repo: DataRepository, state: GameState, code: String) -> int:
	return personnel_capacity(repo, regiment(repo, code)) if state == null else MilitaryRoster.fit(state, code)

static func living_count(repo: DataRepository, state: GameState, code: String) -> int:
	return personnel_capacity(repo, regiment(repo, code)) if state == null else MilitaryRoster.living(state, code)

static func wounded_count(_repo: DataRepository, state: GameState, code: String) -> int:
	return 0 if state == null else MilitaryRoster.living(state, code) - MilitaryRoster.fit(state, code)

## The men still under the banner: `heads` less the dead and the deserted of
## a regiment's state `st`, never below 0.
static func under_arms(heads: int, st: Dictionary) -> int:
	return maxi(0, heads - maxi(0, int(st.get("dead", 0))) - maxi(0, int(st.get("deserted", 0))) - maxi(0, int(st.get("captured_current", 0))))

## Live people by arm; mixed legacy units attribute unspecified losses proportionally.
static func personnel_by_arm(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var arms := repo.world_table("military", "unit_types").keys()
	var counts: Dictionary = {}
	for arm: String in arms:
		counts[arm] = 0
	for regiment: Dictionary in MapObjects.regiments_of(repo, realm, state):
		var code := String(regiment["regiment_code"])
		var people := living_count(repo, state, code)
		var weights: Array = []
		for arm: String in arms:
			weights.append(int(float(regiment.get(arm, 0))) * int(repo.world_row("military", "unit_types", arm).get("crew", 0)))
		var shares := BattleSystem.apportion(weights, people)
		for i in arms.size():
			counts[arms[i]] += int(shares[i])
	return counts


## The men able to fight: `heads` less the wounded, the dead and the deserted
## of a regiment's state `st` (a state with no `dead` or `deserted`, an old
## save's, has none), never below 0.
## The pack's headcount is immutable, so the dead are a count beside it.
static func fit_heads(heads: int, st: Dictionary) -> int:
	return maxi(0, heads - maxi(0, int(st.get("wounded", 0))) - maxi(0, int(st.get("dead", 0))) - maxi(0, int(st.get("deserted", 0))) - maxi(0, int(st.get("captured_current", 0))))

## A regiment's STRENGTH: its fit men (headcount less the wounded, the dead and the deserted)
## per mille of its headcount — what its piece shows (owner 2026-09-30: 满员 / 减员 /
## 残兵, Map3DFormation). A regiment that is not the player's has no state and
## reads as it would start (full); one with no one under arms is 0.
static func fit_permille(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := regiment(repo, code, state)
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per-mille
	return fit_count(repo, state, code) * 1000 / heads

## What a regiment starts a campaign with: army_start_supply_days of its use,
## in whole supplies rounded UP, so the days in hand read the days it was given
## (rounded down, a fresh regiment showed 19 of its 20).
@warning_ignore("integer_division")  # whole supplies
static func starting_state(repo: DataRepository, reg: Dictionary, state: GameState = null) -> Dictionary:
	var home := pack_to_metres(repo, Vector2(float(reg.get("x", 0)), float(reg.get("y", 0))))
	var start_days := int(repo.bal("army_start_supply_days"))
	@warning_ignore("integer_division")
	return {
		"morale": int(repo.bal("army_start_morale")),
		"wounded": 0,
		"dead": 0,
		"supplies": (supply_use(repo, reg, state) * start_days + Calendar.DAYS_PER_TICK - 1) / Calendar.DAYS_PER_TICK,
		"carry_days": int(repo.bal("army_carry_default_days")),
		"training": int(repo.bal("army_start_training")),
		"x_m": home.x,
		"y_m": home.y,
		"dest_x_m": home.x,
		"dest_y_m": home.y,
		"order": ORDER_STANDBY,
		"stance": STANCE_DEFAULT,
		"camp_town": String(reg.get("camp_town", "")),
	}

## Seeds every regiment of the player's realm that has no state yet — a new
## campaign, and an old save at its next settlement.
static func ensure(repo: DataRepository, state: GameState) -> void:
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var code := String(reg["regiment_code"])
		if not state.regiments.has(code):
			state.regiments[code] = starting_state(repo, reg, state)
			continue
		# A save written before the march existed has morale but no position:
		# seat it where the pack put it, standing.
		var entry: Dictionary = state.regiments[code]
		if not entry.has("x_m"):
			var home := pack_to_metres(repo, Vector2(float(reg.get("x", 0)), float(reg.get("y", 0))))
			entry["x_m"] = home.x
			entry["y_m"] = home.y
			entry["dest_x_m"] = home.x
			entry["dest_y_m"] = home.y
			entry["order"] = ORDER_STANDBY
		# A save from before the carried load (spec 2026-10-07-army-supply-lines
		# §6): the default load, and no more than the most a train can carry.
		if not entry.has("carry_days"):
			entry["carry_days"] = int(repo.bal("army_carry_default_days"))
			entry["supplies"] = mini(int(entry["supplies"]), max_units(repo, supply_use(repo, reg, state)))
		# A save from before the battle stances (spec 2026-10-07-enemy-ai-and-
		# battle §4.4): every regiment stood steady.
		if not entry.has("stance"):
			entry["stance"] = STANCE_DEFAULT

## True for a regiment of the raider realm in the field (GameState.foes).
static func is_foe(state: GameState, code: String) -> bool:
	return state != null and state.foes.has(code)

## A regiment's state for reading: a foe's stored one (GameState.foes, spec
## 2026-10-07-enemy-ai-and-battle §2), else the player's stored one, else what
## it would start with. Never writes. {} for a regiment that is neither.
static func state_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	if is_foe(state, code):
		return state.foes[code]
	var reg := regiment(repo, code, state)
	if reg.is_empty() or String(reg["kingdom_code"]) != repo.resolve_realm("player_realm"):
		return {}
	if state != null and state.regiments.has(code):
		return state.regiments[code]
	return starting_state(repo, reg)

## Supplies a regiment uses in a month: living personnel weighted by identity
## (noble_quality.csv) times the per-head use and height
## tier of the cell it stands on NOW (position_of; the pack's own quarters
## when `state` is null — a campaign's opening stores, a regiment with no
## state) (data/army/army_height_supply.csv, spec 2026-09-19-map3d-heights §2) —
## a fleet is not scaled. ONE rounding, at the end (owner review
## 2026-09-19): two per-mille divisions in a row lost heads a first
## regiment's worth of supply to truncation twice.
static func supply_use(repo: DataRepository, reg: Dictionary, state: GameState = null) -> int:
	var supply_milli := personnel_capacity(repo, reg) * 1000 if state == null else int(
		Quality.profile(repo, state, String(reg.get("regiment_code", "")))["supply_milli"])
	if state != null:
		supply_milli += PrisonerBurden.supply_milli(repo, state, String(reg.get("regiment_code", "")))
	var per_head := int(repo.bal("army_supply_per_head_permille"))
	var terrain := int(height_tier(repo, reg, state)["supply_permille"])
	if supply_milli <= 0 or per_head <= 0 or terrain <= 0:
		return 0
	# One final rounding, with one grain unit as the minimum positive ration:
	# living remnants cannot become exempt from hunger through truncation.
	@warning_ignore("integer_division")
	return maxi(1, supply_milli * per_head * terrain / 1_000_000_000)

## Wounded who return to the ranks in a month: a share, at least one while
## any are wounded.
static func wound_recovery(repo: DataRepository, wounded: int) -> int:
	if wounded <= 0:
		return 0
	@warning_ignore("integer_division")  # whole heads back in the ranks
	return maxi(1, wounded * int(repo.bal("army_wound_recovery_permille")) / 1000)

## The month's end for every regiment of the player's realm, in code order:
## wounded return, morale drifts toward what its stores allow, training
## grows. The supplies are not spent here: eat_day eats the month a day at a
## time, so the stores fall under the player's eyes.
static func settle_month(repo: DataRepository, state: GameState) -> void:
	Quality.settle_month(repo, state)
	_recover_month(repo, state)
	ensure(repo, state)
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := regiment(repo, code, state)
		if reg.is_empty():
			continue
		var marker := "army_month:" + code
		if not state.military_rosters.has(code) or int(state.conduct_marks.get(marker, -1)) == state.tick:
			continue
		var entry: Dictionary = state.regiments[code]
		state.conduct_marks[marker] = state.tick
		var use := supply_use(repo, reg, state)
		if String(reg.get("is_naval", "0")) != "1":
			# Morale reads the stores in hand as the month turns, after the
			# supply lines refilled them and before the month is eaten. Only
			# the unit holding a town's seat earns the garrison's bonus; one
			# camped round the town is fed by it but is not behind its walls
			# (spec 2026-10-07-army-split-and-ground §4.1).
			# the camp laws it follows add their mark (laws spec §4.1)
			var mark := clampi(morale_mark(repo, supply_score(repo, int(entry["supplies"]), use),
				ArmyGround.seated_in(repo, state, code) != "") + LawEffects.unit_mark(repo, state, code), 0, 100)
			entry["morale"] = drift_morale(int(entry["morale"]), mark, int(repo.bal("army_morale_drift_per_month")))
		entry["training"] = mini(100, int(entry["training"]) + int(repo.bal("army_training_per_month")))

## Recovery includes personnel not deployed into regiments/foes. A zero-wound
## month is consumed too, so later wounds cannot be healed by replaying it.
static func _recover_month(repo: DataRepository, state: GameState) -> void:
	var codes := state.military_rosters.keys()
	codes.sort()
	for code: String in codes:
		var marker := "recovery:" + code
		if int(state.conduct_marks.get(marker, -1)) == state.tick:
			continue
		var restored := wound_recovery(repo, wounded_count(repo, state, code))
		if restored > 0:
			var result := MilitaryRoster.transfer_units(repo, state, "recovery:%d:%s" % [state.tick, code],
				[{"unit_code": code, "from": "wounded", "to": "fit", "count": restored}], "Monthly wound recovery: " + code)
			if result.has("error"):
				continue
			var battle := BattleSystem.battle_of(state, code)
			if not battle.is_empty():
				BattleGroups.refresh(repo, state, battle)
		state.conduct_marks[marker] = state.tick

## The supplies a regiment eats on day `day` (1..DAYS_PER_TICK) of a month
## whose use is `use`: the month spread over its days in whole supplies, so
## the thirty days sum to exactly `use` (owner 2026-09-30: 每天都在以一定速率
## 减少).
static func day_bite(use: int, day: int) -> int:
	var n := Calendar.DAYS_PER_TICK
	var d := clampi(day, 1, n)
	@warning_ignore("integer_division")  # whole supplies, the month exact
	return use * d / n - use * (d - 1) / n


## One DAY of eating for every regiment of the player's realm, in code order
## (TickEngine, every day of the thirty, the tick's included): today's share of
## the month's use where it stands now.
static func eat_day(repo: DataRepository, state: GameState) -> void:
	ensure(repo, state)
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := regiment(repo, code, state)
		if reg.is_empty():
			continue
		eat_one(repo, state, reg, state.regiments[code])


## One regiment's meal of the day now running, written to its state `entry`
## (a player's or a foe's — EnemyAi feeds its hosts through this): today's
## share (day_bite) of the month's use where it stands now, never below 0.
static func eat_one(repo: DataRepository, state: GameState, reg: Dictionary, entry: Dictionary) -> void:
	entry["supplies"] = maxi(0, int(entry["supplies"]) - day_bite(supply_use(repo, reg, state), state.day))


## Whole days a regiment's `supplies` last at `use` a month (spec
## 2026-10-07-army-supply-lines §2.1): never saved, always read off the units.
static func days_in_hand(supplies: int, use: int) -> int:
	if use <= 0:
		return 999
	@warning_ignore("integer_division")  # whole days
	return maxi(supplies, 0) * Calendar.DAYS_PER_TICK / use

## The most units a regiment of `use` a month can carry: army_supply_max_days.
static func max_units(repo: DataRepository, use: int) -> int:
	@warning_ignore("integer_division")  # whole supplies
	return use * int(repo.bal("army_supply_max_days")) / Calendar.DAYS_PER_TICK

## A regiment entry's carried-load order, the default when it has none.
static func carry_of(repo: DataRepository, entry: Dictionary) -> int:
	return int(entry.get("carry_days", int(repo.bal("army_carry_default_days"))))

## The march's per-mille under a carried load (data/army/army_carry_loads.csv):
## the row with the most days not above `carry_days`; 1000 with no rows.
static func load_permille(repo: DataRepository, carry_days: int) -> int:
	var out := 1000
	for row: Dictionary in repo.army_carry_loads:
		if int(row["days"]) <= carry_days:
			out = int(row["pace_permille"])
	return out

## The map's yellow bar: days in hand over the carried load, per mille,
## capped at 1000 — it falls a little every day the column eats.
static func stores_permille(_repo: DataRepository, supplies: int, use_per_month: int, carry_days: int) -> int:
	if use_per_month <= 0:
		return 1000
	var full := maxi(1, carry_days)
	@warning_ignore("integer_division")  # whole per-mille
	return clampi(maxi(supplies, 0) * Calendar.DAYS_PER_TICK * 1000 / (use_per_month * full), 0, 1000)

## A day of hunger for every land regiment of the player's realm, in code
## order (spec §3.7): under army_supply_low_days days in hand morale falls
## army_morale_hungry_day, at none army_morale_starving_day instead.
static func hunger_day(repo: DataRepository, state: GameState) -> void:
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var use := supply_use(repo, reg, state)
		if use <= 0:
			continue   # it eats nothing: it never starves
		var entry: Dictionary = state.regiments[code]
		var supplies := int(entry["supplies"])
		var loss := 0
		if supplies <= 0:
			loss = int(repo.bal("army_morale_starving_day"))
		elif days_in_hand(supplies, use) < int(repo.bal("army_supply_low_days")):
			loss = int(repo.bal("army_morale_hungry_day"))
		entry["morale"] = maxi(0, int(entry["morale"]) - loss)


## Where a regiment's morale is heading (spec 2026-09-30-ledger-supply-design
## §4): from army_morale_starving with no stores to army_morale_fed with
## full ones, higher in garrison.
static func morale_mark(repo: DataRepository, score: int, garrison: bool) -> int:
	var lo := int(repo.bal("army_morale_starving"))
	var hi := int(repo.bal("army_morale_fed"))
	@warning_ignore("integer_division")
	var mark := lo + (hi - lo) * clampi(score, 0, 1000) / 1000
	if garrison:
		mark += int(repo.bal("army_morale_garrison_bonus"))
	return clampi(mark, 0, 100)

## One month's drift of morale toward its mark, never overshooting.
static func drift_morale(morale: int, mark: int, step: int) -> int:
	if morale < mark:
		return mini(morale + step, mark)
	return maxi(morale - step, mark)

## "well fed" / "on short rations" / "starving" — the word a supply score
## reads as (data/army/army_morale_words.csv, highest min_score first).
static func morale_word(repo: DataRepository, score: int) -> String:
	for row: Dictionary in repo.army_morale_words:
		if score >= int(row["min_score"]):
			return String(row["word"])
	return ""

## --- Terrain (spec §4) ---------------------------------------------------

## The ground a regiment stands on: sea for a fleet; mountains and hills by
## the cell's height (the supply tiers' lines, Elevation.tier_of); else its
## biome's terrain.
static func terrain_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	if String(reg.get("is_naval", "0")) == "1":
		return "sea"
	return terrain_at(repo, position_of(repo, state, reg))

## The land's terrain at a pack point, as terrain_of reads it for a regiment
## standing there: plains off every land cell.
static func terrain_at(repo: DataRepository, at: Vector2) -> String:
	var id := MapEconomy.cell_at(repo, at)
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

## --- Towns (spec 2026-10-06-army-location-and-town-defence §2-3) -------

static var _town_grid_cache: Dictionary = {}
static var _road_grid_cache: Dictionary = {}

## Forget the per-pack grids (DataRepository.load_map, like MapEconomy's).
static func forget_grids() -> void:
	_town_grid_cache.clear()
	_road_grid_cache.clear()

## A burg's reach in pack px: its group's km (data/army/army_town_reach.csv) on
## the pack's own measure; 0 for a group with no row.
static func town_reach_px(repo: DataRepository, burg: Dictionary) -> float:
	var km := float(repo.army_town_reach.get(String(burg.get("group", "")), 0.0))
	return km * 1000.0 / float(metres_per_pack_px(repo))

## The burgs bucketed by a grid as wide as the widest reach, so a point's
## towns are in its own bucket and the eight around it.
static func _town_grid(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _town_grid_cache.has(key):
		return _town_grid_cache[key]
	var size := 1.0
	for g: String in repo.army_town_reach:
		size = maxf(size, float(repo.army_town_reach[g]) * 1000.0 / float(metres_per_pack_px(repo)))
	var grid: Dictionary = {}
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var cell := Vector2i((Vector2(float(b["x"]), float(b["y"])) / size).floor())
		if not grid.has(cell):
			grid[cell] = []
		(grid[cell] as Array).append(code)
	var out := {"size": size, "grid": grid}
	_town_grid_cache[key] = out
	return out

## The town whose reach holds a pack point: the nearest (ties to the earlier
## code); "" in the open.
static func town_at(repo: DataRepository, at: Vector2) -> String:
	var tg := _town_grid(repo)
	var size: float = tg["size"]
	var grid: Dictionary = tg["grid"]
	var home := Vector2i((at / size).floor())
	var best := ""
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for code: String in grid.get(home + Vector2i(dx, dy), []):
				var b: Dictionary = repo.burgs[code]
				var d := at.distance_to(Vector2(float(b["x"]), float(b["y"])))
				if d > town_reach_px(repo, b):
					continue
				if d < best_d or (d == best_d and code < best):
					best_d = d
					best = code
	return best

## The town a land regiment stands IN now (its live position inside the
## town's reach, data/army/army_town_reach.csv); "" in the field and for a fleet.
static func town_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	if String(reg.get("is_naval", "0")) == "1":
		return ""
	return town_at(repo, position_of(repo, state, reg))

## town_of, but only a town the regiment's own kingdom holds (its province's
## owner, MapOwnership.owner_of): a column in a foreign town is in the field.
static func held_town_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	var town := town_of(repo, reg, state)
	if town == "":
		return ""
	var b: Dictionary = repo.burgs[town]
	if MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) != String(reg.get("kingdom_code", "")):
		return ""
	return town

## The works a unit fights from: "citadel", "walls" or "town" for the best
## the town whose SEAT it holds has (ArmyGround.seated_in; political/burgs.csv
## features), "" in the field and in a camp round a town (spec
## 2026-10-07-army-split-and-ground §4.1).
static func works_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	var town := ArmyGround.seated_in(repo, state, String(reg.get("regiment_code", "")))
	if town == "":
		return ""
	var feats := String((repo.burgs[town] as Dictionary).get("features", "")).split("|")
	if "citadel" in feats:
		return "citadel"
	if "walls" in feats:
		return "walls"
	return "town"

## An arm's modifier on a terrain, per mille (1000 when the table has no
## row); the town's works (data/army/army_town_defence.csv) multiply onto it for
## the defender only.
static func terrain_factor(repo: DataRepository, terrain: String, arm: String, stance: String, works: String) -> int:
	var f := int((repo.army_terrain.get("%s|%s" % [terrain, arm], {}) as Dictionary).get(stance, 1000))
	if works != "" and stance == "defend":
		@warning_ignore("integer_division")  # whole per-mille factor
		f = f * int((repo.army_town_defence.get("%s|%s" % [works, arm], {}) as Dictionary).get("defend", 1000)) / 1000
	return f

## "Hills", "Plains — in Garestedmin", "Hills — behind the walls of Walbover",
## "Plains — in the citadel of Axbrigh".
static func terrain_label(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	var text := terrain_of(repo, reg, state).capitalize()
	var works := works_of(repo, reg, state)
	if works == "":
		return text
	var seat := ArmyGround.seated_in(repo, state, String(reg.get("regiment_code", "")))
	var town := String((repo.burgs[seat] as Dictionary).get("label", ""))
	match works:
		"citadel":
			return "%s — in the citadel of %s" % [text, town]
		"walls":
			return "%s — behind the walls of %s" % [text, town]
	return "%s — in %s" % [text, town]

## The province a regiment is in NOW: the one holding the cell it stands on
## (MapManors.province_of, so a manor that changed province carries it), the
## pack's own row for a fleet at sea or a column off every land cell.
static func province_of(repo: DataRepository, state: GameState, reg: Dictionary) -> String:
	var id := _cell_of(repo, reg, state)
	var here := MapManors.province_of(repo, id, state) if id >= 0 else ""
	return here if here != "" else String(reg.get("province_code", ""))

## --- Height (spec 2026-09-19-map3d-heights §2) ---------------------------

## The cell under a regiment, -1 for a fleet or off the land.
static func _cell_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> int:
	if String(reg.get("is_naval", "0")) == "1":
		return -1
	return MapEconomy.cell_at(repo, position_of(repo, state, reg))

## Whole metres the regiment stands at; 0 for a fleet or off the land.
static func elevation_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> int:
	return Elevation.metres_of_cell(repo, _cell_of(repo, reg, state))

## {tier, supply_permille} of the cell the regiment stands on now (the
## pack's quarters when `state` is null); plains / 1000 for a fleet.
static func height_tier(repo: DataRepository, reg: Dictionary, state: GameState = null) -> Dictionary:
	var id := _cell_of(repo, reg, state)
	if id < 0:
		return {"tier": "plains", "supply_permille": 1000}
	return Elevation.tier_of(repo, float(repo.cells[id]["height"]))

## Per mille on a side's power for standing delta_m above (or, negative,
## below) the other: army_height_bonus_permille_per_100m, capped either way.
static func height_factor(repo: DataRepository, delta_m: int) -> int:
	var cap := int(repo.bal("army_height_bonus_cap_permille"))
	@warning_ignore("integer_division")  # whole per-mille per 100 m
	return 1000 + clampi(delta_m * int(repo.bal("army_height_bonus_permille_per_100m")) / 100, -cap, cap)

## --- Hidden strength (spec §5) ------------------------------------------

## A regiment's hidden value against an arm floats round its base, month by
## month: a hash of (regiment, arm, tick), never a draw from the engine's
## RNG stream, so it is deterministic and moves no other seeded roll.
static func float_factor(repo: DataRepository, code: String, vs_arm: String, tick: int) -> int:
	var spread := int(repo.bal("army_float_permille"))
	return 1000 - spread + posmod(("%s|%s|%d" % [code, vs_arm, tick]).hash(), spread * 2 + 1)

## An arm's base, per mille: the mean over its matchups of (attack +
## defense) / 2, each scaled by the month's float — none (1000) for an empty
## code, a host the crown cannot know the float of (a supposed one).
static func _arm_base(repo: DataRepository, code: String, arm: String, tick: int) -> int:
	var rows: Array = repo.army_matchups.get(arm, [])
	if rows.is_empty():
		return 1000
	var sum := 0
	for m: Dictionary in rows:
		var f := 1000 if code == "" else float_factor(repo, code, String(m["vs"]), tick)
		@warning_ignore("integer_division")  # whole per-mille: the arms' mean, then the float factor
		sum += (int(m["attack"]) + int(m["defense"])) / 2 * f / 1000
	@warning_ignore("integer_division")  # the arms' whole mean
	return sum / rows.size()

## A regiment's power where it stands, in the given stance ("defend" or
## "attack"): each arm's heads less its share of the wounded and the dead, times the arm's
## base, the training and morale factors and the terrain. 0 for a regiment
## without state.
static func power(repo: DataRepository, state: GameState, code: String, stance: String) -> int:
	var reg := regiment(repo, code, state)
	if reg.is_empty():
		return 0
	return power_on(repo, state, code, stance, terrain_of(repo, reg, state), works_of(repo, reg, state))


## power(), on a given ground: `terrain` (terrain_at's words) and `works`
## ("citadel", "walls", "town" or ""). The WAR ROOM's slip reads a regiment
## on ground it does not stand on (spec 2026-10-07-war-room-scale-hover §4.1).
static func power_on(repo: DataRepository, state: GameState, code: String, stance: String,
		terrain: String, works: String) -> int:
	var reg := regiment(repo, code, state)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	var fit := fit_count(repo, state, code) - PrisonerBurden.guard_count(repo, state, code)
	var realm := realm_of(repo, code, state)
	var base := power_of_arms(repo, reg, fit, int(st["training"]), int(st["morale"]), stance, terrain, works,
		code, 0 if state == null else state.tick, DevelopmentSystem.arm_permille(repo, state, realm))
	# Identity modifies the equipment-based result once, never the crew count.
	var quality := 1000 if state == null else int(Quality.profile(repo, state, code)["power_permille"])
	@warning_ignore("integer_division")
	return base * quality / 1000


## The realm a unit serves: its row's kingdom ("" for an unknown unit). The
## crown's regiments are the player realm's, the raider's the raider realm's.
static func realm_of(repo: DataRepository, code: String, state: GameState = null) -> String:
	return String(regiment(repo, code, state).get("kingdom_code", ""))


## The power of equipment `arms` (arm -> elements, a regiment's row will do) with
## `fit` of its heads fit, at a training and a morale, on a ground — the body
## of power_on, for a host with no state: the WAR ROOM's supposed enemy (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.2). `float_code`
## names whose hidden monthly float to apply at `tick`; "" applies none.
## `dev_permille` (arm -> per mille, DevelopmentSystem.arm_permille) scales each
## arm's term inside the same pipeline, rounded once at the end; an arm it does
## not name, or {}, is 1000 (unchanged).
static func power_of_arms(repo: DataRepository, arms: Dictionary, fit: int, training: int, morale: int,
		stance: String, terrain: String, works: String, float_code := "", tick := 0,
		dev_permille: Dictionary = {}) -> int:
	return _power_of_counts(repo, arms, personnel_capacity(repo, arms), fit, training, morale,
		stance, terrain, works, float_code, tick, dev_permille)


static func _power_of_counts(repo: DataRepository, arms: Dictionary, heads: int, fit: int,
		training: int, morale: int, stance: String, terrain: String, works: String,
		float_code := "", tick := 0, dev_permille: Dictionary = {}) -> int:
	if heads <= 0:
		return 0
	var training_f := int(repo.bal("army_training_base_permille")) + training * int(repo.bal("army_training_step_permille"))
	var morale_f := int(repo.bal("army_morale_base_permille")) + morale * int(repo.bal("army_morale_step_permille"))
	var total := 0
	for arm: String in repo.world_table("military", "unit_types"):
		var n := int(float(arms.get(arm, 0)))
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
		@warning_ignore("integer_division")  # milli-heads, whole (see the note above)
		var p := n * fit * 1000 / heads
		@warning_ignore("integer_division")  # whole per-mille
		p = p * _arm_base(repo, float_code, arm, tick) / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * training_f / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * morale_f / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * terrain_factor(repo, terrain, arm, stance, works) / 1000
		# The development factor joins here, so the one ceiling below rounds it
		# with the milli-head digit (1000 changes nothing).
		var dev := maxi(0, int(dev_permille.get(arm, 1000)))
		@warning_ignore("integer_division")  # the ceiling of the milli-head digit and the per-mille
		total += (p * dev + 999999) / 1000000
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
	var reg := regiment(repo, code, state)
	if reg.is_empty():
		return ""
	var naval := String(reg.get("is_naval", "0")) == "1"
	var sum := 0
	var n := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if (String(r.get("is_naval", "0")) == "1") != naval:
			continue
		sum += power(repo, state, String(r["regiment_code"]), "defend")
		n += 1
	if n <= 1 or sum <= 0:
		return "Average"
	@warning_ignore("integer_division")  # whole per-mille ratio against the mean
	var ratio := power(repo, state, code, "defend") * 1000 * n / sum
	if ratio >= int(repo.bal("army_strong_ratio_permille")):
		return "Strong"
	if ratio <= int(repo.bal("army_weak_ratio_permille")):
		return "Weak"
	return "Average"

# --- the march (owner 2026-09-19) ----------------------------------------------

## The km a day a regiment's SLOWEST arm marches (data/army/army_speed.csv): horse
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


## Supplies as a score, per mille (spec 2026-10-07-army-supply-lines §3.6):
## full at army_supply_low_days days in hand or more, falling linearly to 0
## at none — only a hungry column is slowed and loses heart. A banner that
## uses nothing never runs short.
static func supply_score(repo: DataRepository, supplies: int, use_per_month: int) -> int:
	if use_per_month <= 0:
		return 1000
	var low := maxi(1, int(repo.bal("army_supply_low_days")))
	@warning_ignore("integer_division")  # whole per-mille
	return clampi(maxi(supplies, 0) * Calendar.DAYS_PER_TICK * 1000 / (use_per_month * low), 0, 1000)


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
	@warning_ignore("integer_division")  # the weighted mean, whole per-mille
	return (wa * 1000 + ws * clampi(supply_permille, 0, 1000)
		+ wm * clampi(morale, 0, 100) * 10 + wt * clampi(training, 0, 100) * 10) / total


## The two bars over a regiment on the map (owner 2026-09-27: 红色是健康度 — 综合
## 战备, the readiness — 黄色是战略补给数), per mille: Vector2i(readiness,
## days in hand over the carried load, stores_permille — it falls every day). A
## regiment that is not the player's has no state, and reads as it would
## start (dev mode shows every realm's).
static func bars_of(repo: DataRepository, state: GameState, code: String) -> Vector2i:
	var reg := regiment(repo, code, state)
	if reg.is_empty():
		return Vector2i.ZERO
	var st := state_of(repo, state, code)
	if st.is_empty():
		st = starting_state(repo, reg)
	var use := supply_use(repo, reg, state)
	var supply := supply_score(repo, int(st["supplies"]), use)
	return Vector2i(readiness_permille(repo, supply, int(st["morale"]), int(st["training"])),
		stores_permille(repo, int(st["supplies"]), use, carry_of(repo, st)))


## The march in TENTHS of a km a day: base_km x 10 x readiness / 1000.
static func pace_tenths(repo: DataRepository, base_km: int, supply_permille: int, morale: int,
		training: int) -> int:
	@warning_ignore("integer_division")  # whole tenths of a km
	return base_km * 10 * readiness_permille(repo, supply_permille, morale, training) / 1000


## A regiment's march in km a day, from its arms, its state and the ground it
## stands on (weather-free); 0 for a regiment that is not the player's (no
## state) or has no one under arms.
static func speed_km_per_day(repo: DataRepository, state: GameState, code: String) -> float:
	var reg := regiment(repo, code, state)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0.0
	# the ground it stands on now (spec 2026-10-06 §6); the weather is its own line
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) / 10.0 \
		* float(load_permille(repo, carry_of(repo, st))) / 1000.0 \
		* float(ground_permille(repo, reg, position_of(repo, state, reg), state)) / 1000.0 \
		* float(LawEffects.unit_pace_permille(repo, state, code)) / 1000.0 \
		* float(PrisonerBurden.pace_permille(repo, state, code)) / 1000.0


## --- The ground's pace (spec 2026-10-06-army-location-and-town-defence §6)

## The roads' and trails' segments bucketed by a grid of the road reach, each
## segment in every bucket its box (grown by the reach) touches.
static func _road_grid(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _road_grid_cache.has(key):
		return _road_grid_cache[key]
	var reach := repo.bal("army_road_reach_m") / float(metres_per_pack_px(repo))
	var size := maxf(reach * 4.0, 1.0)
	var grid: Dictionary = {}
	var codes := repo.routes.keys()
	codes.sort()
	for code in codes:
		var r: Dictionary = repo.routes[code]
		var group := String(r.get("group", ""))
		if not RoadGraph.GROUPS.has(group):
			continue
		var kind := String(RoadGraph.GROUPS[group])
		var pts: Array = r["polyline"]
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var lo := Vector2i(((Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)) / size).floor())
			var hi := Vector2i(((Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)) / size).floor())
			for gy in range(lo.y, hi.y + 1):
				for gx in range(lo.x, hi.x + 1):
					var cell := Vector2i(gx, gy)
					if not grid.has(cell):
						grid[cell] = []
					(grid[cell] as Array).append([a, b, kind])
	var out := {"size": size, "reach": reach, "grid": grid}
	_road_grid_cache[key] = out
	return out

## "road" or "trail" when a pack point is within army_road_reach_m of one (a
## road over a trail), "" off the network.
static func road_at(repo: DataRepository, at: Vector2) -> String:
	var rg := _road_grid(repo)
	var reach: float = rg["reach"]
	var found := ""
	for seg: Array in (rg["grid"] as Dictionary).get(Vector2i((at / float(rg["size"])).floor()), []):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var near := Geometry2D.get_closest_point_to_segment(at, a, b)
		if at.distance_to(near) > reach:
			continue
		if String(seg[2]) == "road":
			return "road"
		found = String(seg[2])
	return found

## A march's pace on the ground at a pack point, per mille of its base
## (data/army/army_ground_speed.csv): on a road or trail, the road's row times its
## height tier's; off it, the terrain's (terrain_at). 1000 for a fleet.
static func ground_permille(repo: DataRepository, reg: Dictionary, at: Vector2, state: GameState = null) -> int:
	if String(reg.get("is_naval", "0")) == "1":
		return 1000
	var base := 1000
	var road := road_at(repo, at)
	if road != "":
		var id := MapEconomy.cell_at(repo, at)
		var tier := "plains"
		if id >= 0:
			tier = String(Elevation.tier_of(repo, float(repo.cells[id]["height"]))["tier"])
		@warning_ignore("integer_division")  # whole per-mille
		base = maxi(1, int(repo.army_ground_speed.get(road, 1000))
			* int(repo.army_ground_speed.get("tier_" + tier, 1000)) / 1000)
	else:
		base = maxi(1, int(repo.army_ground_speed.get(terrain_at(repo, at), 1000)))
	if state == null:
		return base
	@warning_ignore("integer_division")  # whole per-mille: a flood, an avalanche (spec 2026-10-07-war-room-p2 §2.3)
	return maxi(1, base * Hazards.pace_permille(repo, state, at) / 1000)

## The ground a regiment's pace reads now, in words: "road ×1.25",
## "forest ×0.75" (the card and the folio).
static func ground_word(repo: DataRepository, state: GameState, reg: Dictionary) -> String:
	var at := position_of(repo, state, reg)
	var road := road_at(repo, at)
	var what := road if road != "" else terrain_at(repo, at)
	return "%s ×%.2f" % [what, float(ground_permille(repo, reg, at, state)) / 1000.0]


## --- The march (owner 2026-09-22) ----------------------------------------
##
## A regiment's LIVE position is whole METRES on the pack's own measure —
## map_info's distance_scale in its distance_unit, the same measure the scale
## bar and the ruler show, so a day's march covers the distance the ruler
## says it does. It lives in GameState.regiments beside the morale; the
## pack's own x,y stay what the regiment STARTED from and are never written.
##
## Whole metres, and not pack pixels and not a float. Not pixels because a
## pack pixel is a kilometre here and a day's march would round to nothing;
## not a float because the save is JSON and "identical save + identical
## inputs => identical state" (architecture invariant 2) then rests on a
## float surviving a round trip through text. A day's march is
## pace_tenths x 100 metres, which is already a whole number, so nothing is
## lost by keeping the whole thing in metres.

## STANDBY is a column under no order: at the campaign's start. GARRISON is the
## order to hold the ground: a march that ARRIVES garrisons where it stops
## (owner 2026-09-30: 军队到达目的地后自动驻防，取消驻防按钮), and ARMY_GARRISON —
## now only the route menu's Cancel march — halts a column into one (owner
## 2026-09-29: a garrison stands behind the shield, the spear laid over it). The
## 3D piece plays one clip each.
const ORDER_STANDBY := "standby"
const ORDER_GARRISON := "garrison"
const ORDER_MARCH := "march"
## The battle stance (data/battle/battle_stances.csv) a regiment starts with and an
## old save's regiments read as; ARMY_STANCE changes it by courier.
const STANCE_DEFAULT := "steady"


## Metres to one pack pixel, from the pack's own map_info.
static func metres_per_pack_px(repo: DataRepository) -> int:
	var per_unit := 1609 if String(repo.map_info.get("distance_unit", "km")) == "mi" else 1000
	return maxi(1, int(round(float(repo.map_info.get("distance_scale", "1")) * per_unit)))


static func pack_to_metres(repo: DataRepository, p: Vector2) -> Vector2i:
	var k := float(metres_per_pack_px(repo))
	return Vector2i(int(round(p.x * k)), int(round(p.y * k)))


static func metres_to_pack(repo: DataRepository, m: Vector2i) -> Vector2:
	var k := float(metres_per_pack_px(repo))
	return Vector2(float(m.x) / k, float(m.y) / k)


## Where a regiment IS, in pack pixels: its marched position when it has one,
## else the pack's own row. Everything that draws or measures a regiment goes
## through this — the counters, the 3D pieces, the terrain it fights on — so
## a regiment on the road is somewhere else on every one of them at once.
static func position_of(repo: DataRepository, state: GameState, reg: Dictionary) -> Vector2:
	var home := Vector2(float(reg.get("x", 0)), float(reg.get("y", 0)))
	if state == null:
		return home
	var code := String(reg.get("regiment_code", ""))
	var entry: Dictionary = state.foes.get(code, state.regiments.get(code, {}))   # a foe's live place is its own
	if not entry.has("x_m"):
		return home
	return metres_to_pack(repo, Vector2i(int(entry["x_m"]), int(entry["y_m"])))


## A battle stance taking hold (spec 2026-10-07-enemy-ai-and-battle §4.4,
## 2026-10-11-war-room-front-line-design §1): `stance_next` and its
## newest-wins `stance_order_id`; BattleSystem.settle_stances makes it the
## stance at the day's end. `facing` >= 0 is a whole degree the regiment faces
## (WarFront's frame); < 0 leaves the facing alone.
static func apply_hold(entry: Dictionary, stance: String, facing: int, order_id: int) -> void:
	entry["stance_next"] = stance
	entry["stance_order_id"] = order_id
	if facing >= 0:
		entry["facing_deg"] = posmod(facing, 360)


## A hold parked for a march's arrival (`hold_after`) is dropped by any new
## order or a halt: a column caught on the road takes no front (ruling 3).
static func drop_hold(entry: Dictionary) -> void:
	entry.erase("hold_after")


## The way a regiment of the crown FACES where it stands (WarFront's frame,
## a unit vector in pack px): ZERO while marching or with none set; a foe's too
## (a column halted before a unit faces it, spec 2026-10-14-unit-clearance).
static func facing_of(state: GameState, code: String) -> Vector2:
	var entry: Dictionary = state.regiments.get(code, state.foes.get(code, {}))
	if entry.is_empty() or String(entry.get("order", ORDER_STANDBY)) == ORDER_MARCH or not entry.has("facing_deg"):
		return Vector2.ZERO
	return WarFront.facing_vector(int(entry["facing_deg"]))


## The way its piece is turned: its road while marching, else its facing.
static func piece_heading(repo: DataRepository, state: GameState, code: String) -> Vector2:
	var h := heading_of(repo, state, code)
	return h if h != Vector2.ZERO else facing_of(state, code)


## Whether a regiment currently occupies its saved, fully built physical camp.
static func camped(repo: DataRepository, state: GameState, code: String) -> bool:
	var e: Dictionary = state.regiments.get(code, {})
	var camp: Dictionary = e.get("camp_state", {})
	if e.is_empty() or String(camp.get("phase", CampSystem.NONE)) != CampSystem.CAMPED:
		return false
	var site: Dictionary = camp.get("site", {})
	return int(e.get("x_m", -1)) == int(site.get("x_m", -2)) \
		and int(e.get("y_m", -1)) == int(site.get("y_m", -2)) \
		and ArmyGround.garrison_town(repo, state, code) == ""


## The order a regiment is under: "march", "garrison" or "standby" (no order).
static func order_of(repo: DataRepository, state: GameState, code: String) -> String:
	var entry: Dictionary = state_of(repo, state, code)
	return String(entry.get("order", ORDER_STANDBY)) if not entry.is_empty() else ORDER_STANDBY


## Where a marching regiment is headed, in pack pixels; its own position when
## it is not marching.
static func destination_of(repo: DataRepository, state: GameState, code: String) -> Vector2:
	var entry: Dictionary = state_of(repo, state, code)
	if entry.is_empty() or not entry.has("dest_x_m"):
		return position_of(repo, state, regiment(repo, code, state))
	return metres_to_pack(repo, Vector2i(int(entry["dest_x_m"]), int(entry["dest_y_m"])))


## The way a marching regiment faces, as a unit vector in PACK space (y down,
## as the pack's own coordinates are); Vector2.ZERO when it stands. The 3D
## pieces turn by this, so a column faces the road it is on.
static func heading_of(repo: DataRepository, state: GameState, code: String) -> Vector2:
	if order_of(repo, state, code) != ORDER_MARCH:
		return Vector2.ZERO
	# the next point of its route (spec 2026-10-07-march-waypoints), else the end
	var ahead := route_px(repo, state, code)
	var next := ahead[0] if not ahead.is_empty() else destination_of(repo, state, code)
	var away := next - position_of(repo, state, regiment(repo, code, state))
	return away.normalized() if away.length() > 0.0001 else Vector2.ZERO


## Metres a regiment covers in one day: pace_tenths (tenths of a km) x 100,
## under the carried load (load_permille: a heavier train marches slower),
## then under the camp laws it follows (LawEffects.unit_pace_permille).
## 0 for a banner with no one under arms, which is why an order to march is
## refused for one rather than leaving it crawling toward a place forever.
## `carry` (days) prices another load than the standing order — the march
## confirm's rows (spec 2026-10-07-march-waypoints §2); -1 is the regiment's own.
static func day_step_m(repo: DataRepository, state: GameState, code: String, carry := -1) -> int:
	var reg := regiment(repo, code, state)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	@warning_ignore("integer_division")  # whole metres
	var step := pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) * 100 \
		* load_permille(repo, carry if carry >= 0 else carry_of(repo, st)) / 1000
	@warning_ignore("integer_division")  # whole metres
	step = step * LawEffects.unit_pace_permille(repo, state, code) / 1000
	@warning_ignore("integer_division")
	return step * PrisonerBurden.pace_permille(repo, state, code) / 1000


## Metres a regiment covers TODAY (spec 2026-09-27-courier-core §1): its
## day_step_m under the weather of the province it stands in and on the ground
## under it — on `abs_day` when given (the map's preview of the next day),
## else today.
static func day_march_m(repo: DataRepository, state: GameState, code: String, abs_day: int = -1) -> int:
	return day_march_at(repo, state, code, position_of(repo, state, regiment(repo, code, state)), abs_day)


## day_march_m for a column standing at `at` (pack px): its day_step_m under
## that place's weather on the day and on its ground (ground_permille, spec
## 2026-10-06 §6) — a march reads where the column IS each day.
static func day_march_at(repo: DataRepository, state: GameState, code: String, at: Vector2,
		abs_day: int = -1, carry := -1) -> int:
	var step := day_step_m(repo, state, code, carry)
	if step <= 0 or state == null:
		return step
	var kind := Weather.at(repo, state, at, state.absolute_day() if abs_day < 0 else abs_day)
	@warning_ignore("integer_division")  # whole metres
	step = step * Weather.speed_permille(repo, kind) / 1000
	if step <= 0:
		return step
	@warning_ignore("integer_division")  # whole metres
	return maxi(1, step * ground_permille(repo, regiment(repo, code, state), at, state) / 1000)


## Send a regiment to `dest` (pack pixels) through `waypoints` (pack px, in
## order; spec 2026-10-07-march-waypoints). The engine's only writer of a
## march order; ActionSystem calls it after ARMY_MARCH validates. The unit
## leaves its camp and, holding a seat, empties it (ArmyGround.leave).
static func set_march(repo: DataRepository, state: GameState, code: String, dest: Vector2,
		waypoints: Array = []) -> void:
	var wps: Array = []
	for w: Vector2 in waypoints:
		wps.append(pack_to_metres(repo, w))
	set_march_m(repo, state, code, pack_to_metres(repo, dest), wps)


## set_march in whole metres — the courier's order carries metres. The
## regiment keeps the road from where it stands NOW (`route_m`, route_m_of):
## through waypoints the curve (MarchRoute) and the waypoints still ahead
## (`waypoints_m`); without, the way round any ground it cannot climb
## (MarchPath) — and when the straight line is clear, no route at all.
static func set_march_m(repo: DataRepository, state: GameState, code: String, dest: Vector2i,
		waypoints: Array = [], march_already_done := false) -> void:
	ensure(repo, state)
	if not state.regiments.has(code):
		return
	CampSystem.ensure_legacy(repo, state, code)
	var entry: Dictionary = state.regiments[code]
	entry["dest_x_m"] = dest.x
	entry["dest_y_m"] = dest.y
	entry["order"] = ORDER_MARCH
	CampSystem.request_departure(state, code, state.absolute_day(), march_already_done)
	if String(entry.get("camp_state", {}).get("phase", CampSystem.NONE)) == CampSystem.PACKING:
		entry["departure"] = {"dest_x_m": dest.x, "dest_y_m": dest.y,
			"waypoints_m": MarchRoute.to_pairs(waypoints), "received_day": state.absolute_day()}
	drop_hold(entry)
	entry.erase("facing_deg")   # a column on the march faces its road
	for k: String in ["halted_by", "halt_day", "halt_aim_m", "road_blocked_by", "waited", "wait_on"]:
		entry.erase(k)          # a new march is no halt before anyone
	_clear_route(entry)
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var route := route_m_of(repo, here, waypoints, dest, is_naval(repo, state, code))
	if not waypoints.is_empty() or route.size() > 1:
		entry["route_m"] = MarchRoute.to_pairs(route)
	if not waypoints.is_empty():
		entry["waypoints_m"] = MarchRoute.to_pairs(waypoints)
	if not entry.has("departure"):
		ArmyGround.leave(repo, state, code)


## Point a column's state row (a foe's, a retreat's) at `to` (whole metres)
## on the road set_march_m would give it, through no waypoints: the route it
## already walks is kept when it ends there (the hosts re-aim every day).
static func aim_entry(repo: DataRepository, entry: Dictionary, to: Vector2i, naval := false) -> void:
	drop_hold(entry)
	for k: String in ["halted_by", "halt_day", "halt_aim_m", "road_blocked_by"]:
		entry.erase(k)
	var same := String(entry.get("order", "")) == ORDER_MARCH and int(entry.get("dest_x_m", 0)) == to.x \
		and int(entry.get("dest_y_m", 0)) == to.y
	entry["dest_x_m"] = to.x
	entry["dest_y_m"] = to.y
	entry["order"] = ORDER_MARCH
	if entry.has("departure"):
		var departure: Dictionary = entry["departure"]
		departure["dest_x_m"] = to.x
		departure["dest_y_m"] = to.y
		if not same:
			departure["waypoints_m"] = []
	if same:
		return
	entry.erase("facing_deg")   # a new destination: no halt's facing
	_clear_route(entry)
	if not entry.has("x_m"):
		return
	var route := route_m_of(repo, Vector2i(int(entry["x_m"]), int(entry["y_m"])), [], to, naval)
	if route.size() > 1:
		entry["route_m"] = MarchRoute.to_pairs(route)


## True for a fleet.
static func is_naval(repo: DataRepository, state: GameState, code: String) -> bool:
	return String(regiment(repo, code, state).get("is_naval", "0")) == "1"


## The road from `from` (left off) through `waypoints` to `to`, whole metres —
## what a march through them walks: the curve through the waypoints
## (MarchRoute), each leg that would cross ground a column cannot climb
## replaced by MarchPath's way round it (spec 2026-10-10-march-slope-detour);
## [to] for a straight march with nothing in the way. A fleet (`naval`) keeps
## the curve as it is.
static func route_m_of(repo: DataRepository, from: Vector2i, waypoints: Array, to: Vector2i,
		naval := false) -> Array:
	var grid: MarchPath = null if naval else MarchPath.of_pack(repo)
	if waypoints.is_empty():
		return [to] if grid == null else grid.road(from, to)
	var pts: Array = [from]
	pts.append_array(waypoints)
	pts.append(to)
	var ctrl := MarchRoute.distinct(pts)
	var out: Array = []
	var legs := MarchRoute.legs(ctrl, int(repo.bal("army_route_sample_m")))
	for i in legs.size():
		var leg: Array = legs[i]
		if grid != null and not leg_clear(grid, ctrl[i], leg):
			leg = grid.road(ctrl[i], ctrl[i + 1])
		out.append_array(leg)
	return out


## True when a leg's samples, from `start`, cross no closed cell of `grid`
## but its two ends'.
static func leg_clear(grid: MarchPath, start: Vector2i, leg: Array) -> bool:
	if grid == null:
		return true
	if leg.is_empty():
		return false
	var ends := [grid.cell_of(start), grid.cell_of(leg[leg.size() - 1])]
	var prev := start
	for p: Vector2i in leg:
		if not grid.clear(prev, p, ends):
			return false
		prev = p
	return true


## The road a march from `from` through `waypoints` to `to` (all pack px)
## would walk, the start included, in pack px — the line the maps draw while
## it is planned (spec 2026-10-07-march-waypoints rulings 1, 11; round a scarp,
## spec 2026-10-10-march-slope-detour). `naval` for a fleet's.
static func curve_px(repo: DataRepository, from: Vector2, waypoints: Array, to: Vector2,
		naval := false) -> PackedVector2Array:
	var out := PackedVector2Array([from])
	var wps: Array = []
	for w: Vector2 in waypoints:
		wps.append(pack_to_metres(repo, w))
	var route := route_m_of(repo, pack_to_metres(repo, from), wps, pack_to_metres(repo, to), naval)
	if waypoints.is_empty() and route.size() <= 1:
		out.append(to)
		return out
	for p: Vector2i in route:
		out.append(metres_to_pack(repo, p))
	return out


## The road still ahead of a marching regiment, pack px, ending on its
## destination ([] when it is not marching): its route's points, else the end.
static func route_px(repo: DataRepository, state: GameState, code: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if order_of(repo, state, code) != ORDER_MARCH:
		return out
	for p: Vector2i in _path_of(state_of(repo, state, code)):
		out.append(metres_to_pack(repo, p))
	return out


## The waypoints a marching regiment has still to pass, pack px.
static func waypoints_of(repo: DataRepository, state: GameState, code: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if order_of(repo, state, code) != ORDER_MARCH:
		return out
	for p: Vector2i in MarchRoute.from_pairs(state_of(repo, state, code).get("waypoints_m", [])):
		out.append(metres_to_pack(repo, p))
	return out


## An entry's road ahead in whole metres: its route, else the straight line's
## end. A route that no longer ends on the destination (a writer that moved the
## end without set_march_m / aim_entry) is stale and walks the straight line.
static func _path_of(entry: Dictionary) -> Array:
	if entry.has("route_m") and not (entry["route_m"] as Array).is_empty():
		var last: Array = (entry["route_m"] as Array).back()
		if int(last[0]) == int(entry.get("dest_x_m", last[0])) and int(last[1]) == int(entry.get("dest_y_m", last[1])):
			return MarchRoute.from_pairs(entry["route_m"])
	if not entry.has("dest_x_m"):
		return []
	return [Vector2i(int(entry["dest_x_m"]), int(entry["dest_y_m"]))]


static func _clear_route(entry: Dictionary) -> void:
	entry.erase("route_m")
	entry.erase("waypoints_m")


## Halt a regiment where it stands. A column halted on the road settles
## there as an arrival does (ArmyGround.settle); a standing one keeps its ground.
static func set_garrison(repo: DataRepository, state: GameState, code: String) -> void:
	ensure(repo, state)
	if not state.regiments.has(code):
		return
	var entry: Dictionary = state.regiments[code]
	var marching := String(entry.get("order", ORDER_STANDBY)) == ORDER_MARCH
	entry["order"] = ORDER_GARRISON
	entry["dest_x_m"] = int(entry["x_m"])
	entry["dest_y_m"] = int(entry["y_m"])
	entry.erase("departure")
	drop_hold(entry)
	_clear_route(entry)
	if marching:
		ArmyGround.settle(repo, state, code)


## One DAY of marching for every regiment under a march order, in code order,
## the player's first and then the foes' (GameState.foes).
## Each arrival settles at once (ArmyGround.settle: first come, first in).
## Returns the player's codes that arrived today, for the news bar. The column
## walks at its own pace along its route (spec 2026-10-07-march-waypoints), else
## the straight line. The route goes round ground a column cannot climb and
## round water (MarchPath, set when the march is ordered); a fleet's does not.
static func march_day(repo: DataRepository, state: GameState, pace_divisor := 1, substep_index := 0,
		restrict_to_codes := false, allowed_codes: Array = [], daily_budgets: Dictionary = {}) -> Array:
	ensure(repo, state)
	var arrived: Array = []
	# who stands where, the clearance's discs (spec 2026-10-14-unit-clearance-and-
	# scouting-design §a): each unit walks its day against the places the units
	# before it have left theirs at, and writes its own back
	var blockers := clearance_blockers(repo, state)
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		if restrict_to_codes and not code in allowed_codes:
			continue
		if BattleSystem.may_withdraw(state, code):
			_resume_departure(repo, state, code, state.regiments[code])
		var entry: Dictionary = state.regiments[code]
		for battle: Dictionary in state.battles:
			BattleGroups.follow_anchor(repo, state, battle, code)
		var origin := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
		var had_departure := entry.has("departure")
		var was_packing := String(entry.get("camp_state", {}).get("phase", CampSystem.NONE)) == CampSystem.PACKING
		var pursuit_stopped := false
		if not bool(entry.get("battle_retreat", false)) and int(entry.get("disengaging", 0)) != 1:
			pursuit_stopped = BattleTaskSystem.credit_pursuit(repo, state, code, 0) \
				or BattleTaskSystem.current(state, code).get("status", "") == "bounded"
		if pursuit_stopped and String(entry.get("order", "")) == ORDER_MARCH:
			BattleSystem._halt(state, code)
			_clear_route(entry)
			entry.erase("departure")
		var travelled: Array = []
		var arrived_today := false
		if not pursuit_stopped:
			arrived_today = _march_one(repo, state, code, entry, state.absolute_day(), blockers, [], pace_divisor,
				substep_index, int(daily_budgets.get(code, -1)), -1, travelled)
			if not bool(entry.get("battle_retreat", false)) and int(entry.get("disengaging", 0)) != 1:
				BattleTaskSystem.credit_pursuit(repo, state, code,
					int(travelled[0]) if not travelled.is_empty() else 0,
					String(travelled[1]) if travelled.size() > 1 else "")
		if had_departure and was_packing \
				and String(entry.get("camp_state", {}).get("phase", CampSystem.NONE)) != CampSystem.PACKING \
				and Vector2i(int(entry["x_m"]), int(entry["y_m"])) != origin:
			ArmyGround.leave(repo, state, code)
		if arrived_today:
			var halted_by := String(entry.get("halted_by", ""))
			if halted_by == "" or not _enemies(blockers, code, halted_by):
				# a column halted before a unit it is not at war with camps on the
				# side it came from; before an enemy it stands where it halted
				ArmyGround.settle(repo, state, code,
					Vector2i(int(entry["x_m"]), int(entry["y_m"])) if halted_by != "" else ArmyGround.NONE)
			if halted_by != "" and blockers.has("pos") and (blockers["pos"] as Dictionary).has(halted_by):
				entry["facing_deg"] = _facing_to(Vector2i(int(entry["x_m"]), int(entry["y_m"])),
					(blockers["pos"] as Dictionary)[halted_by])
			arrived.append(code)
			# a front's hold parked for the arrival takes effect now (spec
			# 2026-10-11-war-room-front-line-design §1): the facing always, the
			# stance only when no newer stance order has come since
			if entry.has("hold_after"):
				var hold: Dictionary = entry["hold_after"]
				entry.erase("hold_after")
				entry["facing_deg"] = posmod(int(hold.get("facing", 0)), 360)
				if int(hold.get("id", 0)) >= int(entry.get("stance_order_id", 0)):
					apply_hold(entry, String(hold.get("stance", STANCE_DEFAULT)), -1, int(hold.get("id", 0)))
			# the column holds its ground: a halt pencilled in the war room has
			# nothing left to stop (a pencilled new march still stands; a halt
			# with a hold of its own still has its stance to give)
			var draft := WarDrafts.of(state, code)
			if String(draft.get("order", "")) == WarDrafts.GARRISON and not draft.has("hold"):
				WarDrafts.strike(state, code)
		for battle: Dictionary in state.battles:
			BattleGroups.follow_anchor(repo, state, battle, code)
		_note_place(blockers, code, state.regiments[code])
	# The foes' second pass (spec 2026-10-07-enemy-ai-and-battle §2), in code
	# order and by the same even step: a column in a battle stands; one that
	# arrives holds its ground, and a foreign column's arrival is not news, so
	# it is not in `arrived`.
	var foes := state.foes.keys()
	foes.sort()
	for c in foes:
		var code := String(c)
		if restrict_to_codes and not code in allowed_codes:
			continue
		if BattleSystem.may_withdraw(state, code):
			var fe: Dictionary = state.foes[code]
			for battle: Dictionary in state.battles:
				BattleGroups.follow_anchor(repo, state, battle, code)
			_resume_departure(repo, state, code, fe)
			var aim := Vector2i(int(fe.get("dest_x_m", 0)), int(fe.get("dest_y_m", 0)))
			if _march_one(repo, state, code, fe, state.absolute_day(), blockers, [], pace_divisor,
					substep_index, int(daily_budgets.get(code, -1))):
				var hb := String(fe.get("halted_by", ""))
				if hb != "" and not _enemies(blockers, code, hb):
					_spread_foe(repo, state, code, fe, aim, blockers)
			for battle: Dictionary in state.battles:
				BattleGroups.follow_anchor(repo, state, battle, code)
			_note_place(blockers, code, state.foes[code])
	return arrived

static func _resume_departure(repo: DataRepository, state: GameState, code: String, entry: Dictionary) -> void:
	if not entry.has("departure"):
		return
	var departure: Dictionary = entry["departure"]
	var dest := Vector2i(int(departure["dest_x_m"]), int(departure["dest_y_m"]))
	# A battle may have replaced the march order with a retreat/halt. Restore its
	# saved route after combat, but keep packing protection until the column moves.
	for k: String in ["halted_by", "halt_day", "halt_aim_m", "road_blocked_by"]:
		entry.erase(k)
	entry["dest_x_m"] = dest.x
	entry["dest_y_m"] = dest.y
	entry["order"] = ORDER_MARCH
	entry.erase("facing_deg")
	_clear_route(entry)
	var here := Vector2i(int(entry.get("x_m", 0)), int(entry.get("y_m", 0)))
	var waypoints := MarchRoute.from_pairs(departure.get("waypoints_m", []))
	var route := route_m_of(repo, here, waypoints, dest, is_naval(repo, state, code))
	if not waypoints.is_empty() or route.size() > 1:
		entry["route_m"] = MarchRoute.to_pairs(route)
	if not waypoints.is_empty():
		entry["waypoints_m"] = MarchRoute.to_pairs(waypoints)


## A host column halted by a FRIENDLY unit near its target (owner 2026-10-15,
## R-B) does not queue down the road: it takes the nearest free camp-lattice
## slot round the target (ArmyGround.free_slot from ring 1, `near_m` its halt
## point, held_taken), so the whole host stands at the town. Further than
## army_spread_reach_m from the target it stays where it halted unless its
## actual friendly blocker is inside that circle and touching within the
## two clearance radii plus army_clearance_touch_m. Slots remain inside the circle.
static func _spread_foe(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		aim: Vector2i, blockers: Dictionary) -> void:
	var at := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	if blockers.is_empty():
		return
	var reach := int(repo.bal("army_spread_reach_m"))
	if MarchClearance.dist2(at, aim) > reach * reach:
		var blocker := String(entry.get("halted_by", ""))
		var old_aim: Array = entry.get("halt_aim_m", [])
		var positions: Dictionary = blockers.get("pos", {})
		var radii: Dictionary = blockers.get("r", {})
		if old_aim.size() != 2 or Vector2i(old_aim[0], old_aim[1]) != aim \
				or not positions.has(blocker) or not radii.has(code) or not radii.has(blocker) \
				or _enemies(blockers, code, blocker):
			return
		var near: Vector2i = positions[blocker]
		var touch := int(radii[code]) + int(radii[blocker]) + int(repo.bal("army_clearance_touch_m"))
		if MarchClearance.dist2(near, aim) > reach * reach or MarchClearance.dist2(at, near) > touch * touch:
			return
	var arm := MapObjects.regiment_arm(repo, regiment(repo, code, state))
	var taken := ArmyGround.held_taken(repo, state, code)
	var slot := ArmyGround.free_slot(repo, aim, arm, taken, "", false, at, 1, reach)
	if slot == ArmyGround.NONE:
		slot = ArmyGround.free_slot(repo, aim, arm, taken, "", true, at, 1, reach)
	if slot == ArmyGround.NONE or MarchClearance.dist2(slot, aim) > reach * reach:
		return
	entry["x_m"] = slot.x
	entry["y_m"] = slot.y
	entry["dest_x_m"] = slot.x
	entry["dest_y_m"] = slot.y
	entry["facing_deg"] = _facing_to(slot, aim)


## The whole-metre place of `entry` written into the clearance's record (a unit
## that moved, settled or halted), when it is in the record.
static func _note_place(blockers: Dictionary, code: String, entry: Dictionary) -> void:
	if blockers.is_empty() or not (blockers["pos"] as Dictionary).has(code) or not entry.has("x_m"):
		return
	var at := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	blockers["pos"][code] = at
	blockers["moving"][code] = String(entry.get("order", ORDER_STANDBY)) == ORDER_MARCH
	var i := int((blockers["index"] as Dictionary)[code])
	(blockers["xs"] as Array)[i] = at.x
	(blockers["ys"] as Array)[i] = at.y


## The units that hold ground for clearance, in code order: every land unit
## with men under arms — the crown's, the foes', and the roster's others at
## their pack places — {codes, pos (code -> whole metres), r (code -> its
## clearance radius, ArmyGround.unit_radius), realm (code -> kingdom), side
## (code -> "crown" | "foe" | "other"), maxr, hostile (a cache of kingdom pairs
## at war)}. {} when the rule is off (army_clearance_on 0). A fleet holds none.
static func clearance_blockers(repo: DataRepository, state: GameState) -> Dictionary:
	if not ArmyGround.clearance_on(repo) or state == null:
		return {}
	var all := roster(repo, state)
	var info := _unit_info(repo, all)
	var keys: Array = info["codes"]
	if not state.foes.is_empty():
		for f: Variant in state.foes:
			if not all.has(f):
				keys = keys + [f]
		keys.sort()
	var codes: Array = []
	var pos: Dictionary = {}
	var side: Dictionary = {}
	var rad: Dictionary = {}
	var realm: Dictionary = {}
	var xs: Array = []
	var ys: Array = []
	var rs: Array = []
	var moving: Dictionary = {}
	var maxr := 0
	var rows: Dictionary = info["rows"]
	var spread := _deployment_reach(repo, state)
	for k: Variant in keys:
		var code := String(k)
		var row: Array = rows.get(code, [])
		if row.is_empty():
			continue                       # a fleet, or no such unit
		var st: Dictionary = {}
		var kind := "other"
		if state.foes.has(code):
			st = state.foes[code]
			kind = "foe"
		elif state.regiments.has(code):
			st = state.regiments[code]
			kind = "crown"
		if living_count(repo, state, code) <= 0:
			continue
		codes.append(code)
		side[code] = kind
		moving[code] = String(st.get("order", ORDER_STANDBY)) == ORDER_MARCH
		realm[code] = row[2]
		var at: Vector2i = Vector2i(int(st["x_m"]), int(st["y_m"])) if st.has("x_m") \
			else pack_to_metres(repo, position_of(repo, state, all[code]))
		var radius := int(row[1])
		if spread.has(code):                # its deployed groups are the ground it holds
			radius = maxi(radius, _group_reach(repo, spread[code], at))
		rad[code] = radius
		maxr = maxi(maxr, radius)
		pos[code] = at
		xs.append(at.x)
		ys.append(at.y)
		rs.append(radius)
	var index: Dictionary = {}
	for i in codes.size():
		index[codes[i]] = i
	return {"codes": codes, "pos": pos, "r": rad, "realm": realm, "side": side, "maxr": maxr, "hostile": {},
		"moving": moving,
		"xs": xs, "ys": ys, "rs": rs, "index": index,
		"player": repo.resolve_realm("player_realm"), "raider": repo.resolve_realm("raider_realm"),
		"diplomacy": repo.world_table("political", "diplomacy")}


## The saved groups of every unit in a live battle, code -> rows.
static func _deployment_reach(_repo: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for b: Dictionary in state.battles:
		var groups: Dictionary = b.get("groups", {})
		for code: Variant in groups:
			out[String(code)] = groups[code]
	return out


## The radius that covers a unit's groups round `anchor`: the farthest group's
## distance rounded up to whole metres, plus half the group spacing.
static func _group_reach(repo: DataRepository, rows: Array, anchor: Vector2i) -> int:
	var far := 0
	for g: Dictionary in rows:
		var dx := int(g["x_m"]) - anchor.x
		var dy := int(g["y_m"]) - anchor.y
		var d2 := dx * dx + dy * dy
		var d := int(sqrt(float(d2)))
		while d * d < d2:
			d += 1
		while d > 0 and (d - 1) * (d - 1) >= d2:
			d -= 1
		far = maxi(far, d)
	@warning_ignore("integer_division")
	return far + int(repo.bal("battle_group_spacing_m")) / 2


## What never changes about a roster unit: [headcount, clearance radius, kingdom]
## by code (a fleet has no row), with the sorted codes — kept for the roster it
## was made from (the roster's rows are immutable; a changed size rebuilds).
static var _unit_cache: Dictionary = {}


static func _unit_info(repo: DataRepository, all: Dictionary) -> Dictionary:
	var key := [all.size(), repo.get_instance_id(), int(repo.bal("army_clearance_on"))]
	if _unit_cache.get("key", []) == key and is_same(_unit_cache.get("all"), all):
		return _unit_cache
	var rows: Dictionary = {}
	var codes: Array = all.keys()
	codes.sort()
	for code: String in codes:
		var reg: Dictionary = all[code]
		if String(reg.get("is_naval", "0")) == "1":
			continue
		rows[code] = [headcount(repo, reg), ArmyGround.unit_radius(repo, reg), String(reg.get("kingdom_code", ""))]
	_unit_cache = {"key": key, "all": all, "rows": rows, "codes": codes}
	return _unit_cache


## Whether two kingdoms are at war with each other for clearance: the player's
## and the raider's, or a pair whose diplomacy row says Enemy (cached).
static func _hostile(blockers: Dictionary, ka: String, kb: String) -> bool:
	if ka == kb:
		return false
	var key := ka + "|" + kb
	var cache: Dictionary = blockers["hostile"]
	if cache.has(key):
		return bool(cache[key])
	var player := String(blockers["player"])
	var raider := String(blockers["raider"])
	var war := (ka == player and kb == raider) or (ka == raider and kb == player)
	if not war:
		var dip: Dictionary = blockers["diplomacy"]
		war = String((dip.get("%s>%s" % [ka, kb], {}) as Dictionary).get("stance", "")) == "Enemy" \
			or String((dip.get("%s>%s" % [kb, ka], {}) as Dictionary).get("stance", "")) == "Enemy"
	cache[key] = war
	return war


## Whether two of the record's units are at war: their kingdoms are (the raider
## realm's standing units too, not only its hosts, owner 2026-10-15 R-D).
static func _enemies(blockers: Dictionary, a: String, b: String) -> bool:
	if blockers.is_empty():
		return false
	var realm: Dictionary = blockers["realm"]
	return _hostile(blockers, String(realm.get(a, "")), String(realm.get(b, "")))


## The facing from `at` toward `target` (whole metres): WarFront's whole degree.
static func _facing_to(at: Vector2i, target: Vector2i) -> int:
	return WarFront.facing_deg(Vector2(target - at))


## The news bar's line for a regiment that arrived today (owner 2026-10-06:
## 加一条军队到达目的地的新闻): its name and where it now stands. "" for a
## regiment not the player's realm's — a foreign column's march is not news.
static func arrival_headline(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("kingdom_code", "")) != repo.resolve_realm("player_realm"):
		return ""
	var blocked := String((state.regiments.get(code, {}) as Dictionary).get("road_blocked_by", ""))
	if blocked != "":
		return MissiveWriter.battle_words(repo, "army_road_blocked", {"unit": String(reg.get("label", code)),
			"blocker": String(regiment(repo, blocked, state).get("label", blocked)),
			"place": Intel.place_label(repo, state, position_of(repo, state, reg))}, state.absolute_day())
	var halted_by := String((state.regiments.get(code, {}) as Dictionary).get("halted_by", ""))
	if halted_by != "":
		return MissiveWriter.battle_words(repo, "army_halt_short", {"unit": String(reg.get("label", code)),
			"blocker": String(regiment(repo, halted_by, state).get("label", halted_by)),
			"place": Intel.place_label(repo, state, position_of(repo, state, reg))}, state.absolute_day())
	return "%s reaches %s." % [String(reg.get("label", code)),
		Intel.place_label(repo, state, position_of(repo, state, reg))]


## Where the day now running's march leaves a regiment whose state row is `entry`
## (a copy — CourierSystem.day_ahead_of; a courier's order takes effect only
## as the day ends, owner 2026-10-02), in whole metres; the map draws the piece
## walking it as the day runs (owner 2026-09-28: it lagged a day behind).
## Nothing is written but `entry`.
static func march_ahead(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		passed: Array = []) -> Vector2i:
	if entry.has("x_m"):
		_march_one(repo, state, code, entry, state.absolute_day(), _ahead_blockers(repo, state), passed)
		return Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	return pack_to_metres(repo, position_of(repo, state, regiment(repo, code, state)))


## The clearance record the day's previews share (the map asks for every piece
## when a day turns): built once per state, day and set of places, not per piece.
static var _ahead: Dictionary = {}


static func _ahead_blockers(repo: DataRepository, state: GameState) -> Dictionary:
	var sig := 0
	for table: Dictionary in [state.regiments, state.foes]:
		for c: Variant in table:
			var e: Dictionary = table[c]
			sig = hash([sig, int(e.get("x_m", 0)), int(e.get("y_m", 0))])
	for code: String in state.military_rosters:
		sig = hash([sig, code, living_count(repo, state, code)])
	for b: Dictionary in state.battles:     # a deployment's layout sets its units' radii
		sig = hash([sig, b.get("groups", {})])
	var key := hash([state.get_instance_id(), repo.get_instance_id(), state.absolute_day(), sig,
		state.regiments.size(), state.foes.size(), int(repo.bal("army_clearance_on"))])
	if int(_ahead.get("key", 0)) != key or not _ahead.has("blockers"):
		_ahead = {"key": key, "blockers": clearance_blockers(repo, state)}
	return _ahead["blockers"]


## One regiment's day on the road, written to `entry`; true when it arrives.
## It marches EVENLY, as a courier rides (owner 2026-10-06: 军队是匀速移动的，
## 如果他应该在第N天到达目的地，则应该是第N天结束的时候到达): each day only its
## share of what is left — the metres ahead over the whole days they take at
## the day's pace (march_days), rounded up — so an N-day march is covered at
## one pace over all N and ends exactly as the Nth day ends.
static func day_walk_budget(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
	if entry.is_empty() or String(entry.get("order", ORDER_STANDBY)) != ORDER_MARCH:
		return 0
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var pace := day_march_at(repo, state, code, metres_to_pack(repo, here), state.absolute_day(),
		int(entry.get("carry_days", -1)))
	if pace <= 0:
		return 0
	var left := MarchRoute.length_from(here, _path_of(entry))
	var days := int(ceil(float(left) / float(pace)))
	if days <= 1:
		return mini(pace, int(ceil(left)))
	return int(ceil(float(left) / float(days)))


## March only the entries saved when this day's movement phase began. A courier
## or AI route change later in the day must not replace today's order.
static func march_day_saved(repo: DataRepository, state: GameState, pace_divisor: int,
		substep_index: int, saved_entries: Dictionary, daily_budgets: Dictionary) -> Array:
	ensure(repo, state)
	var arrived: Array = []
	var blockers := clearance_blockers(repo, state)
	for table: Dictionary in [state.regiments, state.foes]:
		var codes: Array = table.keys().filter(func(c: Variant) -> bool: return saved_entries.has(String(c)))
		codes.sort()
		for value: Variant in codes:
			var code := String(value)
			var current := _entry_of(state, code)
			if current.is_empty():
				_note_place(blockers, code, current)
				continue
			var saved: Dictionary = saved_entries[code].duplicate(true)
			if saved.get("march_step", []) == [state.absolute_day(), substep_index]:
				_note_place(blockers, code, current)
				continue
			for battle: Dictionary in state.battles:
				BattleGroups.follow_anchor(repo, state, battle, code)
			var task := BattleTaskSystem.current(state, code)
			if not bool(current.get("battle_retreat", false)) and int(current.get("disengaging", 0)) != 1:
				var bounded_now := BattleTaskSystem.credit_pursuit(repo, state, code, 0)
				if bounded_now or task.get("status", "") == "bounded":
					if String(current.get("order", "")) == ORDER_MARCH:
						BattleSystem._halt(state, code)
					_clear_route(current)
					current.erase("departure")
					UnitGait.refresh(repo, state, code, current)
					_retire_saved_march(saved, current)
					saved_entries[code] = saved
					_note_place(blockers, code, current)
					continue
			if not BattleSystem.may_withdraw(state, code) or bool(current.get("captured", false)):
				saved["x_m"] = int(current["x_m"])
				saved["y_m"] = int(current["y_m"])
				saved["order"] = ORDER_GARRISON
				saved_entries[code] = saved
				_note_place(blockers, code, current)
				continue
			var command_changed := int(current.get("order_id", 0)) != int(saved.get("order_id", 0)) \
				or String(current.get("order", "")) != String(saved.get("order", "")) \
				or int(current.get("dest_x_m", 0)) != int(saved.get("dest_x_m", 0)) \
				or int(current.get("dest_y_m", 0)) != int(saved.get("dest_y_m", 0))
			UnitGait.refresh(repo, state, code, current)
			var budget := int(daily_budgets.get(code, 0))
			if budget <= 0 or not CampSystem.can_march_entry(current, state.absolute_day()):
				_note_place(blockers, code, current)
				continue
			var walked_today := int(saved.get("day_walked_m", 0))
			@warning_ignore("integer_division")
			var step_budget := budget / maxi(pace_divisor, 1)
			if substep_index < budget % maxi(pace_divisor, 1):
				step_budget += 1
			if substep_index == pace_divisor - 1:
				step_budget = maxi(step_budget, budget - walked_today)
			# a running substep (spec 2026-10-17 §5), paid first; packing is never shortened
			if String(saved.get("order", "")) == ORDER_MARCH \
					and UnitGait.pays_run(repo, state, code, current, pace_divisor):
				step_budget = UnitGait.run_step_m(repo, step_budget)
			var was_packing := String(current.get("camp_state", {}).get("phase", CampSystem.NONE)) == CampSystem.PACKING
			var travelled: Array = []
			var walked := _march_one(repo, state, code, saved, state.absolute_day(), blockers, [],
				pace_divisor, substep_index, budget, step_budget, travelled)
			saved["day_walked_m"] = walked_today + (int(travelled[0]) if not travelled.is_empty() else 0)
			saved_entries[code] = saved.duplicate(true)
			if int(saved.get("moved_day", -1)) == state.absolute_day():
				current["moved_day"] = state.absolute_day()
			if not command_changed:
				for key: String in ["camp_state", "departure", "moved_day"]:
					if saved.has(key):
						current[key] = saved[key]
					else:
						current.erase(key)
				if was_packing and String(current.get("camp_state", {}).get("phase", CampSystem.NONE)) != CampSystem.PACKING:
					ArmyGround.leave(repo, state, code)
			if walked:
				if state.regiments.has(code):
					var halted_by := String(saved.get("halted_by", ""))
					if command_changed:
						current["x_m"] = int(saved["x_m"])
						current["y_m"] = int(saved["y_m"])
						if String(current.get("order", "")) == ORDER_GARRISON:
							current["dest_x_m"] = int(current["x_m"])
							current["dest_y_m"] = int(current["y_m"])
							ArmyGround.settle(repo, state, code)
					else:
						_publish_march_state(current, saved)
						if halted_by == "" or not _enemies(blockers, code, halted_by):
							ArmyGround.settle(repo, state, code,
								Vector2i(int(saved["x_m"]), int(saved["y_m"])) if halted_by != "" else ArmyGround.NONE)
						if halted_by != "" and (blockers.get("pos", {}) as Dictionary).has(halted_by):
							current["facing_deg"] = _facing_to(Vector2i(int(saved["x_m"]), int(saved["y_m"])),
								(blockers["pos"] as Dictionary)[halted_by])
						if current.has("hold_after"):
							var hold: Dictionary = current["hold_after"]
							current.erase("hold_after")
							current["facing_deg"] = posmod(int(hold.get("facing", 0)), 360)
							if int(hold.get("id", 0)) >= int(current.get("stance_order_id", 0)):
								apply_hold(current, String(hold.get("stance", STANCE_DEFAULT)), -1, int(hold.get("id", 0)))
						var draft := WarDrafts.of(state, code)
						if String(draft.get("order", "")) == WarDrafts.GARRISON and not draft.has("hold"):
							WarDrafts.strike(state, code)
				else:
					var aim := Vector2i(int(saved.get("dest_x_m", 0)), int(saved.get("dest_y_m", 0)))
					var halted_by := String(saved.get("halted_by", ""))
					if halted_by != "" and not _enemies(blockers, code, halted_by):
						_spread_foe(repo, state, code, saved, aim, blockers)
					if command_changed:
						current["x_m"] = int(saved["x_m"])
						current["y_m"] = int(saved["y_m"])
					else:
						_publish_march_state(current, saved)
				if state.regiments.has(code):
					arrived.append(code)
				if command_changed:
					_retire_saved_march(saved, current)
				else:
					_publish_march_state(saved, current)
				saved_entries[code] = saved
			else:
				if command_changed:
					current["x_m"] = int(saved["x_m"])
					current["y_m"] = int(saved["y_m"])
					if substep_index >= pace_divisor - 1 and String(current.get("order", "")) == ORDER_GARRISON:
						current["dest_x_m"] = int(current["x_m"])
						current["dest_y_m"] = int(current["y_m"])
						ArmyGround.settle(repo, state, code)
						_retire_saved_march(saved, current)
				else:
					_publish_march_state(current, saved)
			if command_changed and String(current.get("order", "")) == ORDER_MARCH:
				# Today's saved walk moved the start of tomorrow's newly ordered road.
				var here := Vector2i(int(current["x_m"]), int(current["y_m"]))
				var dest := Vector2i(int(current["dest_x_m"]), int(current["dest_y_m"]))
				var waypoints := MarchRoute.from_pairs(current.get("waypoints_m", []))
				var route := route_m_of(repo, here, waypoints, dest, is_naval(repo, state, code))
				if not waypoints.is_empty() or route.size() > 1:
					current["route_m"] = MarchRoute.to_pairs(route)
				else:
					current.erase("route_m")
			# pursuit bounds (c3): a bound reached halts the march, today's saved walk included
			if not bool(current.get("battle_retreat", false)) and int(current.get("disengaging", 0)) != 1 \
					and BattleTaskSystem.credit_pursuit(repo, state, code,
						int(travelled[0]) if not travelled.is_empty() else 0,
						String(travelled[1]) if travelled.size() > 1 else ""):
				_clear_route(current)
				_retire_saved_march(saved, current)
				saved_entries[code] = saved
			saved["march_step"] = [state.absolute_day(), substep_index]
			saved_entries[code] = saved
			for battle: Dictionary in state.battles:
				BattleGroups.follow_anchor(repo, state, battle, code)
			UnitGait.refresh(repo, state, code, current)
			_note_place(blockers, code, current)
	return arrived


static func _entry_of(state: GameState, code: String) -> Dictionary:
	if state.regiments.has(code):
		return state.regiments[code]
	return state.foes.get(code, {})


static func _publish_march_state(current: Dictionary, marched: Dictionary) -> void:
	for key: String in ["x_m", "y_m", "dest_x_m", "dest_y_m", "order", "route_m", "waypoints_m",
			"waited", "waited_day", "wait_on", "halted_by", "halt_day", "halt_aim_m", "road_blocked_by"]:
		if marched.has(key):
			current[key] = marched[key]
		else:
			current.erase(key)


static func _retire_saved_march(saved: Dictionary, current: Dictionary) -> void:
	saved["x_m"] = int(current["x_m"])
	saved["y_m"] = int(current["y_m"])
	saved["dest_x_m"] = int(current["x_m"])
	saved["dest_y_m"] = int(current["y_m"])
	saved["order"] = ORDER_GARRISON
	_clear_route(saved)


static func _march_one(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		abs_day: int, blockers: Dictionary = {}, passed_out: Array = [], pace_divisor := 1,
		substep_index := 0, daily_budget := -1, step_budget := -1, travelled_out: Array = []) -> bool:
	if bool(entry.get("captured", false)):
		return false
	if not BattleSystem.may_withdraw(state, code) \
			or String(entry.get("order", ORDER_STANDBY)) != ORDER_MARCH \
			or regiment(repo, code, state).is_empty():
		return false
	if not CampSystem.can_march_entry(entry, abs_day):
		return false
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var divisor := maxi(pace_divisor, 1)
	var full := 0
	if step_budget >= 0:
		full = step_budget
	elif daily_budget >= 0:
		@warning_ignore("integer_division") # split the day's route budget over fixed substeps
		full = daily_budget / divisor
		if substep_index < daily_budget % divisor:
			full += 1
	else:
		var daily_pace := day_march_at(repo, state, code, metres_to_pack(repo, here), abs_day,
			int(entry.get("carry_days", -1)))
		if daily_pace <= 0:
			return false
		@warning_ignore("integer_division") # legacy one-call day movement, or direct substep callers
		full = daily_pace / divisor
		if substep_index < daily_pace % divisor:
			full += 1
	if full <= 0:
		return false
	# along its route when it has one (spec 2026-10-07-march-waypoints), else
	# the straight line to the end — the same sums either way
	var path := _path_of(entry)
	# the clearance (spec 2026-10-14-unit-clearance-and-scouting-design §a): the
	# day's walk stops short of an enemy or an occupied end (a halt, which is an
	# arrival), goes round any other unit it would meet, or waits behind it
	var detoured := false
	var wait_m := -1
	var waiting_on := ""
	if not blockers.is_empty() and (blockers["pos"] as Dictionary).has(code):
		var passes := 0
		var seed_names: Array = []     # the units it has gone round: later passes keep them in the clump
		while true:
			var left_p := MarchRoute.length_from(here, path)
			var days_p := int(ceil(left_p / float(full)))
			var walk_p: int = mini(full, int(ceil(left_p / float(maxi(days_p, 1))))) \
				if daily_budget < 0 else mini(left_p, full)
			var verdict := _clearance(repo, state, code, entry, here, path, walk_p, blockers, seed_names)
			var kind := String(verdict["kind"])
			if kind == "free":
				break
			if kind == "halt":
				var before_contact: Array = path.slice(0, int(verdict["leg"]))
				before_contact.append(verdict["at"])
				var approach := BattleTaskSystem.pursuit_walk(repo, state, code, entry, here, before_contact,
					ceili(MarchRoute.length_from(here, before_contact)))
				travelled_out.append(ceili(MarchRoute.length_from(here, approach["passed"] + [approach["at"]])))
				travelled_out.append(approach["pursuit_reason"])
				if String(approach["pursuit_reason"]) != "":
					_stop_pursuit(entry, approach["at"], abs_day)
					passed_out.append_array(approach["passed"])
					return false
				passed_out.append_array(before_contact.slice(0, -1))
				_halt_before(entry, verdict["at"], String(verdict["blocker"]), blockers, abs_day)
				if Vector2i(int(entry["x_m"]), int(entry["y_m"])) != here \
						and String(entry.get("camp_state", {}).get("phase", CampSystem.NONE)) == CampSystem.PACKING:
					_release_camp_on_movement(entry)
				return true
			waiting_on = String(verdict["blocker"])
			if kind == "wait":
				wait_m = int(verdict["dist"])
				break
			path = verdict["path"]
			seed_names.append_array(verdict["members"])
			detoured = true
			entry["day_detoured"] = true
			passes += 1
			if passes >= 4:
				wait_m = 0   # the way round meets one unit after another: it waits
				break
	if wait_m >= 0:
		# a column that waits two days running for a road that does not clear
		# stops where it stands (R-C): of two waiting on each other, the later
		# code; the crown is told (arrival_headline), the AI simply re-plans
		if int(entry.get("waited_day", -1)) != abs_day:
			entry["waited"] = int(entry.get("waited", 0)) + 1
			entry["waited_day"] = abs_day
		entry["wait_on"] = waiting_on
		if int(entry.get("waited", 0)) >= 2 and _gives_way(state, code, waiting_on):
			_stop_blocked(entry, here, waiting_on)
			return true
	else:
		entry.erase("waited")
		entry.erase("wait_on")
	var left := MarchRoute.length_from(here, path)
	var days := int(ceil(left / float(full)))
	var step: int = mini(full, int(ceil(left / float(maxi(days, 1))))) \
		if daily_budget < 0 else mini(full, ceili(left))
	if wait_m >= 0:
		step = mini(step, wait_m)
		days = maxi(days, 2)    # waiting behind a unit never arrives
	var walked := BattleTaskSystem.pursuit_walk(repo, state, code, entry, here, path, step)
	var at: Vector2i = walked["at"]
	var after_walk := MarchRoute.length_from(at, walked["path"])
	travelled_out.append(ceili(MarchRoute.length_from(here, walked["passed"] + [at])) \
		if bool(walked["limited"]) else maxi(0, ceili(left - after_walk)))
	travelled_out.append(walked["pursuit_reason"])
	if String(walked["pursuit_reason"]) != "":
		_stop_pursuit(entry, at, abs_day)
		passed_out.append_array(walked["passed"])
		return false
	var final_rounding_arrival := daily_budget >= 0 and substep_index == divisor - 1 \
		and bool(entry.get("finish_today", false)) and not bool(entry.get("day_detoured", false)) \
		and String(entry.get("halted_by", "")).is_empty() and after_walk <= float(divisor) \
		and not bool(walked["limited"])
	if wait_m < 0 and (walked["path"].is_empty() or (not bool(walked["limited"]) \
			and (left <= full or after_walk <= 1.0 or final_rounding_arrival))):
		entry["x_m"] = int(entry["dest_x_m"])
		entry["y_m"] = int(entry["dest_y_m"])
		if Vector2i(int(entry["x_m"]), int(entry["y_m"])) != here:
			_release_camp_on_movement(entry)
		entry["moved_day"] = abs_day
		entry["order"] = ORDER_GARRISON          # arrived: it holds the ground it was sent to
		_clear_route(entry)
		passed_out.append_array(path)
		return true
	entry["x_m"] = (walked["at"] as Vector2i).x
	entry["y_m"] = (walked["at"] as Vector2i).y
	if Vector2i(int(entry["x_m"]), int(entry["y_m"])) != here:
		_release_camp_on_movement(entry)
	entry["moved_day"] = abs_day
	passed_out.append_array(walked["passed"])
	if entry.has("route_m") or detoured:
		# new arrays, never the old ones cut: a preview walks a shallow copy
		entry["route_m"] = MarchRoute.to_pairs(walked["path"])
		var wps := MarchRoute.from_pairs(entry.get("waypoints_m", []))
		if detoured:
			wps = wps.filter(func(p: Vector2i) -> bool: return p in path)   # one the way round skipped is gone
		for p: Vector2i in walked["passed"]:
			if not wps.is_empty() and wps[0] == p:
				wps = wps.slice(1)
		if entry.has("waypoints_m") or not wps.is_empty():
			entry["waypoints_m"] = MarchRoute.to_pairs(wps)
	return false

## A pursuit limit stops advance at the physical point; camping must not snap
## it to a town slot or remove an encounter that is still in contact.
static func _stop_pursuit(entry: Dictionary, at: Vector2i, abs_day: int) -> void:
	if Vector2i(int(entry["x_m"]), int(entry["y_m"])) != at:
		_release_camp_on_movement(entry)
	entry["x_m"] = at.x
	entry["y_m"] = at.y
	entry["dest_x_m"] = at.x
	entry["dest_y_m"] = at.y
	entry["order"] = ORDER_GARRISON
	entry["moved_day"] = abs_day
	_clear_route(entry)
	drop_hold(entry)
	entry.erase("departure")


static func _release_camp_on_movement(entry: Dictionary) -> void:
	if String(entry.get("camp_state", {}).get("phase", CampSystem.NONE)) != CampSystem.PACKING:
		return
	CampSystem.departure_started(entry)
	entry.erase("departure")


## Whether a column waiting on `blocker` is the one to stop: always unless the
## blocker waits on it too and has the later code.
static func _gives_way(state: GameState, code: String, blocker: String) -> bool:
	var other: Dictionary = state.foes.get(blocker, state.regiments.get(blocker, {}))
	var mutual := String(other.get("wait_on", "")) == code and int(other.get("waited", 0)) >= 1
	return not mutual or code > blocker


## A column that gave way: halted where it stands, its road dropped, marked
## `road_blocked_by` (the news bar's "road blocked").
static func _stop_blocked(entry: Dictionary, at: Vector2i, blocker: String) -> void:
	entry["dest_x_m"] = at.x
	entry["dest_y_m"] = at.y
	entry["order"] = ORDER_GARRISON
	_clear_route(entry)
	drop_hold(entry)
	entry.erase("waited")
	entry.erase("wait_on")
	entry["road_blocked_by"] = blocker


## The clearance's verdict on a day's walk of `walk` metres along `here` ->
## `path` (whole metres): the first unit whose disc (the two arms' radii, plus a
## metre) the walk enters within today's reach; a unit already inside the disc
## stops it only if the leg closes on it. {kind "free", path} when none;
## {kind "halt", at, blocker} before a unit AT WAR with it (anywhere on the
## road), or before a unit standing within clearance of the destination, or
## one whose clump's hull holds the destination; else {kind "detour", path,
## members, blocker} round the clump of the other units (MarchClearance.detour,
## each leg checked against the march grid) or {kind "wait", dist, blocker}
## (the metres up to where it must stand) when neither side of it is open.
## `seed_names` are the units an earlier pass of the day went round: kept in the clump.
static func _clearance(repo: DataRepository, state: GameState, code: String, entry: Dictionary, here: Vector2i,
		path: Array, walk: float, blockers: Dictionary, seed_names: Array = []) -> Dictionary:
	var rs := int((blockers["r"] as Dictionary)[code])
	var dest := Vector2i(int(entry["dest_x_m"]), int(entry["dest_y_m"]))
	# only the units near today's walk can matter: a box round the part of the
	# road it can cover (wide enough for a clump's octagons once something is hit)
	var box_lo := here
	var box_hi := here
	var acc := 0.0
	var prev := here
	for p: Vector2i in path:
		box_lo = Vector2i(mini(box_lo.x, p.x), mini(box_lo.y, p.y))
		box_hi = Vector2i(maxi(box_hi.x, p.x), maxi(box_hi.y, p.y))
		acc += Vector2(prev).distance_to(Vector2(p))
		prev = p
		if acc > walk:
			break
	var near := _near_units(code, blockers, box_lo, box_hi, rs + int(blockers["maxr"]) + 8, rs)
	var hit := MarchClearance.first_entry(here, path, near["centres"], near["ds"])
	if hit.is_empty() or float(hit["dist"]) > walk:
		return {"kind": "free", "path": path}
	var margin := 3 * (rs + int(blockers["maxr"])) + 8
	near = _near_units(code, blockers, box_lo, box_hi, margin, rs)
	var names: Array = near["names"]
	var centres: Array = near["centres"]
	var ds: Array = near["ds"]
	hit = MarchClearance.first_entry(here, path, centres, ds)
	if hit.is_empty() or float(hit["dist"]) > walk:
		return {"kind": "free", "path": path}
	var bi := int(hit["index"])
	var blocker := String(names[bi])
	var dm := int(ds[bi]) + 1
	if _enemies(blockers, code, blocker) or MarchClearance.dist2(dest, centres[bi]) < dm * dm:
		return {"kind": "halt", "at": hit["at"], "leg": hit["leg"], "blocker": blocker}
	# go round: the units not at war with it whose octagons touch the first's, and each other's
	var friends: Array = []
	var friend_centres: Array = []
	var friend_ds: Array = []
	var first := 0
	for i in names.size():
		if i == bi:
			first = friends.size()
		# a clump is the first unit and the units STANDING round it; a column on the
		# march is its own obstacle (a host strung out on a road is not one wall)
		if i == bi or (not _enemies(blockers, code, String(names[i])) and not bool((blockers["moving"] as Dictionary)[names[i]])):
			friends.append(i)
			friend_centres.append(centres[i])
			friend_ds.append(ds[i])
	var members: Array = MarchClearance.clump(first, friend_centres, friend_ds, margin)
	for fi in friends.size():     # and the units an earlier pass went round
		if not fi in members and String(names[friends[fi]]) in seed_names:
			members.append(fi)
	var round_centres: Array = []
	var round_ds: Array = []
	var round_names: Array = []
	for m: int in members:
		round_centres.append(friend_centres[m])
		round_ds.append(friend_ds[m])
		round_names.append(names[friends[m]])
	var round_hull := MarchClearance.hull_of(round_centres, round_ds)
	if MarchClearance.in_hull(round_hull, dest):
		return {"kind": "halt", "at": hit["at"], "leg": hit["leg"], "blocker": blocker}
	var grid: MarchPath = null if is_naval(repo, state, code) else MarchPath.of_pack(repo)
	var leg_ok := Callable()
	if grid != null:
		leg_ok = func(a: Vector2i, b: Vector2i) -> bool:
			return grid.clear(a, b, [grid.cell_of(a), grid.cell_of(b)])
	var d := MarchClearance.detour(here, path, round_centres, round_ds, leg_ok, round_hull)
	if String(d["kind"]) == "wait":
		return {"kind": "wait", "dist": int(d["dist"]), "blocker": blocker}
	return {"kind": "detour", "path": d["path"], "members": round_names, "blocker": blocker}


## The units standing in the box round a walk, widened by `margin`: {names,
## centres, ds} with ds the pair clearance to a mover of radius `rs`.
static func _near_units(code: String, blockers: Dictionary, lo: Vector2i, hi: Vector2i, margin: int, rs: int) -> Dictionary:
	var names: Array = []
	var centres: Array = []
	var ds: Array = []
	var all_codes: Array = blockers["codes"]
	var xs: Array = blockers["xs"]
	var ys: Array = blockers["ys"]
	var rr: Array = blockers["rs"]
	var x0 := lo.x - margin
	var y0 := lo.y - margin
	var x1 := hi.x + margin
	var y1 := hi.y + margin
	for i in all_codes.size():
		var qx: int = xs[i]
		var qy: int = ys[i]
		if qx < x0 or qx > x1 or qy < y0 or qy > y1:
			continue
		var o: String = all_codes[i]
		if o == code:
			continue
		names.append(o)
		centres.append(Vector2i(qx, qy))
		ds.append(rs + int(rr[i]))
	return {"names": names, "centres": centres, "ds": ds}


## A column halted at `at` before `blocker`: an ARRIVAL there (order garrison,
## the destination here, the road and any hold parked for it dropped), marked
## `halted_by` and `halt_day`, and facing the unit.
static func _halt_before(entry: Dictionary, at: Vector2i, blocker: String, blockers: Dictionary, abs_day: int) -> void:
	entry["halt_aim_m"] = [int(entry.get("dest_x_m", at.x)), int(entry.get("dest_y_m", at.y))]   # where it was bound
	entry["x_m"] = at.x
	entry["y_m"] = at.y
	entry["dest_x_m"] = at.x
	entry["dest_y_m"] = at.y
	entry["order"] = ORDER_GARRISON
	_clear_route(entry)
	drop_hold(entry)
	entry["halted_by"] = blocker
	entry["halt_day"] = abs_day
	entry["facing_deg"] = _facing_to(at, (blockers["pos"] as Dictionary)[blocker])


## Days still on the road, rounded up; 0 for a regiment that is not marching.
## Its own route walked, as it stands.
static func days_out(repo: DataRepository, state: GameState, code: String) -> int:
	if order_of(repo, state, code) != ORDER_MARCH or day_step_m(repo, state, code) <= 0:
		return 0
	var st := state_of(repo, state, code)
	var entry := {"x_m": int(st["x_m"]), "y_m": int(st["y_m"]), "dest_x_m": int(st["dest_x_m"]),
		"dest_y_m": int(st["dest_y_m"]), "order": ORDER_MARCH}
	if st.has("route_m"):
		entry["route_m"] = (st["route_m"] as Array).duplicate(true)
	if st.has("camp_state"):
		entry["camp_state"] = (st["camp_state"] as Dictionary).duplicate(true)
	if st.has("departure"):
		entry["departure"] = (st["departure"] as Dictionary).duplicate(true)
	if MarchRoute.length_from(Vector2i(int(st["x_m"]), int(st["y_m"])), _path_of(entry)) <= 0.0:
		return 0
	return _days_walking(repo, state, code, entry, state.absolute_day() if state != null else 0)


## Whole days for a regiment to march from `from` to `to` (pack px) through
## `waypoints` (pack px, along the curve it would walk) starting on
## `start_day` (today when -1) under the load `carry` (days; -1 its own):
## the march walked day by day exactly as march_day will walk it
## (_march_one), each day on the ground and in the weather where the column
## then stands — the weather is a seeded function of the day, so the figure
## is the day it will arrive. 0 for a regiment that cannot move. `max_days` >= 0
## stops the walk there (the figure is then min(the true days, max_days)): a
## caller that only needs to know "more than N" (EnemyAi's supply reach) walks
## N + 1 days, never army_march_days_cap.
static func march_days_between(repo: DataRepository, state: GameState, code: String, from: Vector2,
		to: Vector2, start_day: int = -1, waypoints: Array = [], carry := -1, max_days: int = -1) -> int:
	if day_step_m(repo, state, code, carry) <= 0:
		return 0
	var a := pack_to_metres(repo, from)
	var b := pack_to_metres(repo, to)
	if a == b and waypoints.is_empty():
		return 0
	var entry := {"x_m": a.x, "y_m": a.y, "dest_x_m": b.x, "dest_y_m": b.y, "order": ORDER_MARCH}
	if carry >= 0:
		entry["carry_days"] = carry
	var wps: Array = []
	for w: Vector2 in waypoints:
		wps.append(pack_to_metres(repo, w))
	var route := route_m_of(repo, a, wps, b, is_naval(repo, state, code))
	if not waypoints.is_empty() or route.size() > 1:
		entry["route_m"] = MarchRoute.to_pairs(route)
	var day := (state.absolute_day() if state != null else 0) if start_day < 0 else start_day
	var unit: Dictionary = state.regiments.get(code, state.foes.get(code, {}))
	if unit.has("camp_state") and int(unit.get("x_m", a.x)) == a.x and int(unit.get("y_m", a.y)) == a.y:
		entry["camp_state"] = CampSystem.forecast_departure(unit["camp_state"], day, true)
	return _days_walking(repo, state, code, entry, day, max_days)


## Days an `entry` (a copy) takes to arrive, walked from `day`.
static func _days_walking(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		day: int, max_days: int = -1) -> int:
	var cap := int(repo.bal("army_march_days_cap"))
	if max_days >= 0:
		cap = mini(cap, max_days)
	for n in range(1, cap + 1):
		if _march_one(repo, state, code, entry, day + n - 1):
			return n
	return cap


## Whole days, rounded up, for a regiment to march `metres` at today's pace
## where it stands (day_march_m, the weather in): the card's "days out" and
## the aim ruler's figure, so the two agree. 0 for a regiment that cannot move.
static func march_days(repo: DataRepository, state: GameState, code: String, metres: float) -> int:
	var step := day_march_m(repo, state, code)
	if step <= 0:
		return 0
	return int(ceil(metres / float(step)))


## The attacker's power in the attack stance over both sides' powers, each on
## its own ground, as a float for a single pair. A battle's round is
## BattleSystem (spec 2026-10-07-enemy-ai-and-battle §4.2), which sums whole
## sides and settles in per mille with the same height factor (spec
## 2026-09-19-map3d-heights §2): the higher side's power is scaled up and the
## lower side's down by the same height_factor.
static func battle_odds(repo: DataRepository, state: GameState, attacker_code: String, defender_code: String) -> float:
	var delta := elevation_of(repo, regiment(repo, attacker_code, state), state) \
		- elevation_of(repo, regiment(repo, defender_code, state), state)
	@warning_ignore("integer_division")  # whole power, per-mille height factor
	var a := power(repo, state, attacker_code, "attack") * height_factor(repo, delta) / 1000
	@warning_ignore("integer_division")  # whole power, per-mille height factor
	var d := power(repo, state, defender_code, "defend") * height_factor(repo, -delta) / 1000
	if a + d <= 0:
		return 0.5
	return float(a) / float(a + d)

## Explicit hypothetical personnel preview; production power reads equipment.
static func power_of_personnel(repo: DataRepository, people: Dictionary, fit: int, training: int,
		morale: int, stance: String, terrain: String, works: String) -> int:
	var heads := 0
	for arm: String in repo.world_table("military", "unit_types"):
		heads += int(people.get(arm, 0))
	return _power_of_counts(repo, people, heads, fit, training, morale, stance, terrain, works)

## Explicit candidate march transaction. No production dispatcher selects these entries.
static func _body_result(status: String, reason: String, candidate: GameState = null, plan: Dictionary = {}) -> Dictionary:
	return {"status": status, "reason": reason, "candidate": candidate, "plan": plan}

static func _body_boundary(state: GameState) -> Dictionary:
	var control: Dictionary = state.day_resolution.body_march
	return {"version": 1, "abs_day": int(control.abs_day), "substep": int(control.next_substep)}

static func _body_source_error(repo: DataRepository, state: GameState) -> String:
	if repo == null or state == null: return "Missing candidate march source"
	var error := DayResolution.body_march_incompatibility_reason(state.day_resolution)
	if not error.is_empty(): return error
	var validated := UnitBodies.validate_march_candidate(repo, state, _body_boundary(state))
	if validated.status != "complete": return validated.reason
	var tx := state.day_resolution
	if int(tx.day) != state.day or int(tx.absolute_day) != state.absolute_day(): return "Candidate march day mismatch"
	var control: Dictionary = tx.body_march
	var raw: Variant = state.military_migration.get("body_motion")
	if state.military_migration.has("body_motion"):
		if not BodyMotion._saved_ok(raw): return "Invalid inner motion receipt"
		if int(raw.abs_day) > int(control.abs_day): return "Future inner motion receipt"
		if int(control.next_substep) > 0 and int(raw.abs_day) != int(control.abs_day): return "Inner motion day disagrees with outer march cursor"
		if int(raw.abs_day) == int(control.abs_day):
			if int(control.next_substep) == 0 or int(raw.substep) != int(control.next_substep) - 1:
				return "Inner motion receipt disagrees with outer march cursor"
	elif int(control.next_substep) > 0: return "Missing inner motion receipt"
	var seen := {}
	for code: Variant in tx.marching_codes:
		if not code is String or seen.has(code) or not tx.march_entries.has(code): return "Invalid frozen march membership"
		seen[code] = true
	if seen.size() != tx.march_entries.size() or seen.size() != tx.march_budgets.size(): return "Inconsistent frozen march inputs"
	for code: Variant in tx.march_entries:
		if not code is String or _entry_of(state, code).is_empty() or not tx.march_entries[code] is Dictionary \
			or not BodyMotion._natural(tx.march_budgets.get(code)) or int(tx.march_budgets[code]) > BodyMotion.LOCAL_LIMIT:
			return "Invalid frozen march entry/budget"
		if not _body_entry_ok(tx.march_entries[code]): return "Invalid raw frozen route: " + code
	for code: String in state.regiments.keys() + state.foes.keys():
		if not _body_entry_ok(_entry_of(state, code)): return "Invalid raw current route: " + code
	return _body_terrain_error(repo, state, [])

static func _body_entry_ok(entry: Dictionary) -> bool:
	if not entry.get("order") is String or entry.order not in [ORDER_MARCH, ORDER_GARRISON, ORDER_STANDBY]: return false
	for field: String in ["morale", "training"]:
		if not BodyMotion._natural(entry.get(field)): return false
	if entry.has("carry_days") and not BodyMotion._integer(entry.carry_days): return false
	for field: String in ["captured", "battle_retreat"]:
		if entry.has(field) and not entry[field] is bool: return false
	if entry.has("disengaging") and (not BodyMotion._natural(entry.disengaging) or int(entry.disengaging) > 1): return false
	for field: String in ["gait", "camp_state", "departure"]:
		if entry.has(field) and not entry[field] is Dictionary: return false
	var gait: Dictionary = entry.get("gait", {})
	for field: String in ["mode", "until", "reason", "town"]:
		if gait.has(field) and not gait[field] is String: return false
	if gait.has("battle_id") and not BodyMotion._natural(gait.battle_id): return false
	var camp: Dictionary = entry.get("camp_state", {})
	if camp.has("phase") and camp.phase not in [CampSystem.NONE, CampSystem.PACKING, CampSystem.BUILDING, CampSystem.CAMPED]: return false
	for field: String in ["move_not_before_day", "pack_start_day"]:
		if camp.has(field) and not BodyMotion._integer(camp[field]): return false
	if entry.has("event_march_after") and not BodyMotion._integer(entry.event_march_after): return false
	if entry.has("departure"):
		var departure: Dictionary = entry.departure
		for field: String in ["dest_x_m", "dest_y_m"]:
			if not BodyMotion._integer(departure.get(field)) or int(departure[field]) < -2147483648 or int(departure[field]) > 2147483647: return false
		if departure.has("waypoints_m"):
			if not departure.waypoints_m is Array: return false
			for point: Variant in departure.waypoints_m:
				if not point is Array or point.size() != 2: return false
				for coordinate: Variant in point:
					if not BodyMotion._integer(coordinate) or int(coordinate) < -2147483648 or int(coordinate) > 2147483647: return false
	for field: String in ["x_m", "y_m", "dest_x_m", "dest_y_m"]:
		if not BodyMotion._integer(entry.get(field)) or int(entry[field]) < -2147483648 or int(entry[field]) > 2147483647: return false
	for field: String in ["order_id", "day_walked_m", "supplies", "run_supply_rem"]:
		if entry.has(field) and not BodyMotion._natural(entry[field]): return false
	for field: String in ["route_m", "waypoints_m"]:
		if not entry.has(field): continue
		if not entry[field] is Array: return false
		for point: Variant in entry[field]:
			if not point is Array or point.size() != 2: return false
			for coordinate: Variant in point:
				if not BodyMotion._integer(coordinate) or int(coordinate) < -2147483648 or int(coordinate) > 2147483647: return false
	return true

static func _body_basis(repo: DataRepository, state: GameState, grid: MarchPath) -> String:
	return BodyMotion._hash([state.to_dict(), _body_boundary(state), repo.balance, repo.unit_footprints,
		repo.army_speed, repo.army_ground_speed, repo.noble_quality, repo.commanders, repo.battle_behaviors, repo.law_effects, repo.army_height_supply, repo.world_table("military", "unit_types"), repo.world_table("political", "diplomacy"),
		grid.cols, grid.rows, grid.cell_m, Array(grid.closed), Array(grid.water), grid.water_open])

static func plan_body_march_candidate(repo: DataRepository, source: GameState) -> Dictionary:
	var error := _body_source_error(repo, source)
	if not error.is_empty(): return _body_result("error", error)
	var boundary := _body_boundary(source)
	var tx := source.day_resolution
	if int(boundary.substep) == int(tx.substep_count): return _body_result("complete", "Candidate march day complete")
	var staged := _body_stage(repo, source)
	if staged.has("error"): return _body_result("error", staged.error)
	return _body_result("complete", "Planned one simultaneous body march slice", null, staged.plan)

static func commit_body_march_candidate(repo: DataRepository, source: GameState, proposed: Dictionary) -> Dictionary:
	var error := _body_source_error(repo, source)
	if not error.is_empty(): return _body_result("error", error)
	if not BodyMotion._keys(proposed, ["version", "abs_day", "substep", "basis", "motion", "units", "arrivals"]):
		return _body_result("error", "Invalid march plan schema")
	for field: String in ["version", "abs_day", "substep"]:
		if not BodyMotion._natural(proposed[field]): return _body_result("error", "Invalid raw march plan cursor")
	if int(proposed.version) != 1 or not proposed.basis is String or not proposed.motion is Dictionary \
		or not proposed.units is Array or not proposed.arrivals is Array: return _body_result("error", "Invalid march plan")
	var control: Dictionary = source.day_resolution.body_march
	var receipt := BodyMotion._hash(proposed)
	if int(proposed.abs_day) != int(control.abs_day): return _body_result("error", "Wrong march plan day")
	if not control.last.is_empty() and int(proposed.substep) == int(control.last.substep):
		if receipt != control.last.receipt or BodyMotion._hash(proposed.motion) != source.military_migration.body_motion.receipt:
			return _body_result("error", "Cursor already committed with another march plan")
		return _body_result("complete", "Already committed", UnitBodies._copy(source), proposed.duplicate(true))
	if int(proposed.substep) != int(control.next_substep) or int(control.next_substep) >= int(control.substep_count):
		return _body_result("error", "Stale or skipped march cursor")
	var staged := _body_stage(repo, source)
	if staged.has("error"): return _body_result("error", staged.error)
	if BodyMotion._hash(staged.plan) != receipt: return _body_result("error", "Stale or modified march plan")
	var candidate: GameState = staged.candidate
	var committed := BodyMotion.commit(repo, candidate, staged.plan.motion, _body_boundary(source))
	if committed.status != "complete": return _body_result("error", committed.reason)
	# BodyMotion owns only rows. Publish metadata without replacing those new rows.
	for row: Dictionary in staged.plan.units:
		var entry := _entry_of(candidate, row.unit)
		var bodies: Variant = entry.get("body_groups")
		entry.clear()
		entry.merge(row.entry_after.duplicate(true), true)
		if bodies != null: entry.body_groups = bodies
		candidate.day_resolution.march_entries[row.unit] = row.saved_entry_after.duplicate(true)
	candidate.unit_tasks = staged.tasks
	var next := int(control.next_substep) + 1
	candidate.day_resolution.substep_index = next
	candidate.day_resolution.body_march.next_substep = str(next)
	candidate.day_resolution.body_march.last = {"substep": str(int(proposed.substep)), "receipt": receipt}
	candidate.day_resolution.journal.arrivals.append_array(staged.plan.arrivals)
	error = _body_source_error(repo, candidate)
	if not error.is_empty(): return _body_result("error", "Final march validation: " + error)
	if candidate.military_cohorts != source.military_cohorts or candidate.rng.to_dict() != source.rng.to_dict():
		return _body_result("error", "March changed personnel or RNG")
	return _body_result("complete", "Committed atomic body march slice", candidate, staged.plan)

static func _body_stage(repo: DataRepository, source: GameState) -> Dictionary:
	var candidate := UnitBodies._copy(source)
	var tx := candidate.day_resolution
	var boundary := _body_boundary(source)
	var count := int(tx.substep_count)
	var slice := int(boundary.substep)
	var codes: Array = tx.march_entries.keys()
	codes.sort()
	var intents: Array = []
	var units: Array = []
	var requests := {}
	var pursuit_limits := {}
	for code: String in codes:
		var current := _entry_of(candidate, code)
		var saved: Dictionary = tx.march_entries[code].duplicate(true)
		var here: Array = [int(current.x_m), int(current.y_m)]
		var path: Array = [here]
		for point: Vector2i in _path_of(saved): path.append([point.x, point.y])
		# Full-route projection shares the real planner's local arithmetic bound.
		for point: Array in path:
			if absf(BodyMotion._difference(point[0], here[0])) > BodyMotion.LOCAL_LIMIT or absf(BodyMotion._difference(point[1], here[1])) > BodyMotion.LOCAL_LIMIT:
				return {"error": "Received route exceeds safe local sweep range"}
		# A slice limit clips intents, not the received route remaining after movement.
		requests[code] = path.duplicate(true)
		var budget := int(tx.march_budgets[code])
		var step := 0
		var allowed: bool = saved.get("order") == ORDER_MARCH and not bool(current.get("captured", false)) \
			and BattleSystem.may_withdraw(candidate, code) and CampSystem.can_march_entry(current, candidate.absolute_day()) \
			and not is_naval(repo, candidate, code)
		var task := BattleTaskSystem.current(candidate, code)
		if task.get("status", "") == "bounded": allowed = false
		if allowed:
			UnitGait.refresh(repo, candidate, code, current)
			@warning_ignore("integer_division")
			step = budget / count + (1 if slice < budget % count else 0)
			if slice == count - 1: step = maxi(step, budget - int(saved.get("day_walked_m", 0)))
			if step > 0 and UnitGait.pays_run(repo, candidate, code, current, count): step = UnitGait.run_step_m(repo, step)
			var walked := BattleTaskSystem.pursuit_walk(repo, candidate, code, current, Vector2i(here[0], here[1]), _path_of(saved), step)
			if bool(walked.limited):
				path = [here]
				for point: Vector2i in walked.passed: path.append([point.x, point.y])
				path.append([walked.at.x, walked.at.y])
				step = mini(step, BodyMotion._length(path))
				if not String(walked.pursuit_reason).is_empty():
					pursuit_limits[code] = {"at": path.back(), "reason": walked.pursuit_reason}
		if step < 0 or step > BodyMotion.LOCAL_LIMIT: return {"error": "Unsafe slice budget"}
		for body: Dictionary in UnitBodies.rows(repo, candidate, code):
			var translated: Array = []
			for point: Array in path:
				var x: int = int(point[0]) + int(body.x_m) - int(here[0])
				var y: int = int(point[1]) + int(body.y_m) - int(here[1])
				translated.append([x, y])
			intents.append({"unit": code, "slot": int(body.slot), "path_m": translated, "budget_m": step, "hostile": false})
		units.append({"unit": code, "anchor_path_m": [here], "used_m": 0, "step_budget_m": step,
			"entry_after": {}, "saved_entry_after": saved})
	var motion := BodyMotion.plan(repo, candidate, intents, int(boundary.abs_day), slice, boundary)
	if motion.cursor.is_empty(): return {"error": str(motion.reasons.get("error", "Motion refused candidate"))}
	var terrain := _body_terrain_error(repo, candidate, motion.moves)
	if not terrain.is_empty(): return {"error": terrain}
	var arrivals: Array[String] = []
	# Keep the cost-staged basis intact until BodyMotion.commit has validated it.
	var after := UnitBodies._copy(candidate)
	for row: Dictionary in units:
		var code: String = row.unit
		var current := _entry_of(after, code)
		var saved: Dictionary = row.saved_entry_after
		var path: Array = requests[code]
		var common: Array = []
		var minimum := BodyMotion.LOCAL_LIMIT + 1
		for move: Dictionary in motion.moves:
			if move.unit != code: continue
			row.used_m = maxi(int(row.used_m), int(move.used_m))
			var prefix := _body_route_prefix(path, move.path_m)
			var length := BodyMotion._length(prefix)
			if length < minimum:
				minimum = length
				common = prefix
		if common.is_empty(): common = [path[0]]
		row.anchor_path_m = common
		var at: Array = common.back()
		var remaining: Array = _body_remaining(path, common)
		var changed: bool = int(current.get("order_id", 0)) != int(saved.get("order_id", 0)) \
			or current.get("order") != saved.get("order") or current.dest_x_m != saved.dest_x_m or current.dest_y_m != saved.dest_y_m
		saved.x_m = int(at[0])
		saved.y_m = int(at[1])
		saved.route_m = remaining
		saved.day_walked_m = int(saved.get("day_walked_m", 0)) + int(row.used_m)
		saved.march_step = [int(boundary.abs_day), slice]
		if int(row.used_m) > 0:
			current.moved_day = int(boundary.abs_day)
			saved.moved_day = int(boundary.abs_day)
			_release_camp_on_movement(current)
			_release_camp_on_movement(saved)
		if remaining.is_empty() and int(row.step_budget_m) > 0 and not UnitBodies.rows(repo, after, code).is_empty() and saved.order == ORDER_MARCH:
			saved.order = ORDER_GARRISON
			_clear_route(saved)
			arrivals.append(code)
		if not changed: _publish_march_state(current, saved)
		else:
			current.x_m = int(at[0])
			current.y_m = int(at[1])
			if current.order == ORDER_GARRISON:
				current.dest_x_m = int(at[0])
				current.dest_y_m = int(at[1])
			# A later received order keeps its destination and begins from the actual anchor.
			if current.order == ORDER_MARCH:
				current.route_m = MarchRoute.to_pairs(route_m_of(repo, Vector2i(current.x_m, current.y_m),
					MarchRoute.from_pairs(current.get("waypoints_m", [])), Vector2i(current.dest_x_m, current.dest_y_m)))
		if not bool(current.get("battle_retreat", false)) and int(current.get("disengaging", 0)) != 1:
			var limit: Dictionary = pursuit_limits.get(code, {})
			var reason: String = limit.reason if not limit.is_empty() and common.back() == limit.at else ""
			if BattleTaskSystem.credit_pursuit(repo, after, code, int(row.used_m), reason): _retire_saved_march(saved, current)
		row.entry_after = current.duplicate(true)
		row.saved_entry_after = saved.duplicate(true)
		var anchor_error := _body_path_terrain(MarchPath.of_pack(repo), common, 0)
		if not anchor_error.is_empty(): return {"error": anchor_error}
	var plan := {"version": 1, "abs_day": int(boundary.abs_day), "substep": slice,
		"basis": _body_basis(repo, source, MarchPath.of_pack(repo)), "motion": motion, "units": units, "arrivals": arrivals}
	return {"candidate": candidate, "plan": plan, "tasks": after.unit_tasks}

## Match actual rejoined points to ordered requested legs; a side leg alone earns no anchor progress.
static func _body_route_prefix(path: Array, travelled: Array) -> Array:
	var ox: int = int(travelled[0][0]) - int(path[0][0])
	var oy: int = int(travelled[0][1]) - int(path[0][1])
	var best: Array = [path[0]]
	var best_cost := 0
	var travelled_cost := 0
	for index: int in range(1, travelled.size()):
		var actual: Array = travelled[index]
		travelled_cost += BodyMotion._distance_ceil(travelled[index - 1], actual)
		var point: Array = [int(actual[0]) - ox, int(actual[1]) - oy]
		for i: int in range(1, path.size()):
			var ax: int = int(path[i][0]) - int(path[i - 1][0])
			var ay: int = int(path[i][1]) - int(path[i - 1][1])
			if ax == 0 and ay == 0: continue
			var px: int = int(point[0]) - int(path[i - 1][0])
			var py: int = int(point[1]) - int(path[i - 1][1])
			if px * ay != py * ax or px * ax + py * ay < 0 or px * ax + py * ay > ax * ax + ay * ay: continue
			var prefix: Array = path.slice(0, i)
			if prefix.back() != point: prefix.append(point)
			var cost := BodyMotion._length(prefix)
			if cost >= best_cost and cost <= travelled_cost:
				best = prefix
				best_cost = cost
				break
	return best

static func _body_remaining(path: Array, prefix: Array) -> Array:
	var index := prefix.size() - 1
	while index < path.size() and prefix.back() == path[index]: index += 1
	return path.slice(index).duplicate(true)

static func _body_terrain_error(repo: DataRepository, state: GameState, moves: Array) -> String:
	var grid := MarchPath.of_pack(repo)
	if grid == null or grid.cols <= 0 or grid.rows <= 0 or grid.cell_m <= 0 \
		or grid.closed.size() != grid.cols * grid.rows or grid.water.size() != grid.closed.size() or grid.water_open:
		return "Candidate march requires a valid land terrain grid"
	var paths := {}
	for move: Dictionary in moves: paths[BodyMotion._id(move)] = move.path_m
	for code: String in state.regiments.keys() + state.foes.keys():
		if is_naval(repo, state, code): continue
		var entry := _entry_of(state, code)
		var error := _body_path_terrain(grid, [[int(entry.x_m), int(entry.y_m)]], 0)
		if not error.is_empty(): return error
		var piece := MapObjects.army_piece(repo, state.army_roster[code])
		var radius := int(repo.unit_footprints[piece].radius_m)
		for row: Dictionary in UnitBodies.rows(repo, state, code):
			var path: Array = paths.get(BodyMotion._id({"unit": code, "slot": row.slot}), [[int(row.x_m), int(row.y_m)]])
			error = _body_path_terrain(grid, path, radius)
			if not error.is_empty(): return error
	return ""

static func _body_path_terrain(grid: MarchPath, path: Array, radius: int) -> String:
	var width: int = grid.cols * grid.cell_m
	var height: int = grid.rows * grid.cell_m
	for point: Variant in path:
		if not point is Array or point.size() != 2: return "Invalid terrain path"
		for coordinate: Variant in point:
			if not BodyMotion._integer(coordinate) or int(coordinate) < -2147483648 or int(coordinate) > 2147483647: return "Terrain bounds exceed int32 coordinate range"
		if int(point[0]) < radius or int(point[1]) < radius or int(point[0]) > width - radius or int(point[1]) > height - radius:
			return "Swept body extends outside terrain bounds"
	for i: int in path.size():
		var a: Array = path[maxi(0, i - 1)]
		var b: Array = path[i]
		var left := maxi(0, floori(float(mini(int(a[0]), int(b[0])) - radius) / grid.cell_m) - 1)
		var right := mini(grid.cols - 1, floori(float(maxi(int(a[0]), int(b[0])) + radius) / grid.cell_m))
		var top := maxi(0, floori(float(mini(int(a[1]), int(b[1])) - radius) / grid.cell_m) - 1)
		var bottom := mini(grid.rows - 1, floori(float(maxi(int(a[1]), int(b[1])) + radius) / grid.cell_m))
		for y: int in range(top, bottom + 1):
			for x: int in range(left, right + 1):
				var cell := y * grid.cols + x
				if grid.closed[cell] == 0 and grid.water[cell] == 0: continue
				if _body_rect_distance(a, b, x * grid.cell_m, y * grid.cell_m, grid.cell_m) <= float(radius) * radius:
					return "Swept segment touches forbidden terrain"
	return ""

## Double-precision local segment/rectangle distance, including corner grazing.
static func _body_rect_distance(a: Array, b: Array, x: int, y: int, size: int) -> float:
	var lo := 0.0
	var hi := 1.0
	var intersects := true
	for axis: int in 2:
		var start := float(a[axis])
		var delta := float(int(b[axis]) - int(a[axis]))
		var low := float(x if axis == 0 else y)
		if delta == 0:
			if start < low or start > low + size: intersects = false
		else:
			var t0 := (low - start) / delta
			var t1 := (low + size - start) / delta
			lo = maxf(lo, minf(t0, t1))
			hi = minf(hi, maxf(t0, t1))
	if intersects and lo <= hi: return 0.0
	var best := INF
	for point: Array in [a, b]:
		var dx := maxf(maxf(x - float(point[0]), 0.0), float(point[0]) - x - size)
		var dy := maxf(maxf(y - float(point[1]), 0.0), float(point[1]) - y - size)
		best = minf(best, dx * dx + dy * dy)
	var dx := float(int(b[0]) - int(a[0]))
	var dy := float(int(b[1]) - int(a[1]))
	var squared := dx * dx + dy * dy
	for corner: Array in [[x, y], [x + size, y], [x, y + size], [x + size, y + size]]:
		var px := float(int(corner[0]) - int(a[0]))
		var py := float(int(corner[1]) - int(a[1]))
		var t := clampf((px * dx + py * dy) / squared, 0.0, 1.0) if squared > 0 else 0.0
		best = minf(best, (px - t * dx) * (px - t * dx) + (py - t * dy) * (py - t * dy))
	return best

static func _body_enemies(repo: DataRepository, state: GameState, a: String, b: String) -> bool:
	if a == b: return false
	for battle: Dictionary in state.battles:
		if not UnitBodies._live(battle): continue
		if (a in battle.att and b in battle.def) or (b in battle.att and a in battle.def): return true
	return _hostile({"player": repo.resolve_realm("player_realm"), "raider": repo.resolve_realm("raider_realm"),
		"diplomacy": repo.world_table("political", "diplomacy"), "hostile": {}},
		str(state.army_roster[a].get("kingdom_code", "")), str(state.army_roster[b].get("kingdom_code", "")))
