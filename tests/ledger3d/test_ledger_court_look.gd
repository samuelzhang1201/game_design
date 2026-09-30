# tests/ledger3d/test_ledger_court_look.gd
extends GutTest
## The LEDGER's look rulings of 2026-09-30 (owner, choosing variant A): the
## court is read one person's web at a time — thin cords whose width follows
## the feeling, the player's own ties lit while no one is selected and the
## rest standing back, the selected person's ties lit once one is — and
## every layer's disc fades out over the same metres of rim.

var repo: DataRepository
var view: LedgerView3D
var snap: Dictionary


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	var state := GameState.new_campaign(repo, 42)
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.bind(repo)
	snap = Ledger.snapshot(repo, state, "court", {})
	view.show_snapshot(snap, true)


func _fade_of(link_id: String) -> float:
	var mi := view._thread_mi[link_id] as MeshInstance3D
	return float((mi.material_override as ShaderMaterial).get_shader_parameter("fade"))


func _touches(l: Dictionary, id: String) -> bool:
	return String(l["from"]) == id or String(l["to"]) == id


func test_a_court_tie_is_a_thin_cord_by_its_feeling() -> void:
	var lo := repo.bal("ledger_tie_width_min")
	var hi := repo.bal("ledger_tie_width_max")
	for l: Dictionary in snap["links"]:
		var r := ((view._thread_mi[String(l["id"])] as MeshInstance3D).mesh as CylinderMesh).top_radius
		var want := lerpf(lo, hi, clampf(absf(float(l["flow"])) / repo.bal("ledger_tie_ref"), 0.0, 1.0))
		assert_almost_eq(r, want, 0.0001, "%s is drawn by its feeling" % l["id"])
		assert_true(r <= hi + 0.0001, "no court tie is wider than a cord")


func test_at_rest_the_players_ties_are_lit_and_the_rest_stand_back() -> void:
	var lit := 0
	for l: Dictionary in snap["links"]:
		if _touches(l, LedgerView3D.EGO_AT_REST):
			lit += 1
			assert_eq(_fade_of(String(l["id"])), 1.0, "the player's tie %s is lit" % l["id"])
		else:
			assert_eq(_fade_of(String(l["id"])), repo.bal("ledger_tie_rest_fade"),
				"%s stands back while no one is selected" % l["id"])
	assert_gt(lit, 0, "the player has ties at court")


func test_selecting_someone_makes_them_the_lit_one() -> void:
	var other := ""
	for l: Dictionary in snap["links"]:
		if not _touches(l, LedgerView3D.EGO_AT_REST):
			other = String(l["from"])
			break
	assert_ne(other, "", "a courtier with a tie that does not touch the player")
	view.select(other)
	for l: Dictionary in snap["links"]:
		if _touches(l, other):
			assert_eq(_fade_of(String(l["id"])), 1.0, "the selected person's tie %s is lit" % l["id"])
	view.select("")
	for l: Dictionary in snap["links"]:
		if _touches(l, LedgerView3D.EGO_AT_REST):
			assert_eq(_fade_of(String(l["id"])), 1.0, "back at rest the player's ties are lit again")


func test_every_disc_fades_over_the_same_metres_of_rim() -> void:
	var m := repo.bal("ledger_disc_fade_m")
	var share := repo.bal("ledger_disc_fade_max_share")
	assert_almost_eq(view._fade_start(11.5), 1.0 - m / 11.5, 0.0001, "a large disc fades over its last metres")
	assert_almost_eq(view._fade_start(3.0), 1.0 - minf(m, 3.0 * share) / 3.0, 0.0001,
		"a small disc fades over at most its share")
	var disc := view.disc_of("people")
	var r := (disc.mesh as PlaneMesh).size.x * 0.5
	assert_almost_eq(float((disc.material_override as ShaderMaterial).get_shader_parameter("fade_start")),
		view._fade_start(r), 0.0001, "the drawn disc wears the fade for its own radius")
