class_name BattleReportPanel
extends Control

signal closed
var _reports: Array = []
var _report: Dictionary = {}

func _ready() -> void:
	%Close.pressed.connect(func() -> void: hide(); closed.emit())
	%Report.item_selected.connect(_selected)

func show_view(view: Dictionary) -> void:
	_reports = view.get("detailed_reports", [])
	var previous: int = %Report.selected
	%Report.clear()
	for report: Dictionary in _reports:
		%Report.add_item("%s — day %s" % [report.get("place", ""), _number(report.get("end_day"))])
	if _reports.is_empty(): %Summary.text = "No detailed battle report has been delivered or witnessed locally."
	else:
		%Report.select(clampi(previous, 0, _reports.size() - 1))
		_selected(%Report.selected)
	show()

func _selected(index: int) -> void:
	if index < 0 or index >= _reports.size(): return
	_report = _reports[index]
	var lines: PackedStringArray = ["%s — %s days (day %s–%s)" % [_report.get("place", ""), _number(_report.get("duration_days")), _number(_report.get("start_day")), _number(_report.get("end_day"))], "Historical battle snapshot; later releases do not rewrite these totals."]
	if _report.has("received_day"): lines.append("Report received %s." % CourierCard.date_of(int(_report.received_day)))
	var personnel: Dictionary = _report.get("personnel", {})
	var own: Dictionary = personnel.get("own", {})
	if not own.is_empty():
		lines.append("Participants: %s\nFit: %s     Wounded: %s\nDead: %s     Captured: %s\nReleased during battle: %s." % [_number(own.get("participants")), _number(own.get("fit")), _number(own.get("wounded")), _number(own.get("dead")), _number(own.get("captured")), _number(own.get("released"))])
	var enemy: Dictionary = personnel.get("enemy", {})
	if not enemy.is_empty(): lines.append("Enemy losses (reported estimates): %s dead; %s wounded." % [_number(enemy.get("dead")), _number(enemy.get("wounded"))])
	lines.append("PARTICIPANTS")
	for unit: Dictionary in _report.get("participants", []):
		lines.append("%s, commanded by %s; joined on day %s." % [unit.get("label", "The regiment"), unit.get("commander", "the field officers"), _number(unit.get("day"))])
	for unit: Dictionary in _report.get("reinforcements", []):
		lines.append("Reinforcement: %s, day %s. %s" % [_unit(String(unit.get("unit", ""))), _number(unit.get("day")), unit.get("reason", "")])
	lines.append("FORMATION AND COMMAND")
	for formation: Dictionary in _report.get("formations", {}).values():
		lines.append("Formation: " + _words(String(formation.get("current", "unreported"))))
	for order: Dictionary in _report.get("orders", []):
		var request: Dictionary = order.get("request", {})
		lines.append("%s — %s. %s" % [order.get("label", _words(String(request.get("kind", "Order")))), _words(String(order.get("status", "unreported"))), order.get("reason", "")])
	for event: Dictionary in _report.get("events", []):
		lines.append("%s: %s. %s" % [event.get("title", "Battlefield event"), _words(String(event.get("selected", event.get("kind", "recorded")))), event.get("reason", event.get("why", event.get("receipt", {}).get("reason", "")))])
	lines.append("PRISONERS, EQUIPMENT AND SUPPLIES")
	for batch: Dictionary in _report.get("prisoners", []):
		lines.append("%s captured; actual holder: %s; %s wounded within the captured total." % [_number(batch.get("initial_count", batch.get("count"))), batch.get("holder_label", _unit(String(batch.get("holder_code", "")))), _number(batch.get("wounded_subset", batch.get("wounded_count")))])
		for person: Dictionary in batch.get("named", []): lines.append("Named captive: " + String(person.get("name", "")))
	for equipment: Dictionary in _report.get("equipment", []):
		for kind: String in equipment.get("equipment", {}):
			lines.append("Surrendered equipment: %s %s. %s" % [_number(equipment.equipment[kind]), _words(kind), equipment.get("reason", "")])
	for supply: Dictionary in _report.get("supplies", []):
		lines.append("%s supplies: %s → %s." % [_unit(String(supply.get("unit_code", ""))), _number(supply.get("before")), _number(supply.get("after"))])
	lines.append("OUTCOME AND FAMILY TIES")
	var outcome: Dictionary = _report.get("outcome", {})
	lines.append(String(outcome.get("reason", outcome.get("why", outcome.get("result", "No further result recorded.")))))
	if String(outcome.get("winner_label", "")) != "": lines.append("Victorious: " + String(outcome.winner_label))
	if String(outcome.get("town_label", "")) != "": lines.append("Town: " + String(outcome.town_label))
	for change: Dictionary in _report.get("family_changes", []): lines.append("%s: %s. %s" % [change.get("name", "Family standing"), _number(change.get("delta")), change.get("reason", "")])
	lines.append("LATER SETTLEMENTS — separate from the battle totals")
	for settlement: Dictionary in _report.get("settlements", []):
		lines.append("%s. %s" % [_words(String(settlement.get("kind", settlement.get("status", "Settlement")))), settlement.get("reason", "")])
		if settlement.has("released"): lines.append("%s people released as civilians." % _number(settlement.released))
		if settlement.has("strategic"): lines.append("Battlefield spoils: %s." % _number(settlement.strategic))
		for payment: Dictionary in settlement.get("payments", []): lines.append("%s received %s gold; crown received %s gold. %s" % [_unit(String(payment.get("holder_code", ""))), _number(payment.get("captor_gold")), _number(payment.get("crown_gold")), payment.get("reason", "")])
	%Summary.text = "\n\n".join(lines)

func _unit(code: String) -> String:
	for unit: Dictionary in _report.get("participants", []):
		if String(unit.get("code", "")) == code: return String(unit.get("label", "The regiment"))
	return "The reported regiment"

func _number(value: Variant) -> String:
	if value is Dictionary and value.has("lo") and value.has("hi"): return "≈ %s–%s" % [_number(value.lo), _number(value.hi)]
	return UiPalette.format_int(int(value)) if value is int or value is float else "not reported"

func _words(value: String) -> String:
	return value.replace("_", " ").capitalize()
