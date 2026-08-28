class_name OpinionDrift
extends RefCounted
## Deterministic ideology-distance opinion drift (spec §2.2). No RNG.

const AXES := ["centralism", "militarism", "orthodoxy", "tax_incidence", "expansionism"]

static func signature_for(data: DataRepository, code: String, params: Dictionary) -> Dictionary:
	for row in data.signatures:
		if row["action_code"] != code:
			continue
		if _variant_matches(String(row.get("variant", "")), params):
			var sig := {}
			for ax in AXES:
				sig[ax] = float(row[ax])
			return sig
	return {}

static func _variant_matches(variant: String, params: Dictionary) -> bool:
	if variant == "":
		return true
	if variant == "delta_pos":
		return float(params.get("delta", 0)) > 0.0
	if variant == "delta_neg":
		return float(params.get("delta", 0)) < 0.0
	if "=" in variant:
		var kv := variant.split("=")
		return String(params.get(kv[0], "")) == kv[1]
	return false

static func alignment(sig: Dictionary, ideology: Dictionary) -> float:
	var dot := 0.0
	var norm := 0.0
	for ax in AXES:
		dot += float(sig.get(ax, 0)) * float(ideology.get(ax, 0))
		norm += absf(float(sig.get(ax, 0)))
	if norm == 0.0:
		return 0.0
	return dot / (norm * 100.0)

static func dominant_axis(sig: Dictionary, ideology: Dictionary) -> String:
	var best := ""
	var best_v := -1.0
	for ax in AXES:
		var v := absf(float(sig.get(ax, 0)) * float(ideology.get(ax, 0)))
		if v > best_v:
			best_v = v
			best = ax
	return best

static func apply(data: DataRepository, state: GameState, sig: Dictionary, label: String) -> Array:
	var out: Array = []
	if sig.is_empty():
		return out
	for seat in state.council:
		var char_id: String = state.council[seat]
		var c: Character = state.characters[char_id]
		var a := alignment(sig, c.ideology)
		var delta := roundi(a * float(c.ideology.get("policy_sensitivity", 50)) / 100.0 \
			* (1.0 - float(c.attributes.get("pragmatism", 50)) / 100.0) \
			* data.bal("opinion_drift_scale"))
		if delta == 0:
			continue
		var stance := "approves" if delta > 0 else "opposes"
		var reason := "%s (%s, %s)" % [label, stance, dominant_axis(sig, c.ideology)]
		c.change_opinion(delta, reason, state.tick)
		out.append({"character_id": char_id, "delta": delta, "reason": reason})
	return out
