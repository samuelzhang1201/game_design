extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Event scene prose comes from RANDOM_EVENTS.md, the author's own story
## document (user ruling 2026-08-31). No model ever writes or rewrites an
## event; the markdown is the single source and templates.csv no longer
## carries a duplicate that could drift from it.

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_every_event_in_events_csv_has_a_scene() -> void:
	# Monthly, chapter and battle-only prose share the authored documents.
	assert_eq(data.event_scenes.size(), data.events.size() + data.chapter_events.size() + data.battle_events.size(),
		"every authored event has a parsed scene, and nothing else is in there")
	assert_eq(data.events.size(), 30, "the random pool: 20 starter events and 10 development ones")
	for row in data.events + data.chapter_events + data.battle_events.values():
		var id := String(row["event_id"])
		assert_true(data.event_scenes.has(id), id + " has authored scene text")
		assert_ne(String(data.event_scenes[id]).strip_edges(), "",
			id + "'s scene is not blank")


## ev_08 read from the document: its own words, emphasis stripped, and the
## Scene field alone though Trigger shares its line.
func test_ev_08_is_the_documents_scene_as_displayed() -> void:
	var scene := String(data.event_scenes["ev_08"])
	# The document's calf scene says the Steward notes it "mildly" — a word
	# that never appeared in the old templates.csv copy. If this passes, the
	# text genuinely came from RANDOM_EVENTS.md.
	assert_string_contains(scene, "two heads")
	assert_string_contains(scene, "mildly",
		"proves the source is the markdown, not the retired CSV row")
	# "*two heads, two kings.*" must not reach a Label with its asterisks.
	assert_false(scene.contains("*"), "no markdown emphasis survives")
	assert_false(scene.contains("**Choices:**"), "the scene stops at its own field")
	# Trigger and Scene share a line; only the Scene half is the story.
	assert_false(scene.contains("Trigger"))
	assert_false(scene.contains("weight"))
	assert_true(scene.begins_with("A calf"), "scene starts at its own first word")

func test_parses_a_minimal_document() -> void:
	var doc := "### EV-03 · A Title — `court · mini`\n" \
		+ "**Trigger:** always. **Scene:** The hall goes *quiet*.\n" \
		+ "**Choices:** (1) Nothing.\n"
	var out := StorySource.parse(doc)
	assert_eq(out.size(), 1)
	assert_eq(String(out["ev_03"]), "The hall goes quiet.")

func test_entry_without_a_scene_field_is_omitted_not_faked() -> void:
	var doc := "### EV-04 · No Scene Here — `folk`\n**Trigger:** always.\n"
	assert_eq(StorySource.parse(doc).size(), 0,
		"a missing scene is absent, so the coverage test fails loudly")

func test_missing_document_yields_no_scenes_rather_than_crashing() -> void:
	assert_eq(StorySource.load_scenes("res://no_such_story.md").size(), 0)
