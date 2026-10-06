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

## A regiment's STRENGTH: its fit men (headcount less the wounded) per mille
## of its headcount — what its piece shows (owner 2026-09-30: 满员 / 减员 /
## 残兵, Map3DFormation). A regiment that is not the player's has no state and
## reads as it would start (full); one with no one under arms is 0.
static func fit_permille(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := regiment(repo, code)
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	var st := state_of(repo, state, code)
	var wounded := clampi(int(st.get("wounded", 0)), 0, heads)
	@warning_ignore("integer_division")  # whole per-mille
	return (heads - wounded) * 1000 / heads

## What a regiment starts a campaign with.
static func starting_state(repo: DataRepository, reg: Dictionary) -> Dictionary:
	var home := pack_to_metres(repo, Vector2(float(reg.get("x", 0)), float(reg.get("y", 0))))
	return {
		"morale": int(repo.bal("army_start_morale")),
		"wounded": 0,
		"supplies": supply_use(repo, reg) * int(repo.bal("army_start_supply_months")),
		"training": int(repo.bal("army_start_training")),
		"x_m": home.x,
		"y_m": home.y,
		"dest_x_m": home.x,
		"dest_y_m": home.y,
		"order": ORDER_STANDBY,
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

## A regiment's state for reading: the stored one, else what it would start
## with. Never writes. {} for a regiment that is not the player's.
static func state_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
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


## What is still to be eaten of `use` after day `day` of the month: the
## supply lines refill against the stores the month's END will leave
## (SupplySystem.plan), so their projection holds all month.
static func left_to_eat(use: int, day: int) -> int:
	@warning_ignore("integer_division")  # the same whole split as day_bite
	return use - use * clampi(day, 0, Calendar.DAYS_PER_TICK) / Calendar.DAYS_PER_TICK


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
		var entry: Dictionary = state.regiments[code]
		entry["supplies"] = maxi(0, int(entry["supplies"]) - day_bite(supply_use(repo, reg, state), state.day))


## A regiment's stores per mille of a FULL train — army_supply_target_months
## of its use, what the supply lines refill it to — capped at 1000: the map's
## yellow bar, which therefore falls day by day as the month is eaten (the
## supply SCORE, over army_speed_supply_full_months, stays full for the first
## of those months and would not show it).
static func stores_permille(repo: DataRepository, supplies: int, use_per_month: int) -> int:
	if use_per_month <= 0:
		return 1000
	var full := maxi(1, int(repo.bal("army_supply_target_months")))
	@warning_ignore("integer_division")  # whole per-mille of a full train
	return clampi(maxi(supplies, 0) * 1000 / (use_per_month * full), 0, 1000)


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
	var id := MapEconomy.cell_at(repo, position_of(repo, state, reg))
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
static func is_fortified(repo: DataRepository, reg: Dictionary, state: GameState = null) -> bool:
	if String(reg.get("is_naval", "0")) == "1":
		return false
	var id := MapEconomy.cell_at(repo, position_of(repo, state, reg))
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
		@warning_ignore("integer_division")  # whole per-mille factor
		f = f * int((repo.army_terrain.get("fortified|%s" % arm, {}) as Dictionary).get("defend", 1000)) / 1000
	return f

## "Hills", or "Hills (fortified)".
static func terrain_label(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
	var text := terrain_of(repo, reg, state).capitalize()
	return text + " (fortified)" if is_fortified(repo, reg, state) else text

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
	var terrain := terrain_of(repo, reg, state)
	var walls := is_fortified(repo, reg, state)
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
		p = p * terrain_factor(repo, terrain, arm, stance, walls) / 1000
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


## Supplies as a score, per mille: the months in hand over
## army_speed_supply_full_months, capped at 1000. A banner that uses nothing
## never runs short.
static func supply_score(repo: DataRepository, supplies: int, use_per_month: int) -> int:
	if use_per_month <= 0:
		return 1000
	var full := maxi(1, int(repo.bal("army_speed_supply_full_months")))
	@warning_ignore("integer_division")  # whole per-mille of a full supply train
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
	@warning_ignore("integer_division")  # the weighted mean, whole per-mille
	return (wa * 1000 + ws * clampi(supply_permille, 0, 1000)
		+ wm * clampi(morale, 0, 100) * 10 + wt * clampi(training, 0, 100) * 10) / total


## The two bars over a regiment on the map (owner 2026-09-27: 红色是健康度 — 综合
## 战备, the readiness — 黄色是战略补给数), per mille: Vector2i(readiness,
## stores against a full train, stores_permille — it falls every day). A
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
		stores_permille(repo, int(st["supplies"]), use))


## The march in TENTHS of a km a day: base_km x 10 x readiness / 1000.
static func pace_tenths(repo: DataRepository, base_km: int, supply_permille: int, morale: int,
		training: int) -> int:
	@warning_ignore("integer_division")  # whole tenths of a km
	return base_km * 10 * readiness_permille(repo, supply_permille, morale, training) / 1000


## A regiment's march in km a day, from its arms and its state; 0 for a
## regiment that is not the player's (no state) or has no one under arms.
static func speed_km_per_day(repo: DataRepository, state: GameState, code: String) -> float:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0.0
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) / 10.0


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
	var entry: Dictionary = state.regiments.get(String(reg.get("regiment_code", "")), {})
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


## Metres a regiment covers in one day: pace_tenths (tenths of a km) x 100.
## 0 for a banner with no one under arms, which is why an order to march is
## refused for one rather than leaving it crawling toward a place forever.
static func day_step_m(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) * 100


## Metres a regiment covers TODAY (spec 2026-09-27-courier-core §1): its
## day_step_m under the weather of the province it stands in — on `abs_day`
## when given (the map's preview of the next day), else today.
static func day_march_m(repo: DataRepository, state: GameState, code: String, abs_day: int = -1) -> int:
	var step := day_step_m(repo, state, code)
	if step <= 0 or state == null:
		return step
	var kind := Weather.at(repo, state, position_of(repo, state, regiment(repo, code)),
		state.absolute_day() if abs_day < 0 else abs_day)
	@warning_ignore("integer_division")  # whole metres
	return step * Weather.speed_permille(repo, kind) / 1000


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


## One DAY of marching for every regiment under a march order, in code order.
## Returns the codes that arrived today, for the news bar. Straight-line: the
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
	return arrived


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
	var full := day_march_m(repo, state, code, abs_day)
	if full <= 0:
		return false
	var here := Vector2(float(entry["x_m"]), float(entry["y_m"]))
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
	var k := float(metres_per_pack_px(repo))
	var left := position_of(repo, state, regiment(repo, code)) \
		.distance_to(destination_of(repo, state, code)) * k
	return march_days(repo, state, code, left)


## Whole days, rounded up, for a regiment to march `metres` at today's pace
## where it stands (day_march_m, the weather in): the card's "days out" and
## the aim ruler's figure, so the two agree. 0 for a regiment that cannot move.
static func march_days(repo: DataRepository, state: GameState, code: String, metres: float) -> int:
	var step := day_march_m(repo, state, code)
	if step <= 0:
		return 0
	return int(ceil(metres / float(step)))


## PLACEHOLDER (owner 2026-09-17: the battle formula is not decided). The
## attacker's power in the attack stance over both sides' powers, each on its
## own ground. Called by nothing but its test; replace it whole when the
## owner settles the formula. Height is its first settled factor (spec
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
