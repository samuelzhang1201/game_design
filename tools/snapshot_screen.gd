extends Node
## Render one gameplay screen to a PNG — the court by default — drawn exactly
## as the game draws it, so a UI change can be looked at without playing to it.
## The sibling of tools/snapshot_map.gd, which frames the map alone.
##
## Runs as a scene so the autoloads (Game) exist; needs the real renderer, so
## a window opens for a moment:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn \
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
	"court": "res://scenes/screens/court.tscn",
	"conversation": "res://scenes/screens/conversation.tscn",
	"main_menu": "res://scenes/screens/main_menu.tscn",
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
## --layer manors|heights lights that bottom-bar tab once
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
## --town CODE selects that settlement as a click on the map does and opens
## its card in the left column; --hover-icon N then rests the pointer, by
## real mouse-motion events, on the Nth control of that card that carries a
## tooltip (0 the first), so the shot shows the tooltip as the player sees it
## (owner 2026-10-01: a town card's icon tooltip read dark on dark).
var _town := ""
var _hover_icon := -1
var _hover_target: Control
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
## --set TARGET:PROP=VALUE overrides one LOOK value for the shot (repeatable),
## for bracketing an inspector value before it is set in the editor. TARGET is
## a res:// resource (set before anything instances it: a .tres material or
## the world's Environment) or the name of a node in the 3D world (set as the
## camera is framed, so it needs --zoom3d); VALUE is parsed by str_to_var
## ("0.5", "Color(0.2, 0.3, 0.4, 1)"). Material uniforms are
## shader_parameter/NAME.
var _sets: Array = []
## The resources --set changed, held so the cache keeps the changed copy
## (a resource nothing holds is freed, and the next load reads the file).
var _held: Array[Resource] = []
## --zoom3d M (with --screen root) frames the capital M metres away.
var _zoom3d := -1.0
## --at3d x,y (with --zoom3d) frames that pack pixel instead of the capital.
var _at3d := Vector2(-1, -1)
## --day-share F holds the clock at F of the day (0..1), so a shot shows the
## sun where it stands then: 0.25 noon in the south, 0.75 the north's dusk.
var _day_share := -1.0
## --weather KIND (with --screen root) lays that weather over every province on
## the 3D map (spec 2026-09-29-weather-visuals) — the look only, the engine's
## weather is untouched.
var _weather := ""
## --march3d fx,fy (with --screen root) plays the player's march as the owner
## specified it (2026-09-24, 2026-09-27): a left click on the first regiment's
## piece opens its orders, MARCH is chosen, the pointer is put at that share of
## the 3D map (the aim's ruler follows it); with --march-confirm a left click
## there opens COMMIT / CANCEL, and --march-commit then commits it. --shot-frame N waits
## N frames before the shot (default 40), so a run with --speed can show the
## piece walking; without --speed the clock stays stopped and nothing moves.
var _march3d := Vector2(-1, -1)
## --march-at F: the frame the --march3d clicks begin (default 14) — later
## when the world is still loading its pieces.
var _march_at := 14
var _march_confirm := false
## --march-commit (with --march-confirm): choose COMMIT on the confirm menu.
var _march_commit := false
## --dev: the 3D map in DEV MODE (every realm's regiments) for this shot only —
## the view's switch, never GameRoot's, which would write the player's settings.
var _dev := false
## --pause-menu (with --screen root): opens the pause menu at frame 20, as the
## MENU button does, to set it beside the title screen's (owner 2026-09-30:
## the two are one menu).
var _pause_menu := false
## --title (with --screen root): stays on GameRoot's own title screen, the menu
## as the player meets it (GameRoot hands it its settings rows; --screen
## main_menu shows the bare scene without them).
var _title := false
## --title-click ROW@F (with --title): at frame F a real left click on the title
## menu's row ROW (StartGame, LoadGame, ...) — Take the Throne or Continue the
## Chronicle, so --also can follow the sweep and the landing.
var _title_click := ""
var _title_click_frame := -1
## --council-click N@F (with --screen root): at frame F a real left click on the
## Nth councillor's miniature by the council seal (0 the nearest the seal), so
## the shot shows the audience it opens (owner 2026-10-02); --council-hover N@F
## rests the pointer on it instead, for its tooltip.
var _council_click := -1
## --click-reply N@F (with --screen root): at frame F a real left click on the
## conversation stage's Nth option (0 the first) — the opening narration's
## "I am ready", an event's choice.
var _reply_click := -1
var _reply_click_frame := -1
var _council_click_frame := -1
var _council_hover := false
## --look3d x,y,M,F (with --screen root) frames pack px (x,y) M metres away at
## frame F — after an order, to follow its courier from the capital.
var _look3d := PackedFloat32Array()
## --click-courier F (with --screen root) left-clicks, as a player would, the
## first courier drawn inside the 3D map at frame F and prints the card the
## left column then shows.
var _click_courier := -1
## --trace-couriers (with --screen root): every frame while a courier rides or
## the clock runs, print the day, the day's share, each courier's engine spot
## and where he is DRAWN, and his regiment's drawn spot — the courier's pace
## and the column's start read off the running window.
var _trace_couriers := false
var _shot_frame := 40
## The Missive board and spies (2026-09-28), all with --screen root:
## --quiet drops the chapter's scheduled beats, rolls no random event and runs the
## reign's opening tick (as a new game does), so a
## run can play whole months without the council taking the screen.
var _quiet := false
## --spy3d x,y[;x,y…] sends a spy to each PACK px as the player does: the view
## looks at the point, a real right click at the view's centre opens
## SpyOrderMenu, and its row is chosen (hide, then id_pressed — PopupMenu's
## own order). One point every 4 frames from frame 26. --spy-menu-only stops
## at the first open menu, for a shot of it.
var _spy3d: Array = []
var _spy_menu_only := false
## --play-days N (with --speed) plays the clock after the orders until N days
## have passed, pressing Seal (a real click) on each spy report and play again
## after it, as the player would; then the clock stops.
var _play_days := -1
## --missives COL, once the play is done: a real click on the MISSIVE tab,
## then on the first letter of column COL; --show-on-map then presses the
## desk's Show on map.
var _missives := ""
var _show_on_map := false
## --ledger LENS (with --screen root): the LEDGER through real clicks — its
## tab, then the lens chip (a ledger_lenses.csv id: all, economy, war, court,
## intelligence). --ledger-open CODE then opens that province and
## --ledger-select ID selects that star (its web framed) — both by emitting
## the view's drill_requested, what a double click on the star emits, not by
## a real double click. --ledger-search TEXT clicks the search box and types
## TEXT into it key by key (its list of matches shown); --ledger-search-pick
## then presses Enter. The moment is `ledger`, once the chart has settled.
var _ledger := ""
var _ledger_search := ""
var _ledger_search_pick := false
var _ledger_open := ""
var _ledger_select := ""
## --war-room (with --screen root): the WAR ROOM through real input — its tab,
## then --war-sheet N lays that sheet (WarRoomView.swap_to; the later steps wait
## until it is laid and the roll is over), --war-zoom M leans the camera to M
## metres (on --war-piece's place when given, or --war-focus CODE's, which
## centres on that piece without clicking it), --war-piece CODE
## clicks that regiment's piece (a chalk ring, its card) or, with
## --war-focus-px x,y leans in on that pack point instead of a piece;
## --war-hover fx,fy rests the pointer at that share of the view (a real
## motion) until the hover slip is up; --war-drag fx,fy (a share of the view), RAKES it there: a real left press
## on the piece, eight pushed motion events with the left button held, a real
## release (the arrow and its COMMIT / CANCEL menu show; --war-commit then
## chooses COMMIT the way PopupMenu.activate_item does, so the order's pennant
## is planted). --war-folio
## DRILL|explode opens the folio's drill or presses Take apart — it says so
## and skips while the folio, its drill tabs or its Take apart button are not
## built; an explode waits out its flight (war_explode_s) before the moment.
## The moment is `war`, taken at frame +90 unless --shot-on says otherwise.
## v2 (spec 2026-10-02-war-room-v2 §1): --war-turn DEG turns the room by a
## REAL right drag (after any --war-zoom); --war-board clicks the easel's
## board (the camera flies to it); --war-board-click fx,fy (implies
## --war-board) then clicks that share of the view — a note there opens the
## full Missive board over the room. v2 B: --war-cell ID (a sheet id such as
## D4) clicks that cell of the index chart for real — the war marker is
## tossed, then the sheet is laid — and the later steps wait for both.
## v2 C (spec §3): a --war-commit now PENCILS a draft. --war-deploy MODE then
## clicks the room's resolutions scroll for real: `review` shoots it unrolled,
## `seal` clicks Seal and send and shoots the crown's arms pressing into the
## wax, `sent` waits for the seal to be sent (the news, the riding pennants).
## --war-leave TAB clicks that bottom tab with drafts standing and shoots the
## leave prompt.
var _war_deploy := ""
var _war_leave := ""
var _war_room := false
## --war-room-at F (with --war-room): the frame the WAR ROOM tab is clicked
## (default 30), so a run with --speed can open the room mid-march. Every run
## prints `war sync`: each regiment's spot by the engine, where the 3D map
## DRAWS it and where the room's piece stands, all in pack px (owner
## 2026-10-02: the room's pieces stand where the map shows them).
var _war_room_at := 30
var _war_focus := ""
var _war_commit := false
var _war_sheet := -1
var _war_piece := ""
var _war_folio := ""
var _war_drag := Vector2(-1, -1)
var _war_focus_px := Vector2(-1, -1)   # --war-focus-px x,y: lean in on a pack point, not a piece
var _war_hover := Vector2(-1, -1)   # --war-hover fx,fy: rest the pointer there for the slip
var _war_zoom := -1.0
var _war_turn := 0.0
var _war_cell := ""
var _war_board := false
var _war_board_click := Vector2(-1, -1)
var _war_phase := 0
var _war_at := 0
## --shot-on report|flight|board|card|spymenu takes the shot --shot-delay N
## frames (default 6) after that moment rather than at --shot-frame.
var _shot_on := ""
var _shot_delay := 6
var _shot_at := -1
var _play_from := -1
var _play_done := -1
## --also F:path takes an extra shot at frame F (repeatable), so one run's
## world load serves several pictures.
var _also: Dictionary = {}


