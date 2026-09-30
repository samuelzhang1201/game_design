extends GutTest
## Markets and trade routes (spec 2026-09-30-ledger-industry-trade-design, M6).

var data: DataRepository
var s: GameState
var realm := ""
var sys: ActionSystem

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	realm = data.resolve_realm("player_realm")
	_able_honest_steward()
	RealmEconomy.forget()
	MarketSystem.forget()

func after_each() -> void:
	RealmEconomy.forget()
	MarketSystem.forget()

## An able, honest steward: efficiency 1000, no skim — so a toll is the
## plain arithmetic value × trade_toll_permille / 1000.
func _able_honest_steward() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.skills["sk_steward"] = 16
	st.opinion = 50
	st.traits = []
	st.attributes["integrity"] = 50

## Another kingdom than the player's, by code order.
func _other_kingdom() -> String:
	var codes: Array = data.kingdoms.keys()
	codes.sort()
	for k: String in codes:
		if k != realm:
			return k
	return ""

func test_the_deals_are_loaded() -> void:
	assert_gt(data.deals.size(), 10000)
	var d: Dictionary = data.deals[0]
	for k: String in ["seller_type", "seller", "buyer_type", "buyer", "good", "units", "price"]:
		assert_true(d.has(k), "a deal carries " + k)
	assert_typeof(d["units"], TYPE_FLOAT)
	assert_typeof(d["price"], TYPE_FLOAT)

func test_the_deals_are_cleared_with_the_pack() -> void:
	var n := data.deals.size()
	assert_true(data.load_map(data.map_id))
	assert_eq(data.deals.size(), n, "reloading the pack does not double its deals")

func test_the_realms_markets_are_those_its_towns_centre() -> void:
	var ids := MarketSystem.realm_markets(data, s)
	assert_gt(ids.size(), 0)
	for id: String in ids:
		var burg := String(data.world_table("economy", "markets")[id]["center_burg"])
		assert_eq(MarketSystem.kingdom_of_party(data, s, "burg", burg), realm)
	for i in range(1, ids.size()):
		assert_lt(int(ids[i - 1]), int(ids[i]), "sorted as numbers")

func test_markets_follow_live_ownership() -> void:
	var ids := MarketSystem.realm_markets(data, s)
	assert_gt(ids.size(), 0)
	var burg := String(data.world_table("economy", "markets")[ids[0]]["center_burg"])
	var prov := String(data.burgs[burg]["province_code"])
	assert_true(MapOwnership.set_owner(data, s, prov, _other_kingdom(), "a test conquest"))
	assert_false(ids[0] in MarketSystem.realm_markets(data, s))

func test_a_market_party_is_its_centre_towns_kingdom() -> void:
	var id := String(MarketSystem.realm_markets(data, s)[0])
	assert_eq(MarketSystem.kingdom_of_party(data, s, "market", id), realm)
	assert_eq(MarketSystem.kingdom_of_party(data, s, "market", "no such market"), "")
	assert_eq(MarketSystem.kingdom_of_party(data, s, "burg", "no such town"), "")

## A town the crown annexed across the border (MapManors.annex writes
## GameState.manor_province) trades as the realm's.
func test_an_annexed_town_trades_as_the_realms() -> void:
	var home := MapManors.home_province(data, s)
	for cell: int in data.manors:
		var burg := MapManors.burg_of(data, cell)
		if burg == "" or MarketSystem.kingdom_of_party(data, s, "burg", burg) == realm:
			continue
		s.manor_province[str(cell)] = home
		assert_eq(MarketSystem.kingdom_of_party(data, s, "burg", burg), realm)
		return
	fail_test("no foreign town to annex")

func test_a_route_sums_its_deals_by_buyer_kingdom() -> void:
	var routes := MarketSystem.routes(data, s)
	assert_gt(routes.size(), 0)
	var r: Dictionary = routes[0]
	assert_ne(String(r["kingdom"]), realm)
	var sum := 0.0
	var n := 0
	for d: Dictionary in data.deals:
		if MarketSystem.kingdom_of_party(data, s, String(d["seller_type"]), String(d["seller"])) == realm \
				and MarketSystem.kingdom_of_party(data, s, String(d["buyer_type"]), String(d["buyer"])) == String(r["kingdom"]):
			sum += float(d["units"]) * float(d["price"])
			n += 1
	assert_eq(int(r["value"]), int(roundf(sum)))
	assert_eq(int(r["deals"]), n)
	for i in range(1, routes.size()):
		assert_lt(String(routes[i - 1]["kingdom"]), String(routes[i]["kingdom"]), "sorted by kingdom code")
		assert_ne(String(routes[i]["kingdom"]), realm, "no route to the realm itself")

func test_routes_follow_a_conquest() -> void:
	var before := MarketSystem.routes(data, s)
	var r: Dictionary = before[0]
	# The buyer's kingdom loses every province to the realm: its trade is
	# no longer foreign, so the route is gone (the cache must see it).
	for prov: String in MapOwnership.provinces_of(data, s, String(r["kingdom"])):
		MapOwnership.set_owner(data, s, prov, realm, "a test conquest")
	for after: Dictionary in MarketSystem.routes(data, s):
		assert_ne(String(after["kingdom"]), String(r["kingdom"]))

