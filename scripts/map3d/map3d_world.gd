@tool
class_name Map3DWorld
extends Node3D
## The 3D map's WORLD (owner 2026-10-02: 优先处理3d地图的场景): every 3D node
## of the map — WorldSlot for the built terrain, the camera rig, the layers,
## the sky, the sun and the fill light — as its own scene,
## scenes/map3d/map3d_world.tscn, which Map3DView instances into its
## SubViewport. Opened on its own in the editor it is a plain 3D scene: the
## editor's 3D view shows the map, orbits it and picks its nodes.
##
## Opened that way it previews ITSELF (`editor_preview`): the built terrain
## goes under WorldSlot and every layer builds as the game would (each
## layer's `preview`), all of it with NO owner, so a save never writes it —
## the previews are put away before a save and come back after it. Turn
## `editor_preview` off for a quick open (the terrain takes seconds to load).

## The pack a preview draws ("" = maps.csv's default).
@export var preview_pack := ""
## Whether a preview loads the built terrain.
@export var preview_terrain := true
## Opened on its own in the editor, preview the whole world.
@export var editor_preview := true


func _ready() -> void:
	if Engine.is_editor_hint() and _is_edited_root() and editor_preview:
		preview_all.call_deferred(true)


## Every layer's `preview` switch under the world, on or off.
func preview_all(on: bool) -> void:
	for c: Node in find_children("*", "", true, false):
		if is_instance_valid(c) and c.owner == self and "preview" in c and bool(c.get("preview")) != on:
			c.set("preview", on)


func _is_edited_root() -> bool:
	return is_inside_tree() and get_tree().edited_scene_root == self


## A save never writes a preview: put everything back before it, and show
## the world again after it when it is the scene being edited.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		Map3DPreview.reset(self)
	elif what == NOTIFICATION_EDITOR_POST_SAVE and _is_edited_root() and editor_preview:
		preview_all.call_deferred(true)


## The editor's first 3D viewport (what draws the world opened on its own),
## or null outside the editor.
static func editor_viewport_3d() -> SubViewport:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return null
	return Engine.get_singleton("EditorInterface").call("get_editor_viewport_3d", 0) as SubViewport


## The built terrain a preview put under `slot`, taken off it (kept by
## Map3DPreview for the next preview, never freed here).
static func give_back(slot: Node) -> void:
	if slot == null:
		return
	for c: Node in slot.get_children():
		if c.owner == null:
			slot.remove_child(c)
