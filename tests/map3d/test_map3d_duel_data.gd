extends GutTest
## The duel's data (spec 2026-11-16-infantry-duel-animation-design.md): which
## clips an arm strikes, blocks, takes a hit and falls with (army_art.csv `duel`)
## and where in each clip the blade meets (`contact`).

const SuiteData := preload("res://tests/suite_data.gd")


func test_duel_columns_parse() -> void:
	var art := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
		"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.3;HIT:0.1"}
	assert_eq(Map3DClipChain.of_column(art, "duel")["STRIKE"], ["ATTACK", "SLASH"])
	assert_eq(Map3DDuel.contact_of(art), {"ATTACK": 0.4, "SLASH": 0.35, "BLOCK": 0.3, "HIT": 0.1})
	assert_eq(Map3DDuel.contact_of({}), {})
	assert_eq(Map3DDuel.contact_of({"contact": "ATTACK|0.4;SLASH:x"}), {}, "a malformed part is skipped")


func test_chains_still_read_through_the_column_parser() -> void:
	assert_eq(Map3DClipChain.of_art({"chains": "ATTACK:ATTACK;SLASH"}), Map3DClipChain.of_column({"chains": "ATTACK:ATTACK;SLASH"}, "chains"))


func test_the_infantry_row_names_the_new_infantrys_clips() -> void:
	var repo: DataRepository = SuiteData.repo()
	var duel := Map3DClipChain.of_column(repo.army_art["infantry"], "duel")
	assert_eq(duel.get("STRIKE"), ["ATTACK", "SLASH", "ATTACK_VAR1"])
	assert_eq(duel.get("BLOCK"), ["BLOCK", "BLOCK_2", "BLOCK_3", "BLOCK_4"])
	assert_eq(duel.get("HIT"), ["HIT", "HIT_2", "HIT_3"])
	assert_eq(duel.get("DEATH"), ["DEATH", "DEATH_2"])
	for piece: String in ["archers", "cavalry", "artillery", "royal"]:
		assert_eq(Map3DClipChain.of_column(repo.army_art.get(piece, {}), "duel"), {}, piece + " never duels")
