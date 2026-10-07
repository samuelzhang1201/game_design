class_name StorySource
extends RefCounted
## Event scene prose, read from the author's own story documents
## (RANDOM_EVENTS.md for the random pool, game_story/chapter_0/ for the
## prologue) rather than from CSV or from a model (user ruling 2026-08-31:
## every event story is fixed, authored text; no prompt ever generates or
## rewrites one).
##
## A document's shape is therefore a runtime contract:
##
##   ### EV-08 · The Two-Headed Calf — `folk · once`
##   **Trigger:** year 1+, weight 2. **Scene:** A calf with two heads is born...
##   **Choices:** ...
##
## Trigger and Scene share a line, so a scene runs from `**Scene:**` to the
## end of that line. The heading carries two things: the id ("EV-08" ->
## "ev_08", matching events.csv) and the TITLE — what stands between the
## first "·" and the trailing "— `tags`" — which the audience window's
## banner shows over the event. Deterministic, no RNG, no Nodes.

const DEFAULT_PATH := "res://RANDOM_EVENTS.md"
const SCENE_FIELD := "**Scene:**"
const HEADING_PREFIX := "### EV-"
const ID_PREFIX := "ev_"

## Every story document the game loads, with the heading prefix that opens an
## entry and the id prefix its number becomes. Adding a chapter is adding a
## row here plus its own `data/chapter_events.csv` rows.
const DOCUMENTS: Array[Dictionary] = [
	{"path": DEFAULT_PATH, "heading": HEADING_PREFIX, "id": ID_PREFIX},
	{"path": "res://game_story/chapter_0/chapter_0_events.md",
		"heading": "### C0-", "id": "c0_"},
	# the beats the engine fires off the war (DefeatSystem), not the chain
	{"path": "res://game_story/chapter_0/war_events.md",
		"heading": "### W-", "id": "war_"},
]

## event_id -> scene text, over every document. Empty when the files are
## absent: a missing document is not a crash, and the coverage tests turn it
## into a loud failure.
static func load_all_scenes() -> Dictionary:
	var out: Dictionary = {}
	for doc: Dictionary in DOCUMENTS:
		out.merge(load_scenes(String(doc["path"]), String(doc["heading"]),
			String(doc["id"])))
	return out

## event_id -> the title from its heading, over every document.
static func load_all_titles() -> Dictionary:
	var out: Dictionary = {}
	for doc: Dictionary in DOCUMENTS:
		out.merge(load_titles(String(doc["path"]), String(doc["heading"]),
			String(doc["id"])))
	return out

static func load_scenes(path: String = DEFAULT_PATH,
		heading: String = HEADING_PREFIX, id_prefix: String = ID_PREFIX) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path), heading, id_prefix)

static func load_titles(path: String = DEFAULT_PATH,
		heading: String = HEADING_PREFIX, id_prefix: String = ID_PREFIX) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse_titles(FileAccess.get_file_as_string(path), heading, id_prefix)

## Parses the document text. Split out so it can be unit-tested against small
## fixtures without touching the filesystem.
static func parse(document: String, heading: String = HEADING_PREFIX,
		id_prefix: String = ID_PREFIX) -> Dictionary:
	var out: Dictionary = {}
	var current := ""
	for raw_line in document.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with(heading):
			current = _id_from_heading(line, heading, id_prefix)
		elif current != "" and line.contains(SCENE_FIELD):
			var scene := line.substr(line.find(SCENE_FIELD) + SCENE_FIELD.length())
			out[current] = _plain_text(scene)
			current = ""
	return out

## The titles beside the ids: "### C0-05 · The Ledger — `chapter`" -> "The
## Ledger". An entry with no "·" keeps whatever follows the id.
static func parse_titles(document: String, heading: String = HEADING_PREFIX,
		id_prefix: String = ID_PREFIX) -> Dictionary:
	var out: Dictionary = {}
	for raw_line in document.split("\n"):
		var line := String(raw_line).strip_edges()
		if not line.begins_with(heading):
			continue
		var id := _id_from_heading(line, heading, id_prefix)
		if id == "":
			continue
		var title := line.substr(heading.length())
		var dot := title.find("·")
		title = title.substr(dot + 1) if dot >= 0 else title
		var dash := title.find("—")
		title = title.substr(0, dash) if dash >= 0 else title
		out[id] = _plain_text(title)
	return out

## "### EV-08 · The Two-Headed Calf — `court · mini`" -> "ev_08". Takes the
## token right after the prefix so a title containing digits cannot confuse
## it, and keeps a trailing letter ("C0-03S" -> "c0_03s") so a branch of one
## beat can carry its own id.
static func _id_from_heading(line: String, heading: String = HEADING_PREFIX,
		id_prefix: String = ID_PREFIX) -> String:
	var rest := line.substr(heading.length()).strip_edges()
	var token := ""
	for i in rest.length():
		var c := rest[i]
		if (c >= "0" and c <= "9") or (token != "" and c >= "A" and c <= "Z"):
			token += c
		else:
			break
	return id_prefix + token.to_lower() if token != "" else ""

## Strips the markdown a Label cannot render. Emphasis markers go; the words
## they wrapped stay.
static func _plain_text(text: String) -> String:
	return text.replace("**", "").replace("*", "").replace("`", "").strip_edges()
