# scripts/ledger3d/ledger_view_3d.gd
class_name LedgerView3D
extends Control
## The LEDGER's galaxy (spec 2026-09-30-ledger-galaxy-design §5-§6): every
## object the crown knows of is a small bright star in its tab's cluster, the
## links shade from one cluster's colour to the other's, on a warm black
## night. It draws a snapshot (Ledger.galaxy) and signals what the player did;
## it reads no autoload and changes no state. It renders into a SubViewport at
## WINDOW resolution shown by a TextureRect, and only while active. How a
## star or a link is drawn comes from its type's row alone (`cluster`, `star`,
## `look` — spec §3b): no type is named here, so a type or link type the owner
## adds in data is drawn with no change here.

signal sphere_selected(id: String)
signal thread_selected(id: String)
signal drill_requested(id: String)
signal orders_requested(id: String, at: Vector2)

const CLICK_SLOP := 10.0
const EGO_AT_REST := "character:you"  # the player, whose ties are lit while no one is selected
const STAR_SEGMENTS := 24          # a star sphere's radial segments
const STAR_RINGS := 12             # and its rings
const TITLE_INK_BLEND := 0.45      # a cluster's title: its colour this far toward the label ink
const HAZE_MIN_RADIUS_M := 8.0     # a cluster's haze never smaller than this mean spread
const RING_GAP_RINGS := 2.0        # the selection ring stands this many ring widths off the star
const STAR_MAT := preload("res://scenes/ledger/materials/star.tres")
const STAR_FAINT_MAT := preload("res://scenes/ledger/materials/star_faint.tres")
const LINK_MAT := preload("res://scenes/ledger/materials/link.tres")
const HAZE_MAT := preload("res://scenes/ledger/materials/haze.tres")
const SPARK_MAT := preload("res://scenes/ledger/materials/spark.tres")

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _env: WorldEnvironment = %Env
@onready var _camera: Camera3D = %Camera
@onready var _stars: MultiMeshInstance3D = %Stars
@onready var _faint_stars: MultiMeshInstance3D = %FaintStars   # the dimmed ones, blended toward the sky (F1)
@onready var _sparks: MultiMeshInstance3D = %Sparks   # the current round every star, whole then dimmed (LedgerStarMotion)
@onready var _links: MeshInstance3D = %Links
@onready var _haze_root: Node3D = %Haze
@onready var _hud: LedgerHud = %Hud

var _repo: DataRepository
var _pal: Dictionary = {}
var _cluster_col: Dictionary = {}   # cluster -> Color
var _orbit := LedgerOrbit.new()
var _lay := LedgerGalaxyLayout.new()
var _snap: Dictionary = {}
var _nodes: Dictionary = {}
var _order: Array[String] = []
var _size: Dictionary = {}
var _drawn: Dictionary = {}
var _segs: Array = []                 # the links drawn now: every styled strand whose two ends are apart
var _styled: Array = []               # every strand of every link, styled at the last restyle (ends refreshed as the chart moves)
var _link_arrays: Array = []          # LedgerLinkMesh.arrays of _styled, its ends moved in place while settling
var _styled_ws := 0.0                 # the window scale _styled was styled at
var _frame_ids: Array = []            # what the camera frames while _framed
var _title_font: Font
var _star_cols := PackedColorArray()  # what each star wears, in _order (the MultiMesh's own copy is the renderer's)
var _index_of: Dictionary = {}       # id -> its place in _order
var _whole_cols := PackedColorArray()  # the colours dealt to the whole MultiMesh, in _whole
var _faint_cols := PackedColorArray()  # and to the blended one, in _faint
var _whole: Array[String] = []        # the stars drawn whole (opaque), in _order
var _faint: Array[String] = []        # the dimmed stars (alpha under 1), drawn blended, in _order
var _spark_ids: Array[String] = []    # the stars the current is dealt to: _whole then _faint (none at strength 0)
var _custom: Dictionary = {}          # id -> its seed and its current's weight (LedgerStarMotion.custom_of)
var _spark_cols := PackedColorArray() # the colours dealt to the current, in _spark_ids
var _buffers: Dictionary = {}         # MultiMesh node name -> the instance buffer last handed to it
var _near: Dictionary = {}           # the selected star's lineage: id -> LedgerLineage.FULL / FAR
var _lineage_links: Dictionary = {}  # and its links: link id -> LedgerLineage.FULL / FAR
var _star_mat: ShaderMaterial
var _faint_mat: ShaderMaterial
var _spark_mat: ShaderMaterial
var _link_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _haze: Dictionary = {}
var _ids_of_cluster: Dictionary = {}  # cluster -> its stars' ids, in _order (read once a snapshot)
var _hub_type: Dictionary = {}        # type -> whether its stars may be hubs (`hub` not 0), read once a snapshot
var _looks: Dictionary = {}         # link type -> its look (ledger_link_types.csv), read once a snapshot
var _cluster := "all"
var _selected := ""
var _hovered := ""
var _framed := false
var _button := 0
var _press_at := Vector2.ZERO
var _moved := false
var _drag_id := ""
var _fly_left := 0.0
var _fly_from: Array = []
var _fly_to: Array = []
var _last_pose := Transform3D()


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	mouse_exited.connect(_on_exit)
	_fit_viewport()
	set_process(false)


