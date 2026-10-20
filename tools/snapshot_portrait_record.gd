extends "res://tools/snapshot_screen.gd"
## Existing GameRoot record path; use --screen root --speaker CHARACTER.
func _process(delta: float) -> void:
	if _frames != 20:
		super._process(delta)
		return
	assert(_root != null and not _speaker.is_empty(), "Use --screen root --speaker CHARACTER")
	assert(Game.state.characters.has(_speaker), "Unknown character")
	var before: Dictionary = Game.state.to_dict()
	_root._open_character_record(_speaker)
	var dossier := _root._character_dossier as CharacterDossier
	assert(dossier.inspected_id == _speaker and dossier.visible)
	assert(CharacterPortrait.texture_for(_speaker) != null, "Missing chip")
	assert(CharacterPortrait.full_texture_for(_speaker) != null, "Missing full portrait")
	assert(dossier.get_node("%PortraitBox").get_node("FullArt") is TextureRect)
	assert(dossier.get_node("%BioArt").get_node("FullArt") is TextureRect)
	assert(Game.state.to_dict() == before, "Inspection mutated campaign")
	print("portrait record verified: %s; chip/full loaded; campaign unchanged" % _speaker)
	super._process(delta)
