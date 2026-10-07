class_name ArmySystem
extends RefCounted
## The player's regiments as more than a headcount (owner 2026-09-17, spec
## docs/superpowers/specs/2026-09-17-regiment-state-design.md): morale,
## wounded, supplies and a hidden training value, stored in
## GameState.regiments, moved once a month by settle_month — but for the
## supplies, eaten a DAY at a time by eat_day (owner 2026-09-30: 军事单位的补给
## 要每天都在以一定速率减少). Every number is a whole number and every rate is
## data (balance.csv army_*).

## The pack's row for a regiment, {} when there is none.
static func regiment(repo: DataRepository, code: String) -> Dictionary:
	return repo.world_table("military", "regiments").get(code, {})

## Heads under a regiment's banner, as a whole number.
static func headcount(repo: DataRepository, reg: Dictionary) -> int:
	return int(MapObjects.regiment_size(repo, reg))

## The men able to fight: `heads` less the wounded and the dead of a regiment's
## state `st` (a state with no `dead`, an old save's, has none), never below 0.
## The pack's headcount is immutable, so the dead are a count beside it.
static func fit_heads(heads: int, st: Dictionary) -> int:
	return maxi(0, heads - maxi(0, int(st.get("wounded", 0))) - maxi(0, int(st.get("dead", 0))))

