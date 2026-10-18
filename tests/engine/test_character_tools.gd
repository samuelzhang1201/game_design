extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## CharacterTools (user request 2026-08-31): the dossier's SKILLS tab lists
## the tools a courtier can be called on to use — kingdom operations bound to
## their council seat, and person-to-person tools everyone has — with
## human-readable labels from the action CSVs, never raw codes.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)

func test_marshal_kingdom_tools_are_his_seats_implemented_actions() -> void:
	var tools := CharacterTools.kingdom_tools(data, state.characters["char_marshal"])
	assert_gt(tools.size(), 0, "a seated minister has kingdom tools")
	var advises := String(data.seats["marshal"]["advises_on"]).split("|", false)
	var labels: Array = []
	for t in tools:
		assert_has(advises, String(t["code"]), "every kingdom tool comes from advises_on")
		assert_true(data.actions.has(t["code"]), "only implemented actions are listed")
		labels.append(String(t["label"]))
	assert_has(labels, "Train the standing army", "labels are the CSV's human-readable text")

func test_unimplemented_advises_on_codes_are_not_listed() -> void:
	# The marshal's seat advises on ARMY_MOVE etc., which have no action row
	# yet — a tool the game cannot actually call must never be shown.
	for t in CharacterTools.kingdom_tools(data, state.characters["char_marshal"]):
		assert_ne(String(t["code"]), "ARMY_MOVE")

func test_unseated_courtier_has_personal_tools_only() -> void:
	var princess: Character = state.characters["char_princess"]
	assert_eq(CharacterTools.kingdom_tools(data, princess).size(), 0,
		"no seat, no kingdom operations")
	var labels: Array = []
	for t in CharacterTools.personal_tools(data, princess):
		labels.append(String(t["label"]))
	assert_has(labels, "Confide in a courtier")
	assert_false("Rule on a council dispute" in labels,
		"only actions flagged personal=yes qualify")

func test_personal_tools_never_repeat_a_kingdom_tool() -> void:
	# A hypothetical Chief Justice advises on CHARACTER_PUNISH, which is also
	# flagged personal — it must appear once, on the kingdom side.
	var c := Character.new()
	c.seat = "chief_justice"
	var kingdom_codes: Array = []
	for t in CharacterTools.kingdom_tools(data, c):
		kingdom_codes.append(String(t["code"]))
	assert_has(kingdom_codes, "CHARACTER_PUNISH")
	for t in CharacterTools.personal_tools(data, c):
		assert_false(String(t["code"]) in kingdom_codes,
			"personal list must not repeat " + String(t["code"]))
