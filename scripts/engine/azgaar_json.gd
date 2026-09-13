class_name AzgaarJson
extends RefCounted
## Reading an Azgaar "Full" export. Azgaar (1.151) sometimes writes marker
## legends containing astral-plane glyphs as *unpaired* \uD800-\uDFFF
## escapes, which Godot's JSON parser rejects outright ("unpaired trail
## surrogate") — one bad marker would otherwise cost the whole file. The
## lone halves are dropped; well-formed pairs stay and decode normally.
## Shared by tools/import_azgaar.gd and tools/bake_manors.gd. Pure.

## The export parsed, or {} (with an error pushed) when it cannot be read.
static func load_export(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("AzgaarJson: cannot read " + path)
		return {}
	var parsed: Variant = JSON.parse_string(drop_lone_surrogates(text))
	if not (parsed is Dictionary):
		push_error("AzgaarJson: %s is not a JSON object" % path)
		return {}
	return parsed

static func drop_lone_surrogates(text: String) -> String:
	var out := ""
	var i := 0
	while true:
		var at := text.find("\\u", i)
		if at < 0:
			out += text.substr(i)
			return out
		out += text.substr(i, at - i)
		var esc := text.substr(at, 6)
		if esc.length() < 6 or not is_surrogate_escape(esc):
			out += text.substr(at, 2)
			i = at + 2
			continue
		var next := text.substr(at + 6, 6)
		if is_high_surrogate(esc) and is_surrogate_escape(next) \
				and not is_high_surrogate(next):
			out += esc + next
			i = at + 12
		else:
			i = at + 6
	return out

static func is_surrogate_escape(esc: String) -> bool:
	if esc.length() != 6 or not esc.begins_with("\\u"):
		return false
	if not esc.substr(2).is_valid_hex_number():
		return false
	var cp := esc.substr(2).hex_to_int()
	return cp >= 0xD800 and cp <= 0xDFFF

static func is_high_surrogate(esc: String) -> bool:
	if not is_surrogate_escape(esc):
		return false
	var cp := esc.substr(2).hex_to_int()
	return cp <= 0xDBFF
