class_name PrisonerPanel
extends Control

signal action_requested(code: String, params: Dictionary)
signal character_selected(id: String)
signal closed
var _view: Dictionary = {}

func _ready() -> void:
	%Close.pressed.connect(func() -> void: hide(); closed.emit())
	%Batch.item_selected.connect(_batch_selected)
	%Reciprocal.item_selected.connect(_reciprocal_selected)
	%Kind.item_selected.connect(_kind_selected)
	%Proposal.item_selected.connect(_proposal_selected)
	%People.meta_clicked.connect(func(meta: Variant) -> void: character_selected.emit(String(meta)))
	for list: ItemList in [%Names, %OtherNames]:
		list.item_activated.connect(func(index: int) -> void: character_selected.emit(String(list.get_item_metadata(index))))
	%Propose.pressed.connect(_propose)
	%Accept.pressed.connect(_respond.bind(true))
	%Reject.pressed.connect(_respond.bind(false))
	%Settle.pressed.connect(func() -> void:
		if not %Settle.disabled: action_requested.emit("PRISONER_SETTLE", {"proposal_id":_proposal_id()}))

func show_view(view: Dictionary) -> void:
	_view = view
	%Summary.text = "%s reported held; %s historical captures.\nReleased people become civilians; historical battle totals stay unchanged." % [UiPalette.format_int(int(view.get("current_count", 0))), UiPalette.format_int(int(view.get("historical_captured", 0)))]
	var selected := _selected(%Batch)
	var old_id := String(selected.get("id", ""))
	var remembered := _remember(%Batch, %Count, %Wounded, %Names)
	var reciprocal := _remember(%Reciprocal, %OtherCount, %OtherWounded, %OtherNames)
	%Batch.clear()
	%Reciprocal.clear()
	for batch: Dictionary in view.get("batches", []):
		%Batch.add_item("%s — %s from %s" % [batch.get("holder_label", "The holding regiment"), _people(int(batch.get("count", 0))), batch.get("origin_label", batch.get("origin_realm", ""))])
		%Batch.set_item_metadata(%Batch.item_count - 1, batch)
		if String(batch.get("id", "")) == old_id: %Batch.select(%Batch.item_count - 1)
	if %Batch.item_count > 0:
		_batch_selected(%Batch.selected)
		_restore(remembered, %Batch, %Count, %Wounded, %Names)
	else:
		%BatchDetails.text = "No known prisoners held by your realm."
		%People.clear()
	if %Reciprocal.item_count > 0:
		for i: int in %Reciprocal.item_count:
			if String(_selected_at(%Reciprocal, i).get("id", "")) == String(reciprocal.get("id", "")): %Reciprocal.select(i)
		_reciprocal_selected(%Reciprocal.selected)
		_restore(reciprocal, %Reciprocal, %OtherCount, %OtherWounded, %OtherNames)
	var previous := _proposal_id()
	%Proposal.clear()
	for proposal: Dictionary in view.get("proposals", []):
		%Proposal.add_item("%s — %s gold (%s)" % [String(proposal.get("kind", "")).capitalize(), UiPalette.format_int(int(proposal.get("request", {}).get("money", 0))), String(proposal.get("status", "proposed")).capitalize()])
		%Proposal.set_item_metadata(%Proposal.item_count - 1, proposal)
		if String(proposal.get("id", "")) == previous: %Proposal.select(%Proposal.item_count - 1)
	_proposal_selected(%Proposal.selected)
	_kind_selected(%Kind.selected)
	%Status.text = ""
	show()

func _selected_at(picker: OptionButton, index: int) -> Dictionary:
	return picker.get_item_metadata(index)

func _selected(picker: OptionButton) -> Dictionary:
	return picker.get_item_metadata(picker.selected) if picker.selected >= 0 else {}

