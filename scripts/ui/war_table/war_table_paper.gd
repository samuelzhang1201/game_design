class_name WarTablePaper
extends Node
## THE WAR TABLE: what a paper column keeps doing while it lives (WarTable's
## ink_column / fit_report) — turning its shared cards' leather ink into paper
## ink as nodes arrive, and drawing the report only as tall as the realm's card.
## A child of the column (internal), so its connections die with the column.

var _column: Control
var _dashboard: RealmDashboard
var _ink_pending := false
var _fit_pending := false

func _enter_tree() -> void:
	_column = get_parent() as Control

func ink() -> void:
	if _column == null:
		_column = get_parent() as Control
	get_tree().node_added.connect(_on_node_added)
	_column.minimum_size_changed.connect(_queue_ink)
	_column.sort_children.connect(_queue_ink)
	_queue_ink()

func fit(dashboard: RealmDashboard) -> void:
	if _column == null:
		_column = get_parent() as Control
	_dashboard = dashboard
	if dashboard == null:
		return
	dashboard.content_resized.connect(_queue_fit)
	dashboard.visibility_changed.connect(_queue_fit)
	_column.resized.connect(_queue_fit)
	_queue_fit()

func _on_node_added(n: Node) -> void:
	if _column != null and _column.is_ancestor_of(n):
		_queue_ink()

func _queue_ink() -> void:
	if not _ink_pending:
		_ink_pending = true
		_ink_now.call_deferred()

func _ink_now() -> void:
	_ink_pending = false
	if _column != null:
		WarTable._ink_node(_column)

func _queue_fit() -> void:
	if not _fit_pending:
		_fit_pending = true
		_fit_now.call_deferred()

func _fit_now() -> void:
	_fit_pending = false
	var style := _column.get_theme_stylebox("panel") as PaperStyle if _column != null else null
	if style == null or not is_instance_valid(_dashboard):
		return
	var h := 0.0
	if _dashboard.is_visible_in_tree():
		h = _dashboard.content_height() + style.content_margin_top + style.content_margin_bottom + 6.0
	style.fit_height = h if h < _column.size.y else 0.0
	_column.queue_redraw()
