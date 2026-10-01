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
var _part_off: Dictionary = {}     # object name -> WarExplode's offset when fully apart (parts space)
var _part_parent: Dictionary = {}  # object name -> the basis taking a parts-space offset into its parent's
var _part_labels: Array[Label3D] = []
var _label_home: Dictionary = {}   # Label3D -> [its part's centre, its label's reach, its note's Label3D]
var _note_labels: Array[Label3D] = []
var _leaders: Dictionary = {}      # part name -> its leader line's MeshInstance3D
var _leader_ends: Dictionary = {}  # part name -> PackedVector3Array [part centre, label position], parts space
var _leader_mat: StandardMaterial3D
var _parts_mat: ShaderMaterial     # the kit's ink, kept so a resize can re-pitch its hatching
var _label_h_m := 0.0              # a name label's height in model metres (the note hangs under it)
var _note_drop := 0.0
var _model_cam := Transform3D.IDENTITY   # the camera as the drill framed it, for show_drill
var _plate: Array = []             # [box, right, up, centre, margin]: the kit's plate, refitted on a resize


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
	if _parts_mat != null:
		_parts_mat.set_shader_parameter("stroke_px", _stroke_px * s)
	if not _plate.is_empty():
		_fit_camera()   # the page changed shape (the drill tabs make way): the plate still fits


## The graphics tier's MSAA and anisotropy on the figure's viewport (a
## graphics_quality.csv row).
func set_tier_row(row: Dictionary) -> void:
	Map3DEnvironment.apply_viewport_quality(_viewport, row)


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
## Parts may be nested: every measure is taken in the parts root's own space.
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
	_stroke_px = repo.bal("war_figure_stroke_px")
	var ink: Color = repo.war_palette["ink"]
	_parts_mat = INK.duplicate(true) as ShaderMaterial
	_parts_mat.set_shader_parameter("ink", ink)
	_parts_mat.set_shader_parameter("paper", repo.war_palette["paper"])
	_parts_mat.set_shader_parameter("stroke_px", _stroke_px * window_scale())
	(_parts_mat.next_pass as ShaderMaterial).set_shader_parameter("ink", ink)
	var to_root := _parts.global_transform.affine_inverse()
	var centres: Dictionary = {}
	var all := AABB()
	var first := true
	for m: MeshInstance3D in Map3DUnits.meshes(_parts):
		m.material_override = _parts_mat
		var rel := to_root * m.global_transform
		var a := rel * m.get_aabb()
		all = a if first else all.merge(a)
		first = false
		centres[String(m.name)] = a.get_center()
		_part_home[String(m.name)] = m.position
		# a flight is measured in the root's space; the mesh moves in its parent's
		var parent_rel := to_root * (m.get_parent() as Node3D).global_transform if m.get_parent() is Node3D else Transform3D.IDENTITY
		_part_parent[String(m.name)] = parent_rel.basis.inverse()
	var apart := repo.bal("war_explode_m")
	_part_off = WarExplode.offsets(centres, all.get_center(), apart)
	(_parts_mat.next_pass as ShaderMaterial).set_shader_parameter("width", maxf(all.size.y, 0.01) * repo.bal("war_figure_outline_ratio"))
	_leader_mat = StandardMaterial3D.new()
	_leader_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leader_mat.no_depth_test = true
	_leader_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_leader_mat.albedo_color = Color(ink, 0.0)
	var px := repo.bal("war_explode_label_pixel_m")
	_label_h_m = repo.bal("war_explode_label_px") * px
	_note_drop = _label_h_m * repo.bal("war_explode_note_drop")
	for k: Dictionary in WarFolio.kit_of(repo, arm):
		var part := String(k["part"])
		if not centres.has(part):
			continue
		var tag := _label3d(String(k["label"]), int(repo.bal("war_explode_label_px")), px, ink)
		tag.name = "Label_" + part
		tag.set_meta("part", part)
		var note: Label3D = null
		if String(k["note"]) != "":
			note = _label3d(String(k["note"]), int(repo.bal("war_explode_note_px")), px, Color(ink, repo.bal("war_folio_label_alpha")))
			note.name = "Note_" + part
			note.width = repo.bal("war_explode_note_w_px")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			_note_labels.append(note)
		_part_labels.append(tag)
		_label_home[tag] = [centres[part], Vector3.ZERO, note]   # its reach is laid out once the camera frames the kit
		var line := MeshInstance3D.new()
		line.name = "Leader_" + part
		line.mesh = ImmediateMesh.new()
		line.material_override = _leader_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts.add_child(line)
		_leaders[part] = line
	_frame_parts(repo, all, apart)
	_lay_labels(repo, to_root, all.get_center())
	explode(0.0)
	return true


