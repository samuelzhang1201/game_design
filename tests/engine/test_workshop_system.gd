extends GutTest
## The war workshop (spec 2026-09-30-ledger-supply-design §2): the lord's
## civil goods into strategic goods, capacity × rate, at a loss.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _home_cells(n: int) -> Array:
	var cells: Array = MapManors.manors_of_province(data, MapManors.home_province(data, s), s)
	return cells.slice(0, n)

func _build(cell: int) -> void:
	assert_true(MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop"))

## A house of the realm that is not the crown's, for moving a manor away
## from the crown's hold.
func _another_family() -> String:
	var realm := data.resolve_realm("player_realm")
	for province: String in MapOwnership.provinces_of(data, s, realm):
		for cell: int in MapManors.manors_of_province(data, province):
			if not MapManors.is_crowns(data, s, cell):
				return MapManors.owner_of(data, s, cell)
	return ""

func test_the_building_row_exists() -> void:
	var row: Dictionary = data.manor_buildings["war_workshop"]
	assert_eq(String(row["land"]), "town")
	assert_eq(String(row["prereq"]), "smithy")
	assert_eq(int(row["civil_cost"]), 180)

func test_one_workshop_at_full_takes_its_capacity() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.plan(data, s), [{"cell": cell, "rate": 1000, "take": 40, "make": 28}])

func test_half_rate_halves_it() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	WorkshopSystem.set_rate(s, cell, 500)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.plan(data, s)[0], {"cell": cell, "rate": 500, "take": 20, "make": 14})

func test_the_lords_civil_goods_run_out_in_cell_order() -> void:
	var cells := _home_cells(2)
	for c: int in cells:
		_build(c)
	s.metrics["lord_civil"] = 50.0
	var p := WorkshopSystem.plan(data, s)
	cells.sort()
	assert_eq(p[0]["cell"], cells[0])
	assert_eq([p[0]["take"], p[1]["take"]], [40, 10])
	assert_eq([p[0]["make"], p[1]["make"]], [28, 7])
	s.metrics["lord_civil"] = -5.0
	assert_eq(WorkshopSystem.plan(data, s)[0]["take"], 0, "a debt takes nothing")

func test_settlement_moves_the_goods_with_reasons() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.settle_month(data, s), [
		{"metric": "lord_civil", "delta": -40, "reason": "the war workshops take civil goods"},
		{"metric": "lord_strategic", "delta": 28, "reason": "the war workshops make strategic goods"}])
	WorkshopSystem.set_rate(s, cell, 0)
	assert_eq(WorkshopSystem.settle_month(data, s), [], "a cold workshop moves nothing")

func test_the_tick_runs_the_workshops() -> void:
	var twin := GameState.from_dict(s.to_dict())
	var cell: int = _home_cells(1)[0]
	_build(cell)
	for st: GameState in [s, twin]:
		st.metrics["lord_civil"] = 1000.0
		st.metrics["strategic"] = 100000.0
	var eng := TickEngine.new(data)
	eng.advance(s)
	RealmEconomy.forget()
	eng.advance(twin)
	assert_eq(int(s.metrics["lord_strategic"]) - int(twin.metrics["lord_strategic"]), 28)
	assert_eq(int(s.metrics["lord_civil"]) - int(twin.metrics["lord_civil"]), -40)

func test_a_workshop_sold_away_works_for_nobody() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	s.metrics["lord_civil"] = 100.0
	var family := _another_family()
	assert_ne(family, "", "the realm has another house to sell to")
	assert_true(MapManors.set_owner(data, s, cell, family, "a test sale"))
	assert_eq(WorkshopSystem.plan(data, s), [], "no workshop is the crown's any more")
	assert_eq(WorkshopSystem.settle_month(data, s), [], "a workshop not the crown's takes and makes nothing")

func test_workshop_rates_survive_a_save() -> void:
	var cell: int = _home_cells(1)[0]
	WorkshopSystem.set_rate(s, cell, 500)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(WorkshopSystem.rate_of(back, cell), 500)
	WorkshopSystem.set_rate(back, cell, 1000)
	assert_false(back.workshop_rate.has(str(cell)), "full is the default and is not stored")
	var old := s.to_dict()
	old.erase("workshop_rate")
	assert_eq(WorkshopSystem.rate_of(GameState.from_dict(old), cell), 1000, "an old save runs every workshop in full")
