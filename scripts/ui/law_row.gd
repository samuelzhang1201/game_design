class_name LawRow
extends VBoxContainer
## One law on the laws screen (spec 2026-10-08-laws-tab-design §5): its name,
## the decreed value, how far the decree has got, what the chosen value does,
## one menu of the law's values (a toggle's two, a choice's names, a range's
## levels), the preview's cost or refusal beside it, Decree, and Places (the
## list of places not yet told, the screen's). The look is
## scenes/panels/law_row.tscn; this fills it from the engine and computes
## nothing: every figure is LawSystem's or LawEffects'.
##
## The preview works out every courier's ride, so it is kept until what it
## reads changes (the chosen value, the day, the couriers, the decree, the
## chest, and the screen's signature of who would be sent to: the realm's
## provinces and land units); the delivery likewise.

## Decree pressed: the screen gives the order.
signal decree_pressed(law: String, value: String)
## Places pressed: the screen opens the list of places not yet told.
signal places_pressed(law: String)

var _law := ""
## The value chosen in the menu (a law's String); the decreed one until the
## player picks another.
var _chosen := ""
var _preview_key := ""
var _preview: Dictionary = {}
var _delivery_key := ""
var _delivery: Dictionary = {}


## Its nodes are the scene's; Decree and Places speak through the signals.
func _ready() -> void:
	%Decree.pressed.connect(func() -> void: decree_pressed.emit(_law, _chosen))
	%Places.pressed.connect(func() -> void: places_pressed.emit(_law))
	%Choice.item_selected.connect(_on_chosen)


## Fill the row for `law`: its name, its group's title when it is the first
## row of its group (`titled`) with the scene's gap above it when another group
## stands before it (`gapped`), its words, and the menu of its values. The
## menu's popup wears the CardMenuPopup kind (a popup is no scene node, so it
## cannot be authored; MapDetailPanel's build menu does the same).
func setup(law_id: String, titled: bool, gapped := false) -> void:
	_law = law_id
	var repo := Game.data
	var d := LawSystem.def(repo, law_id)
	%Label.text = String(d["label"])
	var group := String(d.get("group", ""))
	%GroupTitle.visible = titled and group != ""
	%GroupGap.visible = titled and gapped and group != ""
	%GroupTitle.text = _word("group_" + group) if group != "" else ""
	%Decree.text = _word("decree")
	%Places.text = _word("places")
	var menu: OptionButton = %Choice
	menu.get_popup().theme_type_variation = &"CardMenuPopup"
	menu.clear()
	for v: String in _values(d):
		menu.add_item(LawSystem.value_label(repo, v))
		menu.set_item_metadata(menu.item_count - 1, v)


## A law's values as Strings: a range's levels from min to max by its step
## (1 when the row gives none), a toggle's or a choice's names.
static func _values(d: Dictionary) -> Array:
	var vals: Array = d["values"]
	if String(d["kind"]) != "range":
		return vals.map(func(v: Variant) -> String: return String(v))
	var step := int(vals[2]) if vals.size() > 2 and int(vals[2]) > 0 else 1
	var out: Array = []
	for n in range(int(vals[0]), int(vals[1]) + 1, step):
		out.append(str(n))
	return out


## Forget the chosen value and the kept preview and delivery (the screen
## closed, or a new reign): the next refresh starts from the decree.
func reset() -> void:
	_chosen = ""
	_preview_key = ""
	_delivery_key = ""


