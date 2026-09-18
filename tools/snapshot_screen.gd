extends Node
## Render one gameplay screen to a PNG — the court by default — drawn exactly
## as the game draws it, so a UI change can be looked at without playing to it.
## The sibling of tools/snapshot_map.gd, which frames the map alone.
##
## Runs as a scene so the autoloads (Game) exist; needs the real renderer, so
## a window opens for a moment:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn \
##     -- --out /tmp/court.png [--screen court] [--seed 42]

## The game's design viewport. --scale reproduces what a window that many
## times larger actually shows: project.godot stretches with canvas_items, so
## the game draws at the WINDOW resolution with the canvas scaled — text and
## every drawn line come out at full resolution and only bitmaps are
## resampled. Scaling the screen itself, rather than blowing the finished PNG
## up afterwards, is the difference between a shot that shows the real
## sharpness and one that makes everything look equally soft.
const WIDTH := 1280
const HEIGHT := 720

const SCENES := {
	"court": "res://scenes/court.tscn",
	"conversation": "res://scenes/conversation.tscn",
	"main_menu": "res://scenes/main_menu.tscn",
	# The whole game: GameRoot owns the top bar, the bottom tab strip and the
	# ticker, so anything outside a screen's own frame only shows here.
	"root": "res://scenes/game_root.tscn",
}

var _out := "user://screen_snapshot.png"
var _screen := "court"
var _seed := 42
var _scale := 2.0
## --resolution WxH renders through the REAL window instead of a SubViewport,
## so the project's own window/stretch settings apply — content scale, font
## oversampling, the canvas texture filter, all of it. A SubViewport plus a
## scaled Control looks similar and is NOT the same path: it cannot show what
## a fractional window size does to the game (owner 2026-09-12).
var _res := Vector2i.ZERO
var _viewport: SubViewport
var _frames := 0
var _root: GameRoot = null
## --layer economy|heights|military|provinces lights that bottom-bar tab once
## the root is up, so a shot can show a thematic view and its left column.
var _layer := ""
## --speaker <portrait_id> opens the council on the conversation screen and
## stands that courtier up in it, which is the only way a shot can show the
## dossier and the full-body art — the screen otherwise boots to the map.
var _speaker := ""
## --tab 0|1|2 opens the dossier's BIO / SKILLS / TIES page over the talk,
## which is where the full-body art is shown at size.
var _tab := -1
## --manor <code|label|cell id> opens that manor's card in the left column
## (its fields and order buttons) and centres the map on it.
var _manor := ""
## --build <building> begins that building on the shot's manor (with
## --manor), so the slot row shows a work; --speed N lights the clock.
var _build := ""
var _speed := -1
## --click3d fx,fy (with --screen root: the court opens on the 3D map when it
## is built) clicks the 3D map
## at that share of its size, so a shot shows the pick: the card in the
## left column and the province's gold outline.
var _click3d := Vector2(-1, -1)
## --hover3d fx,fy (with --screen root) hovers the 3D map there: the country
## card in the left column, the kingdom's wider outline, a town's name.
var _hover3d := Vector2(-1, -1)
## --bal key=value overrides one balance.csv number for the shot (repeatable)
## — for bracketing a look value before it is written to the table.
var _bal: Dictionary = {}
## --zoom3d M (with --screen root) frames the capital M metres away.
var _zoom3d := -1.0
## --at3d x,y (with --zoom3d) frames that pack pixel instead of the capital.
var _at3d := Vector2(-1, -1)
## --ruler fx1,fy1,fx2,fy2 (with --screen root) lights the MEASUREMENT tab
## and clicks the showing map at those shares of its size, so the shot shows
## a fixed ruler; --ruler-open leaves it stretching to the second point.
## --map2d keeps the court on the 2D map (balance map3d_default off).
var _ruler := PackedFloat32Array()
var _ruler_open := false
var _map2d := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size() - 1:
		if args[i] == "--out":
			_out = args[i + 1]
		elif args[i] == "--screen":
			_screen = args[i + 1]
		elif args[i] == "--seed":
			_seed = int(args[i + 1])
		elif args[i] == "--scale":
			_scale = float(args[i + 1])
		elif args[i] == "--layer":
			_layer = args[i + 1]
		elif args[i] == "--speaker":
			_speaker = args[i + 1]
		elif args[i] == "--tab":
			_tab = int(args[i + 1])
		elif args[i] == "--manor":
			_manor = args[i + 1]
		elif args[i] == "--build":
			_build = args[i + 1]
		elif args[i] == "--click3d":
			var parts := args[i + 1].split(",")
			_click3d = Vector2(float(parts[0]), float(parts[1]))
		elif args[i] == "--bal":
			var kv := args[i + 1].split("=")
			if kv.size() == 2:
				_bal[kv[0]] = float(kv[1])
		elif args[i] == "--hover3d":
			var hparts := args[i + 1].split(",")
			_hover3d = Vector2(float(hparts[0]), float(hparts[1]))
		elif args[i] == "--at3d":
			var aparts := args[i + 1].split(",")
			_at3d = Vector2(float(aparts[0]), float(aparts[1]))
		elif args[i] == "--zoom3d":
			_zoom3d = float(args[i + 1])
		elif args[i] == "--ruler":
			for part in args[i + 1].split(","):
				_ruler.append(float(part))
		elif args[i] == "--speed":
			_speed = int(args[i + 1])
		elif args[i] == "--resolution":
			var wh := args[i + 1].split("x")
			if wh.size() == 2:
				_res = Vector2i(int(wh[0]), int(wh[1]))
		i += 1
	_ruler_open = args.has("--ruler-open")
	_map2d = args.has("--map2d")
	if not SCENES.has(_screen):
		push_error("unknown screen %s; choose from %s" % [_screen, SCENES.keys()])
		get_tree().quit(2)
		return
	Game.start_campaign(_seed)
	for key: String in _bal:
		Game.data.balance[key] = _bal[key]
	if _map2d:
		Game.data.balance["map3d_default"] = 0.0
	if _res != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_res)
		get_window().size = _res
	else:
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(int(WIDTH * _scale), int(HEIGHT * _scale))
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_viewport)
	var packed: PackedScene = load(String(SCENES[_screen]))
	var screen: Control = packed.instantiate()
	# GameRoot applies the theme itself; for a bare screen we stand in for it,
	# or every Button would render in Godot's default grey and the shot would lie.
	if _screen != "root":
		screen.theme = UiPalette.build_theme()
	# The screen lays out inside a holder that IS the design viewport, and the
	# holder is what scales — anchoring the screen straight to the enlarged
	# SubViewport would lay it out in window pixels and stretch nothing.
	if _res != Vector2i.ZERO:
		# Straight into the window: the project's stretch settings do the rest,
		# exactly as they do for a player.
		add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var holder := Control.new()
		holder.size = Vector2(WIDTH, HEIGHT)
		holder.scale = Vector2(_scale, _scale)
		_viewport.add_child(holder)
		holder.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _screen == "root":
		_root = screen as GameRoot
	elif screen.has_method("enter_court"):
		screen.call("enter_court", null)
	if _speaker != "" and screen.has_method("enter_council"):
		screen.call("enter_council")
		if screen.has_method("start"):
			screen.call("start", [_minister_beat(_speaker)], null)
		if _tab >= 0 and screen.has_method("select_tab"):
			screen.call("select_tab", _tab)


