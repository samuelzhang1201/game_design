class_name WarInkFigure
extends Control
## The folio's moving ink figure (spec 2026-10-01-war-room-design §4): the
## regiment's arm as its own .glb under the ink shaders, looping a drill's
## clip in its own SubViewport on the left page. Never reaches the Game autoload.

const INK := preload("res://scenes/war_room/materials/ink_drawing.tres")

@onready var _viewport: SubViewport = %FigViewport
@onready var _display: TextureRect = %FigDisplay
@onready var _camera: Camera3D = %FigCamera
@onready var _glyph: TextureRect = %FigGlyph

var _model: Node3D
var _anim: AnimationPlayer
var _playing := ""
var _wanted := false      # the folio asked for it; it renders only while it is also visible
var _loads := 0
var _stroke_px := 5.0
var _material: ShaderMaterial
var label_font: Font      # the leader labels' face, handed in by the folio (this script never reaches UiPalette)
var _parts: Node3D        # the exploded view's static kit, when it is shown
var _part_home: Dictionary = {}    # object name -> its assembled position
var _part_off: Dictionary = {}     # object name -> WarExplode's offset when fully apart
var _part_labels: Array[Label3D] = []
var _label_home: Dictionary = {}   # Label3D -> [its part's centre, its part's offset]
var _model_cam := Transform3D.IDENTITY   # the camera as the drill framed it, for show_drill


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	get_viewport().size_changed.connect(_fit_viewport)   # the window changed under a still folio
	visibility_changed.connect(_sync_render)
	_fit_viewport()
	_sync_render()


## The viewport is window px (the TextureRect shows it at design size), like
## the war room's own view, and the hatching pitch follows it.
func _fit_viewport() -> void:
	var s := window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	if _material != null:
		_material.set_shader_parameter("stroke_px", _stroke_px * s)


func window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


func set_active(on: bool) -> void:
	_wanted = on
	if on:
		_fit_viewport()
	_sync_render()


func _sync_render() -> void:
	var on := _wanted and is_visible_in_tree()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Show `arm`: its model under the ink, and the clip names it carries — or,
## for an arm with no figure of its own, its icon in ink, large, and no clips.
## A drill that was playing resumes on the new model when it has the clip.
func show_arm(repo: DataRepository, arm: String) -> PackedStringArray:
	_drop_model()
	var path := String((repo.army_art.get(arm, {}) as Dictionary).get("model", ""))
	if not WarFolio.modelled(repo, arm) or path == "" or not ResourceLoader.exists(path):
		_playing = ""
		_show_glyph(repo, arm)
		return PackedStringArray()
	_glyph.visible = false
	_loads += 1
	_model = (load(path) as PackedScene).instantiate() as Node3D
	_viewport.add_child(_model)
	_stroke_px = repo.bal("war_figure_stroke_px")
	var whole := Map3DUnits.model_size(_model).y
	var height := Map3DUnitRig.head_m(repo, _model, whole)   # the body, not the lance's tip
	_material = INK.duplicate(true) as ShaderMaterial
	_material.set_shader_parameter("ink", repo.war_palette["ink"])
	_material.set_shader_parameter("paper", repo.war_palette["paper"])
	_material.set_shader_parameter("stroke_px", _stroke_px * window_scale())
	(_material.next_pass as ShaderMaterial).set_shader_parameter("ink", repo.war_palette["ink"])
	(_material.next_pass as ShaderMaterial).set_shader_parameter("width", whole * repo.bal("war_figure_outline_ratio"))
	for m: MeshInstance3D in Map3DUnits.meshes(_model):
		m.material_override = _material
	_camera.fov = repo.bal("war_figure_fov")
	_camera.position = Vector3(repo.bal("war_figure_cam_x"), repo.bal("war_figure_cam_y"), repo.bal("war_figure_cam_z")) * height
	_camera.look_at(Vector3(0.0, repo.bal("war_figure_look_y") * height, 0.0))
	_anim = Map3DUnits.find_anim(_model)
	_own_clips()
	var again := _playing
	_playing = ""
	play(again)
	return clips()


func _drop_model() -> void:
	_drop_parts()
	if _model != null:
		_viewport.remove_child(_model)
		_model.queue_free()
		_model = null
		_anim = null


