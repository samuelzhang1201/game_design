class_name NewsTicker
extends Control
## Persistent chronicle strip (user request 2026-08-31): a TRANSPARENT band
## pinned to the bottom of every gameplay screen, just above the bottom tab
## bar, where realm news crawls slowly right-to-left. Purely presentational:
## it listens to Game.news_published (the Royal Chronicle feeds it as the
## day-run rolls) and never touches sim state or the campaign RNG. Crawl
## speed is balance data (news_ticker_speed), not a hardcoded constant.

const STRIP_HEIGHT := 32.0
const MAX_ITEMS := 12
const SEPARATOR := "      +      "

var _label: Label
var _items: Array = []
var _speed := 18.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -(BottomBar.BAR_HEIGHT + STRIP_HEIGHT)
	offset_bottom = -BottomBar.BAR_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if Game.data != null:
		_speed = Game.data.bal("news_ticker_speed")
	var bg := ColorRect.new()
	bg.name = "TickerBg"
	bg.color = UiPalette.GLASS_BG_SOFT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.name = "CrawlLabel"
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_label.position = Vector2(size.x, 3)
	add_child(_label)
	Game.news_published.connect(add_item)

## Appends one headline to the crawl (oldest fall off past MAX_ITEMS). The
## crawl position is left alone so a new item never makes the line jump.
func add_item(text: String) -> void:
	if text.strip_edges() == "":
		return
	_items.append(text)
	while _items.size() > MAX_ITEMS:
		_items.pop_front()
	_label.text = SEPARATOR.join(_items)
	_label.reset_size()

func _process(delta: float) -> void:
	if _label.text == "":
		return
	_label.position.x -= _speed * delta
	if _label.position.x + _label.size.x < 0.0:
		_label.position.x = size.x

## Test seams.
func crawl_label() -> Label:
	return _label

func items() -> Array:
	return _items.duplicate()

func speed() -> float:
	return _speed
