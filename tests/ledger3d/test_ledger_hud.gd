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
	# Task 11 fix round 3 (S1a): a name over its star carries its gauges UNDER
	# it — the name is lifted by the row, the row between it and the star
	assert_false(kept[0]["gauges_up"], "the gauges sit under the name")
	assert_almost_eq((kept[0]["at"] as Vector2).y, 100.0 - LedgerHud.gauge_row_h(entries[0]["props"],
		LedgerHud.DEFAULT_GAUGE), 0.001, "lifted by the row's height")
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


## I1 (fix round 1): cull() must measure a title entry in the SAME font
## _draw() paints it with, or a cluster title's box can disagree with what
## is drawn and a name can end up sitting on it. Two real, clearly
## different-width faces prove it: at px 20 "War" measures 34px wide in the
## body face (CrimsonPro) and 39px in the title face (UnifrakturMaguntia).
func test_a_title_is_measured_in_the_title_font() -> void:
	var body := load("res://assets/fonts/CrimsonPro.ttf") as Font
	var title_font := load("res://assets/fonts/UnifrakturMaguntia-Book.ttf") as Font
	var px := 20
	var body_w := body.get_string_size("War", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var title_w := title_font.get_string_size("War", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_ne(body_w, title_w, "the two faces must measure the string differently for this test to prove anything")
	assert_almost_eq(body_w, 34.0, 0.01)
	assert_almost_eq(title_w, 39.0, 0.01)

	# a gap that overlaps the neighbour's box only when "War" is measured in
	# the wider title font (half-widths 24.5 + 24.5 = 49 > 47.5) and clears
	# it when (wrongly) measured in the narrower body font (22 + 24.5 = 46.5 < 47.5)
	var entries := [
		{"text": "War", "at": Vector2(100, 100), "strong": false, "title": true, "px": float(px)},
		{"text": "Gold", "at": Vector2(147.5, 100), "strong": false, "px": float(px)},
	]
	var with_title_font := LedgerHud.cull(entries, float(px), body, LedgerHud.DEFAULT_GAUGE, [], title_font)
	assert_eq(with_title_font.size(), 1, "measured in the wider title font, the title's box reaches Gold")
	assert_eq(with_title_font[0]["text"], "War")

	var without_title_font := LedgerHud.cull(entries, float(px), body, LedgerHud.DEFAULT_GAUGE, [], null)
	assert_eq(without_title_font.size(), 2,
		"without a title font the title falls back to the body face and clears Gold")


## Task 11 fix round 2 (R3, replacing 2b/2c's "a kept name may stand on a
## star"): a `keep` name never lies on ANOTHER star's disc; crowded by names
## it takes the least-covered place that is on no other star; a wall is
## never entered.
func test_a_kept_name_never_lies_on_another_star() -> void:
	var own := [Vector2(100, 100), 10.0]
	var other := Rect2(60, 40, 80, 40)   # a star over its own
	var e := {"text": "Walbover", "at": Vector2(100, 76), "alt": Vector2(100, 130), "strong": true, "keep": true,
		"beside": own}
	var kept := LedgerHud.cull([e], 14.0, null, LedgerHud.DEFAULT_GAUGE, [other, Rect2(90, 90, 20, 20)])
	assert_eq(kept.size(), 1, "kept")
	var at: Vector2 = kept[0]["at"]
	var w := 8.0 * 14.0 * 0.55
	assert_false(other.intersects(Rect2(at - Vector2(w * 0.5, 14.0 * 0.45), Vector2(w, 14.0 * 1.05))),
		"not on the other star")
	var crowd := {"text": "Walbover", "at": Vector2(100, 76), "strong": false, "keep": true}
	var first := LedgerHud.cull([crowd, e], 14.0)
	assert_eq(first.size(), 2, "crowded by a name, a kept name still stands")
	var wall := LedgerHud.cull([e], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, [Rect2(0, 0, 400, 400)])
	assert_eq(wall.size(), 0, "never in a wall")
	var plain := e.duplicate()
	plain.erase("keep")
	var boxed := [Rect2(0, 0, 400, 88), Rect2(0, 112, 400, 300), Rect2(0, 88, 88, 24), Rect2(112, 88, 300, 24)]
	assert_eq(LedgerHud.cull([plain], 14.0, null, LedgerHud.DEFAULT_GAUGE, boxed).size(), 0,
		"an ordinary name with every place on other stars is dropped")


## Task 11 fix round 2 (R6): a dimmed name's halo and gauges fade with it.
func test_a_dim_names_gauges_fade_with_it() -> void:
	assert_almost_eq(LedgerHud.fade_of(Color(1, 1, 1, 0.8)), 1.0, 0.001)
	assert_almost_eq(LedgerHud.fade_of(Color(1, 1, 1, 1.0)), 1.0, 0.001, "never past whole")
	assert_almost_eq(LedgerHud.fade_of(Color(1, 1, 1, 0.2)), 0.25, 0.001)


## Task 11: a name with `beside` (its star's centre and radius) may stand to
## the right or left of its star when over and under are taken.
func test_a_name_stands_beside_its_star_when_over_and_under_are_taken() -> void:
	var discs := [Rect2(90, 90, 20, 20)]
	var taken := [Rect2(40, 50, 120, 30), Rect2(40, 120, 120, 30)]
	var e := {"text": "Rothin", "at": Vector2(100, 70), "alt": Vector2(100, 135), "strong": false,
		"beside": [Vector2(100, 100), 10.0]}
	var kept := LedgerHud.cull([e], 14.0, null, LedgerHud.DEFAULT_GAUGE, discs + taken)
	assert_eq(kept.size(), 1)
	var at: Vector2 = kept[0]["at"]
	assert_almost_eq(at.y, 100.0, 0.01, "level with its star")
	assert_true(absf(at.x - 100.0) > 10.0, "to one side of it")


## Task 11 fix round 1 (F6): every name is drawn over a soft wide halo, then
## its crisp outline — a link behind it never cuts a letter.
func test_a_name_wears_a_soft_halo_under_its_outline() -> void:
	var hud := LedgerHud.new()
	autofree(hud)
	hud.style(null, 14.0, Color.WHITE, Color(0.08, 0.06, 0.05), 4)
	assert_eq(hud.halo_passes().size(), 1, "unstyled: the crisp outline alone")
	hud.style_halo(10.0, 0.6)
	var passes := hud.halo_passes()
	assert_eq(passes.size(), 2)
	assert_eq(int(passes[0][0]), 10, "the soft halo first, widest")
	assert_almost_eq((passes[0][1] as Color).a, 0.6, 0.001)
	assert_eq(int(passes[1][0]), 4, "then the crisp outline")


## Task 11 fix round 3 (S1c, S1d): a name round its own star takes the
## nearest clear ring first, and never a place the view's edge would clip.
func test_a_name_takes_the_nearest_ring_and_is_never_clipped() -> void:
	var e := {"text": "8th (Canceswest)", "at": Vector2(100, 60), "strong": false, "beside": [Vector2(100, 100), 6.0]}
	var kept := LedgerHud.cull([e], 14.0)
	var at: Vector2 = kept[0]["at"]
	assert_almost_eq(at.y, 100.0 - 6.0 - 14.0 * 0.35 - 14.0 * 0.6, 0.001, "over its star at the nearest ring")
	var low := e.duplicate()
	low["beside"] = [Vector2(100, 395), 6.0]
	var view := Rect2(0, 0, 400, 400)
	var placed := LedgerHud.cull([low], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, [], view)
	assert_eq(placed.size(), 1)
	var w := 16.0 * 14.0 * 0.55
	var p: Vector2 = placed[0]["at"]
	assert_true(view.encloses(Rect2(p - Vector2(w * 0.5, 14.0 * 0.45), Vector2(w, 14.0 * 1.05))), "inside the view")
	var corner := e.duplicate()
	corner["beside"] = [Vector2(398, 398), 6.0]
	var gone := LedgerHud.cull([corner], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, [], Rect2(0, 0, 400, 400))
	for k: Dictionary in gone:
		var q: Vector2 = k["at"]
		assert_true(Rect2(0, 0, 400, 400).encloses(Rect2(q - Vector2(w * 0.5 + 3.5, 14.0 * 0.45), Vector2(w + 7.0, 14.0 * 1.05))))


## Task 11 fix round 4 (T1): a `first` label becomes a wall; a `lit` label
## prefers a place in its ring that no planned dash crosses; a `dim` name only
## tries its nearest ring; over and under its star a name slides inside the
## view's edge.
func test_the_first_label_walls_off_lit_avoids_dashes_dim_stays_near() -> void:
	var sel := {"text": "10th (Rothbridbu)", "at": Vector2(200, 160), "strong": true, "first": true,
		"beside": [Vector2(200, 200), 10.0]}
	var other := {"text": "Enemy hosts", "at": Vector2(200, 170), "strong": false, "keep": true,
		"beside": [Vector2(200, 210), 1.0]}
	var kept := LedgerHud.cull([sel, other], 14.0)
	var w := 17.0 * 14.0 * 0.55
	var mine := Rect2((kept[0]["at"] as Vector2) - Vector2(w * 0.5, 14.0 * 0.45), Vector2(w, 14.0 * 1.05))
	for k: Dictionary in kept.slice(1):
		var w2 := 11.0 * 14.0 * 0.55
		var b := Rect2((k["at"] as Vector2) - Vector2(w2 * 0.5, 14.0 * 0.45), Vector2(w2, 14.0 * 1.05))
		assert_false(b.intersects(mine), "nothing touches the selected label")
	var lit := sel.duplicate()
	lit.erase("first")
	lit["lit"] = true
	var dash := [[Vector2(100, 175), Vector2(300, 175)]]   # a dashed link right over its star
	var off := LedgerHud.cull([lit], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, [], Rect2(), dash)
	var at: Vector2 = off[0]["at"]
	assert_gt(at.y, 200.0, "it takes the place under its star, off the dashes")
	var dim := {"text": "Enemy hosts", "at": Vector2(200, 160), "strong": false, "dim": true,
		"beside": [Vector2(200, 200), 6.0]}
	var walls := [Rect2(0, 0, 400, 400)]
	walls[0] = Rect2(140, 150, 120, 100)   # its whole nearest ring taken
	assert_eq(LedgerHud.cull([dim], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, walls).size(), 0,
		"a ghost name drops rather than wander")
	var edge := {"text": "10th (Rothbridbu)", "at": Vector2(395, 160), "strong": true,
		"beside": [Vector2(395, 200), 4.0]}
	var slid := LedgerHud.cull([edge], 14.0, null, LedgerHud.DEFAULT_GAUGE, [], null, [], Rect2(0, 0, 400, 400))
	assert_eq(slid.size(), 1)
	assert_lt((slid[0]["at"] as Vector2).x, 395.0, "slid inside the edge")
	assert_almost_eq((slid[0]["at"] as Vector2).y, 200.0 - 4.0 - 14.0 * 0.35 - 14.0 * 0.6, 0.001, "still over its star")
