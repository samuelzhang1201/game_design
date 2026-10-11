class_name MapDetailPanel
extends PanelContainer
## The fact card for what the player clicked on the map. Towns and the
## player's own provinces get a CARD after Azgaar's burg editor — heraldry, a
## field grid, feature and goods glyphs, wealth and treasury, and a preview
## of the map around the place; other objects (kingdoms, roads, rivers,
## points of interest, regiments, foreign provinces) get their lines. ASK THE
## COUNCIL and CLOSE below. Content comes from MapObjects; this renders.
##
## It lives in the screen's LEFT column (owner ruling 2026-09-10: the left
## column holds the facts of an object, the right column holds characters and
## conversations), taking the column from whatever it normally shows until
## CLOSE. The column draws the frame, so the card itself has no border.

signal ask_requested(text: String)
signal closed
## A regiment's card's THE HOST button (owner 2026-09-27: the MILITARY tab is
## gone and the host overview opens from a regiment): the screen puts the
## MilitaryPanel in the left column.
signal host_requested
## A row of a LEDGER instance list was chosen (show_list).
signal list_row_chosen(id: String)

## Sized for the left column's content width (ScreenLayout.LEFT_WIDTH less
## the column panel's margins).
const PREVIEW_SIZE := Vector2(208, 118)
## How much of the world the preview shows, in native map px.
const PREVIEW_SPAN := Vector2(90, 51)

## Screens with an input box turn this on; the day run has none.
var ask_enabled := false:
	set(on):
		ask_enabled = on
		_ask.visible = on and _ask_text != ""

var _shield: HeraldicShield
var _title: Label
var _subtitle: Label
var _fields: GridContainer
var _features: HBoxContainer
var _production: VBoxContainer
var _money: VBoxContainer
var _preview: TerrainPreview
var _lines: VBoxContainer
## The manor card's orders (MANOR_SYSTEM.md §3): one button per action the
## card offers, dim with ActionSystem's reason as its tooltip when it cannot
## be given. A click runs the order through Game.try_execute — never the
## model — and redraws the card from the new state.
var _actions: VBoxContainer
## The manor card's face (owner 2026-09-14): its estate's painting pinned
## over the card at a third of its height, its facts as icon + short value
## with the whole in each tooltip, and its output a month good by good.
var _painting_box: Control
var _painting: TextureRect
## The painting's own texture; `_painting` shows a band of it (_fit_painting).
var _painting_source: Texture2D
var _scroll: ScrollContainer
var _scroll_fade: Control
var _stats: GridContainer
var _rates: VBoxContainer
var _stat_cells: Dictionary = {}
## The build dropdown and its button (owner 2026-09-14): one menu of the
## buildings the manor may raise instead of a button apiece.
var _build_menu: OptionButton
var _build_button: Button
## A stat's or a rate's icon, design px.
const STAT_ICON_PX := 20.0
## The stat grid's default width: 4 columns = 2 icon+value pairs a row. A
## card may ask for fewer (`stat_columns`, owner 2026-09-17 review) when its
## values are too wide for a pair to fit the fixed left column.
const DEFAULT_STAT_COLUMNS := 4
## The manor's building slots (owner 2026-09-13): one box per slot — a
## building's icon, a work's icon dimmed with its days left, or an empty
## "+" — each standing building or work with a cross beneath it that
## pulls it down through MANOR_DEMOLISH.
var _slots: HBoxContainer
var _shown_manor := -1
## A slot box's side, design px.
const SLOT_PX := 34.0
## A slot's box, and a work in progress's see-through box (its dashes are
## drawn over it, _draw_dashed_edge) — edited in the inspector.
const SLOT_STYLE := preload("res://assets/2D/ui/panels/styles/card_slot.tres")
const SLOT_WORK_STYLE := preload("res://assets/2D/ui/panels/styles/card_slot_work.tres")
var _hint: Label
var _ask: Button
var _close: Button
var _ask_text := ""
var _shown_province := ""
## Whether a card is open (distinct from `visible`, which the left column
## sets: a hovered country never closes the card, it only covers it).
var _open := false


## The card's frame is scenes/panels/map_detail_panel.tscn (owner 2026-10-02: the
## look lives in the editor): the painting band, the scrolling body and its
## sections, the map window, ASK and CLOSE. Its rows are made here as cards
## are shown, each a theme kind (CardText, CardLabel, CardStatName,
## CardFigure, …) that game_theme.tres writes in the leather's ink and the
## paper column's paper_theme.tres in the paper's — so the same card reads
## on leather and on paper with no colour set in code.
func _ready() -> void:
	_painting_box = $Col/Painting
	_painting = $Col/Painting/PaintingImage
	var fade: Control = $Col/Painting/PaintingFade
	# Its paper edges fade into the card (owner 2026-09-28, second critique:
	# a cream rectangle on dark leather was a hard-edged tray).
	fade.draw.connect(func() -> void: _draw_painting_fade(fade))
	fade.resized.connect(fade.queue_redraw)
	resized.connect(_fit_painting)
	# The column is narrow and no taller than the screen, so a full town card
	# does not fit: the body scrolls and ASK / CLOSE stay pinned at the bottom.
	_scroll = $Col/CardScroll
	# More lies below: the last row fades into the card instead of being cut
	# through its middle (critic 2026-09-28); top level, placed each frame over
	# the scroll's foot.
	_scroll_fade = $Col/CardScroll/ScrollFade
	_scroll_fade.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _scroll_fade.size)
		var solid := UiPalette.card_ground(self)
		_scroll_fade.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]), PackedColorArray([Color(solid, 0.0), Color(solid, 0.0), solid, solid])))
	var body := $Col/CardScroll/CardBody
	_shield = body.get_node("Head/Shield")
	_title = body.get_node("Head/Titles/Title")
	_subtitle = body.get_node("Head/Titles/Subtitle")
	_fields = body.get_node("Fields")
	_stats = body.get_node("Stats")
	_rates = body.get_node("Rates")
	_slots = body.get_node("Slots")
	_features = body.get_node("Features")
	_production = body.get_node("Production")
	_money = body.get_node("Money")
	_actions = body.get_node("Actions")
	_lines = body.get_node("Rows")
	_hint = body.get_node("Hint")
	_preview = body.get_node("Preview")
	_ask = $Col/DetailAsk
	_ask.pressed.connect(func() -> void: ask_requested.emit(_ask_text))
	_close = $Col/DetailClose
	_close.pressed.connect(func() -> void:
		_close_panel()
		closed.emit())
	# Nothing is selected when a screen opens: the card is closed and the
	# column shows its own content (user ruling 2026-09-09).
	_close_panel()


