class_name WorldLedger
extends RefCounted
## One addressable schema over everything the game can move (spec 2026-09-09
## §2): the player's metrics, the court's opinions and attributes, and the
## pack's domain tables. Paths read `metrics.<name>`, `opinion.<id>`,
## `attribute.<id>.<name>`, or `<domain>.<area>.<code>.<field>`; a code may be
## a realm slot. data/world_schema.csv says what each field is, its range,
## which way is good for the crown, and how far the model may move it.
##
## The pack ships starting values; GameState.world holds only what has moved
## (the province_owner pattern), and an aliased row (the player's treasury)
## has no copy at all — it reads and writes the metric. Engine-pure.

const SEP := "."
const WILDCARD := "*"

## Substitutes realm slots in any segment.
static func resolve(data: DataRepository, path: String) -> String:
	var parts := path.split(SEP)
	for i in parts.size():
		if data.realm_bindings.has(parts[i]):
			parts[i] = String(data.realm_bindings[parts[i]])
	return SEP.join(parts)

## The schema row governing a path: same segment count, every non-wildcard
## segment equal after slot resolution, fewest wildcards wins. {} if none.
## Memoised on the repository (data.schema_cache): the answer is a pure
## function of the pack's schema table and realm bindings, and the search
## is a walk of the whole table.
static func schema_for(data: DataRepository, path: String) -> Dictionary:
	if data.schema_cache.has(path):
		return data.schema_cache[path]
	var row := _match_schema(data, path)
	# The pack's own paths are a few thousand; a caller inventing paths
	# without end starts over rather than growing without bound.
	if data.schema_cache.size() > 8192:
		data.schema_cache.clear()
	data.schema_cache[path] = row
	return row

static func _match_schema(data: DataRepository, path: String) -> Dictionary:
	var parts := resolve(data, path).split(SEP)
	var best: Dictionary = {}
	var best_wild := 1 << 30
	for row: Dictionary in data.world_schema:
		var pat := resolve(data, String(row["path"])).split(SEP)
		if pat.size() != parts.size():
			continue
		var wild := 0
		var ok := true
		for i in parts.size():
			if pat[i] == WILDCARD:
				wild += 1
			elif pat[i] != parts[i]:
				ok = false
				break
		if ok and wild < best_wild:
			best = row
			best_wild = wild
	return best

static func polarity_of(data: DataRepository, path: String) -> int:
	return int(float(schema_for(data, path).get("good_direction", 0)))

static func llm_cap(data: DataRepository, path: String) -> float:
	return float(schema_for(data, path).get("llm_cap", 0))

## The field's current value: an alias reads its truth (scaled), an override
## wins over the pack, the pack row's column is parsed by type. null when the
## path has no schema row or no value behind it.
static func value_of(data: DataRepository, state: GameState, path: String) -> Variant:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return null
	var alias := String(row.get("alias_to", ""))
	if alias != "":
		var truth: Variant = value_of(data, state, alias)
		if truth == null:
			return null
		var key := String(row.get("alias_scale_key", ""))
		return float(truth) / data.bal(key) if key != "" else truth
	if state != null and state.world.has(resolved):
		return state.world[resolved]
	return _base_value(data, state, resolved, row)

static func _base_value(data: DataRepository, state: GameState, resolved: String,
		row: Dictionary) -> Variant:
	var p := resolved.split(SEP)
	match p[0]:
		"metrics":
			if state == null or not state.metrics.has(p[1]):
				return null
			return state.metrics[p[1]]
		"opinion":
			if state == null or not state.characters.has(p[1]):
				return null
			return (state.characters[p[1]] as Character).opinion
		"attribute":
			if state == null or p.size() < 3 or not state.characters.has(p[1]):
				return null
			var attrs: Dictionary = (state.characters[p[1]] as Character).attributes
			return attrs.get(p[2]) if attrs.has(p[2]) else null
	if p.size() != 4:
		return null
	var table_row: Dictionary = data.world_row(p[0], p[1], p[2])
	if table_row.is_empty() or not table_row.has(p[3]):
		return null
	var raw := String(table_row[p[3]])
	match String(row.get("type", "float")):
		"int":
			return int(float(raw))
		"enum":
			return raw
	return float(raw)

