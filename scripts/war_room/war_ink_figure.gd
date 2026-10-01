class_name WarInkFigure
extends Control
## The folio's moving ink figure (spec 2026-10-01-war-room-design §4): the
## regiment's arm as its own .glb under the ink shaders, looping a drill's
## clip in its own SubViewport on the left page. Never reaches the Game autoload.

const INK := preload("res://scenes/war_room/materials/ink_drawing.tres")

@onready var _viewport: SubViewport = %FigViewport
@onready var _display: TextureRect = %FigDisplay
@onready var _camera: Camera3D = %FigCamera

var _model: Node3D
var _anim: AnimationPlayer
var _playing := ""
var _wanted := false      # the folio asked for it; it renders only while it is also visible
var _loads := 0
var _stroke_px := 5.0
var _material: ShaderMaterial


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
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
	_sync_render()


func _sync_render() -> void:
	var on := _wanted and is_visible_in_tree()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Load `arm`'s model under the ink; the clip names it carries. A drill that
## was playing resumes on the new model when it has the clip.
func show_arm(repo: DataRepository, arm: String) -> PackedStringArray:
	if _model != null:
		_viewport.remove_child(_model)
		_model.queue_free()
		_model = null
		_anim = null
	var path := String((repo.army_art.get(arm, {}) as Dictionary).get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		_playing = ""
		return PackedStringArray()
	_loads += 1
	_model = (load(path) as PackedScene).instantiate() as Node3D
	_viewport.add_child(_model)
	_stroke_px = repo.bal("war_figure_stroke_px")
	var height := Map3DUnits.model_size(_model).y
	_material = INK.duplicate(true) as ShaderMaterial
	_material.set_shader_parameter("ink", repo.war_palette["ink"])
	_material.set_shader_parameter("paper", repo.war_palette["paper"])
	_material.set_shader_parameter("stroke_px", _stroke_px * window_scale())
	(_material.next_pass as ShaderMaterial).set_shader_parameter("ink", repo.war_palette["ink"])
	(_material.next_pass as ShaderMaterial).set_shader_parameter("width", height * repo.bal("war_figure_outline_ratio"))
	for m: MeshInstance3D in Map3DUnits.meshes(_model):
		m.material_override = _material
	_camera.fov = repo.bal("war_figure_fov")
	_camera.position = Vector3(repo.bal("war_figure_cam_x"), repo.bal("war_figure_cam_y"), repo.bal("war_figure_cam_z")) * height
	_camera.look_at(Vector3(0.0, repo.bal("war_figure_look_y") * height, 0.0))
	_anim = Map3DUnits.find_anim(_model)
	var again := _playing
	_playing = ""
	play(again)
	return clips()


func clips() -> PackedStringArray:
	return _anim.get_animation_list() if _anim != null else PackedStringArray()


func play(clip_name: String) -> void:
	if _anim == null or not _anim.has_animation(clip_name):
		return
	_anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(clip_name)
	_playing = clip_name


func playing() -> String:
	return _playing


## How many models have been loaded — a refresh must not add to it.
func loads() -> int:
	return _loads
