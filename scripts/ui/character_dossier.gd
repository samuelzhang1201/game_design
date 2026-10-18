class_name CharacterDossier
extends ConversationScene
## Reuse the original character's dossier without starting an audience or moving.
var inspected_id: String = ""

func _ready() -> void:
	_plate_arms = %PlateArms
	_build_skill_rows()
	_build_dossier_tabs()
	%DossierClose.pressed.connect(hide)

func show_character(id: String) -> void:
	if Game.state == null or not Game.state.characters.has(id): return
	inspected_id = id
	_show_speaker({"portrait_id":id, "speaker":Game.state.characters[id].display_name})
	%AudienceTitle.text = "Character record — " + Game.state.characters[id].display_name
	if _tab_index != 0: _select_tab(0)
	show()