func test_the_toll_and_closing() -> void:
	var r: Dictionary = MarketSystem.routes(data, s)[0]
	@warning_ignore("integer_division")
	assert_eq(int(r["toll"]), int(r["value"]) * int(data.bal("trade_toll_permille")) / 1000)
	assert_eq(int(r["claimed"]), int(r["toll"]), "an honest steward claims what he takes")
	assert_eq(int(r["skimmed"]), 0)
	assert_true(r["open"])
	var lines := MarketSystem.settle_month(data, s)
	assert_eq(String(lines[0]["metric"]), "treasury")
	assert_eq(int(lines[0]["delta"]), int(r["toll"]))
	s.closed_routes.append(String(r["kingdom"]))
	var closed: Dictionary = MarketSystem.routes(data, s)[0]
	assert_eq(String(closed["kingdom"]), String(r["kingdom"]))
	assert_false(closed["open"])
	assert_eq(int(closed["toll"]), 0)
	assert_eq(int(closed["claimed"]), 0)
	assert_eq(int(closed["value"]), int(r["value"]), "a closed route still shows what it would carry")

## Invariant 5: the line names the kingdom by its live label, never a code.
func test_a_toll_line_names_the_buyer_by_its_label() -> void:
	var r: Dictionary = MarketSystem.routes(data, s)[0]
	var label := String(data.kingdoms[String(r["kingdom"])]["label"])
	var lines := MarketSystem.settle_month(data, s)
	assert_string_contains(String(lines[0]["reason"]), label)

func test_a_venal_steward_skims_the_tolls_into_his_own_books() -> void:
	var gid := String(s.council["steward"])
	var st: Character = s.characters[gid]
	st.attributes["integrity"] = 0
	var g := Governance.factors(data, s, "trade_route")
	assert_gt(int(g["skim"]), 0, "a low-integrity steward skims")
	var routes := MarketSystem.routes(data, s)
	var skimmed := 0
	var tolls := 0
	for r: Dictionary in routes:
		@warning_ignore("integer_division")
		var claimed := int(r["value"]) * int(data.bal("trade_toll_permille")) / 1000 * int(g["efficiency"]) / 1000
		assert_eq(int(r["claimed"]), claimed)
		@warning_ignore("integer_division")
		assert_eq(int(r["skimmed"]), claimed * int(g["skim"]) / 1000)
		assert_eq(int(r["toll"]), claimed - int(r["skimmed"]))
		assert_eq(String(r["governor"]), gid)
		skimmed += int(r["skimmed"])
		tolls += int(r["toll"])
	assert_gt(skimmed, 0)
	var lines := MarketSystem.settle_month(data, s)
	var paid := 0
	for l: Dictionary in lines:
		paid += int(l["delta"])
	assert_eq(paid, tolls, "the treasury gets the toll less the skim")
	assert_eq(Governance.skimmed_on(s, gid, "trade_route"), skimmed, "his books on the trade tolls")

func test_the_tick_takes_the_tolls() -> void:
	var tolls := 0
	for r: Dictionary in MarketSystem.routes(data, s):
		tolls += int(r["toll"])
	var engine := TickEngine.new(data)
	var report := engine.advance(s)
	var found := 0
	for e: Dictionary in report.metric_deltas:
		if String(e["reason"]).begins_with("tolls on the trade with "):
			assert_eq(String(e["metric"]), "treasury")
			found += int(float(e["delta"]))
	assert_eq(found, tolls)

func test_tolls_are_a_modest_share_of_the_crowns_tax() -> void:
	var tolls := 0
	for r: Dictionary in MarketSystem.routes(data, s):
		tolls += int(r["toll"])
	var p := RealmEconomy.purses(data, s)
	var tax := int(p["lord"]["tax"]) + int(p["realm_share"]["tax"])
	gut.p("tolls %d a month against %d of tax" % [tolls, tax])
	assert_between(float(tolls) / float(maxi(tax, 1)), 0.05, 0.25)

func test_closed_routes_survive_a_save() -> void:
	s.closed_routes = ["x"]
	assert_eq(GameState.from_dict(s.to_dict()).closed_routes, ["x"])
	var d := s.to_dict()
	d.erase("closed_routes")
	assert_eq(GameState.from_dict(d).closed_routes, [], "an old save has every route open")

func test_routes_are_deterministic() -> void:
	var a := MarketSystem.routes(data, s)
	MarketSystem.forget()
	assert_eq(MarketSystem.routes(data, s), a)

func test_routes_timing() -> void:
	MarketSystem.forget()
	var t0 := Time.get_ticks_usec()
	MarketSystem.routes(data, s)
	var cold := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	MarketSystem.routes(data, s)
	var warm := Time.get_ticks_usec() - t0
	gut.p("routes(): %.1f ms cold, %.2f ms warm" % [cold / 1000.0, warm / 1000.0])
	assert_lt(warm, 20000, "a snapshot's routes() stays under 20 ms")

