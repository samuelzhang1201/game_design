# tests/ledger3d/test_ledger_strands.gd
extends GutTest
## Accounts that differ are drawn as STRANDS (spec 2026-09-30-ledger-
## governors-design §4, galaxy-design §5): one ribbon per account,
## ledger_strand_gap_px apart edge to edge on the screen, each picked as
## "<link id>#<i>".

var repo: DataRepository
var state: GameState
var view: LedgerView3D
var code := ""


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	RealmEconomy.forget()
	state.metrics["strategic"] = 1000000.0
	for c in state.regiments.keys():
		state.regiments[c]["supplies"] = 0
	var m: Character = state.characters[String(state.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = ["venal"]
	m.attributes["integrity"] = 50
	code = String(SupplySystem.plan(repo, state)[0]["code"])
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)  # set its own size, not the parent's
	view.size = Vector2(1000, 600)
	view.bind(repo)


func after_each() -> void:
	RealmEconomy.forget()


func _strands(g: Dictionary) -> Array:
	var link := ""
	for l: Dictionary in g["links"]:
		if String(l["type"]) == "supplies_out" and (l["accounts"] as Array).size() == 2:
			link = String(l["id"])
	return view.segments().filter(func(seg: Dictionary) -> bool: return String(seg["link"]) == link)


func test_two_accounts_are_two_strands_a_gap_apart() -> void:
	var g := Ledger.galaxy(repo, state, {})
	view.show_snapshot(g, false)
	view.settle_now()
	var st := _strands(g)
	assert_eq(st.size(), 2, "a venal marshal's word and the regiment's count")
	assert_true(String(st[0]["id"]).ends_with("#0") and String(st[1]["id"]).ends_with("#1"))
	var w0 := float(st[0]["width_px"])
	var w1 := float(st[1]["width_px"])
	assert_gt(w0, w1, "the claim is wider than what arrived")
	assert_almost_eq(absf(float(st[1]["shift_px"]) - float(st[0]["shift_px"])),
		(w0 + w1) * 0.5 + repo.bal("ledger_strand_gap_px") * view._window_scale(), 0.001, "edge to edge, a gap apart")


func test_a_strand_is_picked_by_its_own_id() -> void:
	var g := Ledger.galaxy(repo, state, {})
	view.show_snapshot(g, false)
	view.settle_now()
	var seg: Dictionary = _strands(g)[1]
	var ends := view.seg_ends(seg)
	# the first point along it, from its middle out, that lies on no star (a
	# star is picked before a link, and the layout may set one on the middle)
	var tried := 0
	for t: float in [0.5, 0.4, 0.6, 0.3, 0.7, 0.25, 0.75]:
		var p: Vector3 = (ends[0] as Vector3).lerp(ends[1], t)
		var at := view.camera().unproject_position(p) / view._window_scale()
		var hit := view._pick(at)
		if String(hit.get("kind", "")) == "sphere":
			continue
		tried += 1
		assert_eq(hit, {"kind": "thread", "id": String(seg["id"])})
		break
	assert_eq(tried, 1, "a point of the strand clear of every star")


## Review focus 5 / M-c: at a fractional window scale (1.5) the SubViewport
## renders at window px, and a strand's width and shift are window px.
func test_a_fractional_window_scale_draws_in_window_px() -> void:
	var root := get_tree().root
	var was_size := root.size
	var was_factor := root.content_scale_factor
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.5
	view._fit_viewport()
	var g := Ledger.galaxy(repo, state, {})
	view.show_snapshot(g, false)
	view.settle_now()
	var ws := view._window_scale()
	assert_almost_eq(ws, 1.5, 1e-4, "the window scale follows the content scale")
	assert_eq(view._viewport.size, Vector2i(int(view.size.x * 1.5), int(view.size.y * 1.5)), "window px")
	var st := _strands(g)
	assert_eq(st.size(), 2)
	var w0 := float(st[0]["width_px"])
	var w1 := float(st[1]["width_px"])
	var l: Dictionary = {}
	for x: Dictionary in g["links"]:
		if String(x["id"]) == String(st[0]["link"]):
			l = x
	var one := l.duplicate()
	one["flow"] = (l["accounts"] as Array)[0]["value"]
	one["accounts"] = [(l["accounts"] as Array)[0]]
	assert_almost_eq(w0, view._width_px(one) * 1.5, 1e-4, "the width in window px")
	assert_almost_eq(absf(float(st[1]["shift_px"]) - float(st[0]["shift_px"])),
		(w0 + w1) * 0.5 + repo.bal("ledger_strand_gap_px") * 1.5, 0.001, "the gap in window px")
	root.content_scale_factor = was_factor
	root.size = was_size
