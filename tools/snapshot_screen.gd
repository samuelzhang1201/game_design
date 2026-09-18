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
	"day_run": "res://scenes/day_run.tscn",
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
		elif args[i] == "--speed":
			_speed = int(args[i + 1])
		elif args[i] == "--resolution":
			var wh := args[i + 1].split("x")
			if wh.size() == 2:
				_res = Vector2i(int(wh[0]), int(wh[1]))
		i += 1
	if not SCENES.has(_screen):
		push_error("unknown screen %s; choose from %s" % [_screen, SCENES.keys()])
		get_tree().quit(2)
		return
	Game.start_campaign(_seed)
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