func _ready() -> void:
	FrameCap.forced = 0  # a shot waits frames; the player's cap would only slow it
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
		elif args[i] == "--town":
			_town = args[i + 1]
		elif args[i] == "--hover-icon":
			_hover_icon = int(args[i + 1])
		elif args[i] == "--build":
			_build = args[i + 1]
		elif args[i] == "--click3d":
			var parts := args[i + 1].split(",")
			_click3d = Vector2(float(parts[0]), float(parts[1]))
		elif args[i] == "--pal":
			var pv := args[i + 1].split("=")
			if pv.size() == 2:
				_pal[pv[0]] = pv[1]
		elif args[i] == "--set":
			var sv := args[i + 1]
			var colon := sv.rfind(":", sv.find("="))
			var eq := sv.find("=")
			if colon > 0 and eq > colon:
				_sets.append([sv.substr(0, colon), sv.substr(colon + 1, eq - colon - 1),
					str_to_var(sv.substr(eq + 1))])
			else:
				push_error("--set wants TARGET:PROP=VALUE, got %s" % sv)
		elif args[i] == "--bal":
			var kv := args[i + 1].split("=")
			if kv.size() == 2:
				_bal[kv[0]] = float(kv[1])
		elif args[i] == "--hover3d":
			var hparts := args[i + 1].split(",")
			_hover3d = Vector2(float(hparts[0]), float(hparts[1]))
		elif args[i] == "--weather":
			_weather = args[i + 1]
		elif args[i] == "--day-share":
			_day_share = float(args[i + 1])
		elif args[i] == "--at3d":
			var aparts := args[i + 1].split(",")
			_at3d = Vector2(float(aparts[0]), float(aparts[1]))
		elif args[i] == "--march3d":
			var mparts := args[i + 1].split(",")
			_march3d = Vector2(float(mparts[0]), float(mparts[1]))
		elif args[i] == "--march-at":
			_march_at = int(args[i + 1])
		elif args[i] == "--shot-frame":
			_shot_frame = int(args[i + 1])
		elif args[i] == "--look3d":
			for part in args[i + 1].split(","):
				_look3d.append(float(part))
		elif args[i] == "--click-courier":
			_click_courier = int(args[i + 1])
		elif args[i] == "--zoom3d":
			_zoom3d = float(args[i + 1])
		elif args[i] == "--speed":
			_speed = int(args[i + 1])
		elif args[i] == "--spy3d":
			for pt in args[i + 1].split(";"):
				var sp := pt.split(",")
				_spy3d.append(Vector2(float(sp[0]), float(sp[1])))
		elif args[i] == "--play-days":
			_play_days = int(args[i + 1])
		elif args[i] == "--missives":
			_missives = args[i + 1]
		elif args[i] == "--ledger":
			_ledger = args[i + 1]
		elif args[i] == "--ledger-open":
			_ledger_open = args[i + 1]
		elif args[i] == "--ledger-search":
			_ledger_search = args[i + 1]
		elif args[i] == "--ledger-select":
			_ledger_select = args[i + 1]
		elif args[i] == "--war-room-at":
			_war_room_at = int(args[i + 1])
		elif args[i] == "--war-sheet":
			_war_sheet = int(args[i + 1])
		elif args[i] == "--war-piece":
			_war_piece = args[i + 1]
		elif args[i] == "--war-focus-px":
			var fparts := args[i + 1].split(",")
			_war_focus_px = Vector2(float(fparts[0]), float(fparts[1]))
		elif args[i] == "--war-focus":
			_war_focus = args[i + 1]
		elif args[i] == "--war-zoom":
			_war_zoom = float(args[i + 1])
		elif args[i] == "--war-deploy":
			_war_deploy = args[i + 1].to_lower()
		elif args[i] == "--war-leave":
			_war_leave = args[i + 1].to_upper()
		elif args[i] == "--war-cell":
			_war_cell = args[i + 1].to_upper()
		elif args[i] == "--war-turn":
			_war_turn = float(args[i + 1])
		elif args[i] == "--war-board-click":
			var bparts := args[i + 1].split(",")
			_war_board_click = Vector2(float(bparts[0]), float(bparts[1]))
		elif args[i] == "--war-folio":
			_war_folio = args[i + 1].to_lower()
		elif args[i] == "--war-drag":
			var dparts := args[i + 1].split(",")
			_war_drag = Vector2(float(dparts[0]), float(dparts[1]))
		elif args[i] == "--war-hover":
			var hparts := args[i + 1].split(",")
			_war_hover = Vector2(float(hparts[0]), float(hparts[1]))
		elif args[i] == "--shot-on":
			_shot_on = args[i + 1]
		elif args[i] == "--shot-delay":
			_shot_delay = int(args[i + 1])
		elif args[i] == "--click-reply":
			var rcf := args[i + 1].split("@")
			_reply_click = int(rcf[0])
			_reply_click_frame = int(rcf[1]) if rcf.size() > 1 else 20
		elif args[i] == "--council-click" or args[i] == "--council-hover":
			var cf := args[i + 1].split("@")
			_council_click = int(cf[0])
			_council_click_frame = int(cf[1]) if cf.size() > 1 else 20
			_council_hover = args[i] == "--council-hover"
		elif args[i] == "--title-click":
			var rf := args[i + 1].split("@")
			_title_click = rf[0]
			_title_click_frame = int(rf[1]) if rf.size() > 1 else 20
		elif args[i] == "--also":
			var fp := args[i + 1].split(":")
			_also[int(fp[0])] = fp[1]
		elif args[i] == "--resolution":
			var wh := args[i + 1].split("x")
			if wh.size() == 2:
				_res = Vector2i(int(wh[0]), int(wh[1]))
		i += 1
	_war_room = args.has("--war-room")
	_war_commit = args.has("--war-commit")
	_war_board = args.has("--war-board") or _war_board_click.x >= 0.0
	if _war_room and _shot_on == "":
		_shot_on = "war"
	if _war_drag.x >= 0.0 and _war_piece == "":
		push_warning("--war-drag needs --war-piece (the piece to rake); there is nothing to drag")
	_march_confirm = args.has("--march-confirm")
	_ledger_search_pick = args.has("--ledger-search-pick")
	_march_commit = args.has("--march-commit")
	_trace_couriers = args.has("--trace-couriers")
	_dev = args.has("--dev")
	_pause_menu = args.has("--pause-menu")
	_title = args.has("--title")
	_quiet = args.has("--quiet")
	# --still: the window takes no input at all, so a pointer resting over the
	# shot's window (the owner's own mouse) cannot hover a kingdom, show a
	# town's name or zoom the map; never with a flag that clicks or hovers.
	if args.has("--still"):
		get_tree().root.gui_disable_input = true
	_spy_menu_only = args.has("--spy-menu-only")
	_show_on_map = args.has("--show-on-map")
	if not SCENES.has(_screen):
		push_error("unknown screen %s; choose from %s" % [_screen, SCENES.keys()])
		Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
		get_tree().quit(2)
		return
	Game.start_campaign(_seed)
	# the news bar's lines, so a run shows what the player was told
	Game.news_published.connect(func(t: String) -> void:
		print("news [%s]: %s" % [Calendar.date_of_day(Game.news_day()) if Game.state != null else "", t]))
	for key: String in _bal:
		Game.data.balance[key] = _bal[key]
	for key: String in _pal:
		Game.data.terrain_palette[key] = _pal[key]
	for st: Array in _sets:
		if String(st[0]).begins_with("res://"):
			var r: Resource = load(String(st[0]))
			if r == null:
				push_error("--set: no resource %s" % st[0])
			else:
				r.set(String(st[1]), st[2])
				_held.append(r)
				print("set %s:%s = %s" % [st[0], st[1], r.get(String(st[1]))])
	if _quiet:
		Game.state.event_state["scheduled"] = []
		Game.data.balance["event_base_chance"] = 0.0
		Game.data.balance["event_pity_ticks"] = 1000000.0
		# the reign's opening tick, as GameRoot._on_start_requested runs it —
		# without it the clock starts at tick 0, whose days repeat tick 1's
		Game.next_tick()
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
		# A shot is the game as a new player sees it: the player's own DEV MODE
		# setting (settings.cfg, which would lift the fog and show every realm's
		# regiments) is overridden in memory, never written; --dev asks for it.
		_root._dev_mode = _dev
		Intel.dev_all = _dev
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


