# tests/ledger3d/test_ledger_star_motion.gd
extends GutTest
## The stars' wobble and the current round them (owner 2026-10-01): every
## number is a balance.csv key bound to a uniform, the current is one MultiMesh
## instance per drawn star laid as its star, and 0 turns each off. Headless:
## the dummy renderer draws nothing; the shaders' compile is checked in a real
## window (snapshot_screen), never here.

var repo: DataRepository
var s: GameState
var view: LedgerView3D


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	s = GameState.new_campaign(repo, 42)
	RealmEconomy.forget()


func after_each() -> void:
	RealmEconomy.forget()


func _view() -> LedgerView3D:
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 600)
	view.bind(repo)
	return view


func _show(opened: Dictionary = {}) -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, opened), false)
	view.settle_now()


func test_every_key_binds_to_its_uniform() -> void:
	# a distinct value per key, so a key bound to the wrong uniform is caught
	var want := {}
	var v := 0.11
	for key: String in LedgerStarMotion.WOBBLE.keys() + LedgerStarMotion.SPARK.keys():
		assert_true(repo.balance.has(key), "balance.csv has " + key)
		repo.balance[key] = v
		want[key] = v
		v += 0.07
	_view()
	for m: ShaderMaterial in view.star_materials() + [view.spark_material()]:
		for key: String in LedgerStarMotion.WOBBLE:
			assert_almost_eq(float(m.get_shader_parameter(LedgerStarMotion.WOBBLE[key])), float(want[key]), 1e-5, key)
	for key: String in LedgerStarMotion.SPARK:
		assert_almost_eq(float(view.spark_material().get_shader_parameter(LedgerStarMotion.SPARK[key])),
			float(want[key]), 1e-5, key)


func test_the_current_is_one_instance_per_drawn_star_laid_as_its_star() -> void:
	_view()
	_show()
	var mm := view.sparks().multimesh
	assert_eq(mm.instance_count, view.stars().size(), "every star, whole and dimmed")
	assert_eq(view.spark_ids().size(), view.stars().size())
	# dim a cluster: the stars are dealt again between the two MultiMeshes,
	# and the current follows them, whole first, then the dimmed
	view.focus_cluster("court")
	var dealt := view.dealt()
	var whole: Array = dealt[0]
	var faint: Array = dealt[1]
	assert_gt(faint.size(), 0, "the other clusters are dimmed")
	assert_eq((view.get_node("%Stars") as MultiMeshInstance3D).multimesh.instance_count, whole.size())
	assert_eq((view.get_node("%FaintStars") as MultiMeshInstance3D).multimesh.instance_count, faint.size())
	assert_eq(mm.instance_count, whole.size() + faint.size())
	assert_eq(view.spark_ids(), whole + faint, "the current in the stars' own order")
	# a dimmed star's current is almost none, a whole one's whole
	var fade := view.star_colour(String(faint[0])).a
	assert_almost_eq(view.star_custom(String(faint[0])).b, repo.bal("ledger_spark_dimmed") * pow(fade, 2.2), 1e-6)
	assert_lt(view.star_custom(String(faint[0])).b, 0.05, "a dimmed star's current is almost none")
	assert_almost_eq(view.star_custom(String(whole[0])).b, 1.0, 1e-6)
	# the seed is the star's own, wherever it is dealt
	var c := view.star_custom(String(faint[0]))
	var seed := LedgerStarMotion.seed_of(String(faint[0]))
	assert_eq(Vector2(c.r, c.g), Vector2(seed.r, seed.g))


func test_the_current_is_rebuilt_with_the_stars() -> void:
	_view()
	_show()
	var before := view.sparks().multimesh.instance_count
	var code := ""
	for id: String in view.stars():
		if id.begins_with("province:"):
			code = id.trim_prefix("province:")
			break
	_show({code: true})
	assert_gt(view.stars().size(), before, "an opened province unfolds stars")
	assert_eq(view.sparks().multimesh.instance_count, view.stars().size())


func test_strength_zero_draws_no_current() -> void:
	repo.balance["ledger_spark_strength"] = 0.0
	_view()
	_show()
	assert_eq(view.sparks().multimesh.instance_count, 0)
	assert_true(view.spark_ids().is_empty())
	assert_gt((view.get_node("%Stars") as MultiMeshInstance3D).multimesh.instance_count, 0, "the stars still drawn")


func test_share_zero_holds_every_star_still() -> void:
	repo.balance["ledger_star_wobble_share"] = 0.0
	_view()
	for m: ShaderMaterial in view.star_materials() + [view.spark_material()]:
		assert_eq(float(m.get_shader_parameter("wobble_share")), 0.0)


func test_a_stars_seed_is_its_ids_and_its_weight_its_state() -> void:
	var a := LedgerStarMotion.seed_of("character:you")
	assert_eq(a, LedgerStarMotion.seed_of("character:you"), "the same every time")
	assert_ne(a, LedgerStarMotion.seed_of("character:marshal"))
	assert_between(a.r, 0.0, 1.0)
	assert_between(a.g, 0.0, 1.0)
	assert_almost_eq(LedgerStarMotion.custom_of(repo, "x", 1.0, false).b, 1.0, 1e-6)
	assert_almost_eq(LedgerStarMotion.custom_of(repo, "x", 0.4, false).b,
		repo.bal("ledger_spark_dimmed") * pow(0.4, 2.2), 1e-6, "dimmed: its share of the star's perceived opacity")
	assert_almost_eq(LedgerStarMotion.custom_of(repo, "x", 1.0, true).b, repo.bal("ledger_spark_selected"), 1e-6)


func test_the_selected_stars_current_is_stronger() -> void:
	_view()
	_show()
	view.select("character:you")
	assert_almost_eq(view.star_custom("character:you").b, repo.bal("ledger_spark_selected"), 1e-6)
	view.select("")
	assert_almost_eq(view.star_custom("character:you").b, 1.0, 1e-6, "and back once let go")


## The wobble never reaches the edge of a star's own disc, so the links drawn
## to its centre stay hidden in it; its loop is the 3–6 s the owner approved.
func test_the_wobble_stays_inside_the_disc() -> void:
	var share := repo.bal("ledger_star_wobble_share")
	assert_gt(share, 0.0)
	assert_lt(share * sqrt(2.0), 0.5, "the loop's corner is well inside the disc")
	assert_lte(repo.bal("ledger_star_wobble_period_min"), repo.bal("ledger_star_wobble_period_max"))