## The card as the game makes it: its scene.
static func create() -> MapDetailPanel:
	return (load("res://scenes/panels/map_detail_panel.tscn") as PackedScene).instantiate()


## Whether a card is open. The screen's left column asks this rather than
## reading `visible`, which it owns.
## The card's whole height with its body unscrolled: the pinned parts plus the
## scroll's content (the WAR ROOM's roll unrolls exactly this far).
func content_height() -> float:
	var h := get_combined_minimum_size().y
	if _scroll == null:
		return h
	var body := 0.0
	for c in _scroll.get_children():
		if c is Control and not (c as Control).top_level:   # the ScrollFade floats over the foot
			body = maxf(body, (c as Control).get_combined_minimum_size().y)
	return h + body - _scroll.get_combined_minimum_size().y


func has_content() -> bool:
	return _open


func _open_panel() -> void:
	# An empty section takes no room (2026-09-28): five empty boxes' spacing
	# pushed a foreign card's orders below the scroll's fold.
	for box: Control in [_fields, _stats, _rates, _slots, _features, _production, _money, _actions, _lines]:
		box.visible = box.get_child_count() > 0
	_open = true
	show()


func _close_panel() -> void:
	_open = false
	hide()


## Follow a map: pins, lines, and kingdoms through object_selected; provinces
## through province_selected. An empty selection hides the panel. Any map
## with those two signals: the 2D WorldMapView and the 3D Map3DView.
func follow(map: Control) -> void:
	map.connect("object_selected", show_entry)
	map.connect("province_selected", show_province)


## entry = {title, lines, ask, obj?} from the map; a town gets its card,
## everything else its lines; {} hides.
func show_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		_close_panel()
		return
	_shown_province = ""
	var obj: Dictionary = entry.get("obj", {})
	if String(obj.get("kind", "")) == "burg":
		show_card(MapObjects.burg_card(Game.data, Game.state, String(obj["code"])))
		return
	if String(obj.get("kind", "")) == "manor":
		show_manor(int(obj.get("cell", -1)))
		return
	if String(obj.get("kind", "")) == "army":
		show_card(MapObjects.army_card(Game.data, String(obj["code"]), Game.state))
		return
	if String(obj.get("kind", "")) == "courier":
		show_card(CourierCard.card(Game.data, Game.state, int(obj.get("id", -1))))
		return
	_clear()
	_shield.visible = false
	_title.text = String(entry.get("title", ""))
	_subtitle.visible = false
	for line in entry.get("lines", []):
		_lines.add_child(_line(String(line), &"CardText"))
	_set_ask(String(entry.get("ask", "")))
	_open_panel()


## A clickable list in the left column (the LEDGER's instances of a type,
## spec 2026-09-30 §6.1): each row a flat button that ellipsises rather than
## widening the fixed column.
func show_list(title: String, entries: Array) -> void:
	_shown_province = ""
	_clear()
	_shield.visible = false
	_title.text = title
	_subtitle.visible = false
	for row: Dictionary in entries:
		var b := Button.new()
		b.text = String(row["text"])
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.set_meta("ledger_id", String(row["id"]))
		b.theme_type_variation = &"CardRow"
		var id := String(row["id"])
		b.pressed.connect(func() -> void: list_row_chosen.emit(id))
		_lines.add_child(b)
	_set_ask("")
	_open_panel()


## The province card: full for the player's own land, basic abroad; "" hides.
func show_province(province_code: String) -> void:
	_shown_province = province_code
	var card := MapObjects.province_card(Game.data, Game.state, province_code) \
		if province_code != "" else {}
	if card.is_empty():
		_shown_province = ""
		_close_panel()
		return
	show_card(card)


## The manor card, redrawn from the live state (a bought manor shows the
## crown at once); -1 hides.
func show_manor(cell: int) -> void:
	_shown_manor = cell
	var card := MapObjects.manor_card(Game.data, Game.state, cell) if cell >= 0 else {}
	if card.is_empty():
		_shown_manor = -1
		_close_panel()
		return
	show_card(card)

## Whose arms a card wears (owner 2026-09-15): a manor its holding house's,
## a province its house's, a town the house of its province.
static func house_of_card(card: Dictionary) -> String:
	var code := String(card.get("code", ""))
	match String(card.get("kind", "")):
		"manor":
			return MapManors.owner_of(Game.data, Game.state, int(card.get("cell", -1)))
		"province":
			return MapObjects.house_name_of(Game.data, code)
		"burg":
			return MapObjects.house_name_of(Game.data,
				String(Game.data.burgs.get(code, {}).get("province_code", "")))
	return ""

