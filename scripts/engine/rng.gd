class_name Rng
extends RefCounted

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func chance(p: float) -> bool:
	return _rng.randf() < p

## The seed this stream started from — Weather hashes it, so the skies are
## the campaign's own without drawing from the stream.
func seed_value() -> int:
	return int(_rng.seed)

func pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if roll < acc:
			return i
	return weights.size() - 1

func to_dict() -> Dictionary:
	# Serialize state as string to preserve precision through JSON round-trip
	return {"seed": int(_rng.seed), "state": str(_rng.state)}

static func from_dict(d: Dictionary) -> Rng:
	var r := Rng.new(int(d["seed"]))
	r._rng.state = int(d["state"])  # String is auto-converted to int
	return r
