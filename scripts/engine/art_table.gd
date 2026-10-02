@tool
class_name ArtTable
extends Resource
## A key → art table (owner 2026-10-02: 为什么把所有素材的对应关系写在csv里 —
## the art a key wears is picked in the inspector, never a res:// path column
## in a CSV): each entry a Texture2D (a painting, an icon) or a PackedScene
## (a model), UID-safe, so moving a file in the editor keeps it. The tables
## are GameArt's; the CSVs keep only their numbers.

@export var art: Dictionary[String, Resource] = {}


## The art for `key`, or null.
func of(key: String) -> Resource:
	return art.get(key)


## The art's resource path for `key`, or "" (what a card carries in its dict).
func path_of(key: String) -> String:
	var r: Resource = art.get(key)
	return r.resource_path if r != null else ""