## Render a MapObjects card (burg_card / province_card / manor_card).
func show_card(card: Dictionary) -> void:
	if card.is_empty():
		_close_panel()
		return
	_clear()
	_shield.visible = true
	_shield.set_arms(MapPalette.color_of(Game.data, String(card.get("kingdom_code", ""))),
		String(card.get("initial", "")))
	_shield.set_texture(HouseArms.texture_of_house(Game.data, Game.state, house_of_card(card)))
	# a regiment, and the courier riding with its orders, fly the kingdom's arms
	if String(card.get("kind", "")) in ["army", "courier"]:
		_shield.set_texture(HouseArms.texture_of_kingdom(Game.data, String(card.get("kingdom_code", ""))))
	_title.text = String(card.get("title", ""))
	_subtitle.text = String(card.get("subtitle", ""))
	_subtitle.visible = _subtitle.text != ""
	# A manor's card reads as icons (owner 2026-09-14): its painting over the
	# card, its facts as icon + short value with the whole in the tooltip,
	# and what it makes a month. Every other card keeps its fields.
	# The grid is reused across cards, so its column count must be reset
	# per card — a regiment's card asks for fewer, wider pairs.
	_stats.columns = int(card.get("stat_columns", DEFAULT_STAT_COLUMNS))
	_stats.add_theme_constant_override("v_separation", 4)
	var stats: Array = card.get("stats", [])
	if stats.is_empty():
		for f in card.get("fields", []):
			_fields.add_child(_line(String(f[0]), &"CardLabel"))
			_fields.add_child(_line(String(f[1]), &"CardText"))
	elif _as_rows(card):
		_fill_stat_rows(stats, card.get("rates", []))
	else:
		_fill_stats(stats)
		_fill_rates(card.get("rates", []))
	_show_painting(String(card.get("painting", "")))
	# What is known through the missive board (spec 2026-09-28 §1): each row
	# is a label, its text, and — when it came from a letter rather than
	# common knowledge — a tag naming the source and the day, coloured by
	# the column it stands in.
	# The label column is only as wide as its words and a tag stands small
	# under its estimate (Task 10's look check): in the fixed column the
	# estimate and its tag on one line wrapped over four.
	# A run of facts from one letter names it once, under the first: the same
	# tag under every row carried nothing new (the colour still marks each).
	var last_tag := ""
	for row: Dictionary in card.get("intel", []):
		var label := _line(String(row["label"]), &"CardLabel")
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_FILL
		_fields.add_child(label)
		var value := _line(String(row["text"]), &"CardText")
		if String(row["tag"]) == "":
			_fields.add_child(value)
			last_tag = ""
			continue
		var colour := MapPalette.named(Game.data, "intel_" + String(row["column"]))
		value.add_theme_color_override("font_color", colour)  # the report's column, data
		if String(row["tag"]) == last_tag:
			_fields.add_child(value)
			continue
		last_tag = String(row["tag"])
		var tag := _line(last_tag, &"CardTag")
		tag.add_theme_color_override("font_color", colour)  # the report's column, data
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(value)
		cell.add_child(tag)
		_fields.add_child(cell)
	var known := String(card.get("known", "full"))
	var basic := known in ["basic", "general"]
	if known == "army":
		# an army card is its painting and its icons (owner 2026-09-15), and
		# the way to the whole host (owner 2026-09-27)
		var host := Button.new()
		host.name = "TheHost"
		host.text = "The Host — all regiments"
		host.focus_mode = Control.FOCUS_NONE
		host.theme_type_variation = &"CardCommandSmall"
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		host.pressed.connect(func() -> void: host_requested.emit())
		_actions.add_child(host)
	elif known == "courier":
		pass  # a courier's card is his painting and his fields; no land sections
	elif not basic:
		var features: Array = card.get("features", [])
		if not features.is_empty():
			_features.add_child(_line("Features", &"CardLabel"))
			for key in features:
				_features.add_child(ResourceIcon.create(String(key)))
		var production: Array = card.get("production", [])
		if not production.is_empty():
			_production.add_child(_line("Production", &"CardLabel"))
			for i in mini(production.size(), int(Game.data.bal("province_card_max_goods"))):
				var p: Dictionary = production[i]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				if String(p.get("tag", "")) != "":
					row.add_child(ResourceIcon.create(String(p["tag"])))
				row.add_child(_line("%s %s" % [String(p["label"]), _num(float(p["units"]))]))
				_production.add_child(row)
		# One row per sum, never two labels squeezed into one line (user report
		# 2026-09-09: they wrapped letter by letter).
		for spec in [["wealth", "wealth"], ["town_treasury", "treasury"]]:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(ResourceIcon.create(String(spec[0])))
			var text := _line("%s %s" % [
				String((Game.data.resource_icons.get(String(spec[0]), {}) as Dictionary).get("label", spec[1])),
				_num(float(card.get(String(spec[1]), 0.0)))])
			text.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.add_child(text)
			_money.add_child(cell)
		# A manor's painting is its picture (owner 2026-09-14); the map window
		# is for cards without one.
		if String(card.get("painting", "")) == "" or UiPalette.load_art(String(card["painting"])) == null:
			_set_preview(card.get("center", Vector2.ZERO))
		_fill_slots(card)
	else:
		# The intel rows above stand in for the hint once there is something
		# to report; only a card with nothing at all still says so.
		_hint.text = "Little more is known of foreign land."
		_hint.visible = (card.get("intel", []) as Array).is_empty()
	# The orders the card offers stand outside the full/basic split: a foreign
	# manor on the border offers its BUY (owner 2026-09-14). The buildings
	# are one dropdown, not a button apiece (owner 2026-09-14).
	var builds: Array = []
	for a: Dictionary in card.get("actions", []):
		if String(a["action_code"]) == "MANOR_BUILD":
			builds.append(a)
			continue
		var button := Button.new()
		button.name = String(a["action_code"]) + "_" + String((a["params"] as Dictionary).get("building",
			(a["params"] as Dictionary).get("focus", "")))
		button.text = String(a["label"])
		button.focus_mode = Control.FOCUS_NONE
		button.theme_type_variation = &"CardCommandSmall"
		button.disabled = String(a.get("error", "")) != ""
		button.tooltip_text = String(a.get("error", ""))
		if String(a["action_code"]) == "MANOR_BUY":
			# The full label ("BUY — 1,234 gold from the crown's
			# treasury") ran past two lines of the fixed 240 px column
			# (fix round 1 finding 1): a short button, the whole line as
			# its tooltip when it is not disabled — the BUILD button's
			# own pattern (_add_build_menu below).
			button.text = String(a["label"]).get_slice(" from ", 0)
			if not button.disabled:
				button.tooltip_text = String(a["label"])
		button.text = UiPalette.command_label(button.text)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The column's width is fixed (CLAUDE.md invariant 10): a long
		# order wraps rather than pushing the column over the map.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var request := ActionRequest.make(String(a["action_code"]), (a["params"] as Dictionary).duplicate())
		button.pressed.connect(func() -> void: _give_order(request))
		_actions.add_child(button)
		# Foreign land's facts read "—", and the way to learn them stands
		# close by (spec 2026-09-28 §2): the spy is its first order.
		if known == "basic" and String(a["action_code"]) == "SPY_SEND":
			_actions.move_child(button, 0)
	if not builds.is_empty():
		_add_build_menu(builds)
	_set_ask(String(card.get("ask", "")))
	_open_panel()


