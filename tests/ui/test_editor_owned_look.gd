extends GutTest
## The look lives in the editor (owner 2026-10-02): a converted screen's
## scene is what the game draws. Two guards hold it, so neither an agent nor a
## person can quietly put the look back into code:
## 1. a converted script's _ready sets no look (no override, no style, no
##    layout, no art path) — _ready finds nodes, wires them and fills them;
## 2. every look property the scene declares — styles, fonts, sizes, colours,
##    themes, label kinds, art, anchors and offsets — still holds after the
##    screen's _ready, but for the CODE-OWNED ones listed below with why.

const SCRIPTS := ["res://scripts/ui/court_screen.gd", "res://scripts/ui/conversation_scene.gd",
	"res://scripts/ui/top_bar.gd"]

## What a converted _ready may never call.
const FORBIDDEN := ["add_theme_stylebox_override", "add_theme_font_override",
	"add_theme_font_size_override", "add_theme_color_override", "add_theme_constant_override",
	"panel_style(", "StyleBoxFlat.new", "StyleBoxEmpty.new", "StyleBoxTexture.new",
	"UiPalette.style_", "command_button(", "compact_button(", "ScreenLayout.apply(",
	"place_handle(", "load(\"res://assets", "set_anchors"]
## Writes a converted _ready may never make (a read is fine).
const FORBIDDEN_WRITES := ["offset_[a-z]+\\s*=[^=]", "anchor_[a-z]+\\s*=[^=]",
	"custom_minimum_size\\s*=[^=]"]

## Look properties the guard compares (a prefix, or a whole name).
const LOOK_PREFIXES := ["theme_override_", "anchor_", "offset_"]
const LOOK_NAMES := ["theme", "theme_type_variation", "texture", "art", "color",
	"custom_minimum_size", "z_index"]

## Code-owned, by scene path from the screen's root, and why.
const CODE_OWNED := {
	# WaxSeal builds itself in code (its tag, its overrides, its size) until
	# it is converted; the scene places it.
	"CouncilHandle": ["*"],
	# the top bar: the figures' change ink is good / bad by the month
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_treasury/Change": ["theme_override_colors/font_color"],
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_strategic/Change": ["theme_override_colors/font_color"],
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_grain/Change": ["theme_override_colors/font_color"],
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_lord_gold/Change": ["theme_override_colors/font_color"],
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_lord_strategic/Change": ["theme_override_colors/font_color"],
	"TopBar/Bar/Row/TallyBoard/Purses/Cell_lord_civil/Change": ["theme_override_colors/font_color"],
	# sized to the map it stands over (_fit_audience: AUDIENCE_MAX within the
	# map less AUDIENCE_MARGIN)
	"AudienceLayer/AudienceCenter/AudienceWindow": ["custom_minimum_size"],
	# the crown's arms and the house's colour are the live house's
	"TopBar/Bar/Row/DateArms": ["texture"],
	"TopBar/Bar/Row/TallyBoard/Purses/HouseNameBox/LordCrest": ["texture", "color"],
}

func test_a_converted_ready_sets_no_look() -> void:
	for path: String in SCRIPTS:
		var body := _function_body(FileAccess.get_file_as_string(path), "_ready")
		assert_ne(body, "", path + " has a _ready")
		for bad: String in FORBIDDEN:
			assert_false(body.contains(bad), "%s's _ready sets the look in code (%s): put it in the scene" % [path, bad])
		for pattern: String in FORBIDDEN_WRITES:
			var re := RegEx.create_from_string(pattern)
			var hit := re.search(body)
			assert_null(hit, "%s's _ready lays out in code (%s): put it in the scene" % [path,
				hit.get_string() if hit != null else ""])

func test_the_court_keeps_its_scenes_look() -> void:
	var r := _root()
	_start(r)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(3)
	_assert_scene_holds(r.current_screen, "res://scenes/court.tscn")
	_assert_scene_holds(r.current_screen.get_node("%TopBar"), "res://scenes/top_bar.tscn", "TopBar/")
	# the scene's layout, moved in the editor, still starts the columns under the bar
	var bar: TopBar = r.current_screen.get_node("%TopBar")
	for n in ["%LogPanel", "%MapPanel", "%SidePanel"]:
		assert_gte((r.current_screen.get_node(n) as Control).offset_top, bar.bar_height() + 3.0,
			n + " starts under the top bar")

