# scripts/ledger3d/ledger_view_3d.gd
class_name LedgerView3D
extends Control
## The LEDGER's orrery (spec 2026-09-30 §6.2-6.3): spheres for objects,
## threads for links, on three floating discs — KNOW over PEOPLE over
## THINGS. It draws a snapshot and signals what the player did; it reads no
## autoload and changes no state. It renders into a SubViewport at WINDOW
## resolution shown by a TextureRect (never a SubViewportContainer, which
## renders at design size and blurs), and only while active.

signal sphere_selected(id: String)
signal thread_selected(id: String)
signal drill_requested(id: String)
signal orders_requested(id: String, at: Vector2)

const THREAD_SHADER := preload("res://scenes/ledger/thread.gdshader")
const CLICK_SLOP := 10.0
const KIN_TYPES := ["kin", "marriage"]

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _env: WorldEnvironment = %Env
@onready var _camera: Camera3D = %Camera
@onready var _discs: Node3D = %Discs
@onready var _threads_root: Node3D = %Threads
@onready var _spheres_root: Node3D = %Spheres
@onready var _hud: LedgerHud = %Hud

var _repo: DataRepository
var _pal: Dictionary = {}
var _orbit := LedgerOrbit.new()
var _snap: Dictionary = {}
var _pos: Dictionary = {}          # node id -> Vector3
var _dragged: Dictionary = {}      # node id -> Vector3: spheres the player moved this viewing
var _nodes: Dictionary = {}        # node id -> node dict
var _sphere_mi: Dictionary = {}    # node id -> MeshInstance3D
var _thread_mi: Dictionary = {}    # link id -> MeshInstance3D
var _thread_ends: Dictionary = {}  # link id -> [Vector3, Vector3], as drawn
var _pairs: Dictionary = {}        # [id, id] sorted -> threads joining those two spheres
var _sphere_alpha: Dictionary = {} # node id -> its material's own alpha, before any fade
var _disc_mi: Dictionary = {}      # layer -> its disc's MeshInstance3D
var _framed := false               # the camera still stands where the framing put it
var _selected := ""
var _button := 0
var _press_at := Vector2.ZERO
var _moved := false
var _drag_id := ""
var _ease_left := 0.0
var _ease_from := Vector2.ZERO
var _last_pose := Transform3D()


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


func bind(repo: DataRepository) -> void:
	_repo = repo
	_pal = repo.ledger_palette
	_env.environment.background_color = _pal["background"]
	_orbit.distance = repo.bal("ledger_camera_distance")
	_orbit.pitch = repo.bal("ledger_camera_pitch_deg")
	_orbit.min_distance = repo.bal("ledger_camera_min_m")
	_orbit.max_distance = repo.bal("ledger_camera_max_m")
	_orbit.target = Vector3(0, LedgerLayout.layer_y(repo, "people"), 0)
	_hud.style(UiPalette.role_font("body"), repo.bal("ledger_label_px"), _pal["label_ink"], _pal["label_halo"],
		int(repo.bal("ledger_label_halo_px")))
	_build_discs()
	_apply_camera()


func _window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


func _fit_viewport() -> void:
	var s := _window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	# a view the player has not moved keeps its framing as the view resizes
	if _framed and _repo != null and not _snap.is_empty():
		_frame()
		_apply_camera()


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if on:
		_fit_viewport()


## Draw a snapshot. The same lens and focus again (a state change) keeps
## the spheres the player dragged where he put them; a new lens or focus
## forgets them. A sphere under a drag that is no longer drawn ends the drag.
func show_snapshot(snap: Dictionary, keep_camera: bool) -> void:
	if _snap.is_empty() or String(snap.get("lens", "")) != String(_snap.get("lens", "")) \
			or String(snap.get("focus_id", "")) != String(_snap.get("focus_id", "")):
		_dragged.clear()
	_snap = snap
	_nodes.clear()
	for n: Dictionary in snap["nodes"]:
		_nodes[String(n["id"])] = n
	_pos = LedgerLayout.positions(_repo, snap)
	for id: String in _dragged.keys():
		if _pos.has(id):
			_pos[id] = _dragged[id]
		else:
			_dragged.erase(id)
	if _drag_id != "" and not _pos.has(_drag_id):
		_end_gesture()
	var present := LedgerLayout.layers_present(snap)
	for layer: String in _disc_mi:
		var disc := _disc_mi[layer] as MeshInstance3D
		disc.visible = layer in present
		if disc.visible:
			var mesh := disc.mesh as CylinderMesh
			mesh.top_radius = LedgerLayout.disc_radius(_repo, snap, _pos, layer)
			mesh.bottom_radius = mesh.top_radius
	if not _nodes.has(_selected):
		_selected = ""
	_build_spheres()
	_build_threads()
	_apply_focus_fade()
	if not keep_camera:
		front_view()
	_update_hud()


