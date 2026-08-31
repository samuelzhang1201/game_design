class_name StorySource
extends RefCounted
## Event scene prose, read from the author's own story document
## (RANDOM_EVENTS.md) rather than from CSV or from a model (user ruling
## 2026-08-31: every event story is fixed, authored text; no prompt ever
## generates or rewrites one).
##
## The document's shape is therefore a runtime contract:
##
##   ### EV-08 · The Two-Headed Calf — `folk · once`
##   **Trigger:** year 1+, weight 2. **Scene:** A calf with two heads is born...
##   **Choices:** ...
##
## Trigger and Scene share a line, so a scene runs from `**Scene:**` to the
## end of that line. Heading ids are normalised ("EV-08" -> "ev_08") to match
## events.csv. Deterministic, no RNG, no Nodes.

const DEFAULT_PATH := "res://RANDOM_EVENTS.md"
const SCENE_FIELD := "**Scene:**"
const HEADING_PREFIX := "### EV-"

## event_id -> scene text. Empty when the file is absent: a missing document
## is not a crash, and the coverage test turns it into a loud failure.
static func load_scenes(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path))

## Parses the document text. Split out so it can be unit-tested against small
## fixtures without touching the filesystem.
static func parse(document: String) -> Dictionary:
	var out: Dictionary = {}
	var current := ""
	for raw_line in document.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with(HEADING_PREFIX):
			current = _id_from_heading(line)
		elif current != "" and line.contains(SCENE_FIELD):
			var scene := line.substr(line.find(SCENE_FIELD) + SCENE_FIELD.length())
			out[current] = _plain_text(scene)
			current = ""
	return out

## "### EV-08 · The Two-Headed Calf — `folk`" -> "ev_08". Takes the token
## right after the prefix so a title containing digits cannot confuse it.
static func _id_from_heading(line: String) -> String:
	var rest := line.substr(HEADING_PREFIX.length()).strip_edges()
	var number := ""
	for i in rest.length():
		var c := rest[i]
		if c >= "0" and c <= "9":
			number += c
		else:
			break
	return "ev_" + number if number != "" else ""

## Strips the markdown a Label cannot render. Emphasis markers go; the words
## they wrapped stay.
static func _plain_text(text: String) -> String:
	return text.replace("**", "").replace("*", "").replace("`", "").strip_edges()