func test_the_conversation_keeps_its_scenes_look() -> void:
	var r := _root()
	_start(r)
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_process_frames(3)
	_assert_scene_holds(r.current_screen, "res://scenes/conversation.tscn")

## The council column opening moves only the map's right edge, to the gap
## the scene gives short of the column, and closing puts it back.
func test_the_council_column_opens_by_the_scenes_gap() -> void:
	var r := _root()
	_start(r)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	var court: CourtScreen = r.current_screen
	var map: Control = court.get_node("%MapPanel")
	var closed := map.offset_right
	court.enter_council()
	await wait_process_frames(1)
	assert_eq(map.offset_right, (court.get_node("%SidePanel") as Control).offset_left - court.council_gap)
	court.leave_council()
	await wait_process_frames(1)
	assert_eq(map.offset_right, closed)

## Two screens share the report's paper look but each draws its own height.
func test_each_screen_has_its_own_report_paper() -> void:
	var r := _root()
	_start(r)
	r._switch_to(GameRoot.State.COURT)
	var a := (r.current_screen.get_node("%LogPanel") as Control).get_theme_stylebox("panel")
	var b: Control = load("res://scenes/conversation.tscn").instantiate()
	add_child_autofree(b)
	var c := (b.get_node("%MinisterPanel") as Control).get_theme_stylebox("panel")
	assert_true(a is PaperStyle and c is PaperStyle)
	assert_ne(a, c, "local to each scene, so fit_report on one never moves the other")

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _start(_r: GameRoot) -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))

## Every look property `scene_path` declares, compared with the live `screen`.
## `prefix` is where the scene stands in CODE_OWNED's paths.
func _assert_scene_holds(screen: Node, scene_path: String, prefix := "") -> void:
	var state := (load(scene_path) as PackedScene).get_state()
	var checked := 0
	for i in state.get_node_count():
		var rel := String(state.get_node_path(i)).trim_prefix(".").trim_prefix("/")
		var node := screen if rel == "" else screen.get_node_or_null(rel)
		if node == null:
			continue
		var owned: Array = CODE_OWNED.get(prefix + rel, [])
		if owned.has("*"):
			continue
		for j in state.get_node_property_count(i):
			var prop := String(state.get_node_property_name(i, j))
			if not _is_look(prop) or owned.has(prop):
				continue
			var want: Variant = state.get_node_property_value(i, j)
			var got: Variant = node.get(prop)
			checked += 1
			assert_true(_same(want, got), "%s %s: the scene says %s, the game drew %s — set in code?" % [
				scene_path.get_file(), (prefix + rel if rel != "" else "(root)") + "." + prop, want, got])
	assert_gt(checked, 20, scene_path + ": the guard compared the scene's look")

func _is_look(prop: String) -> bool:
	if LOOK_NAMES.has(prop):
		return true
	for p: String in LOOK_PREFIXES:
		if prop.begins_with(p):
			return true
	return false

## Equal, or the same look resource: a resource local to the scene is the
## scene's own copy, of the same script.
func _same(want: Variant, got: Variant) -> bool:
	if want is Resource and got is Resource:
		if want == got:
			return true
		var w := want as Resource
		var g := got as Resource
		return w.resource_local_to_scene and w.get_class() == g.get_class() and w.get_script() == g.get_script()
	if want is float or got is float:
		return is_equal_approx(float(want), float(got))
	return want == got

## The body of `fname` in GDScript `src`: from its line to the next line that
## starts at column 0 (the next function, var or comment block).
func _function_body(src: String, fname: String) -> String:
	var start := src.find("\nfunc %s(" % fname)
	if start < 0:
		return ""
	var lines := src.substr(start + 1).split("\n")
	var out := PackedStringArray([lines[0]])
	for k in range(1, lines.size()):
		var line := lines[k]
		if line != "" and not line.begins_with("\t") and not line.begins_with(" "):
			break
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
