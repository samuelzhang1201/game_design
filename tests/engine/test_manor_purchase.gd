extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Buying land (owner 2026-09-14): where the crown may buy a manor, from
## which purse, and what a manor bought across the border becomes.
##
## - Your own province, and the realm's provinces bordering it: the LORD's
##   purse pays (lord_gold), the manor is the crown's.
## - A province of the realm that borders none of yours: refused.
## - Across the border, a manor touching the realm: the CROWN's treasury
##   pays, the manor is annexed into the richest bordering province of the
##   realm (the most tax a month) and that province's house holds it; the
##   realm's outline takes it in.
## - Across the border, a manor that touches nothing of the realm: refused.

var data: DataRepository
var sys: ActionSystem
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	RealmEconomy.forget()
	MapManors.invalidate()
	MapOwnership.invalidate()
	sys = ActionSystem.new(data)
	s = SuiteData.campaign(data, 42)

func _realm() -> String:
	return data.resolve_realm("player_realm")

## The first manor, in cell order, not the crown's and of this purchase kind
## ("" for refused ones), optionally only inside (or outside) the realm.
func _manor_of_kind(kind: String, in_realm: int = -1) -> int:
	var ids: Array = data.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapManors.is_crowns(data, s, id):
			continue
		var inside := MapOwnership.owner_of(data, s, MapManors.province_of(data, id, s)) == _realm()
		if in_realm == 1 and not inside:
			continue
		if in_realm == 0 and inside:
			continue
		if String(MapManors.purchase_kind(data, s, id)["kind"]) == kind:
			return id
	return -1

func test_a_bordering_province_is_bought_from_the_lords_purse() -> void:
	var cell := _manor_of_kind("domestic")
	assert_gt(cell, -1, "the pack has a province bordering the crown's")
	var req := ActionRequest.make("MANOR_BUY", {"manor": cell})
	var price := MapManors.price_of(data, s, cell)
	s.metrics["treasury"] = 1000000.0
	s.metrics["lord_gold"] = price - 1.0
	assert_string_contains(sys.validate(req, s), "Your own purse cannot afford",
		"a full treasury does not buy land inside the realm")
	s.metrics["lord_gold"] = price + 100.0
	var treasury: float = s.metrics["treasury"]
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_true(MapManors.is_crowns(data, s, cell), "the crown holds it")
	assert_almost_eq(s.metrics["lord_gold"], 100.0, 0.001, "the lord's purse paid the price")
	assert_almost_eq(s.metrics["treasury"], treasury - 2.0, 0.001, "only the notary's fee left the treasury")
	assert_true(s.manor_province.is_empty(), "a manor inside the realm stays in its province")

func test_your_own_province_is_bought_from_the_lords_purse_too() -> void:
	var cell := _manor_of_kind("own")
	if cell < 0:
		pass_test("the crown already holds every manor of its provinces")
		return
	var price := MapManors.price_of(data, s, cell)
	s.metrics["lord_gold"] = price
	assert_eq(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": cell}), s), "")
	sys.execute(ActionRequest.make("MANOR_BUY", {"manor": cell}), s)
	assert_almost_eq(s.metrics["lord_gold"], 0.0, 0.001)

func test_a_province_that_borders_none_of_yours_is_refused() -> void:
	var cell := _manor_of_kind("", 1)
	if cell < 0:
		pass_test("every province of the realm borders the crown's")
		return
	s.metrics["lord_gold"] = 1000000.0
	s.metrics["treasury"] = 1000000.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": cell}), s),
		"does not border your own")

func test_a_foreign_manor_off_the_border_is_refused() -> void:
	var cell := _manor_of_kind("", 0)
	assert_gt(cell, -1, "most of the world does not touch the realm")
	s.metrics["lord_gold"] = 1000000.0
	s.metrics["treasury"] = 1000000.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": cell}), s),
		"does not touch the realm's border")

func test_buying_across_the_border_pays_from_the_treasury_and_annexes_the_manor() -> void:
	var cell := _manor_of_kind("foreign")
	assert_gt(cell, -1, "some foreign manor touches the realm")
	var old_province := MapManors.province_of(data, cell, s)
	var target := String(MapManors.purchase_kind(data, s, cell)["province"])
	# The target is the richest province of the realm the cell touches.
	var best := ""
	var best_tax := -1
	for n: int in (data.cells[cell]["neighbor_ids"] as PackedInt32Array):
		if not MapManors.is_manor(data, n):
			continue
		var p := MapManors.province_of(data, n, s)
		if MapOwnership.owner_of(data, s, p) != _realm():
			continue
		var tax := int(RealmEconomy.province(data, s, p)["tax"])
		if tax > best_tax or (tax == best_tax and p < best):
			best = p
			best_tax = tax
	assert_eq(target, best, "the bordering province with the most gold")
	var seller := MapManors.owner_of(data, s, cell)
	var price := MapManors.price_of(data, s, cell)
	var req := ActionRequest.make("MANOR_BUY", {"manor": cell})
	s.metrics["lord_gold"] = 1000000.0
	s.metrics["treasury"] = price - 1.0
	assert_string_contains(sys.validate(req, s), "treasury cannot afford",
		"the lord's purse does not buy land abroad")
	s.metrics["treasury"] = price + 1000.0
	var outline_before := MapOwnership.outline_of(data, s, _realm()).duplicate(true)
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_almost_eq(s.metrics["treasury"], 1000.0 - 2.0, 0.001, "the price and the notary's fee")
	assert_almost_eq(s.metrics["lord_gold"], 1000000.0, 0.001, "the lord's purse is untouched")
	assert_eq(MapManors.province_of(data, cell, s), target, "the manor joined the bordering province")
	assert_true(MapManors.manors_of_province(data, target, s).has(cell))
	assert_false(MapManors.manors_of_province(data, old_province, s).has(cell))
	assert_eq(MapManors.owner_of(data, s, cell), MapManors.default_owner(data, s, cell),
		"held by the house of the province it joined")
	assert_ne(MapManors.owner_of(data, s, cell), seller)
	assert_eq(MapOwnership.owner_of(data, s, MapManors.province_of(data, cell, s)), _realm(),
		"it lies in the realm now")
	assert_ne(MapOwnership.outline_of(data, s, _realm()), outline_before, "the realm's border takes it in")
	var annexed := false
	for entry: Dictionary in s.manor_log:
		if entry.has("annexed_to") and int(entry["cell"]) == cell:
			annexed = String(entry["annexed_to"]) == target
	assert_true(annexed, "the move is logged with its province")
	assert_eq(RealmEconomy.check_full(data, s), [], "the economy's cache agrees with a fresh count")
	if MapManors.is_crowns(data, s, cell):
		assert_string_contains(sys.validate(req, s), "already holds", "bought once")
	else:
		pass_test("held by another house of the realm")

func test_an_annexation_survives_a_save() -> void:
	var cell := _manor_of_kind("foreign")
	assert_gt(cell, -1)
	var target := String(MapManors.purchase_kind(data, s, cell)["province"])
	assert_true(MapManors.annex(data, s, cell, target, "test: bought"))
	assert_false(MapManors.annex(data, s, cell, target, "test: again"), "already there")
	assert_false(MapManors.annex(data, s, cell, target, ""), "a move needs a reason")
	var loaded := GameState.from_dict(s.to_dict())
	assert_eq(MapManors.province_of(data, cell, loaded), target)
	assert_eq(loaded.manor_province, s.manor_province)