## A regiment's STRENGTH: its fit men (headcount less the wounded and the dead)
## per mille of its headcount — what its piece shows (owner 2026-09-30: 满员 / 减员 /
## 残兵, Map3DFormation). A regiment that is not the player's has no state and
## reads as it would start (full); one with no one under arms is 0.
static func fit_permille(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := regiment(repo, code)
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	var st := state_of(repo, state, code)
	@warning_ignore("integer_division")  # whole per-mille
	return fit_heads(heads, st) * 1000 / heads

## What a regiment starts a campaign with: army_start_supply_days of its use,
## in whole supplies rounded UP, so the days in hand read the days it was given
## (rounded down, a fresh regiment showed 19 of its 20).
@warning_ignore("integer_division")  # whole supplies
static func starting_state(repo: DataRepository, reg: Dictionary) -> Dictionary:
	var home := pack_to_metres(repo, Vector2(float(reg.get("x", 0)), float(reg.get("y", 0))))
	var start_days := int(repo.bal("army_start_supply_days"))
	return {
		"morale": int(repo.bal("army_start_morale")),
		"wounded": 0,
		"dead": 0,
		"supplies": (supply_use(repo, reg) * start_days + Calendar.DAYS_PER_TICK - 1) / Calendar.DAYS_PER_TICK,
		"carry_days": int(repo.bal("army_carry_default_days")),
		"training": int(repo.bal("army_start_training")),
		"x_m": home.x,
		"y_m": home.y,
		"dest_x_m": home.x,
		"dest_y_m": home.y,
		"order": ORDER_STANDBY,
		"stance": STANCE_DEFAULT,
	}

## Seeds every regiment of the player's realm that has no state yet — a new
## campaign, and an old save at its next settlement.
static func ensure(repo: DataRepository, state: GameState) -> void:
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var code := String(reg["regiment_code"])
		if not state.regiments.has(code):
			state.regiments[code] = starting_state(repo, reg)
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
	var reg := regiment(repo, code)
	if reg.is_empty() or String(reg["kingdom_code"]) != repo.resolve_realm("player_realm"):
		return {}
	if state != null and state.regiments.has(code):
		return state.regiments[code]
	return starting_state(repo, reg)

## Supplies a regiment uses in a month: the headcount's use times the height
## tier of the cell it stands on NOW (position_of; the pack's own quarters
## when `state` is null — a campaign's opening stores, a regiment with no
## state) (data/army_height_supply.csv, spec 2026-09-19-map3d-heights §2) —
## a fleet is not scaled. ONE rounding, at the end (owner review
## 2026-09-19): two per-mille divisions in a row lost heads a first
## regiment's worth of supply to truncation twice.
static func supply_use(repo: DataRepository, reg: Dictionary, state: GameState = null) -> int:
	@warning_ignore("integer_division")  # whole supplies, one rounding at the end
	return headcount(repo, reg) * int(repo.bal("army_supply_per_head_permille")) \
		* int(height_tier(repo, reg, state)["supply_permille"]) / 1_000_000

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
		var use := supply_use(repo, reg, state)
		if String(reg.get("is_naval", "0")) != "1":
			# Morale reads the stores in hand as the month turns, after the
			# supply lines refilled them and before the month is eaten. Only
			# an explicit GARRISON order earns the garrison's bonus; a column
			# merely standing by at home is supplied through the town but is
			# not behind its walls (controller ruling, final review).
			var mark := morale_mark(repo, supply_score(repo, int(entry["supplies"]), use),
				SupplySystem.garrisoned_in(repo, state, code) != "")
			entry["morale"] = drift_morale(int(entry["morale"]), mark, int(repo.bal("army_morale_drift_per_month")))
		entry["training"] = mini(100, int(entry["training"]) + int(repo.bal("army_training_per_month")))

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
		var reg := regiment(repo, code)
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

## The march's per-mille under a carried load (data/army_carry_loads.csv):
## the row with the most days not above `carry_days`; 1000 with no rows.
static func load_permille(repo: DataRepository, carry_days: int) -> int:
	var out := 1000
	for row: Dictionary in repo.army_carry_loads:
		if int(row["days"]) <= carry_days:
			out = int(row["pace_permille"])
	return out

## The map's yellow bar: days in hand over the carried load, per mille,
## capped at 1000 — it falls a little every day the column eats.
static func stores_permille(repo: DataRepository, supplies: int, use_per_month: int, carry_days: int) -> int:
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
		var reg := regiment(repo, code)
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
## reads as (data/army_morale_words.csv, highest min_score first).
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

## A burg's reach in pack px: its group's km (data/army_town_reach.csv) on
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
## town's reach, data/army_town_reach.csv); "" in the field and for a fleet.
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

## The town a land regiment is QUARTERED in: one of its own kingdom's
## (held_town_of) while it is not on the march. The map draws such a regiment
## as part of its town's garrison counter, not as a piece (owner 2026-10-06,
## choice A); "" in the field, on the march, and for a fleet.
static func quartered_in(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	if String(reg.get("is_naval", "0")) == "1":
		return ""
	if state != null and order_of(repo, state, String(reg.get("regiment_code", ""))) == ORDER_MARCH:
		return ""
	return held_town_of(repo, reg, state)

## The works a regiment fights from: "citadel", "walls" or "town" for the best
## its held town has (political/burgs.csv features), "" in the field.
static func works_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	var town := held_town_of(repo, reg, state)
	if town == "":
		return ""
	var feats := String((repo.burgs[town] as Dictionary).get("features", "")).split("|")
	if "citadel" in feats:
		return "citadel"
	if "walls" in feats:
		return "walls"
	return "town"

## An arm's modifier on a terrain, per mille (1000 when the table has no
## row); the town's works (data/army_town_defence.csv) multiply onto it for
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
	var town := String((repo.burgs[held_town_of(repo, reg, state)] as Dictionary).get("label", ""))
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
## defense) / 2, each scaled by the month's float.
static func _arm_base(repo: DataRepository, code: String, arm: String, tick: int) -> int:
	var rows: Array = repo.army_matchups.get(arm, [])
	if rows.is_empty():
		return 1000
	var sum := 0
	for m: Dictionary in rows:
		@warning_ignore("integer_division")  # whole per-mille: the arms' mean, then the float factor
		sum += (int(m["attack"]) + int(m["defense"])) / 2 * float_factor(repo, code, String(m["vs"]), tick) / 1000
	@warning_ignore("integer_division")  # the arms' whole mean
	return sum / rows.size()

## A regiment's power where it stands, in the given stance ("defend" or
## "attack"): each arm's heads less its share of the wounded and the dead, times the arm's
## base, the training and morale factors and the terrain. 0 for a regiment
## without state.
static func power(repo: DataRepository, state: GameState, code: String, stance: String) -> int:
	var reg := regiment(repo, code)
	if reg.is_empty():
		return 0
	return power_on(repo, state, code, stance, terrain_of(repo, reg, state), works_of(repo, reg, state))


## power(), on a given ground: `terrain` (terrain_at's words) and `works`
## ("citadel", "walls", "town" or ""). The WAR ROOM's slip reads a regiment
## on ground it does not stand on (spec 2026-10-07-war-room-scale-hover §4.1).
static func power_on(repo: DataRepository, state: GameState, code: String, stance: String,
		terrain: String, works: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	var fit := fit_heads(heads, st)
	var tick := 0 if state == null else state.tick
	var training_f := int(repo.bal("army_training_base_permille")) + int(st["training"]) * int(repo.bal("army_training_step_permille"))
	var morale_f := int(repo.bal("army_morale_base_permille")) + int(st["morale"]) * int(repo.bal("army_morale_step_permille"))
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
		@warning_ignore("integer_division")  # milli-heads, whole (see the note above)
		var p := n * fit * 1000 / heads
		@warning_ignore("integer_division")  # whole per-mille
		p = p * _arm_base(repo, code, arm, tick) / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * training_f / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * morale_f / 1000
		@warning_ignore("integer_division")  # whole per-mille
		p = p * terrain_factor(repo, terrain, arm, stance, works) / 1000
		@warning_ignore("integer_division")  # the ceiling of the milli-head digit
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
	@warning_ignore("integer_division")  # whole per-mille ratio against the mean
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
	var reg := regiment(repo, code)
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
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0.0
	# the ground it stands on now (spec 2026-10-06 §6); the weather is its own line
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) / 10.0 \
		* float(load_permille(repo, carry_of(repo, st))) / 1000.0 \
		* float(ground_permille(repo, reg, position_of(repo, state, reg), state)) / 1000.0


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
## (data/army_ground_speed.csv): on a road or trail, the road's row times its
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
## The battle stance (data/battle_stances.csv) a regiment starts with and an
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


## The order a regiment is under: "march", "garrison" or "standby" (no order).
static func order_of(repo: DataRepository, state: GameState, code: String) -> String:
	var entry: Dictionary = state_of(repo, state, code)
	return String(entry.get("order", ORDER_STANDBY)) if not entry.is_empty() else ORDER_STANDBY


## Where a marching regiment is headed, in pack pixels; its own position when
## it is not marching.
static func destination_of(repo: DataRepository, state: GameState, code: String) -> Vector2:
	var entry: Dictionary = state_of(repo, state, code)
	if entry.is_empty() or not entry.has("dest_x_m"):
		return position_of(repo, state, regiment(repo, code))
	return metres_to_pack(repo, Vector2i(int(entry["dest_x_m"]), int(entry["dest_y_m"])))


## The way a marching regiment faces, as a unit vector in PACK space (y down,
## as the pack's own coordinates are); Vector2.ZERO when it stands. The 3D
## pieces turn by this, so a column faces the road it is on.
static func heading_of(repo: DataRepository, state: GameState, code: String) -> Vector2:
	if order_of(repo, state, code) != ORDER_MARCH:
		return Vector2.ZERO
	var away := destination_of(repo, state, code) - position_of(repo, state, regiment(repo, code))
	return away.normalized() if away.length() > 0.0001 else Vector2.ZERO


## Metres a regiment covers in one day: pace_tenths (tenths of a km) x 100,
## under the carried load (load_permille: a heavier train marches slower).
## 0 for a banner with no one under arms, which is why an order to march is
## refused for one rather than leaving it crawling toward a place forever.
static func day_step_m(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	@warning_ignore("integer_division")  # whole metres
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) * 100 * load_permille(repo, carry_of(repo, st)) / 1000


## Metres a regiment covers TODAY (spec 2026-09-27-courier-core §1): its
## day_step_m under the weather of the province it stands in and on the ground
## under it — on `abs_day` when given (the map's preview of the next day),
## else today.
static func day_march_m(repo: DataRepository, state: GameState, code: String, abs_day: int = -1) -> int:
	return day_march_at(repo, state, code, position_of(repo, state, regiment(repo, code)), abs_day)


## day_march_m for a column standing at `at` (pack px): its day_step_m under
## that place's weather on the day and on its ground (ground_permille, spec
## 2026-10-06 §6) — a march reads where the column IS each day.
static func day_march_at(repo: DataRepository, state: GameState, code: String, at: Vector2,
		abs_day: int = -1) -> int:
	var step := day_step_m(repo, state, code)
	if step <= 0 or state == null:
		return step
	var kind := Weather.at(repo, state, at, state.absolute_day() if abs_day < 0 else abs_day)
	@warning_ignore("integer_division")  # whole metres
	step = step * Weather.speed_permille(repo, kind) / 1000
	if step <= 0:
		return step
	@warning_ignore("integer_division")  # whole metres
	return maxi(1, step * ground_permille(repo, regiment(repo, code), at, state) / 1000)


## Send a regiment to `dest` (pack pixels). The engine's only writer of a
## march order; ActionSystem calls it after ARMY_MARCH validates.
static func set_march(repo: DataRepository, state: GameState, code: String, dest: Vector2) -> void:
	ensure(repo, state)
	if not state.regiments.has(code):
		return
	var entry: Dictionary = state.regiments[code]
	var m := pack_to_metres(repo, dest)
	entry["dest_x_m"] = m.x
	entry["dest_y_m"] = m.y
	entry["order"] = ORDER_MARCH


## Halt a regiment where it stands.
static func set_garrison(repo: DataRepository, state: GameState, code: String) -> void:
	ensure(repo, state)
	if not state.regiments.has(code):
		return
	var entry: Dictionary = state.regiments[code]
	entry["order"] = ORDER_GARRISON
	entry["dest_x_m"] = int(entry["x_m"])
	entry["dest_y_m"] = int(entry["y_m"])


## One DAY of marching for every regiment under a march order, in code order,
## the player's first and then the foes' (GameState.foes).
## Returns the player's codes that arrived today, for the news bar. Straight-line: the
## column walks at its own pace toward where it was sent, and there is no
## pathfinding yet — a march ordered across a bay walks across it.
static func march_day(repo: DataRepository, state: GameState) -> Array:
	ensure(repo, state)
	var arrived: Array = []
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		if _march_one(repo, state, code, state.regiments[code], state.absolute_day()):
			arrived.append(code)
			# the column holds its ground: a halt pencilled in the war room has
			# nothing left to stop (a pencilled new march still stands)
			if String(WarDrafts.of(state, code).get("order", "")) == WarDrafts.GARRISON:
				WarDrafts.strike(state, code)
	# The foes' second pass (spec 2026-10-07-enemy-ai-and-battle §2), in code
	# order and by the same even step: a column in a battle stands; one that
	# arrives holds its ground, and a foreign column's arrival is not news, so
	# it is not in `arrived`.
	var foes := state.foes.keys()
	foes.sort()
	for c in foes:
		var code := String(c)
		if BattleSystem.battle_of(state, code).is_empty():
			_march_one(repo, state, code, state.foes[code], state.absolute_day())
	return arrived


## The news bar's line for a regiment that arrived today (owner 2026-10-06:
## 加一条军队到达目的地的新闻): its name and where it now stands. "" for a
## regiment not the player's realm's — a foreign column's march is not news.
static func arrival_headline(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := regiment(repo, code)
	if reg.is_empty() or String(reg.get("kingdom_code", "")) != repo.resolve_realm("player_realm"):
		return ""
	return "%s reaches %s." % [String(reg.get("label", code)),
		Intel.place_label(repo, state, position_of(repo, state, reg))]


## Where the day now running's march leaves a regiment whose state row is `entry`
## (a copy — CourierSystem.day_ahead_of; a courier's order takes effect only
## as the day ends, owner 2026-10-02), in whole metres; the map draws the piece
## walking it as the day runs (owner 2026-09-28: it lagged a day behind).
## Nothing is written but `entry`.
static func march_ahead(repo: DataRepository, state: GameState, code: String, entry: Dictionary) -> Vector2i:
	if entry.has("x_m"):
		_march_one(repo, state, code, entry, state.absolute_day())
		return Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	return pack_to_metres(repo, position_of(repo, state, regiment(repo, code)))


## One regiment's day on the road, written to `entry`; true when it arrives.
## It marches EVENLY, as a courier rides (owner 2026-10-06: 军队是匀速移动的，
## 如果他应该在第N天到达目的地，则应该是第N天结束的时候到达): each day only its
## share of what is left — the metres ahead over the whole days they take at
## the day's pace (march_days), rounded up — so an N-day march is covered at
## one pace over all N and ends exactly as the Nth day ends.
static func _march_one(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		abs_day: int) -> bool:
	if String(entry.get("order", ORDER_STANDBY)) != ORDER_MARCH or regiment(repo, code).is_empty():
		return false
	var here := Vector2(float(entry["x_m"]), float(entry["y_m"]))
	var full := day_march_at(repo, state, code, metres_to_pack(repo, Vector2i(here)), abs_day)
	if full <= 0:
		return false
	var dest := Vector2(float(entry["dest_x_m"]), float(entry["dest_y_m"]))
	var left := here.distance_to(dest)
	var days := int(ceil(left / float(full)))
	var step := mini(full, int(ceil(left / float(maxi(days, 1)))))
	if days <= 1:
		entry["x_m"] = int(entry["dest_x_m"])
		entry["y_m"] = int(entry["dest_y_m"])
		entry["order"] = ORDER_GARRISON          # arrived: it holds the ground it was sent to
		return true
	var way := (dest - here) / left
	entry["x_m"] = int(round(here.x + way.x * float(step)))
	entry["y_m"] = int(round(here.y + way.y * float(step)))
	return false


## Days still on the road, rounded up; 0 for a regiment that is not marching.
static func days_out(repo: DataRepository, state: GameState, code: String) -> int:
	if order_of(repo, state, code) != ORDER_MARCH:
		return 0
	return march_days_between(repo, state, code, position_of(repo, state, regiment(repo, code)),
		destination_of(repo, state, code))


## Whole days for a regiment to march from `from` to `to` (pack px) starting
## on `start_day` (today when -1): the march walked day by day exactly as
## march_day will walk it (_march_one), each day on the ground and in the
## weather where the column then stands — the weather is a seeded function of
## the day, so the figure is the day it will arrive. 0 for a regiment that
## cannot move.
static func march_days_between(repo: DataRepository, state: GameState, code: String, from: Vector2,
		to: Vector2, start_day: int = -1) -> int:
	if day_step_m(repo, state, code) <= 0:
		return 0
	var a := pack_to_metres(repo, from)
	var b := pack_to_metres(repo, to)
	if a == b:
		return 0
	var entry := {"x_m": a.x, "y_m": a.y, "dest_x_m": b.x, "dest_y_m": b.y, "order": ORDER_MARCH}
	var day := (state.absolute_day() if state != null else 0) if start_day < 0 else start_day
	var cap := int(repo.bal("army_march_days_cap"))
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
	var delta := elevation_of(repo, regiment(repo, attacker_code), state) \
		- elevation_of(repo, regiment(repo, defender_code), state)
	@warning_ignore("integer_division")  # whole power, per-mille height factor
	var a := power(repo, state, attacker_code, "attack") * height_factor(repo, delta) / 1000
	@warning_ignore("integer_division")  # whole power, per-mille height factor
	var d := power(repo, state, defender_code, "defend") * height_factor(repo, -delta) / 1000
	if a + d <= 0:
		return 0.5
	return float(a) / float(a + d)