func _show_glyph(repo: DataRepository, arm: String) -> void:
	var path := String((repo.resource_icons.get(arm, {}) as Dictionary).get("texture", ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = WarInkIcon.inked(load(path) as Texture2D, repo.war_palette["ink"], repo.bal("war_ink_icon_light_keep"))
	_glyph.custom_minimum_size = Vector2.ONE * repo.bal("war_figure_glyph_px")
	_glyph.texture = tex
	_glyph.visible = tex != null


func glyph_shown() -> bool:
	return _glyph.visible


## This model's clips as the folio's OWN copies: the imported Animations are
## shared with every 3D-map piece of the arm, so looping one in place would
## loop it on the map too.
func _own_clips() -> void:
	if _anim == null:
		return
	for lib_name: StringName in _anim.get_animation_library_list():
		var mine := AnimationLibrary.new()
		var shared := _anim.get_animation_library(lib_name)
		for n: StringName in shared.get_animation_list():
			var copy := shared.get_animation(n).duplicate() as Animation
			copy.loop_mode = Animation.LOOP_LINEAR
			mine.add_animation(n, copy)
		_anim.remove_animation_library(lib_name)
		_anim.add_animation_library(lib_name, mine)


func clips() -> PackedStringArray:
	return _anim.get_animation_list() if _anim != null else PackedStringArray()


func play(clip_name: String) -> void:
	if _anim == null or not _anim.has_animation(clip_name):
		return
	_anim.play(clip_name)
	_playing = clip_name


func playing() -> String:
	return _playing


## How many models have been loaded — a refresh must not add to it.
func loads() -> int:
	return _loads


## The loop mode of this figure's own copy of a clip.
func loop_of(clip_name: String) -> Animation.LoopMode:
	return _anim.get_animation(clip_name).loop_mode if _anim != null and _anim.has_animation(clip_name) else Animation.LOOP_NONE


## --- The exploded view ---------------------------------------------------

## Show the arm's parts model (WarExplode.parts_path) in ink, assembled; false
## when the file is missing (an arm the owner has not yet taken apart in Blender).
func show_parts(repo: DataRepository, arm: String) -> bool:
	var path := WarExplode.parts_path(arm)
	if not ResourceLoader.exists(path):
		return false
	return show_parts_from(repo, arm, load(path) as PackedScene)


## show_parts from a scene in hand — the seam the tests (and any other source) use.
func show_parts_from(repo: DataRepository, arm: String, scene: PackedScene) -> bool:
	if scene == null:
		return false
	if _parts == null:
		_model_cam = _camera.transform
	_drop_parts()
	_parts = scene.instantiate() as Node3D
	_viewport.add_child(_parts)
	if _model != null:
		_model.visible = false
	_glyph.visible = false
	var mat := INK.duplicate(true) as ShaderMaterial
	mat.set_shader_parameter("ink", repo.war_palette["ink"])
	mat.set_shader_parameter("paper", repo.war_palette["paper"])
	mat.set_shader_parameter("stroke_px", _stroke_px * window_scale())
	(mat.next_pass as ShaderMaterial).set_shader_parameter("ink", repo.war_palette["ink"])
	var centres: Dictionary = {}
	var all := AABB()
	var first := true
	for m: MeshInstance3D in Map3DUnits.meshes(_parts):
		m.material_override = mat
		var a := m.transform * m.get_aabb()
		all = a if first else all.merge(a)
		first = false
		centres[String(m.name)] = a.get_center()
		_part_home[String(m.name)] = m.position
	var apart := repo.bal("war_explode_m")
	_part_off = WarExplode.offsets(centres, all.get_center(), apart)
	(mat.next_pass as ShaderMaterial).set_shader_parameter("width", maxf(all.size.y, 0.01) * repo.bal("war_figure_outline_ratio"))
	for k: Dictionary in WarFolio.kit_of(repo, arm):
		var part := String(k["part"])
		if _parts.find_child(part, true, false) == null:
			continue
		var tag := Label3D.new()
		tag.name = "Label_" + part
		tag.text = String(k["label"])
		tag.font = label_font
		tag.font_size = int(repo.bal("war_explode_label_px"))
		tag.pixel_size = repo.bal("war_explode_label_pixel_m")
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.shaded = false
		tag.outline_size = 0
		tag.modulate = Color(repo.war_palette["ink"], 0.0)
		_parts.add_child(tag)
		_part_labels.append(tag)
		_label_home[tag] = [centres.get(part, Vector3.ZERO), _part_off.get(part, Vector3.ZERO) * repo.bal("war_explode_label_reach")]
	_frame_parts(repo, all, apart)
	explode(0.0)
	return true


## The camera looks at the kit and the room it flies into.
func _frame_parts(repo: DataRepository, all: AABB, apart: float) -> void:
	var height := all.size.y + 2.0 * apart
	var centre := all.get_center()
	var feet := Vector3(centre.x, all.position.y - apart, centre.z)
	_camera.position = feet + Vector3(repo.bal("war_figure_cam_x"), repo.bal("war_figure_cam_y"), repo.bal("war_figure_cam_z")) * height
	_camera.look_at(centre)


## 0 is the kit assembled, 1 flown apart; its labels fade in with it.
func explode(t: float) -> void:
	if _parts == null:
		return
	for m: MeshInstance3D in Map3DUnits.meshes(_parts):
		var n := String(m.name)
		m.position = (_part_home.get(n, Vector3.ZERO) as Vector3) + (_part_off.get(n, Vector3.ZERO) as Vector3) * t
	for tag: Label3D in _part_labels:
		var at: Array = _label_home[tag]
		tag.position = (at[0] as Vector3) + (at[1] as Vector3) * t
		tag.modulate.a = clampf(t, 0.0, 1.0)


## Put the drill's figure back and the kit away.
func show_drill() -> void:
	if _parts == null:
		return
	_drop_parts()
	_camera.transform = _model_cam
	if _model != null:
		_model.visible = true
	else:
		_glyph.visible = _glyph.texture != null


func _drop_parts() -> void:
	if _parts != null:
		_viewport.remove_child(_parts)
		_parts.queue_free()
		_parts = null
	_part_home = {}
	_part_off = {}
	_part_labels = []
	_label_home = {}


func parts_root() -> Node3D:
	return _parts


func part_labels() -> Array[Label3D]:
	return _part_labels


func model_visible() -> bool:
	return _model != null and _model.visible
