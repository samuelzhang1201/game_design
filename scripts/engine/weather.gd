class_name Weather
extends RefCounted
## Regional weather (owner 2026-09-27, spec 2026-09-27-courier-core §1): each
## province has one kind for a spell of weather_spell_days days, drawn from
## data/world/weather_odds.csv by season and the province's height tier. STATELESS:
## a hash of (campaign seed, province, spell) — never GameState.rng — so it
## costs the save nothing and cannot shift any other roll. It changes speed
## only: a courier's ride and a regiment's march.

const CLEAR := "clear"

static var _tiers: Dictionary = {}
static var _tiers_map := ""


static func forget() -> void:
	_tiers = {}
	_tiers_map = ""


## The spell a day falls in: whole spells of weather_spell_days from day 1.
static func spell_of(repo: DataRepository, abs_day: int) -> int:
	@warning_ignore("integer_division")  # whole spells
	return (maxi(abs_day, 1) - 1) / maxi(1, int(repo.bal("weather_spell_days")))


## A province's height tier: its seat's cell, else its first manor's; plains
## when it has neither. Cached per pack.
static func tier_of_province(repo: DataRepository, province: String) -> String:
	if _tiers_map != repo.map_id:
		_tiers = {}
		_tiers_map = repo.map_id
	if _tiers.has(province):
		return _tiers[province]
	var cell := -1
	var burg := String((repo.provinces.get(province, {}) as Dictionary).get("capital_burg", ""))
	if repo.burgs.has(burg):
		var b: Dictionary = repo.burgs[burg]
		cell = MapEconomy.cell_at(repo, Vector2(float(b["x"]), float(b["y"])))
	if not repo.cells.has(cell):
		var ids := MapManors.manors_of_province(repo, province)
		cell = int(ids[0]) if not ids.is_empty() else -1
	var tier := "plains"
	if repo.cells.has(cell):
		tier = String(Elevation.tier_of(repo, float(repo.cells[cell]["height"]))["tier"])
	_tiers[province] = tier
	return tier


## A well-mixed 32-bit hash of a text: String.hash() alone keeps too much of
## the order of nearby spells.
static func _mix(text: String) -> int:
	var h := text.hash() & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return h ^ (h >> 16)


## The weather over a province on an absolute day. No province, no state,
## or no odds for its season and tier: clear.
static func of(repo: DataRepository, state: GameState, province: String, abs_day: int) -> String:
	if province == "" or state == null:
		return CLEAR
	var key := "%s|%s" % [Calendar.season_of_day(abs_day), tier_of_province(repo, province)]
	var weights: Dictionary = repo.weather_odds.get(key, {})
	var total := 0
	for k: String in weights:
		total += int(weights[k])
	if total <= 0:
		return CLEAR
	var roll := posmod(_mix("%d|%s|%d" % [state.rng.seed_value(), province, spell_of(repo, abs_day)]), total)
	for k: String in weights:
		roll -= int(weights[k])
		if roll < 0:
			return k
	return CLEAR


## The weather at a map point: its land cell's province's, clear at sea.
static func at(repo: DataRepository, state: GameState, pack_px: Vector2, abs_day: int) -> String:
	var cell := MapEconomy.cell_at(repo, pack_px)
	if cell < 0:
		return CLEAR
	return of(repo, state, MapManors.province_of(repo, cell, state), abs_day)


static func speed_permille(repo: DataRepository, kind: String) -> int:
	return int((repo.weather_kinds.get(kind, {}) as Dictionary).get("speed_permille", 1000))


static func label_of(repo: DataRepository, kind: String) -> String:
	return String((repo.weather_kinds.get(kind, {}) as Dictionary).get("label", kind.capitalize()))


## "Clear", or "Rain (march and couriers ×0.85)".
static func describe_kind(repo: DataRepository, kind: String) -> String:
	var permille := speed_permille(repo, kind)
	if permille >= 1000:
		return label_of(repo, kind)
	return "%s (march and couriers ×%.2f)" % [label_of(repo, kind), float(permille) / 1000.0]


## Today's weather over a province, described.
static func describe(repo: DataRepository, state: GameState, province: String) -> String:
	if state == null:
		return label_of(repo, CLEAR)
	return describe_kind(repo, of(repo, state, province, state.absolute_day()))
