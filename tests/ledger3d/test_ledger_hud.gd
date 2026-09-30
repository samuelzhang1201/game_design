# tests/ledger3d/test_ledger_hud.gd
extends GutTest
## The LEDGER's names never overlap (spec §6.2): earlier entries win.

func test_an_overlapping_name_is_dropped_and_order_kept() -> void:
	var entries := [
		{"text": "Regiments", "at": Vector2(100, 100), "strong": true},
		{"text": "Couriers", "at": Vector2(104, 102), "strong": false},
		{"text": "Gold", "at": Vector2(300, 100), "strong": false},
	]
	var kept := LedgerHud.cull(entries, 14.0)
	assert_eq(kept.map(func(e: Dictionary) -> String: return String(e["text"])), ["Regiments", "Gold"])

func test_nothing_to_draw_is_nothing_kept() -> void:
	assert_eq(LedgerHud.cull([], 14.0), [])


func test_a_crowded_name_takes_its_place_under_the_sphere() -> void:
	var entries := [
		{"text": "Regiments", "at": Vector2(100, 100), "alt": Vector2(100, 132), "strong": false},
		{"text": "Couriers", "at": Vector2(104, 102), "alt": Vector2(104, 134), "strong": false},
	]
	var kept := LedgerHud.cull(entries, 14.0)
	assert_eq(kept.size(), 2, "the second name stands under its sphere")
	assert_eq(kept[0]["at"], Vector2(100, 100))
	assert_eq(kept[1]["at"], Vector2(104, 134))


## §6.3 "a property": a sphere's gauges stand in a row under its name.
func test_a_gauge_caption_reads_its_value() -> void:
	assert_eq(LedgerHud.caption_of({"label": "Supplies", "value": 640, "max": 1000}), "Supplies 64%")
	assert_eq(LedgerHud.caption_of({"label": "Morale", "value": 70, "max": 100}), "Morale 70")
	assert_eq(LedgerHud.caption_of({"label": "Stock", "value": 12400, "max": 50000}), "Stock 12,400")


func test_a_gauge_fills_by_its_share_and_never_past_full() -> void:
	assert_almost_eq(LedgerHud.fill_of({"value": 250, "max": 1000}), 0.25, 0.0001)
	assert_eq(LedgerHud.fill_of({"value": 3000, "max": 1000}), 1.0)
	assert_eq(LedgerHud.fill_of({"value": 5, "max": 0}), 0.0)


func test_a_names_gauges_take_room_in_the_cull() -> void:
	var entries := [
		{"text": "Regiments", "at": Vector2(100, 100), "strong": true,
			"props": [{"key": "supplies", "label": "Supplies", "value": 500, "max": 1000}]},
		{"text": "Couriers", "at": Vector2(100, 80), "strong": false},
	]
	var kept := LedgerHud.cull(entries, 14.0)
	assert_eq(kept.size(), 1, "a name just over another's gauges is dropped")
	assert_true(kept[0]["gauges_up"], "a name over its sphere carries its gauges over it")
	var plain := [entries[0].duplicate(), entries[1]]
	plain[0].erase("props")
	assert_eq(LedgerHud.cull(plain, 14.0).size(), 2, "without gauges the two names are clear")


func test_a_name_set_under_its_sphere_carries_its_gauges_under_it() -> void:
	var g := [{"key": "morale", "label": "Morale", "value": 70, "max": 100}]
	var entries := [
		{"text": "Regiments", "at": Vector2(100, 100), "alt": Vector2(100, 132), "strong": false},
		{"text": "Couriers", "at": Vector2(104, 102), "alt": Vector2(104, 134), "strong": false, "props": g},
	]
	var kept := LedgerHud.cull(entries, 14.0)
	assert_eq(kept.size(), 2)
	assert_false(kept[1]["gauges_up"])


func test_a_name_never_sits_on_a_star() -> void:
	var star := Rect2(Vector2(90, 90), Vector2(20, 20))
	var kept := LedgerHud.cull([{"text": "Walbover", "at": Vector2(100, 100), "strong": false}], 14.0, null,
		LedgerHud.DEFAULT_GAUGE, [star])
	assert_true(kept.is_empty(), "the only place covers the star")


func test_a_name_on_a_star_takes_its_other_place() -> void:
	var star := Rect2(Vector2(90, 90), Vector2(20, 20))
	var kept := LedgerHud.cull([{"text": "Walbover", "at": Vector2(100, 100), "alt": Vector2(100, 140),
		"strong": false}], 14.0, null, LedgerHud.DEFAULT_GAUGE, [star])
	assert_eq(kept.size(), 1)
	assert_eq(kept[0]["at"], Vector2(100, 140))


func test_an_entry_keeps_its_own_size_colour_and_ring() -> void:
	var kept := LedgerHud.cull([{"text": "Economy · 32", "at": Vector2(50, 50), "strong": true, "title": true,
		"px": 20.0, "ink": Color.GOLD, "ring": 9.0, "ring_at": Vector2(50, 80)}], 14.0)
	assert_eq(kept[0]["px"], 20.0)
	assert_eq(kept[0]["ink"], Color.GOLD)
	assert_eq(kept[0]["ring"], 9.0)


func test_a_bigger_name_takes_more_room() -> void:
	var small := LedgerHud.cull([{"text": "Economy", "at": Vector2(100, 100), "strong": false},
		{"text": "War", "at": Vector2(100, 122), "strong": false}], 14.0)
	var big := LedgerHud.cull([{"text": "Economy", "at": Vector2(100, 100), "strong": false, "px": 28.0},
		{"text": "War", "at": Vector2(100, 122), "strong": false}], 14.0)
	assert_eq(small.size(), 2)
	assert_eq(big.size(), 1, "the title's box reaches the name below it")
