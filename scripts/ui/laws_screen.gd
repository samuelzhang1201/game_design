class_name LawsScreen
extends Control
## The laws (spec 2026-10-08-laws-tab-design §5): LAWS in the bottom bar
## opens it over the map; it does NOT hold the clock — a decree may be given
## while time runs. Three pages (economy, politics, military), a row a law
## (LawRow, scenes/panels/law_row.tscn), the military rows under their group
## titles. Decree gives LAW_SET through Game.try_execute; Places opens the list
## of places not yet told, a lost one offered again (plan ruling R5). Esc
## closes it before the pause menu. The look is scenes/screens/laws_screen.tscn;
## the screen reads the state and computes nothing.

signal closed
## A decree was given (Decree or Send again): Game.try_execute's result.
signal decreed(result: Dictionary)

const ROW := preload("res://scenes/panels/law_row.tscn")
const PAGES := ["economy", "politics", "military"]

var _page := "economy"
var _rows: Array = []
## A state change waits to be drawn (drained in _process, once a frame).
var _dirty := false
## The law whose places the detail lists ("" while it is shut).
var _detail_law := ""
## The reign the rows last read (its instance id): a new one forgets their
## chosen values and kept previews.
var _reign := 0
## What stands above the screen (GameRoot's pause menu and spy report): while
## one shows, Esc is its, not the screen's.
var above: Array[Control] = []


## Its nodes are the scene's: this wires them, puts in the words of
## law_words.csv and instances a row a law.
func _ready() -> void:
	%Title.text = _word("title")
	for head: Array in [["LawHead", "law"], ["DecreedHead", "decreed"], ["DeliveryHead", "delivered"]]:
		(get_node("Frame/Col/Heads/" + String(head[0])) as Label).text = _word(String(head[1]))
	%Close.pressed.connect(close)
	%DetailClose.pressed.connect(_close_detail)
	%SendAgain.text = _word("send_again")
	%SendAgain.pressed.connect(_send_again)
	for pg: String in PAGES:
		var b := page_button(pg)
		b.text = _word("page_" + pg)
		b.pressed.connect(show_page.bind(pg))
	_build_rows()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	Game.state_changed.connect(func() -> void: _dirty = true)
	show_page(_page)


## A row a law, in each page's file order; a military row titled when it is
## the first of its group.
func _build_rows() -> void:
	var repo := Game.data
	for pg: String in PAGES:
		var last := ""
		for law: String in LawSystem.codes_on(repo, pg):
			var group := String(LawSystem.def(repo, law).get("group", ""))
			var rw: LawRow = ROW.instantiate()
			rw.name = "Law_" + law
			%Rows.add_child(rw)
			rw.setup(law, group != last, last != "")
			last = group
			rw.decree_pressed.connect(_decree)
			rw.places_pressed.connect(_show_places)
			_rows.append(rw)


func open() -> void:
	visible = true


## Closing forgets each row's chosen value: it opens again on the decrees.
func close() -> void:
	if not visible:
		return
	_close_detail()
	for rw: LawRow in _rows:
		rw.reset()
	visible = false
	closed.emit()


## Show `page`'s rows; the others hide.
func show_page(pg: String) -> void:
	_page = pg
	for p: String in PAGES:
		page_button(p).set_pressed_no_signal(p == pg)
	for rw: LawRow in _rows:
		rw.visible = String(LawSystem.def(Game.data, rw.law())["tab"]) == pg
	_close_detail()
	if visible:
		_refresh()


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_refresh()


## The shown page's rows read the state again (a hidden page's when shown),
## and the open list of places.
func _refresh() -> void:
	_dirty = false
	if Game.state == null:
		return
	if Game.state.get_instance_id() != _reign:
		_reign = Game.state.get_instance_id()
		for rw: LawRow in _rows:
			rw.reset()
	var places := _places_signature()
	for rw: LawRow in _rows:
		if rw.visible:
			rw.refresh(places)
	if _detail_law != "":
		_fill_detail()


## Who a decree would be sent to, cheaply: the realm's provinces and land
## units counted (an owner or a unit changing on a paused clock moves it).
func _places_signature() -> String:
	var repo := Game.data
	var realm := repo.resolve_realm("player_realm")
	var land := 0
	for r: Dictionary in MapObjects.regiments_of(repo, realm, Game.state):
		if String(r.get("is_naval", "0")) != "1":
			land += 1
	return "%d|%d" % [MapOwnership.provinces_of(repo, Game.state, realm).size(), land]


## Esc closes the list of places, else the screen — before GameRoot's pause
## menu (a child's _unhandled_input runs first), unless something above it
## shows (the pause menu: Esc is the menu's).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	for c: Control in above:
		if c != null and c.visible:
			return
	if _detail_law != "":
		_close_detail()
	else:
		close()
	get_viewport().set_input_as_handled()


## Give the order; a refusal is said in the news bar. A decree given is said
## once, by its couriers as they set out (CourierSystem.news), not here.
func _decree(law: String, value: String) -> void:
	var out := Game.try_execute(ActionRequest.make(LawSystem.ACTION, {"law": law, "value": value}))
	if not bool(out.get("ok", false)):
		Game.publish_news(String(out.get("error", "")))
	decreed.emit(out)


func _show_places(law: String) -> void:
	_detail_law = law
	%DetailTitle.text = "%s — %s" % [_word("not_told"), String(LawSystem.def(Game.data, law)["label"])]
	_fill_detail()
	%Detail.visible = true


## Each place not yet told, a line: "Name — 4 days", a lost one "Name — lost";
## Send again while a place is lost and the decree may ride again.
func _fill_detail() -> void:
	var lines: PackedStringArray = []
	var any_lost := false
	for u: Dictionary in LawSystem.untold(Game.data, Game.state, _detail_law):
		if bool(u["lost"]):
			any_lost = true
			lines.append("%s — %s" % [String(u["label"]), _word("lost" if bool(u["sent"]) else "not_sent")])
		else:
			var d := int(u["days"])
			lines.append("%s — %d %s" % [String(u["label"]), d, _word("day") if d == 1 else _word("days")])
	%DetailList.text = "\n".join(lines) if not lines.is_empty() else _word("all_told")
	var again := LawSystem.preview(Game.data, Game.state, _detail_law,
		LawSystem.decreed(Game.data, Game.state, _detail_law))
	%SendAgain.disabled = not any_lost or String(again["refusal"]) != ""


func _send_again() -> void:
	if _detail_law != "":
		_decree(_detail_law, LawSystem.decreed(Game.data, Game.state, _detail_law))


func _close_detail() -> void:
	_detail_law = ""
	%Detail.visible = false


static func _word(key: String) -> String:
	return String(Game.data.law_words.get(key, key))


## Test seams.
func page() -> String:
	return _page

func page_button(p: String) -> Button:
	return get_node("%" + p.capitalize())

func rows() -> Array:
	return _rows

func row(law: String) -> LawRow:
	for r: LawRow in _rows:
		if r.law() == law:
			return r
	return null

func detail() -> Control:
	return %Detail

func detail_text() -> String:
	return %DetailList.text

func send_again_button() -> Button:
	return %SendAgain