func _batch_selected(_index: int) -> void:
	var batch := _selected(%Batch)
	_fill_selection(batch, %Count, %Wounded, %Names)
	%BatchDetails.text = "Held by: %s (%s). Wounded: %s.\n%s" % [batch.get("holder_label", ""), batch.get("holder_realm_label", batch.get("holder_realm", "")), UiPalette.format_int(int(batch.get("wounded_count", 0))), "Seen here." if bool(batch.get("current_verified", false)) else "Last reported %s; custody may have changed. Orders will be rechecked." % CourierCard.date_of(int(batch.get("observed_day", 0)))]
	if String(batch.get("holder_realm", "")) != String(_view.get("player_realm", "")):
		%BatchDetails.text += "\nOnly the holding realm can propose terms. We may respond when their proposal arrives."
	%Reciprocal.clear()
	for other: Dictionary in _view.get("batches", []):
		if other.get("holder_realm", "") != batch.get("origin_realm", "") or other.get("origin_realm", "") != _view.get("player_realm", ""): continue
		%Reciprocal.add_item("%s — %s" % [other.get("holder_label", ""), _people(int(other.get("count", 0)))])
		%Reciprocal.set_item_metadata(%Reciprocal.item_count - 1, other)
	if %Reciprocal.item_count > 0: _reciprocal_selected(%Reciprocal.selected)
	_kind_selected(%Kind.selected)
	%People.clear()
	for person: Dictionary in batch.get("named", []):
		%People.push_meta(String(person.id))
		%People.add_text(String(person.name))
		%People.pop()
		%People.add_text("\n")

func _reciprocal_selected(_index: int) -> void:
	_fill_selection(_selected(%Reciprocal), %OtherCount, %OtherWounded, %OtherNames)

func _fill_selection(batch: Dictionary, count: SpinBox, wounded: SpinBox, names: ItemList) -> void:
	count.max_value = int(batch.get("count", 0))
	count.value = count.max_value
	wounded.max_value = int(batch.get("wounded_count", 0))
	wounded.value = wounded.max_value
	names.clear()
	for person: Dictionary in batch.get("named", []):
		names.add_item(String(person.name))
		names.set_item_metadata(names.item_count - 1, String(person.id))
		names.select(names.item_count - 1, false)
	names.visible = names.item_count > 0

func _kind_selected(index: int) -> void:
	%Exchange.visible = index == 1
	%Price.visible = index == 0
	%Propose.disabled = %Batch.item_count == 0 or String(_selected(%Batch).get("holder_realm", "")) != String(_view.get("player_realm", "")) or (index == 1 and %Reciprocal.item_count == 0)

func _selection(batch: Dictionary, count: SpinBox, wounded: SpinBox, names: ItemList) -> Dictionary:
	var ids: Array = []
	for index: int in names.get_selected_items(): ids.append(String(names.get_item_metadata(index)))
	return {"batch_id":String(batch.get("id", "")), "count":int(count.value), "wounded_count":int(wounded.value), "named_ids":ids}

func _remember(picker: OptionButton, count: SpinBox, wounded: SpinBox, names: ItemList) -> Dictionary:
	if picker.selected < 0: return {}
	return _selection(_selected(picker), count, wounded, names).merged({"id":_selected(picker).get("id", "")})

func _restore(previous: Dictionary, picker: OptionButton, count: SpinBox, wounded: SpinBox, names: ItemList) -> void:
	if previous.is_empty() or previous.id != _selected(picker).get("id", ""): return
	count.value = mini(int(previous.count), int(count.max_value))
	wounded.value = mini(int(previous.wounded_count), int(wounded.max_value))
	names.deselect_all()
	for index: int in names.item_count:
		if String(names.get_item_metadata(index)) in previous.named_ids: names.select(index, false)

