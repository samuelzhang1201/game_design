class_name Map3DUnitSound
extends RefCounted
## The MARCH's sound (owner 2026-10-13: 绑到3d大地图上的兵种移动中): a piece
## walking its MARCH clip plays its arm's loop (GameArt.UNIT_SOUNDS, keyed by
## army_art.csv `piece`) from an AudioStreamPlayer3D on its node, so it pans
## with where it stands on screen. The loudness is the CAMERA's distance, not
## the engine's attenuation (a miniature's world spans 400 m to 150 km of zoom):
## full at `map3d_unit_sound_near_m`, down to `_floor_db` at `_far_m`, silent
## past it, and only the `_voices` nearest marching pieces sound at once.
## View-only: nothing here reaches the engine, no RNG (each loop's start is hashed).

const SILENT_DB := -80.0

## code -> AudioStreamPlayer3D, a child of that piece's node (freed with it).
var _players: Dictionary = {}
var _hits: Array = []  ## the duel blows' live one-shots (play_impacts)


## The loudness, dB, of a march heard from `dist_m`; SILENT_DB past far.
static func gain_db(repo: DataRepository, dist_m: float) -> float:
	var near := repo.bal("map3d_unit_sound_near_m")
	var far := repo.bal("map3d_unit_sound_far_m")
	if dist_m > far:
		return SILENT_DB
	var t := clampf((dist_m - near) / maxf(far - near, 0.001), 0.0, 1.0)
	return lerpf(repo.bal("map3d_unit_sound_db"), repo.bal("map3d_unit_sound_floor_db"), t)


## The codes that sound: the `voices` nearest of `dists` ({code: metres}) within
## `far`, nearest first, ties by code (a fixed order).
static func voiced(dists: Dictionary, voices: int, far: float) -> Array:
	var near: Array = dists.keys().filter(func(c: String) -> bool: return float(dists[c]) <= far)
	near.sort_custom(func(a: String, b: String) -> bool:
		return a < b if float(dists[a]) == float(dists[b]) else float(dists[a]) < float(dists[b]))
	return near.slice(0, maxi(voices, 0))


## Each frame: the marching pieces' loops started, eased to their loudness, and the rest eased out and stopped.
func sync(repo: DataRepository, camera: Camera3D, pieces: Dictionary, delta: float) -> void:
	var dists: Dictionary = {}
	if camera != null:
		for code: String in pieces:
			var piece: Dictionary = pieces[code]
			var node: Node3D = piece["node"]
			if String(piece.get("action", "")) == Map3DLayerUnits.MARCH and node.visible \
					and node.is_inside_tree() and sound_of(piece) != null:
				dists[code] = camera.global_position.distance_to(node.global_position)
	var loud := voiced(dists, int(repo.bal("map3d_unit_sound_voices")), repo.bal("map3d_unit_sound_far_m"))
	var step_db := repo.bal("map3d_unit_sound_fade_db_s") * delta
	for code: String in loud:
		var player := _player_for(code, pieces[code])
		player.volume_db = move_toward(player.volume_db, gain_db(repo, float(dists[code])), step_db)
	for code: String in _players.keys():
		if loud.has(code):
			continue
		if not is_instance_valid(_players[code]):  # freed with its piece's node
			_players.erase(code)
			continue
		var player: AudioStreamPlayer3D = _players[code]
		player.volume_db = move_toward(player.volume_db, SILENT_DB, step_db)
		if player.volume_db <= repo.bal("map3d_unit_sound_floor_db") - 20.0 or not pieces.has(code):
			player.queue_free()
			_players.erase(code)


## Every loop stopped at once (the view hidden, the pieces put away).
func silence() -> void:
	for player: Variant in _players.values():
		if is_instance_valid(player):
			(player as AudioStreamPlayer3D).queue_free()
	_players.clear()


## How many loops are sounding (tests).
func playing_count() -> int:
	return _players.values().filter(func(p: Variant) -> bool:
		return is_instance_valid(p) and (p as AudioStreamPlayer3D).playing).size()


## The loop `piece`'s arm marches to, or null (an arm with none is silent).
static func sound_of(piece: Dictionary) -> AudioStream:
	var table := GameArt.table(GameArt.UNIT_SOUNDS)
	return table.of(String(piece.get("model", ""))) as AudioStream if table != null else null


