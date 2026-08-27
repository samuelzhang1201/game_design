class_name Character
extends RefCounted

func to_dict() -> Dictionary:
	return {}

static func from_dict(_d: Dictionary) -> Character:
	return Character.new()
