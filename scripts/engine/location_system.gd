class_name LocationSystem
extends RefCounted
## Regions and locations (data/regions.csv, data/locations.csv): where the
## player currently stands, who is found there, and where they may move.
## Movement within one region is FREE — no tick, no cost; travel between
## regions is post-MVP and will cost time. Deterministic, no RNG, no Nodes.

const DEFAULT_LOCATION := "council_chamber"

static func location(data: DataRepository, code: String) -> Dictionary:
	return data.locations.get(code, {})

static func region_of(data: DataRepository, code: String) -> String:
	return String(location(data, code).get("region_code", ""))

## Free movement is allowed only to a real location in the SAME region as
## the current one (inter-region travel is a future, time-costing action).
static func can_move(data: DataRepository, state: GameState, code: String) -> bool:
	if not data.locations.has(code):
		return false
	return region_of(data, code) == region_of(data, state.current_location)

## Locations reachable for free from where the player stands, in CSV order.
static func reachable(data: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var here_region := region_of(data, state.current_location)
	for code in data.locations:
		if String(data.locations[code]["region_code"]) == here_region:
			out.append(String(code))
	return out

## Character ids present at a location — only those alive in the roster, so
## content can list ids that a given campaign no longer has.
static func occupants(data: DataRepository, state: GameState, code: String) -> Array:
	var out: Array = []
	for id in String(location(data, code).get("occupants", "")).split("|", false):
		if state.characters.has(id):
			out.append(id)
	return out