## The sound `piece`'s arm settles into its guard with (Map3DUnitSettle), or null.
static func settle_sound_of(piece: Dictionary) -> AudioStream:
	var table := GameArt.table(GameArt.UNIT_SETTLE_SOUNDS)
	return table.of(String(piece.get("model", ""))) as AudioStream if table != null else null


## Plays `stream` once from `piece`'s node at the camera distance's loudness
## (gain_db + map3d_unit_settle_db); nothing for a hidden piece, past far, or no
## stream. The player frees itself when the sound ends.
static func one_shot(repo: DataRepository, camera: Camera3D, piece: Dictionary, stream: AudioStream) -> void:
	var node: Node3D = piece.get("node")
	_play(repo, camera, node, stream, repo.bal("map3d_unit_settle_db"), "SettleSound")


## A duel blow's one-shot (spec 2026-11-21-infantry-melee-scrum-design.md: a clash
## on a block, a thud on a hit) on the struck figure's `at_node`, at gain_db +
## map3d_impact_db; null (refused) once `live` reach map3d_impact_voices, past far,
## or hidden. Each clip's attack is at its first sample, so the frame that tells
## the contact (its instant: there is no look-ahead) is the frame it sounds.
static func impact(repo: DataRepository, camera: Camera3D, at_node: Node3D, stream: AudioStream, live: int) -> AudioStreamPlayer3D:
	if live >= int(repo.bal("map3d_impact_voices")):
		return null
	return _play(repo, camera, at_node, stream, repo.bal("map3d_impact_db"), "ImpactSound")


## Each frame: the duels' contacts (Map3DDuelDriver.take_impacts) sounded, each
## while fewer than map3d_impact_voices are still ringing (the cap stops a din).
func play_impacts(repo: DataRepository, camera: Camera3D, contacts: Array) -> void:
	_hits = _hits.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	for c: Dictionary in contacts:
		var node: Variant = (c.get("struck", {}) as Dictionary).get("node")
		if is_instance_valid(node):
			var player := impact(repo, camera, node, impact_sound_of(String(c.get("kind", ""))), _hits.size())
			if player != null:
				_hits.append(player)


## The one-shot a blow of `kind` (HIT | BLOCK) sounds, or null (GameArt.UNIT_IMPACT_SOUNDS:
## each an AudioStreamRandomizer over its variants).
static func impact_sound_of(kind: String) -> AudioStream:
	var table := GameArt.table(GameArt.UNIT_IMPACT_SOUNDS)
	return table.of(kind) as AudioStream if table != null else null


static func _play(repo: DataRepository, camera: Camera3D, node: Node3D, stream: AudioStream, extra_db: float,
		label: String) -> AudioStreamPlayer3D:
	if stream == null or camera == null or node == null or not node.is_visible_in_tree():
		return null
	var db := gain_db(repo, camera.global_position.distance_to(node.global_position))
	if db <= SILENT_DB:
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = label
	player.stream = stream
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # the loudness is gain_db's
	player.volume_db = db + extra_db
	player.finished.connect(player.queue_free)
	node.add_child(player)  # no owner: never saved
	player.get_viewport().audio_listener_enable_3d = true
	player.play()
	return player


func _player_for(code: String, piece: Dictionary) -> AudioStreamPlayer3D:
	# a piece's node rebuilt under the same code frees the old player with it: check
	# the dictionary's value before a typed variable takes it (a freed one errors)
	if is_instance_valid(_players.get(code)):
		var held: AudioStreamPlayer3D = _players[code]
		if not held.playing:  # stopped while the view was put away (its subtree disabled)
			held.play(_start_of(code, held.stream))
		return held
	var player := AudioStreamPlayer3D.new()
	player.name = "MarchSound"
	player.stream = sound_of(piece)
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # the loudness is gain_db's
	player.volume_db = SILENT_DB
	(piece["node"] as Node3D).add_child(player)  # no owner: never saved
	player.get_viewport().audio_listener_enable_3d = true  # the map's SubViewport: its camera hears
	player.play(_start_of(code, player.stream))
	_players[code] = player
	return player


## Where `code`'s loop starts, seconds: its own hashed point, so pieces sound out of step.
static func _start_of(code: String, stream: AudioStream) -> float:
	var length := stream.get_length() if stream != null else 0.0
	return fmod(float(absi(hash(code)) % 10000) / 10000.0 * length, maxf(length, 0.001))