func bind(repo: DataRepository) -> void:
	_repo = repo
	_pal = repo.ledger_palette
	for c: Dictionary in repo.ledger_clusters:
		# a colour not in the palette (validate names it) draws in the planned grey
		_cluster_col[String(c["cluster"])] = _pal.get(String(c["colour"]), _pal["sphere_planned"])
	_orbit.distance = repo.bal("ledger_camera_distance")
	_orbit.pitch = repo.bal("ledger_camera_pitch_deg")
	_orbit.min_distance = repo.bal("ledger_camera_min_m")
	_orbit.max_distance = repo.bal("ledger_camera_max_m")
	var env := _env.environment
	env.glow_intensity = repo.bal("ledger_glow_intensity")
	env.glow_hdr_threshold = repo.bal("ledger_glow_threshold")
	_sky_mat = env.sky.sky_material.duplicate() as ShaderMaterial
	env.sky.sky_material = _sky_mat
	_sky_mat.set_shader_parameter("bg_top", _pal["sky_top"])
	_sky_mat.set_shader_parameter("bg_bottom", _pal["sky_bottom"])
	_sky_mat.set_shader_parameter("neb_a", _pal["nebula_a"])
	_sky_mat.set_shader_parameter("neb_b", _pal["nebula_b"])
	_sky_mat.set_shader_parameter("star_col", _pal["stars"])
	_star_mat = STAR_MAT.duplicate() as ShaderMaterial
	_faint_mat = STAR_FAINT_MAT.duplicate() as ShaderMaterial
	for m: ShaderMaterial in [_star_mat, _faint_mat]:
		m.set_shader_parameter("emit", repo.bal("ledger_star_emit"))
		m.set_shader_parameter("rim_gain", repo.bal("ledger_star_rim"))
		m.set_shader_parameter("metal", repo.bal("ledger_star_metallic"))
		m.set_shader_parameter("rough", repo.bal("ledger_star_roughness"))
		# the generated matcap (its texture is the .tres's; owner 2026-10-10)
		m.set_shader_parameter("matcap_mix", repo.bal("ledger_star_matcap_mix"))
		m.set_shader_parameter("matcap_gain", repo.bal("ledger_star_matcap_gain"))
		m.set_shader_parameter("matcap_white", repo.bal("ledger_star_matcap_white"))
		LedgerStarMotion.bind_wobble(m, repo)
	_stars.material_override = _star_mat
	_faint_stars.material_override = _faint_mat
	_spark_mat = SPARK_MAT.duplicate() as ShaderMaterial
	LedgerStarMotion.bind_spark(_spark_mat, repo)
	_sparks.material_override = _spark_mat
	_link_mat = LINK_MAT.duplicate() as ShaderMaterial
	_link_mat.set_shader_parameter("pulses", repo.bal("ledger_light_pulses"))
	_link_mat.set_shader_parameter("dashes_per_m", repo.bal("ledger_dashes_per_m"))
	_link_mat.set_shader_parameter("edge_soft", repo.bal("ledger_link_edge_soft"))
	_link_mat.set_shader_parameter("light_gain", repo.bal("ledger_light_gain"))
	# the generated strand (its texture is the .tres's; owner 2026-10-10)
	for key: String in ["mix", "widen", "px", "power", "gain", "white"]:
		_link_mat.set_shader_parameter("strand_" + key, repo.bal("ledger_link_strand_" + key))
	_link_mat.set_shader_parameter("glow_virtuous", _pal["loop_virtuous"])
	_link_mat.set_shader_parameter("glow_vicious", _pal["loop_vicious"])
	LedgerStarMotion.bind_wobble(_link_mat, repo)   # a link's ends move with its stars
	_links.material_override = _link_mat
	_hud.style(UiPalette.role_font("body"), repo.bal("ledger_label_px"), _pal["label_ink"], _pal["label_halo"],
		int(repo.bal("ledger_label_halo_px")))
	_hud.style_gauges(repo.bal("ledger_gauge_radius_px"), repo.bal("ledger_gauge_width_px"),
		repo.bal("ledger_gauge_gap_px"), repo.bal("ledger_gauge_caption_px"), _pal["gauge_fill"], _pal["gauge_track"])
	_title_font = UiPalette.role_font("header")
	_hud.style_title(_title_font, repo.bal("ledger_title_px"))
	_hud.style_ring(_pal["focus_ring"], repo.bal("ledger_ring_px"))
	_hud.style_halo(repo.bal("ledger_label_halo_soft_px"), repo.bal("ledger_label_halo_soft_alpha"))
	_apply_camera()


func _window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


func _fit_viewport() -> void:
	var s := _window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	if _repo != null and not _snap.is_empty() and not is_equal_approx(_window_scale(), _styled_ws):
		_rebuild_links()  # widths and shifts are in window px
	if _framed and _repo != null and not _snap.is_empty():
		_frame_on(_frame_ids, true)
	if _repo != null:
		_update_link_uniforms()


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if on:
		_fit_viewport()
	else:
		_viewport.size = Vector2i(2, 2)  # its render targets freed while shut (perf 2026-10-02)


## Draw a snapshot. Stars already placed keep their places (the layout is
## warm: the same stars settle no further, other stars only briefly — final
## review I1b); a star under a drag or the selection that is no longer drawn
## lets go. `keep_camera` holds the camera where it stands — no framing, and a
## framing in hand stops following the chart — else the camera frames the
## chosen cluster. `select_id`, when given, is selected as the chart is drawn
## (one restyle, not a second by select()).
func show_snapshot(snap: Dictionary, keep_camera: bool, select_id: String = "") -> void:
	_snap = snap
	_nodes.clear()
	_looks.clear()
	for r: Dictionary in _repo.ledger_links:
		_looks[String(r["link_id"])] = String(r.get("look", "flow"))
	_hub_type.clear()
	for r: Dictionary in _repo.ledger_types:
		_hub_type[String(r["type_id"])] = String(r.get("hub", "1")) != "0"
	var degree := {}
	for n: Dictionary in snap["nodes"]:
		_nodes[String(n["id"])] = n
	for l: Dictionary in snap["links"]:
		for e: String in [String(l["from"]), String(l["to"])]:
			degree[e] = int(degree.get(e, 0)) + 1
	_order.clear()
	for id: String in _nodes:
		_order.append(id)
	_order.sort()
	_index_of.clear()
	_ids_of_cluster.clear()
	for i in _order.size():
		_index_of[_order[i]] = i
		var c := _cluster_of(_order[i])
		if not _ids_of_cluster.has(c):
			_ids_of_cluster[c] = []
		(_ids_of_cluster[c] as Array).append(_order[i])
	_size.clear()
	for id: String in _order:
		_size[id] = drawn_radius(_nodes[id], int(degree.get(id, 0)))
	_lay.setup(_repo, snap)
	for id: String in _drawn.keys():
		if not _nodes.has(id):
			_drawn.erase(id)
	if select_id != "":
		_selected = select_id
	if not _nodes.has(_selected):
		_selected = ""
	if not _nodes.has(_hovered):
		_hovered = ""
	if _drag_id != "" and not _nodes.has(_drag_id):
		_end_gesture()
	_sync_drawn()
	_build_stars()
	_build_haze()
	_restyle()
	if keep_camera:
		_framed = false
	else:
		_frame_on(_cluster_ids(), true)
	_update_hud()


## A star's DRAWN radius (metres): its layout radius, a planned (ghost)
## star's held to an ordinary small star's (ledger_star_planned_max), all at
## ledger_star_draw_scale — small stars whose glow carries the size (Task 11
## fix round 1, F3 / F5). The layout keeps the full radius for its forces.
func drawn_radius(node: Dictionary, degree: int) -> float:
	var r := LedgerGalaxyLayout.size_of(_repo, node, degree)
	if String(node.get("status", "live")) == "planned":
		r = minf(r, _repo.bal("ledger_star_planned_max"))
	return r * _repo.bal("ledger_star_draw_scale")


func select(id: String) -> void:
	_selected = id if _nodes.has(id) else ""
	_restyle()
	_update_hud()


func front_view() -> void:
	_frame_on(_cluster_ids(), false)


## Choose a cluster ("all" for the whole galaxy): the camera flies to frame it
## and the other clusters dim (spec §6); nothing is hidden.
func focus_cluster(cluster_id: String) -> void:
	_cluster = cluster_id
	_restyle()
	_frame_on(_cluster_ids(), false)
	_update_hud()


## Frame a star and its lineage at full strength (LedgerLineage: its links,
## its flow chain, its own ties — not the dimmer ties of its ties), by LIVE
## links only: a planned (ghost) link's far end does not pull the camera
## (Task 11 fix round 4, T1c).
func frame_web(id: String) -> void:
	if not _nodes.has(id):
		return
	var ids: Array = [id]
	var star_set: Dictionary = lineage(id, false)["stars"]
	for s: String in star_set:
		if s != id and int(star_set[s]) == LedgerLineage.FULL:
			ids.append(s)
	_frame_on(ids, false)