## A window onto the world map around a place, PREVIEW_SPAN native px
## across, drawn from the same terrain mesh as the map (no render exists).
func _set_preview(center: Vector2) -> void:
	_preview.show_place(center)


## A card button's order: through Game, which validates and executes it
## and announces the state change; then the card is drawn again.
func _give_order(request: ActionRequest) -> void:
	var result := Game.try_execute(request)
	if not bool(result.get("ok", false)):
		_hint.text = String(result.get("error", ""))
		_hint.visible = _hint.text != ""
		return
	if request.action_code == "SPY_SEND":
		# A spy is sent from any land card — manor, province or burg — and
		# _shown_manor may be stale from an earlier manor card, so a refresh
		# here would silently swap the shown card for the wrong manor's.
		var outcome: Dictionary = result.get("outcome", {})
		for e: Dictionary in outcome.get("effects", []):
			if String(e.get("metric", "")) == "intel":
				Game.publish_news(String(e["reason"]))
		return
	if _shown_manor >= 0:
		show_manor(_shown_manor)

## One box per slot of a manor card; nothing for cards with no slots.
func _fill_slots(card: Dictionary) -> void:
	var total := int(card.get("slots", 0))
	if total <= 0:
		return
	var demolish: Dictionary = {}
	for a: Dictionary in card.get("slot_actions", []):
		demolish[String(a["building"])] = a
	var filled: Array = []
	for b: String in card.get("buildings", []):
		filled.append({"building": b, "work": false})
	for w: Dictionary in card.get("works", []):
		filled.append({"building": String(w["building"]), "work": true, "days_left": int(w["days_left"]),
			"artisan_pct": int(w.get("artisan_pct", 0))})
	for i in total:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
		box.add_theme_stylebox_override("panel", SLOT_STYLE)
		if i < filled.size():
			var entry: Dictionary = filled[i]
			var code := String(entry["building"])
			box.name = "Slot_" + code
			var icon := ResourceIcon.create("bld_" + code)
			icon.custom_minimum_size = Vector2(SLOT_PX - 8.0, SLOT_PX - 8.0)
			var centre := CenterContainer.new()
			centre.add_child(icon)
			box.add_child(centre)
			var row: Dictionary = Game.data.manor_buildings.get(code, {})
			var label := String(row.get("label", code))
			if bool(entry["work"]):
				# A work in progress is a GHOST of the building (owner
				# 2026-09-14): a see-through box with a dashed edge and the
				# building's art faint inside it, until the days are up.
				box.add_theme_stylebox_override("panel", SLOT_WORK_STYLE)
				box.draw.connect(_draw_dashed_edge.bind(box))
				icon.modulate.a = Game.data.bal("ui_slot_work_alpha")
				var days := Label.new()
				days.name = "Days"
				days.text = "%dd" % int(entry["days_left"])
				days.theme_type_variation = &"CardSmall"
				days.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				column.add_child(box)
				column.add_child(days)
				var artisan_pct := int(entry.get("artisan_pct", 0))
				box.tooltip_text = "%s — %d days to go%s" % [label, int(entry["days_left"]),
					(" (artisans: +%d%%)" % artisan_pct) if artisan_pct > 0 else ""]
			elif (card.get("idle", {}) as Dictionary).has(code):
				# An idle building (LEDGER M5: its inputs went unpaid) is its
				# art dimmed with the word under it, like a work's days, and
				# why in the tooltip ("idle: no iron").
				var why := String(card["idle"][code])
				icon.modulate.a = Game.data.bal("ui_slot_idle_alpha")
				var word := Label.new()
				word.name = "Idle"
				word.text = "idle"
				word.theme_type_variation = &"CardWarn"
				word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				word.tooltip_text = why
				word.mouse_filter = Control.MOUSE_FILTER_PASS
				column.add_child(box)
				column.add_child(word)
				box.tooltip_text = "%s — %s" % [label, why]
			else:
				column.add_child(box)
				box.tooltip_text = label
			if demolish.has(code):
				var a: Dictionary = demolish[code]
				var cross := Button.new()
				cross.name = "DEMOLISH_" + code
				cross.text = "x"
				cross.focus_mode = Control.FOCUS_NONE
				cross.theme_type_variation = &"CardCross"
				cross.custom_minimum_size = Vector2(SLOT_PX, 0)
				cross.tooltip_text = String(a["label"]) if String(a.get("error", "")) == "" else String(a["error"])
				cross.disabled = String(a.get("error", "")) != ""
				var request := ActionRequest.make("MANOR_DEMOLISH", (a["params"] as Dictionary).duplicate())
				cross.pressed.connect(func() -> void: _give_order(request))
				column.add_child(cross)
		else:
			box.name = "Slot_empty_%d" % i
			var plus := Label.new()
			plus.text = "+"
			plus.theme_type_variation = &"CardPlus"
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box.add_child(plus)
			box.tooltip_text = "An empty slot: build below"
			column.add_child(box)
		_slots.add_child(column)

