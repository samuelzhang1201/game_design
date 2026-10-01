extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A selected star's LINEAGE (owner 2026-10-01: 我需要点击一个node的时候，
## highlight整个lineage — the hybrid): its own links, the flow chain down and
## up from it and its neighbours, its ties two hops (the second far).

var repo: DataRepository
var looks := {}


func before_all() -> void:
	repo = SuiteData.repo()
	for r: Dictionary in repo.ledger_links:
		looks[String(r["link_id"])] = String(r["look"])


func _look(l: Dictionary) -> String:
	return String(looks.get(String(l["type"]), "flow"))


func _hand(look: Dictionary) -> Callable:
	return func(l: Dictionary) -> String: return String(look.get(String(l["type"]), "flow"))


func _snap(ids: Array, links: Array) -> Dictionary:
	var nodes: Array = []
	for id: String in ids:
		nodes.append({"id": id})
	var ls: Array = []
	for l: Array in links:
		ls.append({"id": "%s|%s|%s" % [l[2], l[0], l[1]], "from": l[0], "to": l[1], "type": l[2],
			"status": l[3] if l.size() > 3 else "live"})
	return {"nodes": nodes, "links": ls}


## Hand-built: the flow chain runs one way to its end, never back; structure
## is not followed past the first hop; ties go two hops, the second FAR.
func test_the_hybrid_by_hand() -> void:
	var look := {"f": "flow", "s": "structure", "t": "tie"}
	var snap := _snap(["x", "a", "b", "c", "d", "u", "n", "m", "t1", "t2", "z"], [
		["x", "a", "f"], ["a", "b", "f"], ["b", "c", "f"],   # downstream x -> a -> b -> c
		["d", "b", "f"],                                     # flows INTO b: not walked back from b
		["u", "x", "f"],                                     # upstream of x
		["x", "n", "s"], ["n", "m", "s"],                    # structure: n lit, m not
		["n", "z", "f"],                                     # a neighbour's own flow chain
		["x", "t1", "t"], ["t1", "t2", "t"],                 # ties: t1 full, t2 far
		["x", "g", "f", "planned"]])
	var lin := LedgerLineage.of(snap, "x", _hand(look), 2)
	var st: Dictionary = lin["stars"]
	for id: String in ["x", "a", "b", "c", "u", "n", "z", "t1", "g"]:
		assert_eq(int(st.get(id, 0)), LedgerLineage.FULL, id + " full")
	assert_eq(int(st.get("t2", 0)), LedgerLineage.FAR, "a tie of a tie is far")
	assert_false(st.has("d"), "the chain never turns back mid-walk")
	assert_false(st.has("m"), "structure past the first hop is not followed")
	assert_eq(int(lin["links"]["t|t1|t2"]), LedgerLineage.FAR)
	assert_eq(int(lin["links"]["f|b|c"]), LedgerLineage.FULL)
	assert_false(LedgerLineage.of(snap, "x", _hand(look), 2, false)["stars"].has("g"),
		"without planned links the ghost's end is left out")
	assert_eq(LedgerLineage.of(snap, "x", _hand(look), 1)["stars"].has("t2"), false, "one tie hop: no far ties")
	assert_true((LedgerLineage.of(snap, "nobody", _hand(look))["stars"] as Dictionary).is_empty())


## The owner's anchors on the real pack after six months (seed 42), counts
## derived from the data: a regiment lights its supply chain; the King his
## ties and his house, and his ties' ties dimmer.
func test_the_real_pack_anchors() -> void:
	var s := SuiteData.campaign(repo, 42)
	var eng := TickEngine.new(repo)
	for i in 6:
		eng.advance(s)
		s.pending_event = {}
	var g := Ledger.galaxy(repo, s, {})
	var reg := ""
	for n: Dictionary in g["nodes"]:
		if String(n["type"]) == "regiment" and (g["nodes"] as Array).any(func(m: Dictionary) -> bool:
				return String(m["id"]) == "supply_line:" + String(n["id"]).substr(9)):
			reg = String(n["id"])
			break
	assert_ne(reg, "", "a regiment with a supply line")
	var lin := LedgerLineage.of(g, reg, _look, 2)
	var st: Dictionary = lin["stars"]
	var line := "supply_line:" + reg.substr(9)
	assert_eq(int(st.get(line, 0)), LedgerLineage.FULL, "its supply line")
	assert_eq(int(st.get("type:strategic_goods", 0)), LedgerLineage.FULL, "the strategic goods it is fed from")
	# whatever feeds the strategic goods is lit (markets, a province's manors)
	var feeders := 0
	for l: Dictionary in g["links"]:
		if String(l["to"]) == "type:strategic_goods" and _look(l) == "flow" and String(l["status"]) == "live":
			feeders += 1
			assert_eq(int(st.get(String(l["from"]), 0)), LedgerLineage.FULL, String(l["from"]) + " feeds the chain")
	assert_gt(feeders, 0)
	assert_gt(st.size(), 6, "more than its neighbours: %d" % st.size())
	# the King: his own ties and his house full, the ties of his ties far
	var king := LedgerLineage.of(g, "character:you", _look, 2)
	var ks: Dictionary = king["stars"]
	var own := 0
	for l: Dictionary in g["links"]:
		if String(l["from"]) == "character:you" or String(l["to"]) == "character:you":
			own += 1
			var other := String(l["to"]) if String(l["from"]) == "character:you" else String(l["from"])
			assert_eq(int(ks.get(other, 0)), LedgerLineage.FULL, other)
	assert_gt(own, 0)
	var far := ks.values().filter(func(v: int) -> bool: return v == LedgerLineage.FAR).size()
	assert_gt(far, 0, "his ties' ties, dimmer")
	for id: String in ks:
		if int(ks[id]) == LedgerLineage.FAR:
			assert_true(String(id).begins_with("character:"), "a far star is a person: " + id)