## The lineage a selection of `id` lights (LedgerLineage.of over this
## snapshot, ledger_lineage_tie_hops); `with_planned` false leaves out a
## planned link's far end.
func lineage(id: String, with_planned: bool = true) -> Dictionary:
	return LedgerLineage.of(_snap, id, _look, int(_repo.bal("ledger_lineage_tie_hops")), with_planned)


## Frame an opened province and the stars it unfolded (its manors, towns
## and buildings: every star whose home is it), as frame_web frames a web
## (Task 11 fix round 1, F8).
func frame_opened(province_id: String) -> void:
	if not _nodes.has(province_id):
		return
	var ids: Array = [province_id]
	for id: String in _order:
		if String((_nodes[id] as Dictionary).get("home_id", "")) == province_id:
			ids.append(id)
	_frame_on(ids, false)


func cluster() -> String:
	return _cluster


## The selected star's id, or "".
func selected() -> String:
	return _selected


## Where the stars stand and how much settling is left (tests, tools).
func layout() -> LedgerGalaxyLayout:
	return _lay


func orbit() -> LedgerOrbit:
	return _orbit


func camera() -> Camera3D:
	return _camera


func link_material() -> ShaderMaterial:
	return _link_mat


func star_materials() -> Array[ShaderMaterial]:
	return [_star_mat, _faint_mat]


func spark_material() -> ShaderMaterial:
	return _spark_mat


## The current round the stars: one instance per drawn star, the whole ones
## then the dimmed ones, laid as they are (tests, tools).
func sparks() -> MultiMeshInstance3D:
	return _sparks


## The stars the current is dealt to, in its instances' order.
func spark_ids() -> Array[String]:
	return _spark_ids


## The stars drawn whole, then the dimmed ones, in their MultiMeshes' order.
func dealt() -> Array:
	return [_whole, _faint]


## A star's custom data: its seed (x, y) and its current's weight (z).
func star_custom(id: String) -> Color:
	return _custom.get(id, Color(0, 0, 0, 0))


## The instance buffer last handed to a star MultiMesh ("Stars",
## "FaintStars" or "Sparks"), in LedgerStarMotion.pack's layout: what the
## renderer was given (a headless run's dummy renderer keeps none of it).
func instance_buffer(node_name: String) -> PackedFloat32Array:
	return _buffers.get(node_name, PackedFloat32Array())


func stars() -> Array[String]:
	return _order


func drawn(id: String) -> Vector3:
	return _drawn.get(id, Vector3.ZERO)


func segments() -> Array:
	return _segs


func star_colour(id: String) -> Color:
	var i := int(_index_of.get(id, -1))
	return _star_cols[i] if i >= 0 and i < _star_cols.size() else Color(0, 0, 0, 0)


## Settles the chart at once and ends any ease (tests and shots).
func settle_now() -> void:
	while not _lay.settled():
		_lay.step(10)
	_sync_drawn()
	_place_stars()
	_relay_links()
	_place_haze()
	if _framed:
		_frame_on(_frame_ids, true)
	elif not _fly_to.is_empty():
		_ease_camera(1.0)
	_fly_left = 0.0
	_apply_camera()
	_update_link_uniforms()
	_update_hud()


func screen_pos_of(id: String) -> Variant:
	if not _drawn.has(id) or _camera.is_position_behind(_drawn[id]):
		return null
	return _camera.unproject_position(_drawn[id]) / _window_scale()


# --- stars, links, haze ------------------------------------------------------

func _sync_drawn() -> void:
	for id: String in _order:
		_drawn[id] = _lay.pos[id]


func _build_stars() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = STAR_SEGMENTS
	sphere.rings = STAR_RINGS
	# the current round each star: a quad the shader turns to the camera
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	for mi: MultiMeshInstance3D in [_stars, _faint_stars, _sparks]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true   # the star's seed (and its current's weight)
		mm.mesh = (quad as Mesh) if mi == _sparks else (sphere as Mesh)
		mi.multimesh = mm


## Deals the stars between the whole (opaque) and the dimmed (blended)
## MultiMesh by what each wears now, then places them.
func _fill_stars() -> void:
	_whole.clear()
	_faint.clear()
	var whole_cols := PackedColorArray()
	var faint_cols := PackedColorArray()
	for i in _order.size():
		if _star_cols[i].a >= 1.0:
			_whole.append(_order[i])
			whole_cols.append(_star_cols[i])
		else:
			_faint.append(_order[i])
			faint_cols.append(_star_cols[i])
	_whole_cols = whole_cols
	_faint_cols = faint_cols
	_custom.clear()
	for i in _order.size():
		_custom[_order[i]] = LedgerStarMotion.custom_of(_repo, _order[i], _star_cols[i].a, _order[i] == _selected)
	_spark_ids = []
	_spark_cols = PackedColorArray()
	if LedgerStarMotion.sparks_on(_repo):
		_spark_ids.append_array(_whole)
		_spark_ids.append_array(_faint)
		_spark_cols = whole_cols + faint_cols
	for pair: Array in [[_stars, _whole], [_faint_stars, _faint], [_sparks, _spark_ids]]:
		var mm: MultiMesh = (pair[0] as MultiMeshInstance3D).multimesh
		var n: int = (pair[1] as Array).size()
		if mm != null and mm.instance_count != n:
			mm.instance_count = n
	_place_stars()


## Lays every star where it is drawn now, and its current with it: ONE
## buffer per MultiMesh (transform, colour, seed and weight per instance,
## LedgerStarMotion.pack), the current's built from the very transforms its
## stars are given.
func _place_stars() -> void:
	var laid := {}   # id -> its transform now
	for ids: Array[String] in [_whole, _faint]:
		for id: String in ids:
			var r := _draw_r(id)
			laid[id] = Transform3D(Basis().scaled(Vector3(r, r, r)), _drawn[id])
	# a dimmed star the camera has come right up to (another cluster's, seen
	# from inside the chosen one) fades out rather than fill the view as a
	# blurred disc (critic, round 2): its body's alpha and its current's weight
	var faint_cols := _faint_cols
	var spark_cols := _spark_cols
	var custom := _custom
	var near := {}
	for k in _faint.size():
		var f := near_fade(_faint[k])
		if f < 1.0:
			near[k] = f
	if not near.is_empty():
		faint_cols = _faint_cols.duplicate()
		custom = _custom.duplicate()
		for k: int in near:
			var id := _faint[k]
			var c: Color = faint_cols[k]
			c.a *= float(near[k])
			faint_cols[k] = c
			var u: Color = custom[id]
			u.b *= float(near[k])
			custom[id] = u
		if not _spark_ids.is_empty():
			spark_cols = _whole_cols + faint_cols
	_buffers.clear()
	for group: Array in [[_stars, _whole, _whole_cols], [_faint_stars, _faint, faint_cols],
			[_sparks, _spark_ids, spark_cols]]:
		var mi: MultiMeshInstance3D = group[0]
		var ids: Array[String] = group[1]
		if mi.multimesh == null or mi.multimesh.instance_count != ids.size():
			continue
		var buf := LedgerStarMotion.pack(ids, laid, group[2], custom)
		_buffers[String(mi.name)] = buf
		if not ids.is_empty():
			mi.multimesh.buffer = buf


