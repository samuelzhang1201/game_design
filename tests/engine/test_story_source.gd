extends GutTest
## Event scene prose comes from RANDOM_EVENTS.md, the author's own story
## document (user ruling 2026-08-31). No model ever writes or rewrites an
## event; the markdown is the single source and templates.csv no longer
## carries a duplicate that could drift from it.

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_every_event_in_events_csv_has_a_scene() -> void:
	# The random pool's 20, plus every beat of every scripted chapter: the
	# documents are loaded together (StorySource.DOCUMENTS) into one table.
	assert_eq(data.event_scenes.size(), data.events.size() + data.chapter_events.size(),
		"every event in both tables has a parsed scene, and nothing else is in there")
	assert_eq(data.events.size(), 20, "the random pool is still 20")
	for row in data.events + data.chapter_events:
		var id := String(row["event_id"])
		assert_true(data.event_scenes.has(id), id + " has authored scene text")
		assert_ne(String(data.event_scenes[id]).strip_edges(), "",
			id + "'s scene is not blank")

func test_heading_ids_are_normalised_to_event_ids() -> void:
	# The document heads entries "### EV-08 ·"; events.csv calls it "ev_08".
	assert_true(data.event_scenes.has("ev_08"))
	assert_true(data.event_scenes.has("ev_01"))
	assert_true(data.event_scenes.has("ev_20"))

func test_scene_text_comes_from_the_markdown_not_the_csv() -> void:
	# The document's calf scene says the Steward notes it "mildly" — a word
	# that never appeared in the old templates.csv copy. If this passes, the
	# text genuinely came from RANDOM_EVENTS.md.
	var scene := String(data.event_scenes["ev_08"])
	assert_string_contains(scene, "two heads")
	assert_string_contains(scene, "mildly",
		"proves the source is the markdown, not the retired CSV row")

func test_markdown_emphasis_is_stripped_for_display() -> void:
	# "*two heads, two kings.*" must not reach a Label with its asterisks.
	var scene := String(data.event_scenes["ev_08"])
	assert_false(scene.contains("*"), "no markdown emphasis survives")
	assert_false(scene.contains("**Choices:**"), "the scene stops at its own field")

func test_scene_excludes_the_trigger_that_precedes_it_on_the_line() -> void:
	# Trigger and Scene share a line; only the Scene half is the story.
	var scene := String(data.event_scenes["ev_08"])
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
