class_name TickReport
extends RefCounted

var tick: int = 0
var season: String = ""
var year: int = 1
var metric_deltas: Array = []
var concerns: Array = []
var suggestions: Array = []
var outcomes: Array = []

func to_dict() -> Dictionary:
	var sug_dicts: Array = []
	for s in suggestions:
		sug_dicts.append({"seat": s["seat"], "request": s["request"].to_dict(),
			"pitch_key": s["pitch_key"], "tradeoff": s["tradeoff"]})
	return {"tick": tick, "season": season, "year": year,
		"metric_deltas": metric_deltas.duplicate(true), "concerns": concerns.duplicate(true),
		"suggestions": sug_dicts, "outcomes": outcomes.duplicate(true)}
