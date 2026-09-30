# tests/ledger3d/test_ledger_court_look.gd
extends GutTest
## The LEDGER's look rulings of 2026-09-30 (owner, choosing variant A): the
## court is read one person's web at a time — thin cords whose width follows
## the feeling, the player's own ties lit while no one is selected and the
## rest standing back, the selected person's ties lit once one is.

var repo: DataRepository
var view: LedgerView3D
var snap: Dictionary


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	var state := GameState.new_campaign(repo, 42)
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
		assert_true(w >= repo.bal("ledger_tie_min_px") - 0.001 and w <= repo.bal("ledger_tie_max_px") + 0.001,
			String(seg["id"]))


func test_at_rest_the_players_ties_are_lit_and_the_rest_stand_back() -> void:
	var rest := pow(repo.bal("ledger_tie_rest_fade"), 2.2)
	for seg: Dictionary in _ties():
		var mine := String(seg["a_id"]) == LedgerView3D.EGO_AT_REST or String(seg["b_id"]) == LedgerView3D.EGO_AT_REST
		var a := (seg["ca"] as Color).a
		if mine:
			assert_gt(a, rest + 0.01, "the player's tie is lit: " + String(seg["id"]))
		else:
			assert_lte(a, rest + 0.001, "stands back: " + String(seg["id"]))


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
