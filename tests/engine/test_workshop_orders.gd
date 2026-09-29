extends GutTest
## WORKSHOP_RATE (spec 2026-09-30-ledger-supply-design §2).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")

func test_the_rate_is_set_and_costs_the_stewards_goodwill() -> void:
	var req := ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 500})
	assert_eq(sys.validate(req, s), "")
	var before := OrderCosts.snapshot_opinions(s)
	var out := sys.execute(req, s)
	assert_eq(WorkshopSystem.rate_of(s, cell), 500)
	assert_true(OrderCosts.has_cost(data, s, out["effects"], out["drift"], before), "the order left a cost")

func test_refusals() -> void:
	assert_ne(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 700}), s), "", "no such rate")
	assert_ne(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 1000}), s), "", "already in full")
	var bare := int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[1])
	assert_string_contains(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": bare, "rate": 0}), s), "no war workshop")

func test_the_order_is_catalogued() -> void:
	assert_true(data.actions.has("WORKSHOP_RATE"))
	assert_true(data.order_costs.has("WORKSHOP_RATE"))
