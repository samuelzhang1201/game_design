extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## LedgerSearch (owner 2026-10-01: 在ledger界面新增一个搜索栏，可以搜索node):
## stars and folded instances found by label, case-insensitively.

var repo: DataRepository
var state: GameState
var snap: Dictionary


func before_all() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	snap = Ledger.galaxy(repo, state, {})


func _a_province() -> Dictionary:
	for n: Dictionary in snap["nodes"]:
		if String(n["type"]) == "province":
			return n
	return {}


func test_a_star_is_found_by_its_label_in_any_case() -> void:
	var idx := LedgerSearch.index(repo, state, snap)
	var p := _a_province()
	assert_false(p.is_empty())
	for text: String in [String(p["label"]).to_upper(), String(p["label"]).to_lower()]:
		var found := LedgerSearch.matches(idx, text, 8)
		assert_false(found.is_empty(), text)
		assert_eq(String(found[0]["id"]), String(p["id"]), "the star itself first: " + text)
		assert_eq(String(found[0]["kind"]), "province")
		assert_eq(String(found[0]["fold"]), "", "a drawn star needs nothing opened")


func test_a_folded_manor_is_found_with_its_province() -> void:
	var folded: Dictionary = snap["folded"]
	var manor := ""
	for id: String in folded:
		if id.begins_with("manor:"):
			manor = id
			break
	assert_ne(manor, "", "the galaxy folds manors")
	var idx := LedgerSearch.index(repo, state, snap)
	var label := LedgerResolvers.label_of(repo, state, manor)
	var hit: Array = idx.filter(func(e: Dictionary) -> bool: return String(e["id"]) == manor)
	assert_eq(hit.size(), 1)
	assert_eq(String(hit[0]["fold"]), String(folded[manor]), "it names the province to open")
	assert_eq(String(hit[0]["label"]), label)
	assert_eq(String(hit[0]["kind"]), "manor")


func test_a_prefix_ranks_before_a_substring_and_the_limit_holds() -> void:
	var idx := [
		{"id": "b", "label": "Old Walbover", "low": "old walbover", "kind": "x", "fold": ""},
		{"id": "c", "label": "Sowalb", "low": "sowalb", "kind": "x", "fold": ""},
		{"id": "a", "label": "Walbover", "low": "walbover", "kind": "x", "fold": "province:p"},
		{"id": "d", "label": "Walden", "low": "walden", "kind": "x", "fold": ""}]
	var found := LedgerSearch.matches(idx, "WALB", 8)
	assert_eq(found.map(func(e: Dictionary) -> String: return String(e["id"])), ["a", "b", "c"])
	assert_eq(LedgerSearch.matches(idx, "wal", 2).size(), 2, "at most the limit")
	assert_eq(LedgerSearch.matches(idx, "   ", 8), [], "blank finds nothing")
