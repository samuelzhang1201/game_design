@tool
class_name ResourceIconSet
extends Resource
## Which art each resource-icon key wears (owner 2026-10-02: the art is
## picked in the editor, not written as a res:// path in a CSV). One saved
## resource, assets/2D/icons/resource_icons.tres: open it in the inspector and
## drop a texture on a key. The words a key carries — its label, its glyph
## for when it has no art, its tooltip — stay in data/resource_icons.csv.

const PATH := "res://assets/2D/icons/resource_icons.tres"

@export var textures: Dictionary[String, Texture2D] = {}

static var _shared: ResourceIconSet = null

## The project's set, loaded once (an empty set when the file is missing).
static func shared() -> ResourceIconSet:
	if _shared == null:
		if ResourceLoader.exists(PATH):
			_shared = load(PATH) as ResourceIconSet
		if _shared == null:
			_shared = ResourceIconSet.new()
	return _shared

## A key's art, or null when it has none.
static func texture_of(key: String) -> Texture2D:
	return shared().textures.get(key, null)

## Whether a key has art.
static func has_art(key: String) -> bool:
	return shared().textures.has(key)