## The buildings the manor may raise, as ONE dropdown (owner 2026-09-14):
## each entry its art, name, civil cost and days; one still waiting on a
## building it needs is disabled with the reason as its tooltip, the others
## say what they yield. BUILD gives the chosen one.
func _add_build_menu(builds: Array) -> void:
	var row := VBoxContainer.new()
	row.name = "BuildRow"
	row.add_theme_constant_override("separation", 4)
	var menu := OptionButton.new()
	menu.name = "BuildMenu"
	menu.focus_mode = Control.FOCUS_NONE
	menu.theme_type_variation = &"CardMenu"
	menu.get_popup().theme_type_variation = &"CardMenuPopup"
	menu.clip_text = true
	# An OptionButton is as wide as its longest entry unless told otherwise,
	# and "Stonecutter — 150 civil, 40d" pushed the fixed column over the map
	# (CLAUDE.md invariant 10): it takes the column's width and clips instead.
	menu.fit_to_longest_item = false
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var first_ok := -1
	for i in builds.size():
		var a: Dictionary = builds[i]
		var code := String((a["params"] as Dictionary)["building"])
		var text := String(a["label"]).trim_prefix("BUILD ")
		var tex := ResourceIcon.texture_of("bld_" + code)
		if tex != null:
			menu.add_icon_item(tex, text, i)
		else:
			menu.add_item(text, i)
		menu.set_item_metadata(i, a)
		var err := String(a.get("error", ""))
		menu.set_item_disabled(i, err != "")
		menu.set_item_tooltip(i, err if err != "" else building_tooltip(code))
		if err == "" and first_ok < 0:
			first_ok = i
	var go := Button.new()
	go.name = "BuildButton"
	go.text = "BUILD"
	go.focus_mode = Control.FOCUS_NONE
	go.theme_type_variation = &"CardCommandSmall"
	go.text = UiPalette.command_label(go.text)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sync := func(index: int) -> void:
		var chosen: Dictionary = menu.get_item_metadata(index) if index >= 0 else {}
		var err := String(chosen.get("error", "")) if not chosen.is_empty() else "Nothing can be built here"
		go.disabled = chosen.is_empty() or err != ""
		go.tooltip_text = err if err != "" else building_tooltip(String((chosen["params"] as Dictionary)["building"]))
	menu.item_selected.connect(sync)
	menu.select(first_ok if first_ok >= 0 else 0)
	sync.call(menu.selected)
	go.pressed.connect(func() -> void:
		if menu.selected < 0:
			return
		var chosen: Dictionary = menu.get_item_metadata(menu.selected)
		if not chosen.is_empty() and String(chosen.get("error", "")) == "":
			_give_order(ActionRequest.make("MANOR_BUILD", (chosen["params"] as Dictionary).duplicate())))
	row.add_child(menu)
	row.add_child(go)
	_actions.add_child(row)
	_build_menu = menu
	_build_button = go


## What a building yields once it stands, for its menu entry and button:
## "Mill — +6 grain a month, tax +5%, output +15%, +2 civil goods a month".
static func building_tooltip(code: String) -> String:
	var row: Dictionary = Game.data.manor_buildings.get(code, {})
	var parts: Array[String] = []
	var units := int(float(row.get("produce_units", 0)))
	var good := String(row.get("produce_good", ""))
	if units > 0 and good != "":
		parts.append("+%d %s a month" % [units,
			String(Game.data.world_row("economy", "goods", good).get("label", good)).to_lower()])
	var pct := func(key: String) -> int: return roundi(float(row.get(key, 0)) * 100.0)
	if pct.call("tax_bonus") != 0:
		parts.append("tax %+d%%" % pct.call("tax_bonus"))
	if pct.call("output_bonus") != 0:
		parts.append("output %+d%%" % pct.call("output_bonus"))
	if float(row.get("defence_bonus", 0)) != 0.0:
		parts.append("defence %+d" % int(float(row.get("defence_bonus", 0))))
	if float(row.get("gold_per_tick", 0)) != 0.0:
		parts.append("%+d gold a month" % int(float(row.get("gold_per_tick", 0))))
	if float(row.get("grain_per_tick", 0)) != 0.0:
		parts.append("%+d civil goods a month" % int(float(row.get("grain_per_tick", 0))))
	if float(row.get("church_bonus", 0)) != 0.0:
		parts.append("church %+.1f a month" % float(row.get("church_bonus", 0)))
	if float(row.get("contentment_per_tick", 0)) != 0.0:
		parts.append("contentment %+.1f a month" % float(row.get("contentment_per_tick", 0)))
	if float(row.get("unrest_per_tick", 0)) != 0.0:
		parts.append("unrest %+.1f a month" % float(row.get("unrest_per_tick", 0)))
	var needs: Array[String] = []
	for p in MapManors.building_prereqs(Game.data, code):
		needs.append(String((Game.data.manor_buildings.get(p, {}) as Dictionary).get("label", p)).to_lower())
	var text := "%s — %s" % [String(row.get("label", code)), ", ".join(parts) if not parts.is_empty() else "no yield"]
	if not needs.is_empty():
		text += " (needs %s)" % ", ".join(needs)
	return text