## How much of a star stands as the camera nears it: 1, down to 0 between
## ledger_near_fade_start and _end of the camera's distance to its target
## (a share, so it holds at every zoom).
func near_fade(id: String) -> float:
	if not _drawn.has(id):
		return 1.0
	var ref := maxf(_orbit.distance, 1e-3)
	var d := (_drawn[id] as Vector3).distance_to(_camera.transform.origin)
	return smoothstep(ref * _repo.bal("ledger_near_fade_end"), ref * _repo.bal("ledger_near_fade_start"), d)


## A star's radius as drawn NOW (metres): its drawn radius, held to
## ledger_star_max_px of screen (Task 11 fix round 2, R6: close in, a pool
## grew into a 70 px shaded ball).
func _draw_r(id: String) -> float:
	var cap := _repo.bal("ledger_star_max_px") * _window_scale() * _m_per_px_at(_drawn[id])
	return minf(float(_size[id]), cap)


func _cluster_of(id: String) -> String:
	return String((_nodes.get(id, {}) as Dictionary).get("cluster", ""))


func _look(l: Dictionary) -> String:
	return String(_looks.get(String(l["type"]), "flow"))


## Colours and fades from the selection and the chosen cluster, then the links.
func _restyle() -> void:
	_near.clear()
	_lineage_links.clear()
	if _selected != "":
		var lin := lineage(_selected)
		_near = lin["stars"]
		_lineage_links = lin["links"]
	_star_cols.resize(_order.size())
	for i in _order.size():
		_star_cols[i] = _star_colour(_order[i])
	_fill_stars()
	_rebuild_links()
	_place_haze()


func _star_colour(id: String) -> Color:
	var n: Dictionary = _nodes[id]
	var c: Color = _cluster_col.get(_cluster_of(id), _pal["sphere_planned"])
	var f := 1.0
	# a planned (ghost) star: its own cluster's colour, desaturated and
	# faint — not yet built, never a neutral grey clay ball (F3)
	if String(n.get("status", "live")) == "planned":
		c = Color.from_hsv(c.h, c.s * _repo.bal("ledger_star_planned_sat"), c.v)
		f = _repo.bal("ledger_star_planned_fade")
	if _selected != "" and _near.has(id):
		# the selected lineage reads WHOLE, whatever the tab (owner
		# 2026-10-01): at its own level, never under the tab's dimming
		if int(_near[id]) == LedgerLineage.FAR:
			f = minf(f, _repo.bal("ledger_lineage_far_fade"))
		return Color(c, f)
	if _selected != "":
		f = minf(f, _repo.bal("ledger_focus_fade"))
	if _cluster != "all" and _cluster_of(id) != _cluster:
		f = minf(f, _repo.bal("ledger_galaxy_other_fade"))
	return Color(c, f)


## Styles every link afresh (a new snapshot, selection, cluster or window
## scale) and draws it.
func _rebuild_links() -> void:
	_styled = _segments()
	_styled_ws = _window_scale()
	_link_arrays = LedgerLinkMesh.arrays(_styled)
	_segs = _styled.filter(func(seg: Dictionary) -> bool: return not (seg["a"] as Vector3).is_equal_approx(seg["b"]))
	_links.mesh = LedgerLinkMesh.mesh_of(_link_arrays)
	_update_link_uniforms()


## Re-lays the links where their stars now stand, their styling kept (a
## settling or dragged chart): only the ends move. A link whose two ends meet
## draws nothing (its quad has no length) and is not picked.
func _relay_links() -> void:
	var ends: Array = []
	_segs = []
	for seg: Dictionary in _styled:
		var a: Vector3 = _drawn.get(String(seg["a_id"]), seg["a"])
		var b: Vector3 = _drawn.get(String(seg["b_id"]), seg["b"])
		seg["a"] = a
		seg["b"] = b
		ends.append([a, b])
		if not a.is_equal_approx(b):
			_segs.append(seg)
	if _styled.is_empty():
		return
	LedgerLinkMesh.move_ends(_link_arrays, ends)
	_links.mesh = LedgerLinkMesh.mesh_of(_link_arrays)


func _update_link_uniforms() -> void:
	if _link_mat == null:
		return
	var h := float(maxi(_viewport.size.y, 1))
	for m: ShaderMaterial in [_link_mat, _spark_mat]:
		m.set_shader_parameter("px_per_dist", 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) / h)
	_link_mat.set_shader_parameter("star_cap_px", _repo.bal("ledger_star_max_px") * _window_scale())
	_spark_mat.set_shader_parameter("ring_out_px", LedgerStarMotion.ring_out_px(_repo, RING_GAP_RINGS, _window_scale()))
	_spark_mat.set_shader_parameter("ring_band_px", LedgerStarMotion.ring_band_px(_repo, _window_scale()))


func _running_links() -> Dictionary:
	var out := {}
	for lp: Dictionary in _snap.get("loops", []):
		if bool(lp["running"]):
			for t: String in lp["links"]:
				out[t] = String(lp["kind"])
	return out


func _pair_key(l: Dictionary) -> Array:
	var key := [String(l["from"]), String(l["to"])]
	key.sort()
	return key


func _segments() -> Array:
	var out: Array = []
	var pairs := {}
	for l: Dictionary in _snap.get("links", []):
		var key := _pair_key(l)
		pairs[key] = int(pairs.get(key, 0)) + 1
	var running := _running_links()
	var ws := _window_scale()
	for l: Dictionary in _snap.get("links", []):
		var a_id := String(l["from"])
		var b_id := String(l["to"])
		if not _drawn.has(a_id) or not _drawn.has(b_id):
			continue
		var a: Vector3 = _drawn[a_id]
		var b: Vector3 = _drawn[b_id]
		var cols := _link_colours(l)
		var alpha := _ink(l) * pow(_link_fade(l), 2.2)
		var wide := _repo.bal("ledger_focus_width") if _lit_web(l) else 1.0
		var key := _pair_key(l)
		var pair_shift := 0.0
		if int(pairs[key]) > 1:
			pair_shift = _repo.bal("ledger_pair_offset_px") * (1.0 if a_id == key[0] else -1.0)
		var planned := String(l["status"]) == "planned" or bool(l.get("vacant", false))
		var speed := 0.0
		if not planned and _look(l) == "flow" and l["flow"] != null and int(l["flow"]) > 0:
			var t := inverse_lerp(_repo.bal("ledger_link_min_px"), _repo.bal("ledger_link_max_px"), _width_px(l))
			speed = _repo.bal("ledger_light_speed") * (0.4 + 0.6 * clampf(t, 0.0, 1.0))
		var glow := {"virtuous": 1, "vicious": 2}.get(String(running.get(String(l["type"]), "")), 0) as int
		for st: Array in _split(l):
			out.append({"id": String(st[0]), "link": String(l["id"]), "a_id": a_id, "b_id": b_id, "a": a, "b": b,
				"a_star": LedgerStarMotion.link_star(a_id, float(_size[a_id]), a_id == _selected),
				"b_star": LedgerStarMotion.link_star(b_id, float(_size[b_id]), b_id == _selected),
				"ca": Color(cols[0] as Color, alpha), "cb": Color(cols[1] as Color, alpha),
				"width_px": _width_px(st[1]) * wide * ws, "shift_px": (float(st[2]) + pair_shift) * ws,
				"dashed": planned, "speed": speed, "glow": glow})
	return out