func _real_key(c: Control, code: Key, unicode: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = unicode if down else 0
		e.pressed = down
		c.get_viewport().push_input(e, true)


## A real left DRAG across a control: press at `from`, eight motion events with
## the left button held walking to `to`, release at `to` — all pushed through
## the viewport, like a hand.
func _real_drag(c: Control, from: Vector2, to: Vector2) -> void:
	_real_move(c, from)
	var origin := c.get_global_transform_with_canvas()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = origin * from
	press.global_position = press.position
	c.get_viewport().push_input(press, true)
	var last := from
	for i in range(1, 9):
		var at := from.lerp(to, float(i) / 8.0)
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = origin * at
		m.global_position = m.position
		m.relative = at - last
		last = at
		c.get_viewport().push_input(m, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = origin * to
	release.global_position = release.position
	c.get_viewport().push_input(release, true)


## A real RIGHT drag across a control (the WAR ROOM's turn): press, eight
## motions with the right button held, release — pushed through the viewport.
func _real_right_drag(c: Control, from: Vector2, to: Vector2) -> void:
	_real_move(c, from)
	var origin := c.get_global_transform_with_canvas()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	press.position = origin * from
	press.global_position = press.position
	c.get_viewport().push_input(press, true)
	var last := from
	for i in range(1, 9):
		var at := from.lerp(to, float(i) / 8.0)
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_RIGHT
		m.position = origin * at
		m.global_position = m.position
		m.relative = at - last
		last = at
		c.get_viewport().push_input(m, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = origin * to
	release.global_position = release.position
	c.get_viewport().push_input(release, true)


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
	if _root != null and _pause_menu and _frames == 20:
		_root.toggle_pause_menu()
	if _root != null and _frames == _title_click_frame and _root.current_screen is MainMenu:
		var row := (_root.current_screen as MainMenu).menu_column().get_node_or_null(_title_click) as Control
		if row == null:
			push_error("--title-click: no title row %s" % _title_click)
		else:
			_real_click(row, row.size * 0.5)
	if _root != null and _frames == _reply_click_frame and _root.current_screen is ConversationScene:
		var replies: Array = (_root.current_screen as ConversationScene).reply_buttons()
		var shown: Array = replies.filter(func(b: Variant) -> bool: return (b as Control).is_visible_in_tree())
		if _reply_click >= shown.size():
			push_error("--click-reply: no option %d (%d shown)" % [_reply_click, shown.size()])
		else:
			var rb: Control = shown[_reply_click]
			_real_click(rb, rb.size * 0.5)
	if _root != null and _frames == _council_click_frame and _root.current_screen != null \
			and _root.current_screen.has_method("council_handle"):
		var seal := _root.current_screen.council_handle() as WaxSeal
		if seal == null or _council_click >= seal.mini_centres().size():
			push_error("--council-click: no councillor %d by the seal" % _council_click)
		elif _council_hover:
			_real_move(seal, seal.mini_centres()[_council_click])
		else:
			_real_click(seal, seal.mini_centres()[_council_click])
	if _day_share >= 0.0:
		Game.day_progress = _day_share
	# GameRoot boots into the menu; step it into the court so the shot shows
	# the gameplay chrome (top bar, bottom tabs, ticker) around a real screen.
	if _root != null and _frames == 4 and not _title:
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
		if _speed >= 0 and _march3d.x < 0.0 and _spy3d.is_empty():
			_start_clock()
	if _root != null and _frames == _march_at + 10 and _speed >= 0 and _march3d.x >= 0.0 and _spy3d.is_empty():
		_start_clock()
	if _root != null and not _spy3d.is_empty():
		_spy_step()
	if _root != null:
		_missive_step()
	if _root != null and _ledger != "":
		_ledger_step()
	if _root != null and _war_room:
		_war_room_step()
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
		for st: Array in _sets:
			if not String(st[0]).begins_with("res://"):
				var node := v3.find_child(String(st[0]), true, false)
				if node == null:
					push_error("--set: no node %s in the 3D view" % st[0])
				else:
					node.set(String(st[1]), st[2])
					print("set %s:%s = %s" % [st[0], st[1], node.get(String(st[1]))])
		if _dev:
			v3.set_dev_mode(true)
		if _weather != "":
			v3.set_weather_override(_weather)
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
	if _root != null and _march3d.x >= 0.0 and _frames - _march_at in [0, 2, 4, 6, 8] \
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
		if _frames - _march_at == 0:
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
		elif _frames - _march_at == 2:
			# The first row, MARCH…, chosen in the order PopupMenu.activate_item
			# (not exposed to scripts) does it: the menu HIDES first, and only
			# then emits id_pressed. That order is what threw every chosen
			# order away until 2026-09-24, so the shot must keep it.
			menu.hide()
			menu.id_pressed.emit(0)
			print("march3d: aiming=%s" % menu.aiming())
		elif _frames - _march_at == 4:
			_real_move(mv, at)
		elif _frames - _march_at == 6 and _march_confirm:
			# the destination click only ASKS: COMMIT / CANCEL (owner 2026-09-27)
			_real_click(mv, at)
			print("march3d: confirm open=%s pending=%s" % [menu.visible, menu.pending()])
		elif _frames - _march_at == 8 and _march_confirm and _march_commit:
			var code := menu.aiming()
			menu.hide()
			menu.id_pressed.emit(ArmyOrderMenu.COMMIT)
			print("march3d: order=%s days=%d clock=%d aiming_after=%s couriers=%s" % [
				ArmySystem.order_of(Game.data, Game.state, code),
				ArmySystem.days_out(Game.data, Game.state, code), Game.clock_speed, menu.aiming(),
				Game.state.couriers])
	if _root != null and _frames == 6 and _town != "" and _root.current_screen.has_method("detail_panel"):
		var burg: Dictionary = Game.data.burgs.get(_town, {})
		if burg.is_empty():
			push_error("no such town: " + _town)
		else:
			var v3: Map3DView = _root.current_screen.map3d_view()
			if v3 != null:
				v3.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])))
				v3.select_object({"kind": "burg", "code": _town})
			_root.current_screen.detail_panel().show_entry(
				{"title": String(burg.get("label", _town)), "obj": {"kind": "burg", "code": _town}})
	if _root != null and _hover_icon >= 0 and _frames == 40 and _root.current_screen.has_method("detail_panel"):
		var found: Array[Control] = []
		_tooltipped(_root.current_screen.detail_panel(), found)
		if _hover_icon < found.size():
			_hover_target = found[_hover_icon]
			print("hover-icon: %s \"%s\"" % [_hover_target.get_class(), _hover_target.tooltip_text])
		else:
			push_error("hover-icon: only %d controls with a tooltip" % found.size())
	if _hover_target != null and _frames > 40:
		var ev := InputEventMouseMotion.new()
		ev.position = get_viewport().get_final_transform() * (_hover_target.get_global_rect().get_center()
			+ Vector2(float(_frames % 2), 0.0))
		ev.global_position = ev.position
		get_viewport().push_input(ev)
	if _trace_couriers and _root != null:
		_trace_courier_frame()
	if _also.has(_frames):
		_save_shot(String(_also[_frames]))
	if (_shot_on == "" and _frames == _shot_frame) or (_shot_at >= 0 and _frames == _shot_at):
		if Game.state != null:
			print("state at shot: day=%d clock=%d pending_event=%s couriers=%d" % [Game.state.absolute_day(),
				Game.clock_speed, not Game.state.pending_event.is_empty(), Game.state.couriers.size()])
		var err := _save_shot(_out)
		var how := ("%dx%d window" % [_res.x, _res.y]) if _res != Vector2i.ZERO else ("x%.1f" % _scale)
		print("snapshot %s -> %s (%s, %s, filter %d)" % [
			"ok" if err == OK else "FAILED %d" % err, _out, _screen, how,
			int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 0))])
		Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
		get_tree().quit()