## The dashed edge of a work's ghost box, in the accent at three quarters.
func _draw_dashed_edge(box: Control) -> void:
	var r := Rect2(Vector2(1.0, 1.0), box.size - Vector2(2.0, 2.0))
	var ink := Color(UiPalette.GOLD, 0.75)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		box.draw_dashed_line(corners[i], corners[(i + 1) % 4], ink, 1.5, 4.0)


func _clear() -> void:
	for box in [_fields, _stats, _rates, _slots, _features, _production, _money, _lines, _actions]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_stat_cells.clear()
	_build_menu = null
	_build_button = null
	_painting_box.visible = false
	_painting.texture = null
	_painting_source = null
	_hint.visible = false
	_hint.text = ""
	_preview.visible = false


## The painted estate over the card, when the card names one and it is on
## disk; the box is hidden otherwise.
func _show_painting(path: String) -> void:
	var tex: Texture2D = UiPalette.load_art(path) if path != "" else null
	_painting_source = tex
	_painting.texture = tex
	_painting_box.visible = tex != null
	_fit_painting()


func _process(_delta: float) -> void:
	if _scroll_fade == null or _scroll == null:
		return
	var d := Game.data.bal("ui_card_scroll_fade_px")
	var bar := _scroll.get_v_scroll_bar()
	var more := bar.visible and _scroll.scroll_vertical < int(bar.max_value - bar.page) - 1
	_scroll_fade.visible = d > 0.0 and more and _scroll.is_visible_in_tree()
	if not _scroll_fade.visible:
		return
	var w := _scroll.size.x - (bar.size.x if bar.visible else 0.0)
	var at := _scroll.global_position + Vector2(0.0, _scroll.size.y - d)
	if _scroll_fade.global_position != at or _scroll_fade.size != Vector2(w, d):
		_scroll_fade.global_position = at
		_scroll_fade.size = Vector2(w, d)
		_scroll_fade.queue_redraw()


## Four soft edges in the card's own colour, `ui_manor_painting_fade_px` deep.
func _draw_painting_fade(on: Control) -> void:
	var d := Game.data.bal("ui_manor_painting_fade_px")
	var r := Rect2(Vector2.ZERO, on.size)
	if d <= 0.0:
		# Framed like the audience window's portrait: a gilt hairline.
		on.draw_rect(r.grow(-0.5), UiPalette.BORDER_GOLD, false, 1.0)
		return
	var solid := UiPalette.card_ground(self)
	var clear := Color(solid, 0.0)
	var quads := [
		[r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + d), Vector2(r.position.x, r.position.y + d), true],
		[Vector2(r.position.x, r.end.y - d), Vector2(r.end.x, r.end.y - d), r.end, Vector2(r.position.x, r.end.y), false],
	]
	for q: Array in quads:
		var top_solid: bool = q[4]
		on.draw_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), PackedColorArray(
			[solid, solid, clear, clear] if top_solid else [clear, clear, solid, solid]))
	on.draw_polygon(PackedVector2Array([r.position, Vector2(r.position.x + d, r.position.y),
		Vector2(r.position.x + d, r.end.y), Vector2(r.position.x, r.end.y)]),
		PackedColorArray([solid, clear, clear, solid]))
	on.draw_polygon(PackedVector2Array([Vector2(r.end.x - d, r.position.y), Vector2(r.end.x, r.position.y),
		r.end, Vector2(r.end.x - d, r.end.y)]), PackedColorArray([clear, solid, solid, clear]))


## The painting cut to its scene (owner 2026-09-28, second critique: a third
## of the card, a third of it bare paper, pushed the facts below the fold):
## a band `ui_manor_painting_aspect` wide to 1 high, centred
## `ui_manor_painting_focus_y` down the picture where the estates stand, and
## never more than `ui_manor_painting_max_share` of the card. Was a third of
## the card's height (owner 2026-09-14).
func _fit_painting() -> void:
	if _painting_box == null:
		return
	var aspect := maxf(Game.data.bal("ui_manor_painting_aspect"), 0.5)
	var w := _painting_box.size.x if _painting_box.size.x > 0.0 else size.x
	var h := minf(w / aspect, size.y * Game.data.bal("ui_manor_painting_max_share"))
	_painting_box.custom_minimum_size = Vector2(0.0, maxf(h, 72.0))
	if _painting_source == null:
		return
	var tw := float(_painting_source.get_width())
	var th := float(_painting_source.get_height())
	var band := minf(th, tw / aspect)
	var y0 := clampf(th * Game.data.bal("ui_manor_painting_focus_y") - band * 0.5, 0.0, th - band)
	var atlas := _painting.texture as AtlasTexture
	if atlas == null or atlas.atlas != _painting_source:
		atlas = AtlasTexture.new()
		atlas.atlas = _painting_source
		_painting.texture = atlas
	atlas.region = Rect2(0.0, y0, tw, band)


