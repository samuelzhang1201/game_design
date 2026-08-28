class_name ConcernScanner
extends RefCounted

## metric -> [balance threshold key, owning seat, direction]
## direction "below" fires when value < threshold, "above" when value > threshold.
const RULES := {
	"treasury": ["concern_treasury_low", "steward", "below"],
	"grain": ["concern_grain_low", "steward", "below"],
	"unrest": ["concern_unrest_high", "chancellor", "above"],
	"church_opinion": ["concern_church_low", "chaplain", "below"],
	"army_quality": ["concern_army_low", "marshal", "below"],
	"legitimacy": ["concern_legitimacy_low", "spymaster", "below"],
}

static func scan(state: GameState, data: DataRepository) -> Array:
	var out: Array = []
	for metric in RULES:
		var rule: Array = RULES[metric]
		var threshold := data.bal(rule[0])
		var value: float = state.metrics[metric]
		var breached := value < threshold if rule[2] == "below" else value > threshold
		if breached:
			var severity := absf(value - threshold) / maxf(threshold, 1.0)
			out.append({"seat": rule[1], "metric": metric, "value": value,
				"severity": clampf(severity, 0.05, 1.0)})
	out.sort_custom(func(a, b): return a["severity"] > b["severity"])
	return out
