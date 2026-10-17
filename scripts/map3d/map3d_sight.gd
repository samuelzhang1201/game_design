class_name Map3DSight
extends RefCounted
## What the map draws of the armies (spec 2026-10-10-player-sight-and-ghosts),
## behind Map3DContext.regiments / fogged / ghosts: in DEV MODE every realm's
## units; else the player's and the foe units the crown SEES (Sighting.seen_foes,
## kept while the state, the day and every unit's place stand still — the pieces
## and the HUD ask it several times a frame), each at its true place. A FOGGED
## unit (a foe out of DEV MODE) shows no bars, no road ahead and no order menu,
## and its men only as an estimate; the GHOSTS are Sighting.ghosts, data only.

var _key: Array = []
var _seen: Array = []


## The units the map draws, rows of ArmySystem.roster.
func regiments(repo: DataRepository, st: GameState, dev: bool) -> Array:
	if dev:
		return ArmySystem.roster(repo, st).values()
	var out := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), st)
	for c: String in seen(repo, st):
		out.append(ArmySystem.regiment(repo, c, st))
	return out


## The foe units the crown sees now, in code order.
func seen(repo: DataRepository, st: GameState) -> Array:
	if st == null or st.foes.is_empty():
		return []
	var key := [st.get_instance_id(), st.absolute_day(), places_key(st)]
	if key != _key:
		_key = key
		_seen = Sighting.seen_foes(repo, st)
	return _seen


## A whole-number digest of what the sight reads besides the day: where every
## unit stands, its living personnel, and how many provinces and manors have moved.
static func places_key(st: GameState) -> int:
	var h := 0
	for book: Dictionary in [st.regiments, st.foes]:
		for c: Variant in book:
			var e: Dictionary = book[c]
			h = (h * 31 + int(e.get("x_m", 0)) * 7 + int(e.get("y_m", 0)) * 13 + MilitaryRoster.living(st, String(c))
				+ String(e.get("order", "")).hash() % 9973 * 17 + int(e.get("dest_x_m", 0)) * 19 + int(e.get("dest_y_m", 0)) * 23) % 1000000007
	return h + st.province_owner.size() * 1000003 + st.manor_owner.size()