## One --trace-couriers line: the frame, day, share, and every courier's
## engine and drawn spot against his regiment's drawn spot (world XZ metres).
func _trace_courier_frame() -> void:
	if Game.state == null or not _root.current_screen.has_method("map3d_view") \
			or _root.current_screen.map3d_view() == null:
		return
	var v: Map3DView = _root.current_screen.map3d_view()
	var units := v.unit_positions()
	var drawn := v.courier_positions()
	if Game.state.couriers.is_empty() and Game.clock_speed == 0:
		return
	var line := "trace f=%d day=%d bar=\"%s\" share=%.3f clock=%d" % [_frames, Game.state.absolute_day(),
		_bar_date(), Game.day_progress, Game.clock_speed]
	for c: Dictionary in Game.state.couriers:
		var id := int(c["id"])
		var at: Vector2 = drawn.get(id, Vector2(-1, -1))
		var has_reg := units.has(String(c["target"]))
		var reg: Vector2 = units.get(String(c["target"]), Vector2.ZERO)
		line += " | courier %d rode=%d engine=(%d,%d) legs=%d drawn=(%.0f,%.0f) to_column=%.0f" % [
			id, int(c.get("days", 0)), int(c["x_m"]), int(c["y_m"]), (c["path"] as Array).size(),
			at.x, at.y, at.distance_to(reg) if has_reg and drawn.has(id) else -1.0]
	for code: String in units:
		var e: Dictionary = Game.state.regiments.get(code, {})
		var targeted := Game.state.couriers.any(func(c: Dictionary) -> bool: return String(c["target"]) == code)
		if String(e.get("order", "")) == ArmySystem.ORDER_MARCH or targeted:
			var p: Vector2 = units[code]
			line += " | %s %s engine=(%d,%d) drawn=(%.0f,%.0f) days_left=%d" % [code, String(e.get("order", "")),
				int(e.get("x_m", -1)), int(e.get("y_m", -1)), p.x, p.y,
				CourierSystem.days_to_arrival(Game.data, Game.state, code)]
	print(line)