func test_market_value_sums_its_pool() -> void:
	var id := String(MarketSystem.realm_markets(data, s)[0])
	var civil := 0.0
	var strategic := 0.0
	for row: Dictionary in data.world_table("economy", "market_goods").values():
		if String(row["market_id"]) != id:
			continue
		var v := float(row["stock"]) * float(row["price"])
		if String(data.goods_economy_of(String(row["good_code"]))["pool"]) == "strategic":
			strategic += v
		else:
			civil += v
	assert_eq(MarketSystem.market_value(data, id, "civil"), int(roundf(civil)))
	assert_eq(MarketSystem.market_value(data, id, "strategic"), int(roundf(strategic)))
	assert_gt(MarketSystem.market_value(data, id, "civil") + MarketSystem.market_value(data, id, "strategic"), 0)

func test_basket_price_is_stock_weighted_against_the_catalogue() -> void:
	var id := String(MarketSystem.realm_markets(data, s)[0])
	var paid := 0.0
	var list := 0.0
	for row: Dictionary in data.world_table("economy", "market_goods").values():
		if String(row["market_id"]) != id:
			continue
		var ge := data.goods_economy_of(String(row["good_code"]))
		if String(ge["pool"]) != "civil":
			continue
		paid += float(row["stock"]) * float(row["price"])
		list += float(row["stock"]) * float(ge["price_gold"])
	var want := 1000 if list <= 0.0 else int(roundf(paid / list * 1000.0))
	assert_eq(MarketSystem.basket_price_permille(data, id, "civil"), want)
	assert_eq(MarketSystem.basket_price_permille(data, "no such market", "civil"), 1000)

## GOODS_BUY at a realm market: that market's basket price, not the
## spread — floored at the factor's buying price, so a cheap market is never
## cheaper than what the factor pays.
func test_buying_at_a_realm_market_pays_its_basket_price() -> void:
	var id := String(MarketSystem.realm_markets(data, s)[0])
	var basket := MarketSystem.basket_price_permille(data, id, "civil")
	var floor_permille := int(roundf(1000.0 * (1.0 - data.bal("goods_trade_spread"))))
	s.metrics["treasury"] = 1000.0
	s.metrics["grain"] = 0.0
	# A market id arrives as an int from the LEDGER (Ledger.params_of).
	var out := sys.execute(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 100, "market": int(id)}), s)
	assert_true(out["ok"], String(out.get("error", "")))
	assert_eq(int(s.metrics["grain"]), 100)
	var price := int(roundf(100.0 * float(maxi(basket, floor_permille)) / 1000.0))
	assert_eq(MarketSystem.buy_price(data, id, "civil", 100), price)
	assert_eq(int(s.metrics["treasury"]), 1000 - price - 1, "the market's price and the factor's paperwork fee")
	assert_lt(price, int(roundf(100.0 * (1.0 + data.bal("goods_trade_spread")))), "cheaper than the factor")

func test_selling_at_a_realm_market_pays_its_basket_less_the_spread() -> void:
	var id := String(MarketSystem.realm_markets(data, s)[0])
	var basket := MarketSystem.basket_price_permille(data, id, "civil")
	s.metrics["treasury"] = 1000.0
	s.metrics["grain"] = 100.0
	var out := sys.execute(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 100, "market": id}), s)
	assert_true(out["ok"], String(out.get("error", "")))
	assert_eq(int(s.metrics["grain"]), 0)
	var paid := MarketSystem.sell_price(data, s, id, "civil", 100)
	assert_lte(paid, int(roundf(100.0 * float(basket) / 1000.0 * (1.0 - data.bal("goods_trade_spread")))))
	assert_eq(int(s.metrics["treasury"]), 1000 + paid - 1)

## No round trip is a profit: no sale anywhere (a realm market or the
## factor) pays more per mille than any purchase anywhere costs.
func test_no_round_trip_between_markets_pays() -> void:
	var spread := data.bal("goods_trade_spread")
	for pool: String in ["civil", "strategic"]:
		var buys: Array = [int(roundf(1000.0 * (1.0 + spread)))]
		var sells: Array = [int(roundf(1000.0 * (1.0 - spread)))]
		for id: String in MarketSystem.realm_markets(data, s):
			buys.append(MarketSystem.buy_permille(data, id, pool))
			sells.append(MarketSystem.sell_permille(data, s, id, pool))
		assert_lte(int(sells.max()), int(buys.min()), pool + ": the dearest sale is no dearer than the cheapest buy")

func test_a_market_outside_the_realm_is_refused() -> void:
	s.metrics["treasury"] = 1000.0
	var foreign := ""
	for id: String in data.world_table("economy", "markets"):
		if MarketSystem.kingdom_of_party(data, s, "market", id) != realm:
			foreign = id
			break
	assert_ne(foreign, "")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY",
		{"pool": "civil", "gold": 10, "market": foreign}), s), "market")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY",
		{"pool": "civil", "gold": 10, "market": "no such"}), s), "market")
	assert_eq(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 10}), s), "",
		"without a market the flat trade stays")
