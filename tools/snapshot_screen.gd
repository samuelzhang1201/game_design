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
## --layer manors|heights|military|measurement lights that bottom-bar tab once
## the root is up, so a shot can show a thematic view and its left column.
var _layer := ""
## --speaker <portrait_id> opens the council on the conversation screen and
## stands that courtier up in it, which is the only way a shot can show the
## dossier and the full-body art — the screen otherwise boots to the map.
var _speaker := ""
## --event <event_id> fires that event by id and opens the conversation
## screen on it, which is the only way to look at a chapter beat — its
## banner, its illustration band and its choices — as the game draws it.
var _event := ""
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
## --pal key=#hex overrides one terrain_palette.csv colour for the shot (repeatable)
var _pal: Dictionary = {}
## --zoom3d M (with --screen root) frames the capital M metres away.
var _zoom3d := -1.0
## --at3d x,y (with --zoom3d) frames that pack pixel instead of the capital.
var _at3d := Vector2(-1, -1)
## --ruler fx1,fy1,fx2,fy2 (with --screen root) lights the MEASUREMENT tab
## and clicks the showing map at those shares of its size, so the shot shows
## a fixed ruler; --ruler-open leaves it stretching to the second point.
var _ruler := PackedFloat32Array()
var _ruler_open := false
## --march3d fx,fy (with --screen root) plays the player's march as the owner
## specified it (2026-09-24, 2026-09-27): a left click on the first regiment's
## piece opens its orders, MARCH is chosen, the pointer is put at that share of
## the 3D map (the aim's ruler follows it); with --march-confirm a left click
## there opens COMMIT / CANCEL, and --march-commit then commits it. --shot-frame N waits
## N frames before the shot (default 40), so a run with --speed can show the
## piece walking; without --speed the clock stays stopped and nothing moves.
var _march3d := Vector2(-1, -1)
var _march_confirm := false
## --march-commit (with --march-confirm): choose COMMIT on the confirm menu.
var _march_commit := false
## --dev: the 3D map in DEV MODE (every realm's regiments) for this shot only —
## the view's switch, never GameRoot's, which would write the player's settings.
var _dev := false
## --look3d x,y,M,F (with --screen root) frames pack px (x,y) M metres away at
## frame F — after an order, to follow its courier from the capital.
var _look3d := PackedFloat32Array()
## --click-courier F (with --screen root) left-clicks, as a player would, the
## first courier drawn inside the 3D map at frame F and prints the card the
## left column then shows.
var _click_courier := -1
var _shot_frame := 40


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
		elif args[i] == "--event":
			_event = args[i + 1]
		elif args[i] == "--tab":
			_tab = int(args[i + 1])
		elif args[i] == "--manor":
			_manor = args[i + 1]
		elif args[i] == "--build":
			_build = args[i + 1]
		elif args[i] == "--click3d":
			var parts := args[i + 1].split(",")
			_click3d = Vector2(float(parts[0]), float(parts[1]))
		elif args[i] == "--pal":
			var pv := args[i + 1].split("=")
			if pv.size() == 2:
				_pal[pv[0]] = pv[1]
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
		elif args[i] == "--march3d":
			var mparts := args[i + 1].split(",")
			_march3d = Vector2(float(mparts[0]), float(mparts[1]))
		elif args[i] == "--shot-frame":
			_shot_frame = int(args[i + 1])
		elif args[i] == "--look3d":
			for part in args[i + 1].split(","):
				_look3d.append(float(part))
		elif args[i] == "--click-courier":
			_click_courier = int(args[i + 1])
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
	_march_confirm = args.has("--march-confirm")
	_march_commit = args.has("--march-commit")
	_dev = args.has("--dev")
	if not SCENES.has(_screen):
		push_error("unknown screen %s; choose from %s" % [_screen, SCENES.keys()])
		Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
		get_tree().quit(2)
		return
	Game.start_campaign(_seed)
	# the news bar's lines, so a run shows what the player was told
	Game.news_published.connect(func(t: String) -> void: print("news: " + t))
	for key: String in _bal:
		Game.data.balance[key] = _bal[key]
	for key: String in _pal:
		Game.data.terrain_palette[key] = _pal[key]
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
	if _event != "" and screen.has_method("enter_council"):
		screen.call("enter_council")
		var sys := EventSystem.new(Game.data)
		Game.state.pending_event = {}
		var ev := sys._fire(_event, Game.state)
		if ev.is_empty():
			push_error("snapshot_screen: no such event, or every choice gated off: " + _event)
		elif screen.has_method("start"):
			screen.call("start", [{"kind": "event", "portrait_id": "round_table",
				"speaker": "The Council", "event": ev.duplicate(true)}], TickReport.new())
	elif _speaker != "" and screen.has_method("enter_council"):
		screen.call("enter_council")
		if screen.has_method("start"):
			screen.call("start", [_minister_beat(_speaker)], null)
		if _tab >= 0 and screen.has_method("select_tab"):
			screen.call("select_tab", _tab)


## A left click at `local` (design px of `c`), pushed into c's viewport as
## a player's press and release would arrive.
func _real_click(c: Control, local: Vector2) -> void:
	_real_move(c, local)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = c.get_global_transform_with_canvas() * local
		e.global_position = e.position
		c.get_viewport().push_input(e, true)


