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


## The current is laid from the very buffer its stars are given: instance k
## of the whole stars is instance k of the current, the dimmed ones follow,
## each with the same transform and the same seed. The buffers are what the
## view hands each MultiMesh (`instance_buffer`): a headless run's dummy
## renderer keeps no instance data (get_instance_transform reads identity), so
## the test reads the one buffer assignment instead.
func test_the_current_is_laid_as_its_stars() -> void:
	_view()
	_show()
	view.focus_cluster("court")   # deal some stars to the dimmed MultiMesh
	var dealt := view.dealt()
	var whole: Array = dealt[0]
	var faint: Array = dealt[1]
	assert_gt(whole.size(), 0)
	assert_gt(faint.size(), 0, "the other clusters are dimmed")
	var S := LedgerStarMotion.STRIDE
	var stars := view.instance_buffer("Stars")
	var dim := view.instance_buffer("FaintStars")
	var sparks := view.instance_buffer("Sparks")
	assert_eq(stars.size(), whole.size() * S)
	assert_eq(dim.size(), faint.size() * S)
	assert_eq(sparks.size(), (whole.size() + faint.size()) * S, "one current per drawn star")
	assert_eq(view.sparks().multimesh.instance_count, whole.size() + faint.size())
	for k in whole.size():
		var id := String(whole[k])
		var t := LedgerStarMotion.transform_at(stars, k)
		assert_almost_eq(t.origin, view.drawn(id), Vector3.ONE * 1e-4, "a star stands where it is drawn")
		assert_gt(t.basis.x.x, 0.0)
		assert_eq(LedgerStarMotion.transform_at(sparks, k), t, "its current laid as it")
		assert_eq(LedgerStarMotion.custom_at(stars, k), view.star_custom(id))
		assert_eq(LedgerStarMotion.custom_at(sparks, k), view.star_custom(id))
	for k in faint.size():
		var id := String(faint[k])
		assert_eq(LedgerStarMotion.transform_at(sparks, whole.size() + k), LedgerStarMotion.transform_at(dim, k))
		assert_eq(LedgerStarMotion.custom_at(dim, k), view.star_custom(id))
		assert_eq(LedgerStarMotion.colour_at(sparks, whole.size() + k), LedgerStarMotion.colour_at(dim, k))
	# the seed is the star's own wherever it is dealt, and the weight its state
	var c := LedgerStarMotion.custom_at(dim, 0)
	var seed := LedgerStarMotion.seed_of(String(faint[0]))
	assert_eq(Vector2(c.r, c.g), Vector2(seed.r, seed.g))
	assert_almost_eq(c.b, repo.bal("ledger_spark_dimmed") * pow(view.star_colour(String(faint[0])).a, 2.2), 1e-6,
		"a dimmed star's current is its share of its perceived opacity")
	assert_almost_eq(LedgerStarMotion.custom_at(stars, 0).b, 1.0, 1e-6)


## A camera move lays every star again (the screen cap): its current moves with it.
func test_a_camera_move_relays_the_current_with_the_stars() -> void:
	_view()
	_show()
	view.orbit().zoom(0.5)
	view._apply_camera()
	view._place_stars()
	var stars := view.instance_buffer("Stars")
	var sparks := view.instance_buffer("Sparks")
	for k in stars.size() / LedgerStarMotion.STRIDE:
		assert_eq(LedgerStarMotion.transform_at(sparks, k), LedgerStarMotion.transform_at(stars, k))


## Every star shader moves by the ONE shared wobble, called the same way, so a
## star and its current never part.
func test_every_star_shader_wobbles_by_the_shared_formula() -> void:
	var call := "star_wobble(INSTANCE_CUSTOM, length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX, TIME)"
	for path: String in ["res://scenes/ledger/star.gdshader", "res://scenes/ledger/star_faint.gdshader",
			"res://scenes/ledger/spark.gdshader"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains('#include "res://scenes/ledger/star_motion.gdshaderinc"'), path)
		assert_true(text.contains(call), path + " calls " + call)


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
	assert_eq(view.instance_buffer("Sparks").size(), view.stars().size() * LedgerStarMotion.STRIDE)


func test_strength_zero_draws_no_current() -> void:
	repo.balance["ledger_spark_strength"] = 0.0
	_view()
	_show()
	assert_eq(view.sparks().multimesh.instance_count, 0)
	assert_true(view.instance_buffer("Sparks").is_empty())
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
	var k: int = (view.dealt()[0] as Array).find("character:you")
	assert_gt(k, -1, "the selected star is whole")
	var u := LedgerStarMotion.custom_at(view.instance_buffer("Sparks"), k)
	assert_almost_eq(u.b, repo.bal("ledger_spark_selected"), 1e-6, "its current, as handed to the renderer")
	assert_eq(u.a, 1.0, "laid outside its ring")
	view.select("")
	assert_almost_eq(view.star_custom("character:you").b, 1.0, 1e-6, "and back once let go")
	assert_eq(view.star_custom("character:you").a, 0.0)


## The selected star's current starts just past its gold ring: the ring's own
## width and gap off the disc, in SubViewport px.
func test_the_selected_current_clears_its_ring() -> void:
	_view()
	_show()
	var ring := float(view.spark_material().get_shader_parameter("ring_out_px"))
	var ws := maxf(view.get_viewport().get_final_transform().get_scale().x, 1.0)
	assert_almost_eq(ring, repo.bal("ledger_ring_px") * (LedgerView3D.RING_GAP_RINGS + 1.0) * ws, 1e-4)
	assert_gt(ring, repo.bal("ledger_ring_px") * LedgerView3D.RING_GAP_RINGS * ws, "past the ring's centre line")
	assert_eq(float(view.spark_material().get_shader_parameter("ortho_m_per_px")), 0.0, "perspective at rest")
	assert_almost_eq(float(view.spark_material().get_shader_parameter("ring_band_px")), repo.bal("ledger_ring_px") * ws, 1e-4,
		"its sparks keep within one ring width past it")