## Two facts a row: an icon (its tooltip the whole fact) and a short value
## that clips rather than widen the fixed column.
func _fill_stats(stats: Array) -> void:
	for st: Dictionary in stats:
		var key := String(st["key"])
		var tip := String(st["tooltip"])
		var icon := ResourceIcon.create(key)
		icon.name = "StatIcon_" + key
		icon.custom_minimum_size = Vector2(STAT_ICON_PX, STAT_ICON_PX)
		# ResourceIcon sets its own tooltip when it enters the tree; the card's
		# is the fuller one, so it goes on after.
		icon.ready.connect(func() -> void: icon.tooltip_text = tip, CONNECT_ONE_SHOT)
		icon.tooltip_text = tip
		var value := Label.new()
		value.name = "Stat_" + key
		value.text = String(st["text"])
		# a warning fact (a broken or cut supply line) in the card's warning ink
		value.theme_type_variation = &"CardWarn" if String(st.get("tone", "")) == "warn" else &"CardValue"
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size = Vector2(56, 0)
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		value.tooltip_text = tip
		_stats.add_child(icon)
		_stats.add_child(value)
		_stat_cells[key] = value


## Whether a card's facts are laid out as named rows: a manor's, when the
## balance asks for it (owner 2026-09-28, ui_manor_card_rows).
func _as_rows(card: Dictionary) -> bool:
	return String(card.get("kind", "")) == "manor" \
		and Game.data.bal("ui_manor_card_rows") > 0.0 \
		and not Game.data.manor_card_sections.is_empty()


## The manor's facts as NAMED rows in the sections of
## data/manor_card_sections.csv: a muted small-capitals heading over a faint
## rule, then a row a fact — its art, its name, its value on the right, the
## whole fact in the tooltip — and the goods it makes under the section that
## asks for them. A fact no section names falls to the last.
func _fill_stat_rows(stats: Array, rates: Array) -> void:
	_stats.columns = 1
	# Rows sit tighter than the icon grid did: more of the card above the fold.
	_stats.add_theme_constant_override("v_separation", 1)
	var sections: Array = Game.data.manor_card_sections
	var placed := {}
	var by_section: Array = []
	for sec: Dictionary in sections:
		var mine: Array = []
		for want: String in sec["keys"]:
			for st: Dictionary in stats:
				var key := String(st["key"])
				if placed.has(key):
					continue
				if key == want or (want.ends_with("_") and key.begins_with(want)):
					mine.append(st)
					placed[key] = true
		by_section.append(mine)
	for st: Dictionary in stats:
		if not placed.has(String(st["key"])):
			(by_section[by_section.size() - 1] as Array).append(st)
	for i in sections.size():
		var sec: Dictionary = sections[i]
		var mine: Array = by_section[i]
		var show_rates: bool = sec["rates"] and not rates.is_empty()
		if show_rates:
			# The goods rows carry what these rows would repeat (owner
			# 2026-09-28): each good's tooltip names its worth and pool.
			var dropped: Array = sec.get("drop_if_rates", [])
			mine = mine.filter(func(st: Dictionary) -> bool: return not dropped.has(String(st["key"])))
		if mine.is_empty() and not show_rates:
			continue
		var head := Label.new()
		head.name = "Section_" + String(sec["section"])
		head.text = String(sec["label"])
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.theme_type_variation = &"CardSection"
		_stats.add_child(head)
		var per_month: bool = sec.get("per_month", false)
		for st: Dictionary in mine:
			_stats.add_child(_stat_row(st, per_month))
		if show_rates:
			var box := VBoxContainer.new()
			box.name = "SectionRates"
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_theme_constant_override("separation", 2)
			_stats.add_child(box)
			_fill_rates(rates, box, false, per_month)


## One named fact: art, name, value right-aligned in tabular figures. Under a
## heading that says it is a month's (`per_month`), the value drops its /mo.
func _stat_row(st: Dictionary, per_month := false) -> HBoxContainer:
	var key := String(st["key"])
	var tip := String(st["tooltip"])
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	# A one-column grid sizes its column to the widest child's MINIMUM: the
	# row has to ask to fill it, or the value is squeezed to one letter.
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var icon := ResourceIcon.create(key)
	icon.name = "StatIcon_" + key
	icon.custom_minimum_size = Vector2(STAT_ICON_PX, STAT_ICON_PX)
	icon.ready.connect(func() -> void: icon.tooltip_text = tip, CONNECT_ONE_SHOT)
	icon.tooltip_text = tip
	# The art is optional here (ui_manor_row_icons): the name already says it.
	icon.visible = Game.data.bal("ui_manor_row_icons") > 0.0
	icon.custom_minimum_size = Vector2(STAT_ICON_PX - 2.0, STAT_ICON_PX - 2.0)
	row.add_child(icon)
	var name_l := Label.new()
	name_l.text = String((Game.data.resource_icons.get(key, {}) as Dictionary).get("label", key))
	if key.begins_with("weather_"):
		name_l.text = "Weather"
	name_l.theme_type_variation = &"CardStatName"
	name_l.custom_minimum_size = Vector2(Game.data.bal("ui_manor_row_label_px"), 0)
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	name_l.tooltip_text = tip
	row.add_child(name_l)
	var value := Label.new()
	value.name = "Stat_" + key
	value.text = String(st["text"]).trim_suffix("/mo") if per_month else String(st["text"])
	value.theme_type_variation = &"CardWarn" if String(st.get("tone", "")) == "warn" else &"CardFigure"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	value.tooltip_text = tip
	row.add_child(value)
	_stat_cells[key] = value
	return row