func select(id: String) -> void:
	_selected = id
	_apply_focus_fade()
	_update_hud()


## Back to the front: the target and distance snap to the framing of what
## is drawn (_frame), the yaw and pitch ease home over ledger_front_ease_s
## while the view runs.
func front_view() -> void:
	_frame()
	_framed = true
	_ease_from = Vector2(_orbit.yaw, _orbit.pitch)
	_ease_left = _repo.bal("ledger_front_ease_s")
	if _ease_left <= 0.0:
		_orbit.yaw = 0.0
		_orbit.pitch = _repo.bal("ledger_camera_pitch_deg")
	_apply_camera()


## Target and distance that frame the spheres and discs drawn, seen from
## the front (LedgerOrbit.frame), inside the part of the view the screen's
## title, lenses and crumb leave clear; the PEOPLE disc's centre at
## ledger_camera_distance when nothing is drawn.
func _frame() -> void:
	var sz := size if size.x >= 2.0 and size.y >= 2.0 else Vector2(1280, 720)
	var side := _repo.bal("ledger_frame_side_px") / sz.x
	var top := _repo.bal("ledger_frame_top_px") / sz.y
	var bottom := _repo.bal("ledger_frame_bottom_px") / sz.y
	var safe := Rect2(side, top, maxf(1.0 - 2.0 * side, 0.1), maxf(1.0 - top - bottom, 0.1))
	var f := LedgerOrbit.frame(LedgerLayout.frame_points(_repo, _snap, _pos), 0.0,
		_repo.bal("ledger_camera_pitch_deg"), _camera.fov, sz.x / sz.y, safe)
	if f.is_empty():
		_orbit.target = Vector3(0, LedgerLayout.layer_y(_repo, "people"), 0)
		_orbit.distance = _repo.bal("ledger_camera_distance")
		return
	_orbit.target = f["target"]
	_orbit.distance = clampf(float(f["distance"]), _orbit.min_distance, _orbit.max_distance)


## The disc drawn for `layer`, or null (the tests' seam).
func disc_of(layer: String) -> MeshInstance3D:
	return _disc_mi.get(layer)


func orbit() -> LedgerOrbit:
	return _orbit


func screen_pos_of(id: String) -> Variant:
	if not _pos.has(id) or _camera.is_position_behind(_pos[id]):
		return null
	return _camera.unproject_position(_pos[id]) / _window_scale()


# --- building --------------------------------------------------------------

func _build_discs() -> void:
	for c in _discs.get_children():
		c.queue_free()
	_disc_mi.clear()
	for layer: String in Ledger.LAYERS:
		var mesh := CylinderMesh.new()
		mesh.top_radius = _repo.bal("ledger_disc_radius_m")
		mesh.bottom_radius = mesh.top_radius
		mesh.height = _repo.bal("ledger_disc_thickness_m")
		mesh.radial_segments = int(_repo.bal("ledger_disc_segments"))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = _pal["disc_" + layer]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position.y = LedgerLayout.disc_y(_repo, layer)
		_discs.add_child(mi)
		_disc_mi[layer] = mi


func _sphere_color(n: Dictionary) -> Color:
	var layer := String(n["layer"])
	var c: Color = _pal["sphere_planned"] if String(n["status"]) == "planned" else _pal["sphere_" + layer]
	if layer == "know":
		c.a = _repo.bal("ledger_orb_glass_alpha")
	return c


