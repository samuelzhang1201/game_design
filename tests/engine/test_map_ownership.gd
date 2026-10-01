extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Province ownership and the borders that follow from it (user request
## 2026-09-09: territory must be able to change hands and the map must show
## it). The pack ships the starting map; GameState carries what moved.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)
	MapOwnership.invalidate()

func _player() -> String:
	return data.resolve_realm("player_realm")

func _raider() -> String:
	return data.resolve_realm("raider_realm")

func test_untouched_campaign_reports_the_packs_own_owners() -> void:
	assert_true(state.province_owner.is_empty(),
		"nothing has moved, so nothing is stored")
	for code: String in data.provinces:
		assert_eq(MapOwnership.owner_of(data, state, code),
			String(data.provinces[code]["kingdom_code"]),
			"%s still belongs to the pack's kingdom" % code)

## The whole scheme rests on provinces tiling their kingdom exactly: if they
## did not, a merged outline would not be the kingdom's border.
func test_merged_outline_reproduces_the_packs_border() -> void:
	for code: String in data.kingdoms:
		var merged := MapOwnership.outline_of(data, state, code)
		var packed: Array = data.borders.get(code, [])
		var merged_pts := 0
		for l: PackedVector2Array in merged:
			merged_pts += l.size()
		var packed_pts := 0
		for l: PackedVector2Array in packed:
			packed_pts += l.size()
		assert_eq(merged.size(), packed.size(), "%s loop count" % code)
		assert_eq(merged_pts, packed_pts, "%s point count" % code)

func test_transfer_moves_the_province_and_says_why() -> void:
	var mine := MapOwnership.provinces_of(data, state, _player())
	assert_gt(mine.size(), 1, "the player starts with provinces")
	var victim: String = mine[0]
	assert_true(MapOwnership.set_owner(data, state, victim, _raider(), "raid"))
	assert_eq(MapOwnership.owner_of(data, state, victim), _raider())
	assert_eq(MapOwnership.provinces_of(data, state, _player()).size(),
		mine.size() - 1, "the loser is one province lighter")
	assert_eq(state.territory_log.size(), 1, "the transfer is on the record")
	var entry: Dictionary = state.territory_log[0]
	assert_eq(String(entry["reason"]), "raid", "and it carries its reason")
	assert_eq(String(entry["from"]), _player())
	assert_eq(String(entry["to"]), _raider())

func test_transfer_redraws_both_borders() -> void:
	var mine := MapOwnership.provinces_of(data, state, _player())
	var before := MapOwnership.outline_of(data, state, _player()).duplicate(true)
	MapOwnership.set_owner(data, state, mine[0], _raider(), "raid")
	var after := MapOwnership.outline_of(data, state, _player())
	assert_ne(after, before, "the player's outline changed")
	var taker := MapOwnership.outline_of(data, state, _raider())
	assert_false(taker.is_empty(), "and the taker still has one")

func test_a_no_op_transfer_changes_nothing() -> void:
	var mine := MapOwnership.provinces_of(data, state, _player())
	assert_false(MapOwnership.set_owner(data, state, mine[0], _player(), "nothing"),
		"handing a province to the kingdom that already holds it is a no-op")
	assert_true(state.territory_log.is_empty(), "and is not logged")
	assert_false(MapOwnership.set_owner(data, state, "no_such_province",
		_raider(), "typo"), "an unknown province is refused")
	assert_false(MapOwnership.set_owner(data, state, mine[0], "no_such_kingdom",
		"typo"), "an unknown kingdom is refused")

func test_ownership_survives_the_save() -> void:
	var mine := MapOwnership.provinces_of(data, state, _player())
	MapOwnership.set_owner(data, state, mine[0], _raider(), "raid")
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(MapOwnership.owner_of(data, restored, mine[0]), _raider())
	assert_eq(restored.territory_log.size(), 1, "and so does the reason")

## Saves written before territory could move carry neither key.
func test_a_pre_territory_save_loads_as_the_packs_map() -> void:
	var d := state.to_dict()
	d.erase("province_owner")
	d.erase("territory_log")
	var restored := GameState.from_dict(d)
	assert_not_null(restored, "the old save still loads")
	assert_true(restored.province_owner.is_empty())
	for code: String in data.provinces:
		assert_eq(MapOwnership.owner_of(data, restored, code),
			String(data.provinces[code]["kingdom_code"]))

## The label follows the territory, so a kingdom that loses its edge provinces
## has its name drawn over what it still holds.
func test_the_label_anchor_moves_with_the_territory() -> void:
	var before := MapOwnership.label_anchor(data, state, _player())
	var mine := MapOwnership.provinces_of(data, state, _player())
	for i in 5:
		MapOwnership.set_owner(data, state, mine[i], _raider(), "raid")
	var after := MapOwnership.label_anchor(data, state, _player())
	assert_ne(after, before, "losing five provinces moved the name")

func test_describe_counts_follow_ownership() -> void:
	var king: Dictionary = data.kingdoms[_player()]
	var obj := {"kind": "kingdom", "state_id": int(king["state_id"])}
	var before := MapObjects.describe(data, obj, state)
	var mine := MapOwnership.provinces_of(data, state, _player())
	MapOwnership.set_owner(data, state, mine[0], _raider(), "raid")
	var after := MapObjects.describe(data, obj, state)
	assert_ne(after["lines"], before["lines"],
		"the kingdom card reports what it holds now, not the pack's map")

## Province seams (spec 2026-09-09 §5): the edges two held provinces share,
## and never an edge on the kingdom's outline.
func test_seams_are_shared_edges_inside_the_kingdom() -> void:
	var seams := MapOwnership.seams_of(data, state, _player())
	assert_gt(seams.size(), 0, "a kingdom with several provinces has seams")
	var outline_edges: Dictionary = {}
	for loop: PackedVector2Array in MapOwnership.outline_of(data, state, _player()):
		for i in loop.size():
			outline_edges[_edge_key(loop[i], loop[(i + 1) % loop.size()])] = true
	for seg: PackedVector2Array in seams:
		assert_eq(seg.size(), 2, "a seam is one segment")
		assert_false(outline_edges.has(_edge_key(seg[0], seg[1])), "seams are never outline edges")

func test_a_transfer_removes_the_moved_provinces_seams_from_the_old_owner() -> void:
	var before := MapOwnership.seams_of(data, state, _player()).size()
	var mine := MapOwnership.provinces_of(data, state, _player())
	MapOwnership.set_owner(data, state, mine[0], _raider(), "raid")
	assert_lt(MapOwnership.seams_of(data, state, _player()).size(), before)

func _edge_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d,%d" % [roundi(a.x * 100.0), roundi(a.y * 100.0)]
	var kb := "%d,%d" % [roundi(b.x * 100.0), roundi(b.y * 100.0)]
	return ka + "|" + kb if ka < kb else kb + "|" + ka
