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