func _propose() -> void:
	if %Propose.disabled: return
	var batch := _selected(%Batch)
	var kind := ["ransom", "exchange", "release"][%Kind.selected] as String
	var reason := String(%Reason.text).strip_edges()
	if reason.is_empty():
		%Status.text = "Give a reason for these terms."
		return
	var batches: Array = [_selection(batch, %Count, %Wounded, %Names)]
	if kind == "exchange": batches.append(_selection(_selected(%Reciprocal), %OtherCount, %OtherWounded, %OtherNames))
	var terms: Dictionary = {}
	if %Promise.button_pressed: terms["no_fighting_until_day"] = int(%Until.value)
	action_requested.emit("PRISONER_PROPOSE", {"id":String(_view.get("next_proposal_id", "")), "kind":kind, "batches":batches,
		"money":int(%Money.value) if kind == "ransom" else 0, "parties":{"proposer":String(_view.get("player_realm", "")), "payer":String(batch.get("origin_realm", "")) if kind == "ransom" else ""}, "terms":terms, "reason":reason})

func _proposal_id() -> String:
	return String(_selected(%Proposal).get("id", ""))

func _proposal_selected(_index: int) -> void:
	var proposal := _selected(%Proposal)
	var status := String(proposal.get("status", ""))
	var mine := String(_view.get("player_realm", ""))
	var required: Array = proposal.get("required_parties", [])
	var consents: Dictionary = proposal.get("consents", {})
	var pending := status == "proposed" and mine in required and not consents.has(mine)
	%Accept.disabled = not pending
	%Reject.disabled = not pending
	%Settle.disabled = status != "accepted"
	if proposal.is_empty():
		%ProposalDetails.text = "No proposed agreements. A proposal alone pays nothing and releases nobody."
		return
	var request: Dictionary = proposal.get("request", {})
	var lines: PackedStringArray = [status.capitalize() + ". Agreed price: " + UiPalette.format_int(int(request.get("money", 0))) + " gold.", String(request.get("reason", ""))]
	if status == "fulfilling": lines.append("Instructions are riding to the holders; await their receipt.")
	if status in ["rejected", "failed", "unconfirmed"]: lines.append(String(proposal.get("reason", "The agreement could not be fulfilled.")))
	for party: String in required:
		var label := String(_view.get("realm_labels", {}).get(party, party))
		lines.append(label + ": " + ("accepted" if bool(consents[party]) else "rejected") if consents.has(party) else label + ": awaiting decision")
	for selection: Dictionary in request.get("batches", []):
		lines.append("Selected: %s, including %s wounded; named people: %s." % [_people(int(selection.get("count", 0))), UiPalette.format_int(int(selection.get("wounded_count", 0))), UiPalette.format_int(selection.get("named_ids", []).size())])
	var terms: Dictionary = request.get("terms", {})
	if terms.has("no_fighting_until_day"):
		lines.append("Promise not to fight: indefinitely." if int(terms.no_fighting_until_day) == 0 else "Promise not to fight through %s." % CourierCard.date_of(int(terms.no_fighting_until_day)))
	var valuation: Dictionary = proposal.get("valuation", {})
	if not valuation.is_empty(): lines.append("Negotiation reference: %s gold; payer capacity: %s gold." % [UiPalette.format_int(int(valuation.get("asking_gold", 0))), UiPalette.format_int(int(valuation.get("affordable_gold", 0)))])
	if status == "fulfilled":
		var receipt: Dictionary = proposal.get("result", {})
		lines.append("Fulfilled: %s released as civilians. %s" % [_people(int(receipt.get("released", 0))), receipt.get("reason", "")])
		for payment: Dictionary in receipt.get("payments", []):
			lines.append("%s: captor received %s gold; crown received %s gold. %s" % [payment.get("holder_label", "The holding regiment"), UiPalette.format_int(int(payment.get("captor_gold", 0))), UiPalette.format_int(int(payment.get("crown_gold", 0))), payment.get("reason", "")])
	%ProposalDetails.text = "\n".join(lines)

func _respond(accepted: bool) -> void:
	if (%Accept.disabled if accepted else %Reject.disabled): return
	action_requested.emit("PRISONER_RESPOND", {"proposal_id":_proposal_id(), "accepted":accepted})

func show_result(result: Dictionary) -> void:
	%Status.text = String(result.get("reason", result.get("error", result.get("status", "Request recorded."))))

static func _people(count: int) -> String:
	return "%s %s" % [UiPalette.format_int(count), "person" if count == 1 else "people"]
