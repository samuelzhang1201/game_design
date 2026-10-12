class_name OpeningNarration
extends RefCounted
## The opening background narration (owner 2026-10-12), cut into SEGMENTS: one
## topic a page, each in ONE audience-window box with no scrolling, the player
## pressing Continue to turn the page. The words are DATA in
## game_story/chapter_0/game_start.md: a `## left` / `## right` heading opens
## a segment and names the side of the box whose portrait speaks (left = Lord
## Malvern, right = the player's king); text before the first heading is
## ignored. {player_realm}-style tokens are filled from the loaded pack.

const PATH := "res://game_story/chapter_0/game_start.md"
const LEFT_ID := "char_lord_malvern"
const RIGHT_ID := "you"

## [{side: "left"|"right", portrait_id, text}], in reading order. Empty when
## the file is absent.
static func segments(data: DataRepository, path: String = PATH) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var side := ""
	var lines: Array = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var l := String(raw).strip_edges()
		if l.begins_with("## "):
			_close(out, side, lines, data)
			side = l.substr(3).strip_edges().to_lower()
			lines = []
		elif l.begins_with("#"):
			continue
		elif side != "":
			lines.append(l.replace("**", ""))
	_close(out, side, lines, data)
	return out

static func _close(out: Array, side: String, lines: Array, data: DataRepository) -> void:
	if side == "":
		return
	var text := "\n".join(lines).strip_edges()
	if data != null:
		text = data.fill_realms(text)
	out.append({"side": side, "text": text,
		"portrait_id": LEFT_ID if side == "left" else RIGHT_ID})

## The beats ConversationScene plays: a nameless "narration" beat per segment,
## carrying its page number, the page count and its side.
static func beats(data: DataRepository, path: String = PATH) -> Array:
	var segs := segments(data, path)
	var out: Array = []
	for i in segs.size():
		var s: Dictionary = segs[i]
		out.append({"kind": "narration", "portrait_id": "round_table", "speaker": "",
			"text": s["text"], "side": s["side"], "left_id": LEFT_ID,
			"right_id": RIGHT_ID, "page": i + 1, "pages": segs.size()})
	return out
