# tests/ledger3d/test_ledger_court_look.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER's look rulings of 2026-09-30 (owner, choosing variant A): the
## court is read one person's web at a time — thin cords whose width follows
## the feeling, the selected person's ties lit once one is (the player's own
## at rest: test_ledger_view_galaxy's at-rest test). And
## (owner 2026-10-01: King Aldric's tan, red and green ties "非常突兀，应该和周边
## 类似") a tie wears its two clusters' colours like every other link — the
## feeling is its width and its card, never a hue.

var repo: DataRepository
var view: LedgerView3D
var snap: Dictionary


func before_each() -> void:
	repo = SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.bind(repo)
	snap = Ledger.galaxy(repo, state, {})
	view.show_snapshot(snap, true)
	view.settle_now()


func _ties() -> Array:
	return view.segments().filter(func(seg: Dictionary) -> bool:
		return String(Ledger.link_row(repo, String(seg["link"]).get_slice("|", 0))["look"]) in ["tie", "kin"])


func test_a_court_tie_is_a_thin_cord_by_its_feeling() -> void:
	for seg: Dictionary in _ties():
		var w := float(seg["width_px"]) / view._window_scale()
		# at rest the player's own ties are drawn ledger_focus_width wider
		# (Task 11 fix round 2, R4)
		var mine := String(seg["a_id"]) == LedgerView3D.EGO_AT_REST or String(seg["b_id"]) == LedgerView3D.EGO_AT_REST
		var k := repo.bal("ledger_focus_width") if mine else 1.0
		assert_true(w >= repo.bal("ledger_tie_min_px") * k - 0.001 and w <= repo.bal("ledger_tie_max_px") * k + 0.001,
			String(seg["id"]))


func test_selecting_someone_makes_them_the_lit_one() -> void:
	var other := ""
	for seg: Dictionary in _ties():
		if String(seg["a_id"]) != LedgerView3D.EGO_AT_REST and String(seg["b_id"]) != LedgerView3D.EGO_AT_REST:
			other = String(seg["a_id"])
			break
	view.select(other)
	for seg: Dictionary in _ties():
		if String(seg["a_id"]) == other or String(seg["b_id"]) == other:
			assert_gt((seg["ca"] as Color).a, pow(repo.bal("ledger_focus_fade"), 2.2) + 0.01, String(seg["id"]))


func test_a_court_tie_wears_its_clusters_colours_not_a_feeling() -> void:
	var court: Color = view._cluster_col["court"]
	var ties := _ties()
	assert_gt(ties.size(), 0)
	for seg: Dictionary in ties:
		for k: String in ["ca", "cb"]:
			var c: Color = seg[k]
			var id := String(seg["a_id"] if k == "ca" else seg["b_id"])
			var want: Color = view._cluster_col.get(view._cluster_of(id), court)
			# a tie whose accounts have aged leans toward thread_aged like any
			# other link; at the reign's first day none has
			assert_almost_eq(Vector3(c.r, c.g, c.b), Vector3(want.r, want.g, want.b), Vector3.ONE * 0.002,
				"%s %s" % [String(seg["id"]), k])