## What the manor makes a month (owner 2026-09-14: the rate of every
## product): one row a good — its art in its category's colour, its name,
## and "+N / mo", the tooltip adding what the units are worth and to which
## pool they go. Under a heading that says it is a month's (`per_month`) the
## rate is the bare figure in the same ink and face as the rows above it
## (owner 2026-09-28: "217/mo" beside a green "+217 / mo" was two formats).
func _fill_rates(rates: Array, into: VBoxContainer = null, headed := true, per_month := false) -> void:
	if rates.is_empty():
		return
	var target := into if into != null else _rates
	if headed:
		target.add_child(_line("Output a month", &"CardLabel"))
	for r: Dictionary in rates:
		var good := String(r["good"])
		var tip := "%s — %d units a month, worth %d gold to the %s goods" % [
			String(r["label"]), int(r["units"]), int(r["gold"]), String(r["pool"])]
		var row := HBoxContainer.new()
		row.name = "Rate_" + good
		row.add_theme_constant_override("separation", 6)
		# The good's colour icon when it is installed (owner 2026-09-14: every
		# icon on the card is game art); else the map's grey art in its
		# category's colour.
		var icon_path := String(r.get("icon", ""))
		var coloured: Texture2D = UiPalette.load_art(icon_path) if icon_path != "" else null
		var tex: Texture2D = coloured
		if tex == null and String(r.get("texture", "")) != "":
			tex = UiPalette.load_art(String(r["texture"]))
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			pic.custom_minimum_size = Vector2(STAT_ICON_PX, STAT_ICON_PX) - (Vector2(2, 2) if per_month else Vector2.ZERO)
			if coloured == null:
				pic.modulate = ManorBadges.tag_color(Game.data, String(r.get("tag", "")))
			pic.mouse_filter = Control.MOUSE_FILTER_PASS
			pic.tooltip_text = tip
			row.add_child(pic)
		else:
			var glyph := ResourceIcon.create("tag_" + String(r.get("tag", "")))
			glyph.custom_minimum_size = Vector2(STAT_ICON_PX, STAT_ICON_PX)
			row.add_child(glyph)
		var name_l := Label.new()
		name_l.text = String(r["label"])
		# Under a per-month heading the good is one more named row: the rows'
		# muted name and their art's size, so the column lines up.
		name_l.theme_type_variation = &"CardStatName" if per_month else &"CardValue"
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.tooltip_text = tip
		row.add_child(name_l)
		var rate_l := Label.new()
		rate_l.name = "Rate"
		if per_month:
			rate_l.text = UiPalette.format_int(int(r["units"]))
			rate_l.theme_type_variation = &"CardFigure"
		else:
			rate_l.text = "+%d / mo" % int(r["units"])
			rate_l.theme_type_variation = &"CardGood"
		rate_l.mouse_filter = Control.MOUSE_FILTER_PASS
		rate_l.tooltip_text = tip
		row.add_child(rate_l)
		target.add_child(row)


func _set_ask(ask: String) -> void:
	_ask_text = ask
	_ask.visible = ask_enabled and ask != ""


## One line of the card in a theme kind (CardText the body, CardLabel a
## label), written in whichever ink the column's theme gives it.
func _line(text: String, kind: StringName = &"CardText") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = kind
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.2f" % v


## Test seams.
func shield() -> HeraldicShield:
	return _shield

func title_label() -> Label:
	return _title


func subtitle_label() -> Label:
	return _subtitle


func fields() -> GridContainer:
	return _fields


func features_row() -> HBoxContainer:
	return _features


func production_box() -> VBoxContainer:
	return _production


func preview() -> TerrainPreview:
	return _preview


func rows() -> VBoxContainer:
	return _lines


func hint_label() -> Label:
	return _hint


func ask_button() -> Button:
	return _ask


func close_button() -> Button:
	return _close


func actions_box() -> VBoxContainer:
	return _actions

## Test seams for the manor card's face.
func stat_text(key: String) -> String:
	return String((_stat_cells[key] as Label).text) if _stat_cells.has(key) else ""

func stat_tooltip(key: String) -> String:
	return String((_stat_cells[key] as Label).tooltip_text) if _stat_cells.has(key) else ""

func build_menu() -> OptionButton:
	return _build_menu

func build_button() -> Button:
	return _build_button

## The building codes the dropdown offers, in its order.
func build_menu_codes() -> Array:
	var out: Array = []
	if _build_menu == null:
		return out
	for i in _build_menu.item_count:
		out.append(String(((_build_menu.get_item_metadata(i) as Dictionary)["params"] as Dictionary)["building"]))
	return out

## Choose a building in the dropdown as a player would; false when it is not
## offered or cannot be built yet.
func select_build(code: String) -> bool:
	var i := build_menu_codes().find(code)
	if i < 0 or _build_menu.is_item_disabled(i):
		return false
	_build_menu.select(i)
	_build_menu.item_selected.emit(i)
	return true

func stats_grid() -> GridContainer:
	return _stats

## Where the output rows are: under the section that asks for them when the
## card is laid out as rows, else the card's own box.
func rates_box() -> VBoxContainer:
	var in_section := _stats.get_node_or_null("SectionRates") as VBoxContainer
	return in_section if in_section != null else _rates

func painting_box() -> Control:
	return _painting_box

func painting_texture() -> Texture2D:
	return _painting_source

func slots_row() -> HBoxContainer:
	return _slots

func shown_manor() -> int:
	return _shown_manor

func shown_province() -> String:
	return _shown_province
