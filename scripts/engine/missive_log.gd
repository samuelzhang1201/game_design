class_name MissiveLog
extends RefCounted
## The crown's letters (owner 2026-09-28, spec docs/superpowers/specs/2026-09-28-missive-board-and-spies-design.md):
## GameState.missives, the one writer. Each column keeps missive_keep_per_column
## letters; the oldest leaves when one more arrives. Whole numbers and strings only.

const COLUMNS := ["truth", "credible", "consult", "rumour"]
## The marshal's letters: capped apart (missive_keep_supply), so a campaign's
## daily dispatches never push a spy's report or a receipt off a column.
const SUPPLY_KINDS := ["supply", "supply_month"]
## The battle reports (spec 2026-10-07-enemy-ai-and-battle §4.5), a letter a
## day for as long as a fight lasts: capped apart too (missive_keep_battle).
const BATTLE_KINDS := ["battle", "king_report"]
## A decree's letters (laws spec §3: its sending and its reach): capped apart
## too (missive_keep_law), so a decree to every camp never pushes a spy's
## report or a receipt off a column.
const LAW_KINDS := ["law"]
## The couriers' receipts (owner 2026-10-10: the crown's own orders are ground
## truth): capped apart too (missive_keep_receipt), so a campaign's orders
## never push the steward's monthly report off the truth column.
const RECEIPT_KINDS := ["receipt"]
## The scouts' and contact letters (spec 2026-10-14-unit-clearance-and-scouting-
## design §c): capped apart too (missive_keep_scout), so a march across the
## border never pushes a spy's report or a receipt off a column.
const SCOUT_KINDS := ["scout", "contact"]


## Which cap a kind of letter counts against: "supply", "battle", "law",
## "receipt", "scout", or "" for the rest (missive_keep_per_column).
static func keep_group(kind: String) -> String:
	if kind in SCOUT_KINDS:
		return "scout"
	if kind in RECEIPT_KINDS:
		return "receipt"
	if kind in SUPPLY_KINDS:
		return "supply"
	if kind in BATTLE_KINDS:
		return "battle"
	if kind in LAW_KINDS:
		return "law"
	return ""


static func _keep_key(group: String) -> String:
	match group:
		"supply":
			return "missive_keep_supply"
		"battle":
			return "missive_keep_battle"
		"law":
			return "missive_keep_law"
		"receipt":
			return "missive_keep_receipt"
		"scout":
			return "missive_keep_scout"
	return "missive_keep_per_column"


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
	# missive_keep_supply, battle reports against missive_keep_battle, a
	# decree's letters against missive_keep_law, every other kind against
	# missive_keep_per_column.
	var group := keep_group(String(entry["kind"]))
	var keep := maxi(1, int(repo.bal(_keep_key(group))))
	var mine := column(state, String(entry["column"])).filter(
		func(lt: Dictionary) -> bool: return keep_group(String(lt["kind"])) == group)
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


## The letters the player has not yet SEEN (owner 2026-10-10: 括号的数字只显示
## 玩家没看过的): ids above GameState.missives_seen_id not marked `seen` one by
## one. The MISSIVE tab's count; `read` is the note's own gold edge, apart.
static func unseen(state: GameState) -> int:
	var n := 0
	for m: Dictionary in state.missives:
		if int(m["id"]) > state.missives_seen_id and not bool(m.get("seen", false)):
			n += 1
	return n


## Mark letters seen: every letter so far (id < 0: the board was shown), or
## one letter (a spy's report opened in its dialog). Returns whether the count
## of unseen letters can have changed.
static func mark_seen(state: GameState, id := -1) -> bool:
	if id < 0:
		if state.missives_seen_id >= state.next_missive_id:
			return false
		state.missives_seen_id = state.next_missive_id
		for m: Dictionary in state.missives:
			m.erase("seen")   # the mark covers them now
		return true
	var m := find(state, id)
	if m.is_empty() or id <= state.missives_seen_id or bool(m.get("seen", false)):
		return false
	m["seen"] = true
	return true


static func mark_read(state: GameState, id: int) -> void:
	var m := find(state, id)
	if not m.is_empty():
		m["read"] = true

## Only already-filtered report data is attached to a local or delivered missive.
static func battle_payload(letter: Dictionary, payload: Dictionary) -> Dictionary:
	for key: String in ["battle_id", "details", "settlements"]:
		if payload.has(key): letter[key] = payload[key].duplicate(true) if payload[key] is Dictionary or payload[key] is Array else payload[key]
	return letter