## The top bar's date as it is drawn: its dial's day, then its DateLabel.
func _bar_date() -> String:
	var dial := _root.find_child("DateDial", true, false)
	var label := _root.find_child("DateLabel", true, false) as Label
	return "%s %s" % [str(dial.get("day")) if dial != null else "?", label.text if label != null else ""]


func _save_shot(path: String) -> int:
	var img := (get_viewport() if _viewport == null else _viewport).get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("shot %s at frame %d -> %s" % ["ok" if err == OK else "FAILED", _frames, path])
	return err


## Marks the moment a --shot-on names; the shot follows --shot-delay frames later.
func _moment(what: String) -> void:
	if _shot_on == what and _shot_at < 0:
		_shot_at = _frames + _shot_delay
		print("moment %s at frame %d (day %d)" % [what, _frames, Game.state.absolute_day()])


func _start_clock() -> void:
	Game.set_clock_speed(_speed)
	if _play_from < 0:
		_play_from = Game.state.absolute_day()


## --spy3d: one point every 4 frames from frame 26 (look, right click, choose).
func _spy_step() -> void:
	var cs: Node = _root.current_screen
	if not cs.has_method("map3d_view") or cs.map3d_view() == null:
		return
	var mv: Map3DView = cs.map3d_view()
	var menu := cs.get_node("%SpyOrders") as SpyOrderMenu
	var k := _frames - 26
	if k < 0:
		return
	@warning_ignore("integer_division")
	var n := k / 4
	if n >= _spy3d.size():
		if k == _spy3d.size() * 4 and _speed >= 0 and not _spy_menu_only:
			_start_clock()
		return
	if _spy_menu_only and n > 0:
		return
	var at := mv.size * 0.5
	match k % 4:
		0:
			mv.look_at_pack(_spy3d[n], 6000.0)
		2:
			_real_move(mv, at)
			for down in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_RIGHT
				e.pressed = down
				e.position = mv.get_global_transform_with_canvas() * at
				e.global_position = e.position
				mv.get_viewport().push_input(e, true)
			print("spy3d: menu open=%s row=%s where=%s" % [menu.visible,
				menu.get_item_text(0) if menu.item_count > 0 else "-",
				menu.get_item_tooltip(0) if menu.item_count > 0 else "-"])
			if menu.visible:
				_moment("spymenu")
		3:
			if _spy_menu_only:
				return
			menu.hide()
			menu.id_pressed.emit(SpyOrderMenu.SEND)
			var last: Dictionary = Game.state.couriers[-1] if not Game.state.couriers.is_empty() else {}
			print("spy3d: sent kind=%s couriers=%d treasury=%d" % [String(last.get("kind", "-")),
				Game.state.couriers.size(), int(Game.state.metrics.get("treasury", 0))])