## The strands a link is drawn as: itself while its accounts agree; one per
## account when they differ — "<link id>#<i>", each its own width, side by side
## ledger_strand_gap_px apart edge to edge, the bundle centred on the link.
## Each entry is [thread id, the link as that strand, its shift in px].
func _split(l: Dictionary) -> Array:
	var accs: Array = l.get("accounts", [])
	if accs.size() <= 1:
		return [[String(l["id"]), l, 0.0]]
	var items: Array = []
	var widths: Array[float] = []
	for acc: Dictionary in accs:
		var one := l.duplicate()
		one["flow"] = acc["value"]
		one["accounts"] = [acc]
		items.append(one)
		widths.append(_width_px(one))
	var gap := _repo.bal("ledger_strand_gap_px")
	var centres: Array[float] = [0.0]
	for i in range(1, items.size()):
		centres.append(centres[i - 1] + widths[i - 1] * 0.5 + gap + widths[i] * 0.5)
	var mid := (centres[0] - widths[0] * 0.5 + centres[-1] + widths[-1] * 0.5) * 0.5
	var out: Array = []
	for i in items.size():
		out.append(["%s#%d" % [l["id"], i], items[i], centres[i] - mid])
	return out


## The link a picked thread belongs to: a strand's id less its "#<i>".
static func link_id_of(thread_id: String) -> String:
	var at := thread_id.rfind("#")
	if at > 0 and thread_id.substr(at + 1).is_valid_int():
		return thread_id.substr(0, at)
	return thread_id


func _width_px(l: Dictionary) -> float:
	match _look(l):
		"tie", "kin":
			var feel := absf(float(l["flow"])) if l["flow"] != null else 0.0
			return lerpf(_repo.bal("ledger_tie_min_px"), _repo.bal("ledger_tie_max_px"),
				clampf(feel / _repo.bal("ledger_tie_ref"), 0.0, 1.0))
		"structure":
			return _count_width_px(l)
	if l["flow"] == null:
		return _count_width_px(l)
	var f := float(l["flow"])
	if f <= 0.0:
		return _repo.bal("ledger_link_min_px")
	var t := clampf(log(1.0 + f) / log(1.0 + _repo.bal("ledger_thread_flow_ref")), 0.0, 1.0)
	return lerpf(_repo.bal("ledger_link_min_px"), _repo.bal("ledger_link_max_px"), t)


## A link with no figure (words only, or a structural tie) is as wide as
## how many links it stands for: log scale to ledger_link_count_ref.
func _count_width_px(l: Dictionary) -> float:
	var n := maxf(float(l.get("count", 1)), 1.0)
	var t := clampf(log(1.0 + n) / log(1.0 + _repo.bal("ledger_link_count_ref")), 0.0, 1.0)
	return lerpf(_repo.bal("ledger_link_min_px"), _repo.bal("ledger_link_max_px"), t)


## A link's two colours: its ends' clusters', yellowing with its report's
## age; a planned or vacant one grey. A court tie is no exception (owner
## 2026-10-01: King Aldric's ties in tan, red and green "非常突兀，应该和周边类似"):
## its feeling is its width and its card, never a hue of its own.
func _link_colours(l: Dictionary) -> Array:
	if String(l["status"]) == "planned" or bool(l.get("vacant", false)):
		return [_pal["thread_planned"], _pal["thread_planned"]]
	var ca: Color = _cluster_col.get(_cluster_of(String(l["from"])), _pal["thread_live"])
	var cb: Color = _cluster_col.get(_cluster_of(String(l["to"])), _pal["thread_live"])
	var accs: Array = l["accounts"]
	if not accs.is_empty():
		var age := clampf(float(int(_snap["day"]) - int(accs[0]["day"])) / _repo.bal("ledger_age_full_days"), 0.0, 1.0)
		ca = ca.lerp(_pal["thread_aged"], age)
		cb = cb.lerp(_pal["thread_aged"], age)
	return [ca, cb]


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


## Whether a link is drawn ledger_focus_width wider: the selected star's
## web, or — at rest — the player's own web in their cluster, so the knot of
## their ties reads over the rest (Task 11 fix round 2, R4).
func _lit_web(l: Dictionary) -> bool:
	var a := String(l["from"])
	var b := String(l["to"])
	if _selected != "":
		return int(_lineage_links.get(String(l["id"]), 0)) == LedgerLineage.FULL
	if not _nodes.has(EGO_AT_REST) or (a != EGO_AT_REST and b != EGO_AT_REST):
		return false
	var c := _cluster_of(EGO_AT_REST)
	return _look(l) in ["tie", "kin"] or (_cluster_of(a) == c and _cluster_of(b) == c)


## How much of a link shows, as the EYE reads it (spec §6): the selected
## star's lineage lit (its far ties at ledger_lineage_far_fade) whatever the
## tab, the rest at ledger_focus_fade; at rest the court is read
## one person's web at a time (the player's ties lit, other ties at
## ledger_tie_rest_fade) and a link crossing clusters stands back at
## ledger_cross_rest_fade; a chosen cluster dims links that do not touch it.
func _link_fade(l: Dictionary) -> float:
	var a := String(l["from"])
	var b := String(l["to"])
	var f := 1.0
	if _selected != "":
		# a link of the selected lineage reads at its own level, whatever the
		# tab: the tab's dimming is only for what lies outside it
		match int(_lineage_links.get(String(l["id"]), 0)):
			LedgerLineage.FULL:
				return 1.0
			LedgerLineage.FAR:
				return _repo.bal("ledger_lineage_far_fade")
			_:
				f = _repo.bal("ledger_focus_fade")
	elif _nodes.has(EGO_AT_REST) and (_look(l) in ["tie", "kin"] or (_cluster_of(a) == _cluster_of(EGO_AT_REST)
			and _cluster_of(b) == _cluster_of(EGO_AT_REST))):
		# at rest the player's own cluster (the court) is read one web at a
		# time: its ties AND its structure (member, sits) stand back unless
		# they touch the player (Task 11 fix round 1, F2)
		if a != EGO_AT_REST and b != EGO_AT_REST:
			f = _repo.bal("ledger_tie_rest_fade")
	elif _cluster_of(a) != _cluster_of(b):
		f = _repo.bal("ledger_cross_rest_fade")
	if _cluster != "all" and _cluster_of(a) != _cluster and _cluster_of(b) != _cluster:
		f = minf(f, _repo.bal("ledger_galaxy_other_fade"))
	return f


