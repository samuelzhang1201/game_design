extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The truth and the claim (spec 2026-09-30-ledger-governors-design §3):
## a flow runs as its governor runs it — his skill and opinion set how much
## is made, a venal man skims a share of it — and he reports it whole.

var data: DataRepository
var s: GameState
var cell := -1

func before_each() -> void:
	data = SuiteData.repo()
	assert_not_null(data, DataRepository.last_error)
	s = SuiteData.campaign(data, 42)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")
	s.metrics["lord_civil"] = 100.0
	# the supply lines are the regiments' own now: the first land regiment
	# runs one (spec 2026-10-07-army-supply-lines)
	s.supply_lines[_first_land()] = SupplyLines._new_record(TownStores.realm_towns(data, s)[0], 1000, 1)
	s.supply_lines[_first_land()]["state"] = SupplyLines.FLOWING

func after_each() -> void:
	RealmEconomy.forget()

func _govern(seat: String, skill: String, value: int, traits: Array) -> Character:
	var c: Character = s.characters[String(s.council[seat])]
	c.skills[skill] = value
	c.opinion = 50
	c.traits = traits
	c.attributes["integrity"] = 50
	return c

func _first_land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

## A day of `code`'s line with its town well stocked: the line's month counters.
func _a_day_of_the_line(code: String) -> Dictionary:
	var ln: Dictionary = s.supply_lines[code]
	s.town_stock[String(ln["town"])] = {"crown": 100000, "lord": 0, "house": 0}
	TownStores.sync_metrics(data, s)
	s.regiments[code]["supplies"] = 0
	SupplyLines.day_step(data, s)
	return s.supply_lines[code]

func _sum(rows: Array, key: String) -> int:
	var total := 0
	for row: Dictionary in rows:
		total += int(row[key])
	return total

## Workshop take = capacity 40 × rate 1000 / 1000 = 40 civil goods.
## Skill 16: 850 + (16 − 8) × 20 = 1010‰, clamped to 1000.
## made = 40 × 700 × 1000 / 10⁶ = 28; skimmed = 28 × 200 / 1000 = 5.6 → 5.
func test_a_venal_steward_skims_the_workshops_and_reports_them_whole() -> void:
	var st := _govern("steward", "sk_steward", 16, ["venal"])
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["efficiency"]), 1000)
	assert_eq(int(row["skim"]), 200)
	assert_eq(String(row["governor"]), st.id)
	assert_eq(int(row["made"]), 28)
	assert_eq(int(row["skimmed"]), 5, "a fifth of 28, whole gold")
	assert_eq(int(row["make"]), 23, "what reaches the lord's stores: 28 − 5")
	assert_eq(int(row["claimed"]), 28, "what he reports")
	var lines := WorkshopSystem.settle_month(data, s)
	assert_eq(lines[1], {"metric": "lord_strategic", "delta": 23,
		"reason": "the war workshops make strategic goods"}, "the lord's stores take only what reached them")
	assert_eq(s.skims[st.id], {"workshop": 5}, "kept under the flow he skimmed")
	WorkshopSystem.settle_month(data, s)
	assert_eq(Governance.skimmed_on(s, st.id, "workshop"), 10, "a skim adds up month on month")

## Skill 8: 850 + 0 = 850‰. made = 40 × 700 × 850 / 10⁶ = 23.8 → 23.
func test_a_clumsy_steward_makes_less_and_says_so() -> void:
	var st := _govern("steward", "sk_steward", 8, [])
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["efficiency"]), 850)
	assert_eq(int(row["made"]), 23, "28 × 850‰, whole")
	assert_eq(int(row["make"]), 23)
	assert_eq(int(row["claimed"]), 23)
	assert_eq(int(row["skimmed"]), 0)
	WorkshopSystem.settle_month(data, s)
	assert_false(s.skims.has(st.id), "an honest man skims nothing")

## Integrity 20 < gov_skim_integrity_below 30, no trait: skims 100‰.
## made 28 (skill 16); skimmed = 28 × 100 / 1000 = 2.8 → 2.
func test_a_man_of_low_integrity_skims_less() -> void:
	var st := _govern("steward", "sk_steward", 16, [])
	st.attributes["integrity"] = 20
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["skim"]), 100)
	assert_eq(int(row["skimmed"]), 2)
	assert_eq(int(row["make"]), 26)