## --ledger LENS [--ledger-open CODE] [--ledger-select ID] [--ledger-search TEXT
## [--ledger-search-pick]]:
## the LEDGER through its own controls, then the moment `ledger`.
func _ledger_step() -> void:
	var start := 30
	var screen := _root.ledger_screen()
	if _frames == start:
		var tab := _root.bottom_bar().button("LEDGER")
		_real_click(tab, tab.size * 0.5)
		print("ledger: open=%s" % screen.visible)
	elif _frames == start + 6:
		var chip := screen.find_child("Lens_" + _ledger, true, false) as Button
		if chip == null:
			push_error("ledger: no lens chip Lens_" + _ledger)
			return
		_real_click(chip, chip.size * 0.5)
		print("ledger: lens=%s cluster=%s stars=%d links=%d" % [screen.lens(), screen.view().cluster(),
			(screen.snapshot()["nodes"] as Array).size(), (screen.snapshot()["links"] as Array).size()])
	elif _frames == start + 10 and _ledger_open != "":
		screen.view().drill_requested.emit("province:" + _ledger_open)
		print("ledger: opened %s -> stars=%d" % [_ledger_open, (screen.snapshot()["nodes"] as Array).size()])
	elif _frames == start + 14 and _ledger_select != "":
		screen.view().drill_requested.emit(_ledger_select)
		print("ledger: selected %s" % screen.view().selected())
	elif _frames == start + 20:
		screen.view().settle_now()
	elif _frames == start + 24 and _ledger_search != "":
		var box := screen.search_box()
		_real_click(box, box.size * 0.5)
		for ch in _ledger_search:
			_real_key(box, OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE, ch.unicode_at(0))
	elif _frames == start + 26 and _ledger_search != "":
		print("ledger: search '%s' -> %s" % [screen.search_box().text, screen.search_matches().map(
			func(e: Dictionary) -> String: return "%s (%s)" % [e["label"], e["kind"]])])
	elif _frames == start + 28 and _ledger_search_pick:
		_real_key(screen.search_box(), KEY_ENTER, 0)
		print("ledger: picked %s, opened %s" % [screen.view().selected(), screen.opened().keys()])
	elif _frames == start + 32 and _ledger_search_pick:
		screen.view().settle_now()
	elif _frames == start + 40:
		_moment("ledger")


