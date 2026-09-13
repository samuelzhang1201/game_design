class_name NameForge
extends RefCounted
## Place names in a culture's style (owner 2026-09-13: every manor has a
## proper name the player can say). The Azgaar export carries `nameBases` —
## banks of real place names, one per culture — and Azgaar named the burgs
## by walking a letter Markov chain over its bank; this does the same, so a
## manor sounds like the town beside it. Order-2 chain: the next letter is
## drawn from what followed the last two letters anywhere in the bank.
## Pure: the caller hands in the RandomNumberGenerator, seeded from the map
## seed and the cell id, so the same pack forges the same names every time.

const END := "$"
const TRIES := 24

## The chain over `bank`: {"starts": [first two letters of each name],
## "next": {two letters: [what followed, END for a name's end]}}.
static func chain(bank: PackedStringArray) -> Dictionary:
	var starts: Array = []
	var next: Dictionary = {}
	for raw in bank:
		var name := raw.strip_edges().to_lower()
		if name.length() < 2:
			continue
		starts.append(name.substr(0, 2))
		for i in range(2, name.length() + 1):
			var gram := name.substr(i - 2, 2)
			var ch := name.substr(i, 1) if i < name.length() else END
			if not next.has(gram):
				next[gram] = []
			(next[gram] as Array).append(ch)
	return {"starts": starts, "next": next}

## One name from the chain, min_len..max_len letters, capitalised. Empty
## when the chain is empty.
static func forge(model: Dictionary, rng: RandomNumberGenerator, min_len: int, max_len: int) -> String:
	var starts: Array = model.get("starts", [])
	var next: Dictionary = model.get("next", {})
	if starts.is_empty():
		return ""
	var best := ""
	for attempt in TRIES:
		var s: String = starts[rng.randi_range(0, starts.size() - 1)]
		while s.length() < max_len:
			var opts: Array = next.get(s.substr(s.length() - 2, 2), [])
			if opts.is_empty():
				break
			var ch: String = opts[rng.randi_range(0, opts.size() - 1)]
			if ch == END:
				if s.length() >= min_len:
					break
				# Too short to end here: carry on with a letter if one follows
				# this pair anywhere in the bank.
				var alive: Array = opts.filter(func(c: String) -> bool: return c != END)
				if alive.is_empty():
					break
				ch = alive[rng.randi_range(0, alive.size() - 1)]
			s += ch
		if s.length() >= min_len:
			return pretty(s)
		if s.length() > best.length():
			best = s
	return pretty(best)

## A name no one in `taken` (lower-cased labels) has: forged again while it
## clashes, and past TRIES joined to a second forged word ("Aldern Wick"),
## which is how a country runs out of short names and starts using long ones.
static func forge_unique(model: Dictionary, rng: RandomNumberGenerator, min_len: int, max_len: int,
		taken: Dictionary) -> String:
	var first := ""
	for attempt in TRIES:
		var s := forge(model, rng, min_len, max_len)
		if s == "":
			return ""
		if first == "":
			first = s
		if not taken.has(s.to_lower()):
			return s
	while true:
		var s := first + " " + forge(model, rng, mini(min_len, 3), max_len)
		if not taken.has(s.to_lower()):
			return s
	return first

## "aldern wick" -> "Aldern Wick": a capital after the start, a space, a
## hyphen or an apostrophe.
static func pretty(s: String) -> String:
	var out := ""
	var cap := true
	for ch in s:
		out += ch.to_upper() if cap else ch
		cap = ch in [" ", "-", "'"]
	return out

## "Aldern Wick" -> "aldern_wick": the code a label is referred to by.
static func slug(label: String) -> String:
	var out := ""
	var gap := false
	for ch in label.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			if gap and out != "":
				out += "_"
			gap = false
			out += ch
		else:
			gap = true
	return out
