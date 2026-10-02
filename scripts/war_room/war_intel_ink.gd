class_name WarIntelInk
extends RefCounted
## What we KNOW, inked over the laid sheet (owner 2026-10-02, spec
## 2026-10-02-war-room-v2 §2.4): the crown's regiments' supply roads (fainter
## for what they lose), the crown's couriers on the road and the road ahead,
## this spell's weather by province, and every spy report that has COME IN (a
## missive) as a ring of its estimate. Never a foreign regiment's line, never a
## spy still riding as a report. In ink-texture px like WarSheetInk; drawn into
## its own texture once a day (cache_key).


static func cache_key(state: GameState, sheet_index: int) -> int:
	var couriers: Array = state.couriers.map(func(c: Dictionary) -> Array: return [c["id"], c["x_m"], c["y_m"]])
	return hash([sheet_index, state.absolute_day(), couriers, state.missives.size(), state.regiments.hash()])


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var out := {"supply": [], "couriers": [], "weather": [], "spies": []}
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(x: Dictionary) -> String: return String(x["regiment_code"]))
	ours.sort()
	for code: String in ours:
		var route := SupplySystem.route_px(repo, state, code)
		if route.size() >= 2 and WarSheetInk._touches(r, route):
			var line := SupplySystem.line_of(repo, state, code)
			(out["supply"] as Array).append({"code": code, "poly": WarSheetInk._to_tex(r, k, route),
				"loss_permille": int(line["loss_permille"])})
	for c: Dictionary in state.couriers:
		var pts := PackedVector2Array([ArmySystem.metres_to_pack(repo, Vector2i(int(c["x_m"]), int(c["y_m"])))])
		for p: Array in c.get("path", []):
			pts.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
		if WarSheetInk._touches(r, pts):
			(out["couriers"] as Array).append({"poly": WarSheetInk._to_tex(r, k, pts), "at": (pts[0] - r.position) * k,
				"spy": String(c.get("kind", "")) == CourierSystem.SPY})
	var day := state.absolute_day()
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var row: Dictionary = repo.provinces[code]
		var at := Vector2(float(row.get("center_x", 0)), float(row.get("center_y", 0)))
		if not r.has_point(at):
			continue
		var kind := Weather.of(repo, state, code, day)
		var look: Dictionary = repo.weather_kinds.get(kind, {})
		var rain := float(look.get("rainfall", "0"))
		var snow := float(look.get("snowfall", "0"))
		var overcast := float(look.get("overcast", "0"))
		if rain <= 0.0 and snow <= 0.0 and overcast < 0.5:
			continue   # fair weather is not news
		(out["weather"] as Array).append({"at": (at - r.position) * k, "rain": rain, "snow": snow,
			"overcast": overcast, "label": Weather.label_of(repo, kind)})
	var seen: Dictionary = {}
	var spies: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "spy")
	spies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	for m: Dictionary in spies:
		var subj: Dictionary = m["subject"]
		var at := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
		var key := Vector2i(at.round())
		if seen.has(key) or not r.has_point(at):
			continue
		seen[key] = true   # the newest report about a place stands for it
		var spread := 0.0
		var text := String(m["title"])
		for f: Dictionary in m["facts"]:
			if f.has("lo"):
				spread = float(int(f["hi"]) - int(f["lo"])) / maxf(float(f["hi"]), 1.0)
				text = "%s ≈ %s–%s" % [String(f["label"]), WarRoom.group(int(f["lo"])), WarRoom.group(int(f["hi"]))]
				break
		text += " · " + CourierCard.date_of(int(m["day"]))
		(out["spies"] as Array).append({"at": (at - r.position) * k,
			"radius": repo.bal("war_intel_spy_ring_px") * (1.0 + spread * repo.bal("war_intel_spy_spread_k")), "text": text})
	return out
