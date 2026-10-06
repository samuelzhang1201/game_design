class_name WorkshopSystem
extends RefCounted
## The war workshops (spec 2026-09-30-ledger-supply-design §2): each standing
## war workshop turns up to workshop_capacity_gold of the LORD's civil goods
## a month, times its rate, into workshop_ratio_permille as much strategic
## goods. Whole gold, cell order; plan() is the one function the tick, the
## cards and the LEDGER read.

const BUILDING := "war_workshop"


## A war workshop works for the LORD only while the crown's own house holds
## its manor: sold or seized away, it stands idle (owner ruling 2026-09-30).
static func cells(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for key: String in state.manor_buildings:
		var cell := int(key)
		if BUILDING in (state.manor_buildings[key] as Array) and MapManors.is_crowns(repo, state, cell):
			out.append(cell)
	out.sort()
	return out


## The rate a workshop runs at, per mille; 1000 (in full, the default) for
## a cell with no war workshop standing — a rate never outlives its
## workshop (final review), whatever the state still holds.
static func rate_of(state: GameState, cell: int) -> int:
	if not BUILDING in MapManors.buildings_of(state, cell):
		return 1000
	return int(state.workshop_rate.get(str(cell), 1000))


static func set_rate(state: GameState, cell: int, rate: int) -> void:
	if rate == 1000:
		state.workshop_rate.erase(str(cell))
	else:
		state.workshop_rate[str(cell)] = rate


## Forget a cell's rate: its workshop is pulled down, or its manor has left
## the crown (MapManors.demolish / set_owner).
static func forget(state: GameState, cell: int) -> void:
	state.workshop_rate.erase(str(cell))


## The rates WORKSHOP_RATE accepts (data/workshop_rates.csv), lowest first.
static func rates(repo: DataRepository) -> Array:
	var out: Array = []
	for row: Dictionary in repo.workshop_rates:
		out.append(int(row["rate_permille"]))
	return out


## "cold" / "at half" / "in full" — the table's word for a rate.
static func rate_word(repo: DataRepository, rate: int) -> String:
	for row: Dictionary in repo.workshop_rates:
		if int(row["rate_permille"]) == rate:
			return String(row["word"])
	return "at %d per mille" % rate


## Cell order, running out the lord's civil goods as it goes. Never reaches
## into anyone's civil goods but the LORD's, and never takes more than what
## is left once every cell before it has taken its share. The workshops run
## as their governor runs them (spec 2026-09-30-ledger-governors-design §3):
## `made` = take × ratio × his efficiency / 10⁶ is the truth, `skimmed` =
## made × his skim / 1000 goes into his own purse, `make` = made − skimmed
## is what REACHES the lord's strategic goods, and `claimed` = made is what
## he reports — the flow whole. Rows: {cell, rate, take, made, skimmed,
## make, claimed, efficiency, skim, governor}.
static func plan(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var left := maxi(int(state.metrics.get("lord_civil", 0.0)), 0)
	var cap := int(repo.bal("workshop_capacity_gold"))
	var ratio := int(repo.bal("workshop_ratio_permille"))
	var g := Governance.factors(repo, state, "workshop")
	var eff := int(g["efficiency"])
	var skim := int(g["skim"])
	var governor := String(g["governor"])
	for cell: int in cells(repo, state):
		var rate := rate_of(state, cell)
		@warning_ignore("integer_division")
		var take := mini(cap * rate / 1000, left)
		left -= take
		@warning_ignore("integer_division")
		var made := take * ratio * eff / 1000000
		@warning_ignore("integer_division")
		var skimmed := made * skim / 1000
		out.append({"cell": cell, "rate": rate, "take": take, "made": made, "skimmed": skimmed,
			"make": made - skimmed, "claimed": made, "efficiency": eff, "skim": skim, "governor": governor})
	return out


## The month's lines for the tick to apply (it owns the report).
## What the governor skims goes to his own purse (GameState.skims), never
## to the lord's stores.
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var took := 0
	var reached := 0
	var rows := plan(repo, state)
	for row: Dictionary in rows:
		took += int(row["take"])
		reached += int(row["make"])
	Governance.add_skims(state, rows, "workshop")
	# Its goods are stored in the workshop's own town (spec 2026-10-07-army-
	# supply-lines §3.1); the line below raises the lord's metric by the same.
	for row: Dictionary in rows:
		TownStores.add(state, TownStores.town_of_cell(repo, state, int(row["cell"])), "lord",
			int(row["make"]) * TownStores.units_per_gold(repo))
	if took == 0:
		return []
	return [{"metric": "lord_civil", "delta": -took, "reason": "the war workshops take civil goods"},
		{"metric": "lord_strategic", "delta": reached, "reason": "the war workshops make strategic goods"}]