## An empty seat: nobody governs, efficiency min_permille 600.
## made = 40 × 700 × 600 / 10⁶ = 16.8 → 16; nobody's purse is kept.
func test_an_ungoverned_workshop_runs_at_the_floor_and_skims_for_nobody() -> void:
	s.council["steward"] = ""
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(String(row["governor"]), "")
	assert_eq(int(row["made"]), 16)
	assert_eq(int(row["skimmed"]), 0)
	WorkshopSystem.settle_month(data, s)
	assert_false(s.skims.has(""))

## Supply: skimmed = the draw × 200 / 1000; the town gives the full draw,
## less reaches the ranks than he reports (the claim as if nothing were skimmed).
func test_a_venal_marshal_skims_the_supply_gold() -> void:
	var m := _govern("marshal", "sk_admin", 16, ["venal"])
	var rows := SupplySystem.plan(data, s)
	var row: Dictionary = rows[0]
	assert_gt(int(row["paid"]), 0)
	assert_eq(String(row["governor"]), m.id)
	@warning_ignore("integer_division")
	assert_eq(int(row["skimmed"]), TownStores.gold_of_units(data, int(row["need"]) * 200 / 1000))
	@warning_ignore("integer_division")
	assert_eq(int(row["claimed"]), int(row["need"]) * (1000 - int(row["loss_permille"])) / 1000,
		"he reports the draw as if nothing were skimmed")
	assert_lt(int(row["delivered"]), int(row["claimed"]), "less reaches the ranks than he reports")
	# a day's skim is whole units: the hungriest regiment's line, so a fifth
	# of one day's draw is at least one
	var big := _first_land()
	for c in s.regiments.keys():
		var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, String(c)), s)
		if use > ArmySystem.supply_use(data, ArmySystem.regiment(data, big), s):
			big = String(c)
	s.supply_lines[big] = (s.supply_lines[_first_land()] as Dictionary).duplicate(true)
	var ln := _a_day_of_the_line(big)
	assert_gt(int(ln["m_skim"]), 0)
	@warning_ignore("integer_division")
	assert_eq(int(ln["m_skim"]), int(ln["m_drawn"]) * 200 / 1000, "the day's draw, skimmed")
	assert_lt(int(ln["m_arrived"]), int(ln["m_claimed"]))

func test_an_honest_able_marshal_delivers_what_he_says() -> void:
	var m := _govern("marshal", "sk_admin", 16, ["honest"])
	for row: Dictionary in SupplySystem.plan(data, s):
		assert_eq(int(row["skimmed"]), 0)
		assert_eq(int(row["delivered"]), int(row["claimed"]))
	var ln := _a_day_of_the_line(_first_land())
	assert_gt(int(ln["m_drawn"]), 0)
	assert_eq(int(ln["m_skim"]), 0)
	assert_eq(int(ln["m_arrived"]), int(ln["m_claimed"]))
	assert_false(s.skims.has(m.id))

## A clumsy marshal (skill 4: 850 − 80 = 770‰) delivers less than the
## need, and says so: the claim carries his efficiency too.
func test_a_clumsy_marshal_delivers_less_and_says_so() -> void:
	_govern("marshal", "sk_admin", 4, [])
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	assert_eq(int(row["efficiency"]), 770)
	assert_eq(int(row["delivered"]), int(row["claimed"]))
	assert_lt(int(row["delivered"]), int(row["need"]))


# --- Task 2's missing cases (final review) --------------------------------------

## A clumsy AND venal steward: the skim is taken from what his skill made.
## Skill 8: 850‰. made = 40 × 700 × 850 / 10⁶ = 23.8 → 23; skimmed =
## 23 × 200 / 1000 = 4.6 → 4; make = 19; he reports 23.
func test_a_clumsy_venal_steward_skims_what_he_made() -> void:
	var st := _govern("steward", "sk_steward", 8, ["venal"])
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["efficiency"]), 850)
	assert_eq(int(row["made"]), 23)
	assert_eq(int(row["skimmed"]), 4)
	assert_eq(int(row["make"]), 19)
	assert_eq(int(row["claimed"]), 23)
	WorkshopSystem.settle_month(data, s)
	assert_eq(Governance.skimmed_on(s, st.id, "workshop"), 4)