func _sphere_material(n: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _sphere_color(n)
	mat.metallic = _repo.bal("ledger_orb_metallic")
	mat.roughness = _repo.bal("ledger_orb_roughness")
	# Blended even when opaque: the focus fade (ledger_focus_fade) turns
	# every sphere not linked to the selected one see-through.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if String(n["layer"]) == "know":
		mat.metallic = 0.1
	return mat


func _radius(n: Dictionary) -> float:
	return _repo.bal("ledger_sphere_radius_instance") if bool(n["instance"]) \
		else _repo.bal("ledger_sphere_radius_type")


func _build_spheres() -> void:
	for c in _spheres_root.get_children():
		c.queue_free()
	_sphere_mi.clear()
	_sphere_alpha.clear()
	for id: String in _nodes:
		var n: Dictionary = _nodes[id]
		var mesh := SphereMesh.new()
		mesh.radius = _radius(n)
		mesh.height = mesh.radius * 2.0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _sphere_material(n)
		mi.position = _pos[id]
		_spheres_root.add_child(mi)
		_sphere_mi[id] = mi
		_sphere_alpha[id] = (mi.material_override as StandardMaterial3D).albedo_color.a


func _width(l: Dictionary) -> float:
	var lo := _repo.bal("ledger_thread_width_min")
	if l["flow"] == null:
		return _repo.bal("ledger_thread_vague_width")
	var f := float(l["flow"])
	if f <= 0.0:
		return lo
	var t := clampf(log(1.0 + f) / log(1.0 + _repo.bal("ledger_thread_flow_ref")), 0.0, 1.0)
	return lerpf(lo, _repo.bal("ledger_thread_width_max"), t)


func _thread_color(l: Dictionary) -> Color:
	if String(l["status"]) == "planned":
		return _pal["thread_planned"]
	if String(l["type"]) in KIN_TYPES:
		return _pal["thread_kin"]
	var rel := Ledger.link_row(_repo, String(l["type"]))
	if String(rel.get("resolver", "")) == "court_relations":
		return _pal["thread_pos"] if int(l["sentiment"]) >= 0 else _pal["thread_neg"]
	var accs: Array = l["accounts"]
	var c: Color = _pal["thread_live"]
	if not accs.is_empty():
		var age := float(int(_snap["day"]) - int(accs[0]["day"]))
		c = c.lerp(_pal["thread_aged"], clampf(age / _repo.bal("ledger_age_full_days"), 0.0, 1.0))
	return c


func _ink(l: Dictionary) -> float:
	var accs: Array = l["accounts"]
	if accs.is_empty():
		return 1.0
	match String(accs[0]["level"]):
		"general":
			return _repo.bal("ledger_ink_general")
		"basic":
			return _repo.bal("ledger_ink_basic")
	return 1.0


func _running_links() -> Dictionary:
	var out := {}
	for lp: Dictionary in _snap.get("loops", []):
		if bool(lp["running"]):
			for t: String in lp["links"]:
				out[t] = String(lp["kind"])
	return out


func _build_threads() -> void:
	for c in _threads_root.get_children():
		c.queue_free()
	_thread_mi.clear()
	_thread_ends.clear()
	var running := _running_links()
	_pairs.clear()
	for l: Dictionary in _snap["links"]:
		var key := _pair_key(l)
		_pairs[key] = int(_pairs.get(key, 0)) + 1
	for l: Dictionary in _snap["links"]:
		var ends := _ends_of(l)
		if ends.is_empty():
			continue
		var id := String(l["id"])
		_thread_mi[id] = _add_thread(l, ends[0], ends[1], running)
		_thread_ends[id] = ends


func _pair_key(l: Dictionary) -> Array:
	var key := [String(l["from"]), String(l["to"])]
	key.sort()
	return key


## Where a thread runs now: from its source sphere to its end, set aside by
## ledger_pair_offset_m when two threads join the same spheres both ways.
## Empty when an end is missing or the two ends meet.
func _ends_of(l: Dictionary) -> Array:
	if not _pos.has(String(l["from"])) or not _pos.has(String(l["to"])):
		return []
	var a: Vector3 = _pos[String(l["from"])]
	var b: Vector3 = _pos[String(l["to"])]
	if a.is_equal_approx(b):
		return []
	var key := _pair_key(l)
	if int(_pairs.get(key, 0)) > 1:  # both ways between the same spheres: side by side
		var across := (b - a).cross(Vector3.UP)
		if across.length_squared() < 1e-6:  # one straight above the other
			across = Vector3.RIGHT
		var side := across.normalized() * _repo.bal("ledger_pair_offset_m")
		var sgn := 1.0 if String(l["from"]) == key[0] else -1.0
		a += side * sgn
		b += side * sgn
	return [a, b]


## Lays a thread's cylinder from a to b: its length and its transform, in
## place. The cylinder's +Y is the link's end, so the light runs source -> end.
func _place_thread(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	(mi.mesh as CylinderMesh).height = a.distance_to(b)
	var up := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	mi.transform = Transform3D(Basis(x, up, x.cross(up)), (a + b) * 0.5)


func _add_thread(l: Dictionary, a: Vector3, b: Vector3, running: Dictionary) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	var r := _width(l)
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.cap_top = false     # thread.gdshader reads the side's UV only
	mesh.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = THREAD_SHADER
	mat.set_shader_parameter("color", _thread_color(l))
	mat.set_shader_parameter("ink", _ink(l))
	var planned := String(l["status"]) == "planned"
	mat.set_shader_parameter("dashed", 1.0 if planned else 0.0)
	mat.set_shader_parameter("dashes", _repo.bal("ledger_dashes"))
	mat.set_shader_parameter("pulses", _repo.bal("ledger_light_pulses"))
	var flowing := not planned and l["flow"] != null and int(l["flow"]) > 0 \
		and String(Ledger.link_row(_repo, String(l["type"])).get("resolver", "")) != "court_relations"
	var width_t := inverse_lerp(_repo.bal("ledger_thread_width_min"), _repo.bal("ledger_thread_width_max"), r)
	mat.set_shader_parameter("speed", _repo.bal("ledger_light_speed") * (0.4 + 0.6 * width_t) if flowing else 0.0)
	var loop_kind := String(running.get(String(l["type"]), ""))
	if loop_kind != "":
		mat.set_shader_parameter("glow", 1.0)
		mat.set_shader_parameter("glow_color", _pal["loop_" + loop_kind])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_place_thread(mi, a, b)
	_threads_root.add_child(mi)
	return mi


func _apply_focus_fade() -> void:
	var near := {}
	if _selected != "":
		near[_selected] = true
		for l: Dictionary in _snap.get("links", []):
			if String(l["from"]) == _selected or String(l["to"]) == _selected:
				near[String(l["from"])] = true
				near[String(l["to"])] = true
	var faint := _repo.bal("ledger_focus_fade")
	for id: String in _sphere_mi:
		var mat := (_sphere_mi[id] as MeshInstance3D).material_override as StandardMaterial3D
		mat.albedo_color.a = float(_sphere_alpha[id]) * (1.0 if near.is_empty() or near.has(id) else faint)
	for l: Dictionary in _snap.get("links", []):
		var mi: MeshInstance3D = _thread_mi.get(String(l["id"]))
		if mi == null:
			continue
		var lit := near.is_empty() or (near.has(String(l["from"])) and near.has(String(l["to"])))
		(mi.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 if lit else faint)


# --- camera and names ------------------------------------------------------

func _apply_camera() -> void:
	_camera.transform = _orbit.pose()


func _process(delta: float) -> void:
	if _ease_left > 0.0:
		_ease_left = maxf(_ease_left - delta, 0.0)
		var t := 1.0 - _ease_left / maxf(_repo.bal("ledger_front_ease_s"), 0.001)
		_orbit.yaw = lerpf(_ease_from.x, 0.0, t)
		_orbit.pitch = lerpf(_ease_from.y, _repo.bal("ledger_camera_pitch_deg"), t)
		_apply_camera()
	if not _camera.transform.is_equal_approx(_last_pose):
		_last_pose = _camera.transform
		_update_hud()


func _update_hud() -> void:
	var entries: Array = []
	var order: Array = _nodes.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return _rank(a) < _rank(b) if _rank(a) != _rank(b) else a < b)
	var lift := Vector2(0, -_repo.bal("ledger_label_lift_px"))
	# under the sphere, as far below its centre as the name stands above,
	# plus the name's own height: where a crowded name goes instead
	var drop := Vector2(0, _repo.bal("ledger_label_lift_px") + _repo.bal("ledger_label_px"))
	for id: String in order:
		var at: Variant = screen_pos_of(id)
		if at == null:
			continue
		entries.append({"text": String(_nodes[id]["label"]), "at": (at as Vector2) + lift,
			"alt": (at as Vector2) + drop,
			"strong": id == _selected or id == String(_snap.get("focus_id", ""))})
	_hud.show_entries(entries)


func _rank(id: String) -> int:
	if id == _selected:
		return 0
	if id == String(_snap.get("focus_id", "")):
		return 1
	return 2 if not bool(_nodes[id]["instance"]) else 3


# --- input -----------------------------------------------------------------

func _ray(pos: Vector2) -> Array:
	var px := LedgerPick.screen_to_viewport(pos, _window_scale())
	return [_camera.project_ray_origin(px), _camera.project_ray_normal(px)]


func _pick(pos: Vector2) -> Dictionary:
	var ray := _ray(pos)
	var spheres: Array = []
	for id: String in _nodes:
		if _pos.has(id):
			spheres.append({"id": id, "pos": _pos[id], "radius": _radius(_nodes[id])})
	var threads: Array = []
	for l: Dictionary in _snap.get("links", []):
		var id := String(l["id"])
		if _thread_ends.has(id):
			var ends: Array = _thread_ends[id]
			threads.append({"id": id, "a": ends[0], "b": ends[1],
				"radius": maxf(_width(l), _repo.bal("ledger_pick_radius_min_m"))})
	return LedgerPick.pick(ray[0], ray[1], spheres, threads)


func _gui_input(event: InputEvent) -> void:
	if _repo == null:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _button != 0:
		_on_drag(event as InputEventMouseMotion)
	elif event is InputEventMagnifyGesture:
		_framed = false
		_orbit.zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		_apply_camera()
		accept_event()
	elif event is InputEventPanGesture:
		_framed = false
		_orbit.pan(-(event as InputEventPanGesture).delta * _repo.bal("ledger_pan_gesture_px"),
			_orbit.metres_per_px(_camera.fov, size.y))
		_apply_camera()
		accept_event()


func _on_button(mb: InputEventMouseButton) -> void:
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var f := _repo.bal("ledger_zoom_factor")
		_framed = false
		_orbit.zoom(1.0 / f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else f)
		_apply_camera()
		accept_event()
		return
	if mb.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	accept_event()
	if mb.pressed:
		_button = mb.button_index
		_press_at = mb.position
		_moved = false
		_drag_id = ""
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pressed_on := _pick(mb.position)
			if String(pressed_on.get("kind", "")) == "sphere":
				_drag_id = String(pressed_on["id"])
				if mb.double_click:
					_button = 0
					drill_requested.emit(_drag_id)
		return
	if _button != mb.button_index:
		return
	var was := _button
	_button = 0
	if _moved:
		return
	var hit := _pick(mb.position)
	if was == MOUSE_BUTTON_RIGHT:
		if not hit.is_empty():
			orders_requested.emit(String(hit["id"]), mb.position)
		return
	match String(hit.get("kind", "")):
		"sphere":
			select(String(hit["id"]))
			sphere_selected.emit(String(hit["id"]))
		"thread":
			thread_selected.emit(String(hit["id"]))
		_:
			select("")
			sphere_selected.emit("")


## The pressed button's gesture ends quietly: the rest of its motion and its
## release do nothing (the sphere it was dragging is no longer drawn).
func _end_gesture() -> void:
	_button = 0
	_drag_id = ""
	_moved = false


func _on_drag(mm: InputEventMouseMotion) -> void:
	if not _moved and mm.position.distance_to(_press_at) < CLICK_SLOP:
		return
	_moved = true
	if _drag_id == "":
		_framed = false
	if _button == MOUSE_BUTTON_RIGHT:
		_orbit.turn(mm.relative.x, mm.relative.y, _repo.bal("ledger_turn_deg_per_px"))
	elif _drag_id != "":
		_drag_to(_drag_id, mm.position)
	else:
		_orbit.pan(mm.relative, _orbit.metres_per_px(_camera.fov, size.y))
	_apply_camera()
	accept_event()


## A dragged sphere slides on its own layer's plane; the drag is for this
## viewing only and is never saved (spec §6.2).
func _drag_to(id: String, pos: Vector2) -> void:
	if not _pos.has(id) or not _sphere_mi.has(id):
		_end_gesture()
		return
	var ray := _ray(pos)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var y := (_pos[id] as Vector3).y
	if absf(d.y) < 1e-4:
		return
	var t := (y - o.y) / d.y
	if t <= 0.0:
		return
	_pos[id] = o + d * t
	_dragged[id] = _pos[id]
	(_sphere_mi[id] as MeshInstance3D).position = _pos[id]
	_move_threads_of(id)
	_update_hud()


## Re-lays, in place, only the threads that touch the dragged sphere: no
## mesh or material is made during a drag. A thread whose ends come to meet
## is hidden until they part.
func _move_threads_of(id: String) -> void:
	if not _pos.has(id):
		return
	for l: Dictionary in _snap.get("links", []):
		if String(l["from"]) != id and String(l["to"]) != id:
			continue
		var tid := String(l["id"])
		var mi: MeshInstance3D = _thread_mi.get(tid)
		if mi == null:
			continue
		var ends := _ends_of(l)
		mi.visible = not ends.is_empty()
		if ends.is_empty():
			_thread_ends.erase(tid)
			continue
		_place_thread(mi, ends[0], ends[1])
		_thread_ends[tid] = ends
