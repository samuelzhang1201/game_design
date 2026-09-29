class_name LedgerOrderMenu
extends PopupMenu
## The LEDGER's right-click orders (spec 2026-09-30 §5): one row per
## data/ledger_actions.csv row, its gold cost written beside it. PopupMenu
## hides BEFORE it emits id_pressed, so the node and rows are kept past the
## hide and replaced only by the next open.

signal chosen(node_id: String, row: Dictionary)

var _node := ""
var _rows: Array = []


func _ready() -> void:
	id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < _rows.size():
			chosen.emit(_node, _rows[id]))


func open_for(node_id: String, rows: Array, at: Vector2) -> void:
	_node = node_id
	_rows = rows
	clear()
	for i in rows.size():
		var row: Dictionary = rows[i]
		add_item(Ledger.order_text(Game.data, row, node_id), i)
	popup_on_parent(Rect2i(Vector2i(at.round()), Vector2i(1, 1)))