func _build_haze() -> void:
	for c in _haze_root.get_children():
		c.queue_free()
	_haze.clear()
	for row: Dictionary in _repo.ledger_clusters:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := HAZE_MAT.duplicate() as ShaderMaterial
		m.set_shader_parameter("tint", _pal.get(String(row["colour"]), _pal["sphere_planned"]))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze_root.add_child(mi)
		_haze[String(row["cluster"])] = mi
	_place_haze()


func _place_haze() -> void:
	for c: String in _haze:
		var mi: MeshInstance3D = _haze[c]
		var ids: Array = _ids_of_cluster.get(c, [])
		var sum := Vector3.ZERO
		var n := ids.size()
		for id: String in ids:
			sum += _drawn[id]
		mi.visible = n > 0
		if n == 0:
			continue
		var mid := sum / float(n)
		var rad := 0.0
		for id: String in ids:
			rad += (_drawn[id] as Vector3).distance_to(mid)
		rad = maxf(rad / float(n), HAZE_MIN_RADIUS_M)
		(mi.mesh as QuadMesh).size = Vector2.ONE * rad * _repo.bal("ledger_haze_scale")
		mi.position = mid
		var dim := _repo.bal("ledger_galaxy_other_fade") if _cluster != "all" and c != _cluster else 1.0
		(mi.material_override as ShaderMaterial).set_shader_parameter("strength", _repo.bal("ledger_haze_strength") * dim)


# --- camera ------------------------------------------------------------------

func _cluster_ids() -> Array:
	if _cluster == "all":
		return _order.duplicate()
	return _order.filter(func(id: String) -> bool: return _cluster_of(id) == _cluster)


## Frames `ids` (the camera flies there unless `instant`) and holds them
## framed: while the chart settles or eases, each moved frame frames them
## again, until the player moves the camera.
func _frame_on(ids: Array, instant: bool) -> void:
	_frame_ids = ids
	var to := _frame_target(ids)
	if to.is_empty():
		return
	_fly_from = [_orbit.target, _orbit.distance, _orbit.yaw, _orbit.pitch]
	_fly_to = to
	_framed = true
	_fly_left = 0.0 if instant else _repo.bal("ledger_galaxy_fly_s")
	if _fly_left <= 0.0:
		_ease_camera(1.0)


## [target, distance, yaw, pitch] that frame `ids` as they stand now, or [].
func _frame_target(ids: Array) -> Array:
	var points: Array[Vector3] = []
	for id: String in ids:
		if not _drawn.has(id):
			continue
		var r := float(_size.get(id, 1.0))
		points.append((_drawn[id] as Vector3) - Vector3(r, r, r))
		points.append((_drawn[id] as Vector3) + Vector3(r, r, r))
	if points.is_empty():
		return []
	var sz := size if size.x >= 2.0 and size.y >= 2.0 else Vector2(1280, 720)
	var side := _repo.bal("ledger_frame_side_px") / sz.x
	var top := (_repo.bal("ledger_frame_top_px") + _title_reach_px()) / sz.y
	var bottom := _repo.bal("ledger_frame_bottom_px") / sz.y
	var safe := Rect2(side, top, maxf(1.0 - 2.0 * side, 0.1), maxf(1.0 - top - bottom, 0.1))
	var pitch := _repo.bal("ledger_camera_pitch_deg")
	var f := LedgerOrbit.frame(points, 0.0, pitch, _camera.fov, sz.x / sz.y, safe)
	if f.is_empty():
		return []
	return [f["target"], clampf(float(f["distance"]), _orbit.min_distance, _orbit.max_distance), 0.0, pitch]


## Design px from the highest star's disc to the top of its cluster's title
## (a name line, then the title over it — see _update_hud), which the framing
## keeps clear under the screen's top chrome.
func _title_reach_px() -> float:
	return _repo.bal("ledger_label_lift_px") + _repo.bal("ledger_label_px") + _repo.bal("ledger_title_px") * 0.95


func _ease_camera(t: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	_orbit.target = (_fly_from[0] as Vector3).lerp(_fly_to[0], k)
	_orbit.distance = lerpf(float(_fly_from[1]), float(_fly_to[1]), k)
	_orbit.yaw = lerpf(float(_fly_from[2]), float(_fly_to[2]), k)
	_orbit.pitch = lerpf(float(_fly_from[3]), float(_fly_to[3]), k)
	_apply_camera()


func _apply_camera() -> void:
	_camera.transform = _orbit.pose()


func _process(delta: float) -> void:
	if _repo == null or _snap.is_empty():
		return
	var moved := not _lay.settled()
	if moved:
		_lay.step_within(_repo.bal("ledger_galaxy_ms_per_frame"))
		_settle_frame()
	if _fly_left > 0.0:
		_fly_left = maxf(_fly_left - delta, 0.0)
		_ease_camera(1.0 - _fly_left / maxf(_repo.bal("ledger_galaxy_fly_s"), 0.001))
	if moved or not _camera.transform.is_equal_approx(_last_pose):
		if not moved:
			_place_stars()  # the screen cap moves with the camera (R6)
		_last_pose = _camera.transform
		_update_link_uniforms()
		_update_hud()


## One frame of a moving chart (settling): the
## stars, the links' ends and the haze follow, and a framed camera frames
## what it framed again — mid-flight, the flight's end is re-aimed instead.
func _settle_frame() -> void:
	_sync_drawn()
	_place_stars()
	_relay_links()
	_place_haze()
	if not _framed:
		return
	var to := _frame_target(_frame_ids)
	if to.is_empty():
		return
	if _fly_left > 0.0:
		_fly_to = to
	else:
		_fly_from = to
		_fly_to = to
		_ease_camera(1.0)


# --- names ---------------------------------------------------------------------

## Metres per SubViewport px at a point.
func _m_per_px_at(p: Vector3) -> float:
	var h := float(maxi(_viewport.size.y, 1))
	return p.distance_to(_camera.global_position) * 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) / h


func _screen_radius(id: String) -> float:
	return _draw_r(id) / _m_per_px_at(_drawn[id]) / _window_scale()


## A place on the screen (design px) inside the view.
func _in_view(at: Variant) -> bool:
	return at != null and Rect2(Vector2.ZERO, size).has_point(at as Vector2)


