class_name Map3DUnitSettle
extends RefCounted
## The march's last step (owner 2026-10-14: 步兵行进结束后转驻防的时候，加入Equip.wav
## 的音效，注意节奏要和步伐相符): a piece that halts from MARCH into GARRISON keeps
## walking at its pace until its lead figure's next FOOTFALL (army_art.csv
## `steps`, the MARCH clip's shares where a foot plants), and only then drops
## into its guard; its arm's settle sound (GameArt.UNIT_SETTLE_SOUNDS) is started
## `map3d_unit_settle_hit_s` early so the clank lands ON that footfall. An arm
## with no `steps` switches at once, as before. View-only: real seconds, no RNG,
## nothing reaches the engine.

## code -> {action, left (s to the switch), sound_in (s to the sound, < 0 once played)}
var _pending: Dictionary = {}


## Seconds from clip share `pos` until the first footfall in `steps` (shares of
## a `clip_s` clip played at `speed`) at least `lead_s` away. INF with no steps.
static func wait_s(pos: float, clip_s: float, speed: float, steps: Array, lead_s: float) -> float:
	if steps.is_empty() or clip_s <= 0.0:
		return INF
	var rate := maxf(absf(speed), 0.0001)
	for lap in 3:
		for s: float in steps:
			var d := (s + lap - pos) * clip_s / rate
			if d >= lead_s:
				return d
	return INF


## A piece's footfall shares from its army_art.csv row ("0.14;0.43"), sorted.
static func steps_of(art: Dictionary) -> Array:
	var out: Array = []
	for part: String in String(art.get("steps", "")).split(";", false):
		out.append(clampf(float(part), 0.0, 1.0))
	out.sort()
	return out


## Whether `piece`'s switch to `action` is HELD for its last step: true while one
## is pending for that action, or when a MARCH into GARRISON on an arm with steps
## starts one now (its figures keep their pace meanwhile, `settling`).
func holds(repo: DataRepository, code: String, piece: Dictionary, action: String) -> bool:
	if _pending.has(code):
		if String(_pending[code]["action"]) == action:
			return true
		cancel(code, piece)
	var steps: Array = piece.get("steps", [])
	var anims: Array = piece.get("anims", [])
	if action != Map3DLayerUnits.GARRISON or String(piece.get("action", "")) != Map3DLayerUnits.MARCH \
			or steps.is_empty() or anims.is_empty():
		return false
	var lead: AnimationPlayer = anims[0]
	var clip_s := lead.current_animation_length
	if clip_s <= 0.0:
		return false
	var hit := repo.bal("map3d_unit_settle_hit_s")
	var left := wait_s(lead.current_animation_position / clip_s, clip_s, lead.speed_scale, steps, hit)
	if left == INF:
		return false
	_pending[code] = {"action": action, "left": left, "sound_in": left - hit}
	piece["settling"] = true
	return true


## A held switch dropped (the piece marches on, or is ordered elsewhere).
func cancel(code: String, piece: Dictionary) -> void:
	if _pending.erase(code):
		piece.erase("settling")


## Each frame: the sounds come due and the held pieces drop into their guard.
func step(layer: Map3DLayerUnits, delta: float) -> void:
	for code: String in _pending.keys():
		var p: Dictionary = _pending[code]
		if not layer.has_piece(code):
			_pending.erase(code)
			continue
		var piece: Dictionary = layer.built_piece(code)
		p["left"] = float(p["left"]) - delta
		if float(p["sound_in"]) >= 0.0:
			p["sound_in"] = float(p["sound_in"]) - delta
			if float(p["sound_in"]) < 0.0:
				p["sound_in"] = -1.0
				Map3DUnitSound.one_shot(layer.ctx.repo, layer.ctx.camera, piece,
					Map3DUnitSound.settle_sound_of(piece))
		if float(p["left"]) <= 0.0:
			cancel(code, piece)
			layer.play(code, String(p["action"]))


## How many switches are held (tests).
func pending_count() -> int:
	return _pending.size()