## Read the state again: the decreed value, the delivery, the effects and the
## preview of the chosen value (each recomputed only when what it reads moved).
## `places` is the screen's signature of the realm's recipients (provinces and
## land units held now), so a same-day change of either is read again.
func refresh(places := "") -> void:
	var repo := Game.data
	var state := Game.state
	if state == null or _law == "":
		return
	var decreed := LawSystem.decreed(repo, state, _law)
	if _chosen == "":
		_chosen = decreed
	_select(_chosen)
	%Decreed.text = LawSystem.value_label(repo, decreed)
	var id := int((state.law_decree.get(_law, {}) as Dictionary).get("decree_id", 0))
	var dkey := "%d|%d|%d|%d|%s" % [state.tick, state.day, state.couriers.size(), id, places]
	if dkey != _delivery_key:
		_delivery_key = dkey
		_delivery = LawSystem.delivery(repo, state, _law)
	%Delivery.text = _delivery_words(_delivery)
	# Places only while something is outstanding: a courier riding, a place
	# lost or not sent
	%Places.visible = int(_delivery["riding"]) + (_delivery["missing"] as Array).size() > 0
	var pkey := "%s|%s|%d|%d|%d|%d|%d|%s" % [_chosen, decreed, id, state.tick, state.day,
		state.couriers.size(), int(float(state.metrics.get("treasury", 0.0))), places]
	if pkey != _preview_key:
		_preview_key = pkey
		_preview = LawSystem.preview(repo, state, _law, _chosen)
	# The note under the row speaks only while the player decides: the chosen
	# value's effects when it differs from the decree, its cost or the real
	# reason it cannot be sent; the decreed value itself says nothing (the
	# Decree button's tooltip says why it is greyed).
	var differs := _chosen != decreed
	var summary := LawEffects.summary(repo, _law, _chosen) if differs else ""
	%Effects.text = "%s: %s" % [_word("effects"), summary] if summary != "" else ""
	var why := String(_preview["refusal"])
	var unchanged := String(_preview.get("refusal_key", "")) == "unchanged"
	%Preview.text = "" if unchanged else (refusal_words(_preview) if why != "" else _cost_words(_preview))
	%Decree.disabled = why != ""
	%Decree.tooltip_text = refusal_words(_preview) if unchanged else ""
	%Effects.visible = %Effects.text != ""
	%Preview.visible = %Preview.text != ""
	%Notes.visible = %Effects.visible or %Preview.visible


## "20 / 20 provinces"; "8 / 10 camps and 3 / 5 units in the field"; then
## " · 6 couriers riding · the last in 5 days" while any ride, " · 1 lost".
func _delivery_words(d: Dictionary) -> String:
	var kinds: Dictionary = d["kinds"]
	var parts: PackedStringArray = []
	for kind: String in ["province", "town", "unit"]:
		if kinds.has(kind):
			var k: Dictionary = kinds[kind]
			parts.append("%d / %d %s" % [int(k["reached"]), int(k["total"]),
				_word({"province": "provinces", "town": "camps", "unit": "units_in_the_field"}[kind])])
	var text := (" %s " % _word("and")).join(parts) if not parts.is_empty() \
		else "0 / 0 %s" % _word("provinces" if String(LawSystem.def(Game.data, _law)["scope"]) == "province" else "camps")
	var riding := int(d["riding"])
	if riding > 0:
		var last := int(d["last_days"])
		text += " · %d %s · %s %d %s" % [riding, _word("couriers_riding"), _word("last_in"), last,
			_word("day") if last == 1 else _word("days")]
	if int(d["lost"]) > 0:
		text += " · %d %s" % [int(d["lost"]), _word("lost")]
	if int(d["not_sent"]) > 0:
		text += " · %d %s" % [int(d["not_sent"]), _word("not_sent")]
	return text


## A preview's refusal in law_words.csv's words (`refusal_<key>`, a cooldown's
## {n} {days} filled in); the engine's own sentence for a key with no words.
static func refusal_words(p: Dictionary) -> String:
	var key := "refusal_" + String(p.get("refusal_key", ""))
	if not Game.data.law_words.has(key):
		return String(p.get("refusal", ""))
	var n := int(p.get("wait_days", 0))
	return String(Game.data.law_words[key]).format({"n": n, "days": _word("day") if n == 1 else _word("days")})


## "20 couriers · 40 gold · order 5 gold · 9 days at most".
func _cost_words(p: Dictionary) -> String:
	var n := int(p["couriers"])
	return "%d %s · %d %s · %s %d %s · %d %s" % [n, _word("courier") if n == 1 else _word("couriers"),
		int(p["fee"]), _word("gold"), _word("order"), int(p["gold"]), _word("gold"),
		int(p["max_days"]), _word("days_at_most")]


func _on_chosen(index: int) -> void:
	_chosen = String(%Choice.get_item_metadata(index))
	refresh()


func _select(value: String) -> void:
	var menu: OptionButton = %Choice
	for i in menu.item_count:
		if String(menu.get_item_metadata(i)) == value:
			if menu.selected != i:
				menu.select(i)
			return


static func _word(key: String) -> String:
	return String(Game.data.law_words.get(key, key))


## Test seams.
func law() -> String:
	return _law

func choice() -> OptionButton:
	return %Choice

func decree_button() -> Button:
	return %Decree

func places_button() -> Button:
	return %Places

func group_title() -> Label:
	return %GroupTitle

func decreed_text() -> String:
	return %Decreed.text

func delivery_text() -> String:
	return %Delivery.text

func effects_text() -> String:
	return %Effects.text

func preview_text() -> String:
	return %Preview.text
