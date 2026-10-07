class_name MissiveLog
extends RefCounted
## The crown's letters (owner 2026-09-28, spec docs/superpowers/specs/2026-09-28-missive-board-and-spies-design.md):
## GameState.missives, the one writer. Each column keeps missive_keep_per_column
## letters; the oldest leaves when one more arrives. Whole numbers and strings only.

const COLUMNS := ["truth", "credible", "consult", "rumour"]
## The marshal's letters: capped apart (missive_keep_supply), so a campaign's
## daily dispatches never push a spy's report or a receipt off a column.
const SUPPLY_KINDS := ["supply", "supply_month"]


static func subject(kind: String, code: String, cell: int, px: Vector2) -> Dictionary:
	return {"kind": kind, "code": code, "cell": cell, "x": roundi(px.x), "y": roundi(px.y)}


static func exact(key: String, label: String, value: int) -> Dictionary:
	return {"key": key, "label": label, "exact": value}


static func span(key: String, label: String, lo: int, hi: int) -> Dictionary:
	return {"key": key, "label": label, "lo": lo, "hi": hi}


static func words(key: String, label: String, text: String) -> Dictionary:
	return {"key": key, "label": label, "text": text}


static func make(kind: String, col: String, day: int, subj: Dictionary, title: String,
		facts: Array) -> Dictionary:
	return {"kind": kind, "column": col, "day": day, "subject": subj, "title": title,
		"facts": facts.duplicate(true)}


## File a letter: a fresh id, unread, then the column's cap. Returns the id.
static func add(repo: DataRepository, state: GameState, m: Dictionary) -> int:
	state.next_missive_id += 1
	var entry := m.duplicate(true)
	entry["id"] = state.next_missive_id
	entry["read"] = false
	state.missives.append(entry)
	# The cap counts the new letter's own sort: supply letters against
	# missive_keep_supply, every other kind against missive_keep_per_column.
	var supply := String(entry["kind"]) in SUPPLY_KINDS
	var keep := maxi(1, int(repo.bal("missive_keep_supply" if supply else "missive_keep_per_column")))
	var mine := column(state, String(entry["column"])).filter(
		func(m: Dictionary) -> bool: return (String(m["kind"]) in SUPPLY_KINDS) == supply)
	for i in range(keep, mine.size()):
		state.missives.erase(mine[i])
	return state.next_missive_id


## A column's letters, newest (highest id) first.
static func column(state: GameState, col: String) -> Array:
	var out: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m["column"]) == col)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	return out


static func find(state: GameState, id: int) -> Dictionary:
	for m: Dictionary in state.missives:
		if int(m["id"]) == id:
			return m
	return {}


static func unread(state: GameState) -> int:
	var n := 0
	for m: Dictionary in state.missives:
		if not bool(m.get("read", false)):
			n += 1
	return n


static func mark_read(state: GameState, id: int) -> void:
	var m := find(state, id)
	if not m.is_empty():
		m["read"] = true
