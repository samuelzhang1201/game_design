extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The map draws what the crown SEES (spec docs/superpowers/specs/
## 2026-10-10-player-sight-and-ghosts-design.md): out of DEV MODE
## Map3DContext.regiments() is the player's units and the foe units within
## sight (Sighting.seen_foes), each at its true place; ghosts() is the rest of
## what the crown knows, as data. DEV MODE draws every realm's units, no ghost.

var repo: DataRepository
var s: GameState
var ctx: Map3DContext


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 11)
	s.tick = 1
	s.day = 5
	repo.balance["player_sight_km"] = 12.0
	ctx = Map3DContext.new(repo, {})
	ctx.state_fn = func() -> GameState: return s


func _codes(rows: Array) -> Array:
	var out: Array = []
	for reg: Dictionary in rows:
		out.append(String(reg["regiment_code"]))
	out.sort()
	return out


## Two foes: one beside a player unit standing at a host's assembly point (no
## held town near it on the pack), one parked far off.
func _two_foes() -> Array:
	var codes: Array = s.foes.keys()
	codes.sort()
	var host := String(s.foes[codes[0]]["host"])
	var at := EnemyAi.home_m(repo, host)
	Play.park_army(repo, s, at)
	var unit := String(Play.land_regiments(repo)[0])
	Play.place(repo, s, unit, at, ArmySystem.ORDER_STANDBY)
	for c: String in codes:
		Play.place(repo, s, c, at + Vector2i(0, 500000), ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, codes[0], at + Vector2i(Sighting.sight_m(repo), 0), ArmySystem.ORDER_STANDBY)
	return [String(codes[0]), String(codes[1])]


func test_out_of_dev_mode_the_map_draws_the_seen_foe_and_not_the_unseen() -> void:
	var foes := _two_foes()
	var mine := _codes(MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s))
	var drawn := _codes(ctx.regiments())
	assert_true(foes[0] in drawn, "the foe within sight is drawn")
	assert_false(foes[1] in drawn, "the foe out of sight is not")
	assert_eq(drawn.size(), mine.size() + Sighting.seen_foes(repo, s).size(), "the player's units and the seen")
	assert_true(ctx.fogged(foes[0]), "a seen foe is still under the fog")
	assert_false(ctx.fogged(mine[0]))


func test_dev_mode_is_unchanged() -> void:
	_two_foes()
	ctx.dev = true
	assert_eq(_codes(ctx.regiments()), _codes(ArmySystem.roster(repo, s).values()), "every realm's units")
	assert_eq(ctx.ghosts(), [], "no ghost: everything stands")
	assert_false(ctx.fogged(String(s.foes.keys()[0])))


func test_a_foe_that_moves_out_of_sight_leaves_the_map_and_becomes_a_ghost() -> void:
	var foes := _two_foes()
	Sighting.update(repo, s)
	assert_eq(ctx.ghosts(), [], "seen now: its piece, no ghost")
	var e: Dictionary = s.foes[foes[0]]
	var was := Vector2i(int(e["x_m"]), int(e["y_m"]))
	Play.place(repo, s, foes[0], was + Vector2i(3 * Sighting.sight_m(repo), 0), ArmySystem.ORDER_STANDBY)
	assert_false(foes[0] in _codes(ctx.regiments()), "the cache follows the move")
	var gs := ctx.ghosts()
	assert_eq(gs.size(), 1)
	assert_eq([String(gs[0]["key"]), int(gs[0]["x_m"]), int(gs[0]["y_m"]), String(gs[0]["source"])],
		[foes[0], was.x, was.y, "seen"])
	assert_eq(String(gs[0]["label"]), String(ArmySystem.regiment(repo, foes[0], s)["label"]))