## --war-room [--war-sheet N] [--war-zoom M] [--war-piece CODE [--war-drag fx,fy]]
## [--war-folio DRILL|arm:ARM|explode]: the WAR ROOM through its own tab and its own
## gestures, then the moment `war`. Each step waits for the one before it by
## CONDITION, never by a fixed frame: the tab opened and a sheet laid, the
## requested sheet laid and the roll over (then a few frames for its ink), the
## camera leant, the piece clicked or raked (its screen place read AFTER the
## camera and the sheet are settled), then the folio, then the shot.
func _war_room_step() -> void:
	var screen := _root.war_room_screen()
	var view := screen.view()
	if _war_phase == 0:
		if _frames == _war_room_at:
			_war_sync("map")
			var tab := _root.bottom_bar().button("WAR ROOM")
			_real_click(tab, tab.size * 0.5)
			print("war: open=%s sheet=%d" % [screen.visible, view.sheet_index()])
			print("war: pieces=%s" % [WarRoom.pieces(Game.data, Game.state).map(func(q: Dictionary) -> String:
				return "%s@%d" % [q["code"], int(q["sheet"])])])
			_war_to(1)
	elif _war_phase == 1:
		# the room is open and a sheet is laid and not rolling: ask for the other
		if screen.visible and view.sheet_index() >= 0 and not view.rolling():
			if _war_cell != "":
				for s: Dictionary in WarSheets.series(Game.data):
					if String(s["id"]) == _war_cell:
						var cam := view.get_node("%Camera") as Camera3D
						var chart := view.get_node("%IndexChart") as MeshInstance3D
						var p := WarRoomWall.chart_point(chart, WarIndexChart.uv_of_cell(Game.data, s).get_center())
						var at := cam.unproject_position(p) / view.window_scale()
						_real_click(view, at)
						_war_sheet = int(s["index"])
						print("war: chart click on %s at %s tossing=%s" % [_war_cell, at, view.tossing()])
				if _war_sheet < 0:
					print("war: no sheet %s" % _war_cell)
			elif _war_sheet >= 0 and view.sheet_index() != _war_sheet:
				view.swap_to(_war_sheet)
				print("war: swapping to sheet %d" % _war_sheet)
			_war_to(2)
	elif _war_phase == 2:
		# the requested sheet is laid, the roll is over; let its ink settle
		var laid := _war_sheet < 0 or view.sheet_index() == _war_sheet
		if laid and not view.rolling() and not view.tossing() and _frames - _war_at >= 12:
			if _war_zoom > 0.0:
				var focus := Vector2(-1, -1)
				var on := _war_focus if _war_focus != "" else _war_piece
				if on != "":
					focus = view.position_of(on)
				elif _war_focus_px.x >= 0.0:
					focus = _war_focus_px
				view.lean_to(_war_zoom, focus)
				print("war: leant to %.2f m" % view.camera_rig().distance)
			if _war_turn != 0.0:
				var mid := Vector2(view.size) * 0.5
				var px := -_war_turn / Game.data.bal("war_cam_turn_deg_per_px")
				_real_right_drag(view, mid - Vector2(px * 0.5, 0.0), mid + Vector2(px * 0.5, 0.0))
				print("war: yaw=%.1f" % view.camera_rig().yaw_deg)
			_war_to(3)
	elif _war_phase == 3:
		if _frames - _war_at < 6:
			return
		if _war_board:
			var cam := view.get_node("%Camera") as Camera3D
			var panel := view.get_node("%BoardPanel") as Node3D
			var at := cam.unproject_position(panel.global_position) / view.window_scale()
			_real_click(view, at)
			print("war: board click at %s mode=%s" % [at, view.board_mode()])
		if _war_piece != "":
			var at: Variant = view.screen_pos_of_px(view.position_of(_war_piece))
			if at == null:
				push_error("war: piece %s not in view" % _war_piece)
			elif _war_drag.x >= 0.0:
				_real_drag(view, at, Vector2(view.size) * _war_drag)
			else:
				_real_click(view, at)
			print("war: piece=%s sheet=%d at=%s selected=%s aiming=%s" % [_war_piece, view.sheet_index(), at,
				view.selected_army(), screen.orders().aiming()])
		if _war_hover.x >= 0.0:
			_real_move(view, Vector2(view.size) * _war_hover)
			print("war: hover at %s" % (Vector2(view.size) * _war_hover))
		_war_to(4)
	elif _war_phase == 4:
		if _war_hover.x >= 0.0 and _frames - _war_at < ceili(Game.data.bal("war_hover_delay_s") * 120.0) + 10:
			return   # a 120 Hz display's frames: the slip has come up
		if _frames - _war_at < 6:
			return
		if _war_board and _frames - _war_at < ceili(Game.data.bal("war_board_fly_s") * 120.0) + 10:
			return   # a 120 Hz display's frames: the flight to the easel is over
		if _war_board_click.x >= 0.0:
			_real_click(view, Vector2(view.size) * _war_board_click)
			print("war: board mode=%s missive open=%s selected=%d" % [view.board_mode(),
				_root.missive_screen().visible, _root.missive_screen().selected()])
		if _war_commit:
			var menu := screen.orders()
			menu.hide()   # PopupMenu.activate_item's order: hidden first, then id_pressed
			menu.id_pressed.emit(ArmyOrderMenu.COMMIT)
			print("war: committed order=%s pennant=%s draft=%s" % [ArmySystem.order_of(Game.data, Game.state, _war_piece),
				WarRoom.pennant_of(Game.data, Game.state, _war_piece), WarDrafts.of(Game.state, _war_piece)])
		if _war_folio != "":
			var folio := screen.get_node_or_null("%Folio")
			if folio == null:
				print("war: no folio yet")
			elif _war_folio == "explode":
				var b := folio.get_node_or_null("%TakeApart") as Button
				if b == null:
					print("war: no Take apart button yet")
				else:
					_real_click(b, b.size * 0.5)
			elif _war_folio.begins_with("arm:"):
				# an arms button of the left page, by its arm key (arm:artillery)
				var hit_arm := false
				for t: Button in folio.get_node("%Arms").get_children():
					if String(t.get_meta("arm")) == _war_folio.substr(4):
						_real_click(t, t.size * 0.5)
						hit_arm = true
				if not hit_arm:
					print("war: no arms button '%s'" % _war_folio)
			else:
				var drills := folio.get_node_or_null("%Drills")
				var hit := false
				if drills != null:
					for t: Button in drills.get_children():
						if String(t.text).to_lower().contains(_war_folio):
							_real_click(t, t.size * 0.5)
							hit = true
				if not hit:
					print("war: no drill tab '%s' yet" % _war_folio)
		_war_to(10 if _war_deploy != "" or _war_leave != "" else 5)
	elif _war_phase == 5 and _frames - _war_at >= 40 + (ceili(Game.data.bal("war_explode_s") * 120.0)   # a 120 Hz display's frames
			if _war_folio == "explode" else 0):
		_war_sync("room")
		_moment("war")
		_war_to(6)
	elif _war_phase == 10 and _frames - _war_at >= 12:
		var scroll := screen.get_node("%Deploy") as WarDeployScroll
		if _war_leave != "":
			var tab := _root.bottom_bar().button(_war_leave)
			_real_click(tab, tab.size * 0.5)
			print("war: leave by %s — asked=%s drafts=%s" % [_war_leave, screen.asking_leave(),
				WarDrafts.codes(Game.state)])
			_war_to(5)
		else:
			_real_click(scroll.button(), scroll.button().size * 0.5)
			print("war: scroll disabled=%s review=%s lines=%d" % [scroll.button().disabled, scroll.review_open(),
				scroll.line_labels().size()])
			_war_to(11 if _war_deploy != "review" else 5)
	elif _war_phase == 11 and _frames - _war_at >= 20:
		var seal := (screen.get_node("%Deploy") as WarDeployScroll).get_node("%Seal") as Button
		_real_click(seal, seal.size * 0.5)
		_war_to(12)
	elif _war_phase == 12:
		var scroll := screen.get_node("%Deploy") as WarDeployScroll
		if _war_deploy == "seal" and scroll._phase == "press" \
				and scroll._t >= Game.data.bal("war_deploy_press_s") * 0.7:
			_moment("war")
			_war_to(6)
		elif _war_deploy == "sent" and not scroll.sealing() and _frames - _war_at >= 30:
			print("war: sent — drafts=%s couriers=%d" % [WarDrafts.codes(Game.state), Game.state.couriers.size()])
			_war_to(5)