## Move a numeric field by delta, clamped to the schema range. Refuses an
## unlisted path, an enum, or an empty reason. Returns the applied change or
## {error}.
static func apply(data: DataRepository, state: GameState, path: String, delta: float,
		reason: String, source: String) -> Dictionary:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return {"error": "no such field: " + path}
	if reason.strip_edges() == "":
		return {"error": "a change needs a reason: " + path}
	var t := String(row.get("type", "float"))
	if t == "enum":
		return {"error": "%s is not numeric" % path}
	var alias := String(row.get("alias_to", ""))
	if alias != "":
		var key := String(row.get("alias_scale_key", ""))
		var scale := data.bal(key) if key != "" else 1.0
		var out := apply(data, state, alias, delta * scale, reason, source)
		if out.has("error"):
			return out
		out["path"] = resolved
		out["delta"] = float(out["delta"]) / scale
		out["value"] = float(out["value"]) / scale
		return out
	var current: Variant = value_of(data, state, resolved)
	if current == null:
		return {"error": "no value behind " + path}
	var lo := float(row["min"]) if String(row.get("min", "")) != "" else -INF
	var hi := float(row["max"]) if String(row.get("max", "")) != "" else INF
	var target := clampf(float(current) + delta, lo, hi)
	if t == "int":
		target = roundf(target)
	var applied := target - float(current)
	_write(state, resolved, target, applied, reason)
	state.world_log.append({"tick": state.tick, "path": resolved, "delta": applied,
		"reason": reason, "source": source})
	return {"path": resolved, "delta": applied, "value": target, "reason": reason,
		"source": source}

## Set an enum field to one of its listed values.
static func set_enum(data: DataRepository, state: GameState, path: String, value: String,
		reason: String, source: String) -> Dictionary:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return {"error": "no such field: " + path}
	if String(row.get("type", "")) != "enum":
		return {"error": "%s is not an enum" % path}
	if reason.strip_edges() == "":
		return {"error": "a change needs a reason: " + path}
	var legal := String(row.get("enum_values", "")).split("|", false)
	if not legal.is_empty() and not value in legal:
		return {"error": "%s is not a legal %s" % [value, path]}
	state.world[resolved] = value
	state.world_log.append({"tick": state.tick, "path": resolved, "delta": 0.0,
		"value": value, "reason": reason, "source": source})
	return {"path": resolved, "delta": 0.0, "value": value, "reason": reason, "source": source}

static func _write(state: GameState, resolved: String, target: float, applied: float,
		reason: String) -> void:
	var p := resolved.split(SEP)
	match p[0]:
		"metrics":
			state.metrics[p[1]] = target
		"opinion":
			(state.characters[p[1]] as Character).change_opinion(roundi(applied), reason, state.tick)
		"attribute":
			(state.characters[p[1]] as Character).change_attribute(p[2], roundi(applied), reason,
				state.tick)
		_:
			state.world[resolved] = target

## Whether the field is the player's to move: metrics, opinions, and attributes
## always are; a kingdom row must be the player's realm; a province or burg row
## must lie in land the player holds NOW (MapOwnership).
static func belongs_to_player(data: DataRepository, state: GameState, path: String) -> bool:
	var p := resolve(data, path).split(SEP)
	if p[0] in ["metrics", "opinion", "attribute"]:
		return true
	if p.size() != 4:
		return false
	var mine := data.resolve_realm("player_realm")
	# The crown's economy is the provinces it CONTROLS (owner 2026-09-13:
	# the king starts with the capital's province and nothing more); the
	# host is the realm's, so military figures stay the kingdom's.
	match p[1]:
		"kingdoms":
			return p[2] == mine and p[0] == "military"
		"provinces":
			return MapManors.crown_controls(data, state, p[2])
		"burgs":
			var b: Dictionary = data.burgs.get(p[2], {})
			return MapManors.crown_controls(data, state, String(b.get("province_code", "")))
	return false