## The names stand in two columns flanking the flown-apart kit as the camera
## sees it — a part flying to the camera's right is named on the right, its
## text running outward from the leader's end — each column stepped down so no
## name (with its note) lies over another or over the kit.
func _lay_labels(repo: DataRepository, to_root: Transform3D, centre: Vector3) -> void:
	var right := (to_root.basis * _camera.global_transform.basis.x).normalized()
	var up := (to_root.basis * _camera.global_transform.basis.y).normalized()
	var box := Rect2()   # the flown-apart kit, then its names too, in right / up coordinates
	var first := true
	for m: MeshInstance3D in Map3DUnits.meshes(_parts):
		if not _part_home.has(String(m.name)):
			continue   # a leader line, not a part
		var a := (to_root * m.global_transform) * m.get_aabb()
		var off := _part_off.get(String(m.name), Vector3.ZERO) as Vector3
		for i in 8:
			var e := a.get_endpoint(i) + off
			var p := Vector2(e.dot(right), e.dot(up))
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	var lo := box.position.x
	var hi := box.end.x
	var gap := _label_h_m * repo.bal("war_explode_label_gap")
	var step := _label_h_m * repo.bal("war_explode_label_rows")
	var columns := {1: [], -1: []}
	for tag: Label3D in _part_labels:
		var at: Array = _label_home[tag]
		var flown := (at[0] as Vector3) + (_part_off[String(tag.get_meta("part"))] as Vector3)
		var side := 1 if flown.dot(right) >= (lo + hi) * 0.5 else -1
		(columns[side] as Array).append([tag, flown])
	for side: int in columns:
		var col: Array = columns[side]
		col.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector3).dot(up) > (b[1] as Vector3).dot(up))
		var floor_y := INF
		for entry: Array in col:
			var tag: Label3D = entry[0]
			var flown: Vector3 = entry[1]
			var y := minf(flown.dot(up), floor_y)
			floor_y = y - step
			var x := (hi + gap) if side > 0 else (lo - gap)
			var spot := flown + right * (x - flown.dot(right)) + up * (y - flown.dot(up))
			var at: Array = _label_home[tag]
			at[1] = spot - (at[0] as Vector3)
			var align := HORIZONTAL_ALIGNMENT_LEFT if side > 0 else HORIZONTAL_ALIGNMENT_RIGHT
			tag.horizontal_alignment = align
			var reach := _text_w(tag)
			if at[2] != null:
				(at[2] as Label3D).horizontal_alignment = align
				reach = maxf(reach, _text_w(at[2] as Label3D))
			var bottom := y - step
			box = box.expand(Vector2(x + reach * side, y + _label_h_m)).expand(Vector2(x, bottom))
	_plate = [box, right, up, centre, repo.bal("war_explode_fit_margin")]
	_fit_camera()


## A label's text width in model metres (its widest line; a note wraps at its width).
func _text_w(l: Label3D) -> float:
	var f := l.font if l.font != null else ThemeDB.fallback_font
	var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
	return (minf(w, l.width) if l.autowrap_mode != TextServer.AUTOWRAP_OFF else w) * l.pixel_size