## Each regiment's place three ways, in pack px: the engine's, the 3D map's
## drawn piece and the room's piece (when laid), with the day and its share.
func _war_sync(when: String) -> void:
	var mv: Map3DView = _root.current_screen.map3d_view() if _root.current_screen.has_method("map3d_view") else null
	var drawn: Dictionary = mv.unit_pack_positions() if mv != null else {}
	var room := _root.war_room_screen().view().piece_pack_positions()
	print("war sync (%s): day=%d share=%.3f clock=%d held=%s" % [when, Game.state.absolute_day(),
		Game.day_progress, Game.clock_speed, Game.clock_held])
	for reg: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		var code := String(reg["regiment_code"])
		var eng := ArmySystem.position_of(Game.data, Game.state, reg)
		var d: Variant = drawn.get(code)
		var r: Variant = room.get(code)
		print("  %s engine=%s map=%s room=%s map-engine=%.2f px room-map=%s" % [code, eng, d, r,
			(d as Vector2).distance_to(eng) if d != null else -1.0,
			"%.3f px" % (r as Vector2).distance_to(d) if r != null and d != null else "-"])


func _war_to(phase: int) -> void:
	_war_phase = phase
	_war_at = _frames


## --play-days, then --missives: seal each report as the player would, press
## play again, stop after N days; then open the board and pick a letter.
func _missive_step() -> void:
	var pop := _root.report_popup()
	if pop.visible:
		_moment("report")
	if _play_from >= 0 and _play_done < 0 and _play_days >= 0:
		if pop.visible and _shot_on != "report":
			if not pop.has_meta("snap_sealed"):
				pop.set_meta("snap_sealed", true)
				print("report: %s" % String(pop.get_node("%ReportTitle").text))
				_real_click(pop.seal_button(), pop.seal_button().size * 0.5)
				_moment("flight")
		elif not pop.visible:
			if pop.has_meta("snap_sealed"):
				pop.remove_meta("snap_sealed")
			if Game.state.absolute_day() - _play_from >= _play_days:
				Game.set_clock_speed(0)
				_play_done = _frames
				print("play done: day=%d missives=%s" % [Game.state.absolute_day(),
					Game.state.missives.map(func(m: Dictionary) -> String:
						return "%s/%s" % [String(m["column"]), String(m["title"])])])
			elif Game.clock_speed == 0 and _root.pending_reports().is_empty() \
					and _shot_on != "flight":
				Game.set_clock_speed(_speed)
	if _missives == "":
		return
	var start := _play_done if _play_days >= 0 else 30
	if start < 0:
		return
	var board := _root.missive_screen()
	if _frames == start + 60:
		var tab := _root.bottom_bar().button("MISSIVE")
		_real_click(tab, tab.size * 0.5)
		print("missives: board open=%s" % board.visible)
	elif _frames == start + 64:
		var notes := board.find_child(_missives.capitalize() + "Notes", true, false) as Container
		for c in notes.get_children():
			if c is Button:
				_real_click(c, (c as Button).size * 0.5)
				break
		print("missives: selected=%d desk=%s" % [board.selected(), board.desk_text().replace("\n", " | ")])
		_moment("board")
	elif _frames == start + 68 and _show_on_map:
		var b := board.show_on_map_button()
		_real_click(b, b.size * 0.5)
		var title := _root.current_screen.detail_panel().find_child("Title", true, false) as Label
		print("show-on-map: board open=%s card=%s" % [board.visible, title.text if title != null else "?"])
		_moment("card")


## Every visible control under `n` that carries a tooltip, in tree order.
func _tooltipped(n: Node, out: Array[Control]) -> void:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).tooltip_text != "":
		out.append(n)
	for c in n.get_children():
		_tooltipped(c, out)