func _update_hud() -> void:
	if _repo == null:
		return
	var entries: Array = []
	var obstacles: Array = []
	var label_px := _repo.bal("ledger_label_px")
	var strong_px := _repo.bal("ledger_label_strong_px")
	var title_px := _repo.bal("ledger_title_px")
	var lift := _repo.bal("ledger_label_lift_px")
	var chrome := _repo.bal("ledger_frame_top_px")
	var seen := _seen()   # id -> [its screen place, its screen radius], for the stars in view
	var middle := Vector2.ZERO
	for id: String in seen:
		middle += seen[id][0] as Vector2
	if not seen.is_empty():
		middle /= float(seen.size())
	for id: String in seen:
		var at: Vector2 = seen[id][0]
		var r: float = seen[id][1]
		obstacles.append(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
	# The selected star first (spec §7: always named, as a `keep` entry: never
	# pushed away from its own ring; when crowded it takes the least-covered
	# place round its own star), then the titles, the hubs (`keep` while not
	# dimmed), its neighbours and the hovered star.
	var named: Array[String] = []
	var big := {}   # names set in the larger size: the selected star and the hubs
	var keep := {}
	if _selected != "":
		named.append(_selected)
		big[_selected] = true
		keep[_selected] = true
	for id: String in _hubs(seen):
		if not named.has(id):
			named.append(id)
		big[id] = true
		# a hub dimmed by the selection or the chosen cluster names itself
		# only where there is room: it never crosses a star to stand over
		# the web being read
		if star_colour(id).a >= 1.0:
			keep[id] = true
	if _selected != "":
		# its lineage at full strength first; the far ties only where there
		# is room (they are dimmer, and a dimmed name drops rather than wander)
		for level: int in [LedgerLineage.FULL, LedgerLineage.FAR]:
			for id: String in _near:
				if int(_near[id]) == level and not named.has(id):
					named.append(id)
	if _hovered != "" and not named.has(_hovered):
		named.append(_hovered)
	var titles: Array = []
	# Each cluster's title (spec §7): over its highest star's disc and one
	# name line above that, set outward from the galaxy's middle — sideways,
	# and up but never down, nor into the screen's top chrome — so it never
	# sits on a star of its own.
	for row: Dictionary in _repo.ledger_clusters:
		var c := String(row["cluster"])
		var n := 0
		var sum := Vector2.ZERO
		var left := INF
		var right := -INF
		var top := INF
		for id: String in seen:
			if _cluster_of(id) != c:
				continue
			var at: Vector2 = seen[id][0]
			var r: float = seen[id][1]
			n += 1
			sum += at
			left = minf(left, at.x)
			right = maxf(right, at.x)
			top = minf(top, at.y - r)
		if n == 0:
			continue
		var out := (sum / float(n) - middle).normalized()
		var title := "%s  ·  %d" % [row["label"], n]
		var place := Vector2((left + right) * 0.5, top - lift - label_px - title_px * 0.5)
		place += Vector2(out.x, minf(out.y, 0.0)) * title_px
		var half := _title_width(title, title_px) * 0.5
		place.x = clampf(place.x, minf(half, size.x * 0.5), maxf(size.x - half, size.x * 0.5))
		place.y = maxf(place.y, chrome + title_px * 0.45)
		var ink: Color = (_cluster_col[c] as Color).lerp(_pal["label_ink"], TITLE_INK_BLEND)
		if _cluster != "all" and c != _cluster:
			ink.a = _repo.bal("ledger_galaxy_other_fade")
		# the chosen cluster's title (every title in All) is `keep`: it may
		# cross a dimmed star of another cluster rather than go unnamed
		titles.append({"text": title, "strong": true, "title": true, "px": title_px, "ink": ink, "at": place,
			"keep": _cluster == "all" or c == _cluster})
	for id: String in named:
		var at: Variant = screen_pos_of(id)
		if at == null:
			continue
		var r := _screen_radius(id)
		var px := strong_px if big.has(id) else label_px
		var e := {"id": id, "text": drawn_name(id), "px": px, "at": (at as Vector2) - Vector2(0, r + lift),
			"alt": (at as Vector2) + Vector2(0, r + lift + px), "beside": [at, r],
			"strong": id == _selected or int(_near.get(id, 0)) == LedgerLineage.FULL,
			# a star's gauges only for the selected and the hovered star (Task
			# 11 fix round 3, S1a: a row on every hub only repeated the next)
			"props": _nodes[id].get("props", []) if id == _selected or id == _hovered else []}
		if keep.has(id):
			e["keep"] = true
		# a dimmed star's name dims with it (F9)
		var fade := star_colour(id).a
		if fade < 1.0 and id != _selected:
			e["ink"] = Color(_pal["label_ink"] as Color, 0.8 * fade)
		if id == _selected:
			e["ring"] = r + _repo.bal("ledger_ring_px") * RING_GAP_RINGS
			e["ring_at"] = at
			e["beside"] = [at, float(e["ring"]) + _repo.bal("ledger_ring_px")]  # clear of its ring
			e["first"] = true  # placed first; no other name touches its label (T1a)
		if id == _selected or int(_near.get(id, 0)) == LedgerLineage.FULL:
			e["lit"] = true    # off the planned dashes where a near place allows (T1b)
		elif fade < 1.0:
			e["dim"] = true    # a ghost name drops rather than wander (T1a)
		entries.append(e)
	var first := 1 if _selected != "" and not entries.is_empty() and entries[0].has("ring") else 0
	entries = entries.slice(0, first) + titles + entries.slice(first)
	_hud.show_entries(entries, obstacles, [Rect2(0.0, -size.y, size.x, size.y + chrome)], Rect2(Vector2.ZERO, size),
		_dash_paths())


## The planned (dashed) links on the screen, [a, b] in design px: a lit label
## keeps off them where a near place allows (Task 11 fix round 4, T1b).
func _dash_paths() -> Array:
	var out: Array = []
	for seg: Dictionary in _segs:
		if not bool(seg["dashed"]):
			continue
		var a: Variant = screen_pos_of(String(seg["a_id"]))
		var b: Variant = screen_pos_of(String(seg["b_id"]))
		if a != null and b != null:
			out.append([a, b])
	return out


## Whether a star may be an always-named hub: its type's `hub` is not 0, and
## in a chosen cluster it is that cluster's.
func _may_be_hub(id: String) -> bool:
	if _cluster != "all" and _cluster_of(id) != _cluster:
		return false
	return bool(_hub_type.get(String(_nodes[id]["type"]), true))


## The name a star is DRAWN with in the galaxy: its label less the words its
## type already says — the type's `short_name` in ledger_object_types.csv,
## a pattern whose `*` is the part kept, optionally followed by " -> " and a
## template the kept part is set in ("Supply line from * -> Supplies from *":
## "Supply line from Altnesbury to 10th (Rothbridbu) Foot" is drawn "Supplies
## from Altnesbury to 10th (Rothbridbu) Foot", so a supply line never reads as
## its unit); a label
## that does not match — or would leave a blank name — is kept whole. The
## card and the tooltip keep the full label (Task 11 fix rounds 2-3, R2 / S1b).
func drawn_name(id: String) -> String:
	var label := String(_nodes[id]["label"])
	var rule := String(Ledger.type_row(_repo, String(_nodes[id]["type"])).get("short_name", ""))
	var pattern := rule.get_slice(" -> ", 0)
	var template := rule.get_slice(" -> ", 1) if rule.contains(" -> ") else "*"
	var star := pattern.find("*")
	if star < 0:
		return label
	var head := pattern.substr(0, star)
	var tail := pattern.substr(star + 1)
	if label.length() > head.length() + tail.length() and label.begins_with(head) and label.ends_with(tail):
		var kept := label.substr(head.length(), label.length() - head.length() - tail.length()).strip_edges()
		var short := template.replace("*", kept).strip_edges()
		if short != "":
			return short
	return label


## The stars in view: id -> [its screen place (design px), its screen radius]
## (screen_pos_of and _screen_radius, the window's scale read once).
func _seen() -> Dictionary:
	var seen := {}
	var ws := _window_scale()
	var view := Rect2(Vector2.ZERO, size)
	var cap_px := _repo.bal("ledger_star_max_px") * ws
	for id: String in _order:
		var p: Vector3 = _drawn[id]
		if _camera.is_position_behind(p):
			continue
		var at := _camera.unproject_position(p) / ws
		if not view.has_point(at):
			continue
		var mpp := _m_per_px_at(p)
		seen[id] = [at, minf(float(_size[id]), cap_px * mpp) / mpp / ws]
	return seen


## The `ledger_label_hubs` largest stars in view (spec §7: always named),
## largest first, ties by id.
func _hubs(seen: Dictionary = {}) -> Array[String]:
	if seen.is_empty():
		seen = _seen()
	# in a chosen cluster only its own stars are hubs (F9: another cluster's
	# star named as a hub read as one of this cluster's)
	# a type whose stars only mirror another's (`hub` 0 in
	# ledger_object_types.csv: a supply line mirrors its regiment) is never
	# an always-named hub; it is named on hover and selection (R2)
	# the largest few kept in order as the stars go by (no sort of every
	# star: final wave I1d) — largest first, ties by id
	var want := int(_repo.bal("ledger_label_hubs"))
	var out: Array[String] = []
	var sizes: Array[float] = []
	for id: String in _order:
		if not seen.has(id) or not _may_be_hub(id):
			continue
		var r := float(_size[id])
		var at := out.size()
		while at > 0 and (sizes[at - 1] < r or (sizes[at - 1] == r and out[at - 1] > id)):
			at -= 1
		if at >= want:
			continue
		out.insert(at, id)
		sizes.insert(at, r)
		if out.size() > want:
			out.resize(want)
			sizes.resize(want)
	return out


## A title's width in design px, measured in the title font as the HUD cull
## measures it.
func _title_width(text: String, px: float) -> float:
	if _title_font == null:
		return float(text.length()) * px * 0.55
	return _title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x


# --- input ---------------------------------------------------------------------

func _ray(pos: Vector2) -> Array:
	var px := LedgerPick.screen_to_viewport(pos, _window_scale())
	return [_camera.project_ray_origin(px), _camera.project_ray_normal(px)]


## A segment's two ends in the world, its strand's screen shift applied (what
## link.gdshader draws, so what a click meets).
func seg_ends(seg: Dictionary) -> Array:
	var a: Vector3 = seg["a"]
	var b: Vector3 = seg["b"]
	var shift := float(seg["shift_px"])
	if shift == 0.0:
		return [a, b]
	var mid := (a + b) * 0.5
	# link.gdshader's rule: toward the eye
	var to_cam := _camera.global_position - mid
	var across := (b - a).cross(to_cam)
	if across.length_squared() < 1e-8:
		return [a, b]
	var off := across.normalized() * shift * _m_per_px_at(mid)
	return [a + off, b + off]


## A star under the pointer (the nearest along the ray), else the link
## NEAREST the pointer on the screen among those within reach: the ribbons
## are drawn without depth, so which one is "in front" means nothing to the
## eye, and two links of a dense galaxy can cross or run side by side.
func _pick(pos: Vector2) -> Dictionary:
	var ray := _ray(pos)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var spheres: Array = []
	# A real surface wins before any expanded click area. Small stars still
	# receive ledger_star_pick_min_px assistance when the ray hits no surface.
	var least_px := _repo.bal("ledger_star_pick_min_px") * _window_scale()
	for id: String in _order:
		spheres.append({"id": id, "pos": _drawn[id], "draw_radius": _draw_r(id),
			"radius": maxf(_draw_r(id), least_px * _m_per_px_at(_drawn[id]))})
	var hit := LedgerPick.pick(o, d, spheres)
	if not hit.is_empty():
		return hit
	var best := INF
	var least := _repo.bal("ledger_pick_min_px") * _window_scale()
	for seg: Dictionary in _segs:
		var ends := seg_ends(seg)
		var q := LedgerPick.ray_segment(o, d, ends[0], ends[1])
		# how far off the link the pointer is, in SubViewport px at the link
		var px := q.x / maxf(_m_per_px_at(o + d * q.y), 1e-9)
		if px > maxf(float(seg["width_px"]) * 0.5, least):
			continue
		if px < best:
			best = px
			hit = {"kind": "thread", "id": String(seg["id"])}
	return hit


func _gui_input(event: InputEvent) -> void:
	if _repo == null:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if _button != 0:
			_on_drag(event as InputEventMouseMotion)
		else:
			_on_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMagnifyGesture:
		_framed = false
		_orbit.zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		_apply_camera()
		accept_event()
	elif event is InputEventPanGesture:
		_framed = false
		_orbit.pan(-(event as InputEventPanGesture).delta * _repo.bal("ledger_pan_gesture_px"), _pan_m_per_px())
		_apply_camera()
		accept_event()


func _pan_m_per_px() -> float:
	return _orbit.metres_per_px(_camera.fov, size.y)


## The hovered star's id, or "".
func hovered() -> String:
	return _hovered


## The pointer left the view: nothing is hovered — its tooltip, its gauges
## and its name go with it.
func _on_exit() -> void:
	if _hovered == "":
		return
	_hovered = ""
	tooltip_text = ""
	if _repo != null:
		_update_hud()


## Hover names a star (it draws nothing: only a clicked object is ringed).
func _on_hover(pos: Vector2) -> void:
	var hit := _pick(pos)
	var id := String(hit["id"]) if String(hit.get("kind", "")) == "sphere" else ""
	if id == _hovered:
		return
	_hovered = id
	tooltip_text = String(_nodes[id]["label"]) if id != "" else ""
	_update_hud()


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


func _end_gesture() -> void:
	_button = 0
	_drag_id = ""
	_moved = false


func _on_drag(mm: InputEventMouseMotion) -> void:
	if not _moved and mm.position.distance_to(_press_at) < CLICK_SLOP:
		return
	_moved = true
	# any drag drops the framing: a pan or turn moves the camera, and a star
	# held under the pointer must not have the camera re-frame beneath it
	_framed = false
	if _button == MOUSE_BUTTON_RIGHT:
		_orbit.turn(mm.relative.x, mm.relative.y, _repo.bal("ledger_turn_deg_per_px"))
	elif _drag_id != "":
		_drag_to(_drag_id, mm.position)
	else:
		_orbit.pan(mm.relative, _pan_m_per_px())
	_apply_camera()
	accept_event()


## A dragged star slides in the plane through it facing the camera and is PINNED there for this viewing; the rest
## settle round it.
func _drag_to(id: String, pos: Vector2) -> void:
	if not _drawn.has(id):
		_end_gesture()
		return
	var ray := _ray(pos)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var n := -_camera.global_transform.basis.z
	var denom := d.dot(n)
	if absf(denom) < 1e-5:
		return
	var t := ((_drawn[id] as Vector3) - o).dot(n) / denom
	if t <= 0.0:
		return
	var at := o + d * t
	_lay.pin(id, at)
	_drawn[id] = _lay.pos[id]
	_place_stars()
	_relay_links()
	_update_hud()