## One standing minister beat, enough for _advance to raise the dossier.
func _minister_beat(id: String) -> Dictionary:
	var who := id
	if Game.state != null and Game.state.characters.has(id):
		who = Game.state.characters[id].display_name
	return {
		"kind": "minister", "portrait_id": id, "speaker": who,
		"text": "Your Grace, the accounts are before you.", "suggestions": [],
	}


func _process(_delta: float) -> void:
	_frames += 1
	# GameRoot boots into the menu; step it into the court so the shot shows
	# the gameplay chrome (top bar, bottom tabs, ticker) around a real screen.
	if _root != null and _frames == 4:
		_root._switch_to(GameRoot.State.COURT)
		_root.current_screen.enter_court(null)
		if _layer != "":
			_root._on_bottom_tab(_layer.to_upper())
		if _manor != "" and _root.current_screen.has_method("detail_panel"):
			var cell := MapManors.find(Game.data, _manor)
			if cell < 0:
				push_error("no such manor: " + _manor)
			else:
				if _build != "":
					Game.state.metrics["treasury"] += 1000.0
					Game.try_execute(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": _build}))
					Game.state.day = mini(Game.state.day + 5, Calendar.DAYS_PER_TICK)
				_root.current_screen.world_map().highlight_manor(cell)
				_root.current_screen.detail_panel().show_manor(cell)
		if _speed >= 0:
			Game.set_clock_speed(_speed)
	if _root != null and _frames == 8 and _zoom3d > 0.0 \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		var v3: Map3DView = _root.current_screen.map3d_view()
		if _at3d.x >= 0.0:
			v3.look_at_pack(_at3d, _zoom3d)
		else:
			v3.look_at_home(_zoom3d)
	if _root != null and _frames == 10 and _click3d.x >= 0.0 \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		var v: Map3DView = _root.current_screen.map3d_view()
		v.select_at(v.size * _click3d)
		print("click3d: province=%s burg=%s" % [v.selected_province(), v.selected_burg()])
	if _root != null and _frames == 12 and _hover3d.x >= 0.0 \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		var hv: Map3DView = _root.current_screen.map3d_view()
		var at := hv.size * _hover3d
		hv.hover_pick(hv.pick_at(at), at)
		print("hover3d: kingdom=%s name=%s" % [hv.hovered_kingdom(), hv.hover_tooltip()])
	if _root != null and _frames == 12 and _ruler.size() == 4:
		_root.set_ruler_view(true)
		var v: Control = _root.current_screen.world_map()
		if _root.map3d_view() and _root.current_screen.map3d_view() != null:
			v = _root.current_screen.map3d_view()
		var a := v.size * Vector2(_ruler[0], _ruler[1])
		var b := v.size * Vector2(_ruler[2], _ruler[3])
		for at in [a, b]:
			var hover := InputEventMouseMotion.new()
			hover.position = at
			v._gui_input(hover)
			if at == b and _ruler_open:
				break
			for down in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = down
				e.position = at
				v._gui_input(e)
	if _frames == 40:
		var img := (get_viewport() if _viewport == null else _viewport).get_texture().get_image()
		var abs_path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var err := img.save_png(abs_path)
		var how := ("%dx%d window" % [_res.x, _res.y]) if _res != Vector2i.ZERO else ("x%.1f" % _scale)
		print("snapshot %s -> %s (%s, %s, filter %d)" % [
			"ok" if err == OK else "FAILED %d" % err, _out, _screen, how,
			int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 0))])
		get_tree().quit()