## Centre the camera on the kit and its names (the plate's box: right / up
## coordinates in the parts' space round the kit's centre) and stand it back
## just far enough that the whole plate fits the page, its margin to spare.
func _fit_camera() -> void:
	if _parts == null or _plate.is_empty():
		return
	var box: Rect2 = _plate[0]
	var right: Vector3 = _plate[1]
	var up: Vector3 = _plate[2]
	var centre: Vector3 = _plate[3]
	var to_world := _parts.global_transform
	var back := (to_world.basis.inverse() * _camera.global_transform.basis.z).normalized()
	var aspect := float(_viewport.size.x) / maxf(1.0, float(_viewport.size.y))
	var tan_v := tan(deg_to_rad(_camera.fov) * 0.5)
	var d := maxf(box.size.y * 0.5 / tan_v, box.size.x * 0.5 / (tan_v * aspect)) * float(_plate[4])
	var mid := box.get_center()
	var target := centre + right * (mid.x - centre.dot(right)) + up * (mid.y - centre.dot(up))
	_camera.global_position = to_world * (target + back * d)


func _label3d(text: String, font_px: int, pixel_m: float, colour: Color) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.font = label_font
	tag.font_size = font_px
	tag.pixel_size = pixel_m
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.shaded = false
	tag.outline_size = 0
	tag.modulate = Color(colour, 0.0)
	_parts.add_child(tag)
	return tag


## The camera looks at the kit and the room it flies into.
func _frame_parts(repo: DataRepository, all: AABB, apart: float) -> void:
	var height := all.size.y + 2.0 * apart
	var centre := all.get_center()
	var feet := Vector3(centre.x, all.position.y - apart, centre.z)
	_camera.fov = repo.bal("war_figure_fov")
	_camera.position = feet + Vector3(repo.bal("war_figure_cam_x"), repo.bal("war_figure_cam_y"), repo.bal("war_figure_cam_z")) * height
	_camera.look_at(centre)


## 0 is the kit assembled, 1 flown apart; its labels, notes and leader lines
## fade in with it.
func explode(t: float) -> void:
	if _parts == null:
		return
	for m: MeshInstance3D in Map3DUnits.meshes(_parts):
		var n := String(m.name)
		var flight := (_part_off.get(n, Vector3.ZERO) as Vector3) * t
		m.position = (_part_home.get(n, Vector3.ZERO) as Vector3) + (_part_parent.get(n, Basis.IDENTITY) as Basis) * flight
	var a := clampf(t, 0.0, 1.0)
	_leader_mat.albedo_color.a = a
	for tag: Label3D in _part_labels:
		var at: Array = _label_home[tag]
		var part := String(tag.get_meta("part"))
		var from := (at[0] as Vector3) + (_part_off.get(part, Vector3.ZERO) as Vector3) * t   # the part's centre now
		tag.position = (at[0] as Vector3) + (at[1] as Vector3) * t
		tag.modulate.a = a
		var note: Label3D = at[2]
		if note != null:
			note.position = tag.position - Vector3(0.0, _note_drop, 0.0)
			note.modulate.a = a
		_leader_ends[part] = PackedVector3Array([from, tag.position])
		var im := (_leaders[part] as MeshInstance3D).mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(from)
		im.surface_add_vertex(tag.position)
		im.surface_end()


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
	_part_parent = {}
	_part_labels = []
	_note_labels = []
	_label_home = {}
	_leaders = {}
	_leader_ends = {}
	_parts_mat = null
	_leader_mat = null
	_plate = []


func parts_root() -> Node3D:
	return _parts


func part_labels() -> Array[Label3D]:
	return _part_labels


func note_labels() -> Array[Label3D]:
	return _note_labels


## A part's leader line as its two ends in the parts' space: the part's centre
## now and its label's position. Empty for a part with no label.
func leader_ends(part: String) -> PackedVector3Array:
	return _leader_ends.get(part, PackedVector3Array())


func model_visible() -> bool:
	return _model != null and _model.visible