## The model-writable fields for the order prompt: one line per field with
## its current value and cap, wildcard kingdom rows expanded for the player's
## realm, plus the codes the model may put in a province or burg path.
static func prompt_catalog(data: DataRepository, state: GameState) -> String:
	var lines: Array[String] = []
	for row: Dictionary in data.world_schema:
		var cap := float(row.get("llm_cap", 0))
		if cap <= 0.0:
			continue
		var pat := String(row["path"])
		var parts := pat.split(SEP)
		if parts.size() == 4 and parts[1] == "kingdoms" and parts[2] == WILDCARD:
			parts[2] = "player_realm"
			pat = SEP.join(parts)
		if pat.contains(WILDCARD):
			lines.append("- %s (cap %s)" % [pat.replace(WILDCARD, "<code>"), _fmt(cap)])
			continue
		var v: Variant = value_of(data, state, pat)
		if v == null:
			continue
		lines.append("- %s = %s (cap %s)" % [pat, _fmt(float(v)), _fmt(cap)])
	var mine := data.resolve_realm("player_realm")
	# The crown's own provinces are the ones the model may write to; the
	# rest of the realm is named so the model does not think them foreign.
	lines.append("Your provinces: " + ", ".join(MapManors.controlled_provinces(data, state)))
	lines.append("Other provinces of your realm (not yours to change): " + ", ".join(
		MapOwnership.provinces_of(data, state, mine).filter(
			func(c: String) -> bool: return not MapManors.crown_controls(data, state, c))))
	var towns: Array = []
	for code: String in data.burgs:
		var b: Dictionary = data.burgs[code]
		if MapOwnership.owner_of(data, state, String(b["province_code"])) == mine:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	for i in mini(towns.size(), int(data.bal("order_prompt_max_burgs"))):
		names.append(String(towns[i]["burg_code"]))
	lines.append("Your largest towns: " + ", ".join(names))
	return "\n".join(lines)

## One truth (owner ruling 2026-09-09): the player's realm starts with the
## pack's own treasury and tax rates, converted by balance factors. A pack
## without an economy row leaves balance.csv's start values in place.
static func seed_metrics(data: DataRepository, state: GameState) -> void:
	var row: Dictionary = data.world_row("economy", "kingdoms", data.resolve_realm("player_realm"))
	if row.is_empty():
		return
	# The chest holds what the crown's OWN provinces' towns hold (owner
	# 2026-09-13: the starting economy is the capital province's), scaled
	# like the pack's kingdom treasury was; the rates are still the realm's.
	# Two purses (owner 2026-09-14): the LORD's holds what the towns of the
	# player's own provinces hold; the CROWN's treasury its share of the rest
	# of the realm's towns, as the month's settlement shares their taxes.
	var scale := data.bal("pack_treasury_scale")
	state.metrics["lord_gold"] = roundf(crown_town_treasury(data, state) * scale * data.bal("start_lord_gold_scale"))
	state.metrics["treasury"] = roundf(realm_share_town_treasury(data, state) * scale)
	state.metrics["tax_rate"] = clampf(
		roundf(float(row["poll_tax"]) * data.bal("tax_rate_per_poll_tax")), 1.0, 10.0)
	state.metrics["tariff_rate"] = clampf(
		roundf(float(row["sales_tax"]) * data.bal("tariff_rate_per_sales_tax")), 0.0, 10.0)
	# The pools start with months of their own month (spec §5): the lord's
	# of his provinces' goods, the crown's of its share of the realm's.
	var p := RealmEconomy.purses(data, state)
	var st_months := int(data.bal("start_strategic_months"))
	var cv_months := int(data.bal("start_civil_months"))
	state.metrics["lord_strategic"] = float(int(p["lord"]["strategic"]) * st_months)
	state.metrics["lord_civil"] = float(int(p["lord"]["civil"]) * cv_months)
	state.metrics["strategic"] = float(int(p["realm_share"]["strategic"]) * st_months)
	state.metrics["grain"] = float(int(p["realm_share"]["civil"]) * cv_months)

## The pack's treasuries of every town in a province the crown controls.
static func crown_town_treasury(data: DataRepository, state: GameState) -> float:
	var total := 0.0
	var mine := MapManors.controlled_provinces(data, state)
	for code: String in data.burgs:
		if String(data.burgs[code].get("province_code", "")) in mine:
			total += float(data.world_row("economy", "burgs", code).get("treasury", 0.0))
	return total

## The crown's share (crown_share_permille) of what the towns of the realm's
## OTHER provinces hold — the treasury's starting chest.
static func realm_share_town_treasury(data: DataRepository, state: GameState) -> float:
	var total := 0.0
	var mine := MapManors.controlled_provinces(data, state)
	var realm := data.resolve_realm("player_realm")
	for code: String in data.burgs:
		var prov := String(data.burgs[code].get("province_code", ""))
		if prov in mine or MapOwnership.owner_of(data, state, prov) != realm:
			continue
		total += float(data.world_row("economy", "burgs", code).get("treasury", 0.0))
	return total * data.bal("crown_share_permille") / 1000.0

static func _fmt(v: float) -> String:
	return str(int(v)) if v == floorf(v) else String.num(v, 2)