func _real_move(c: Control, local: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = c.get_global_transform_with_canvas() * local
	m.global_position = m.position
	c.get_viewport().push_input(m, true)


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
				_root.current_screen.map3d_view().look_at_pack(
					MapTerrain.cell_center(Game.data, Game.data.cells[cell]))
				_root.current_screen.map3d_view().select_object({"kind": "manor", "cell": cell})
				_root.current_screen.detail_panel().show_manor(cell)
		# A march is given on a PAUSED clock (owner 2026-09-27): with --march3d
		# the clock starts only once the order is in, as the player's play would.
		if _speed >= 0 and _march3d.x < 0.0:
			Game.set_clock_speed(_speed)
	if _root != null and _frames == 24 and _speed >= 0 and _march3d.x >= 0.0:
		Game.set_clock_speed(_speed)
	if _root != null and _look3d.size() == 4 and _frames == int(_look3d[3]) \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		_root.current_screen.map3d_view().look_at_pack(Vector2(_look3d[0], _look3d[1]), _look3d[2])
	if _root != null and _frames == _click_courier \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		var cv: Map3DView = _root.current_screen.map3d_view()
		var hit := Vector2(-1, -1)
		for id in cv.courier_rects():
			var cc := (cv.courier_rects()[id]["rect"] as Rect2).get_center()
			if Rect2(Vector2.ZERO, cv.size).has_point(cc):
				hit = cc
				break
		if hit.x < 0.0:
			push_error("click-courier: no courier on screen (%d couriers)" % Game.state.couriers.size())
		else:
			_real_click(cv, hit)
			var title := _root.current_screen.detail_panel().find_child("Title", true, false) as Label
			print("click-courier: at=%s picked=%s card=%s" % [hit, cv.pick_at(hit),
				title.text if title != null else "?"])
	if _root != null and _frames == 8 and _zoom3d > 0.0 \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		var v3: Map3DView = _root.current_screen.map3d_view()
		if _dev:
			v3.set_dev_mode(true)
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
		var v: Control = _root.current_screen.map3d_view()
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
	if _root != null and _march3d.x >= 0.0 and _frames in [14, 16, 18, 20, 22] \
			and _root.current_screen.has_method("map3d_view") \
			and _root.current_screen.map3d_view() != null:
		# REAL input all the way (2026-09-24: a shot that called the view's and
		# the menu's functions directly hid that a chosen order was thrown
		# away): mouse events pushed into the viewport the view lives in, so
		# they route through the GUI exactly as a player's clicks do, and the
		# menu row chosen through PopupMenu.activate_item, its real path.
		var mv: Map3DView = _root.current_screen.map3d_view()
		var menu := _root.current_screen.get_node("%ArmyOrders") as ArmyOrderMenu
		var at := mv.size * _march3d
		if _frames == 14:
			# the first piece whose box is actually inside the view (a piece in
			# front of the camera but off the panel has a box too)
			var target := Vector2(-1, -1)
			for code: String in mv.unit_rects():
				var c := (mv.unit_rects()[code] as Rect2).get_center()
				if Rect2(Vector2.ZERO, mv.size).has_point(c):
					target = c
					break
			if target.x < 0.0:
				push_error("march3d: no piece on screen")
			else:
				_real_click(mv, target)
				print("march3d: menu open=%s selected=%s" % [menu.visible, mv.selected_army()])
		elif _frames == 16:
			# The first row, MARCH…, chosen in the order PopupMenu.activate_item
			# (not exposed to scripts) does it: the menu HIDES first, and only
			# then emits id_pressed. That order is what threw every chosen
			# order away until 2026-09-24, so the shot must keep it.
			menu.hide()
			menu.id_pressed.emit(0)
			print("march3d: aiming=%s" % menu.aiming())
		elif _frames == 18:
			_real_move(mv, at)
		elif _frames == 20 and _march_confirm:
			# the destination click only ASKS: COMMIT / CANCEL (owner 2026-09-27)
			_real_click(mv, at)
			print("march3d: confirm open=%s pending=%s" % [menu.visible, menu.pending()])
		elif _frames == 22 and _march_confirm and _march_commit:
			var code := menu.aiming()
			menu.hide()
			menu.id_pressed.emit(ArmyOrderMenu.COMMIT)
			print("march3d: order=%s days=%d clock=%d aiming_after=%s couriers=%s" % [
				ArmySystem.order_of(Game.data, Game.state, code),
				ArmySystem.days_out(Game.data, Game.state, code), Game.clock_speed, menu.aiming(),
				Game.state.couriers])
	if _frames == _shot_frame:
		if Game.state != null:
			print("state at shot: day=%d clock=%d pending_event=%s couriers=%d" % [Game.state.absolute_day(),
				Game.clock_speed, not Game.state.pending_event.is_empty(), Game.state.couriers.size()])
		var img := (get_viewport() if _viewport == null else _viewport).get_texture().get_image()
		var abs_path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var err := img.save_png(abs_path)
		var how := ("%dx%d window" % [_res.x, _res.y]) if _res != Vector2i.ZERO else ("x%.1f" % _scale)
		print("snapshot %s -> %s (%s, %s, filter %d)" % [
			"ok" if err == OK else "FAILED %d" % err, _out, _screen, how,
			int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 0))])
		Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
		get_tree().quit()
