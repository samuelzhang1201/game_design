class_name Map3DClipChain
extends RefCounted
## An action that names SEVERAL clips (army_art.csv `chains`, e.g. the infantry's
## `ATTACK:ATTACK;SLASH;ATTACK_VAR1`) is a chain (owner 2026-10-19: 士兵的动作能够
## 根据实际情况做出自动的选择): each figure plays one of its clips ONCE, stands
## in its guard (GARRISON) for a pause, then plays the next. Which clip and how
## long a pause are hashed from the regiment, the figure and the strike's count
## (Map3DMarchLag.unit), so a rank never strikes in step and a replay looks the
## same. View-only: the engine never sees it.


## `art`'s chains: action -> [clip, ...], from "ACTION:clip;clip|ACTION:clip;clip".
static func of_art(art: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for part: String in String(art.get("chains", "")).split("|", false):
		var kv := part.split(":", false)
		if kv.size() != 2:
			continue
		var clips: Array = []
		for c: String in kv[1].split(";", false):
			clips.append(c.strip_edges())
		if not clips.is_empty():
			out[kv[0].strip_edges()] = clips
	return out


## Which of `count` clips figure `index` of `code` plays for its `n`th strike.
static func pick(code: String, index: int, n: int, count: int) -> int:
	return mini(int(Map3DMarchLag.unit("%s|strike|%d|%d" % [code, index, n]) * count), count - 1)


## The guard pause (seconds, lo..hi) before figure `index`'s `n`th strike.
static func rest_s(code: String, index: int, n: int, lo: float, hi: float) -> float:
	return lo + Map3DMarchLag.unit("%s|rest|%d|%d" % [code, index, n]) * (hi - lo)


## Puts `anim` on the chain `clips` for `action` (already on it: left alone). The
## figure first stands its guard for its own pause, so the rank starts staggered.
static func start(anim: AnimationPlayer, action: String, clips: Array, code: String, index: int,
		lo: float, hi: float, blend_s: float) -> void:
	if anim.has_meta("chain") and String(anim.get_meta("chain")["action"]) == action:
		return
	anim.set_meta("chain", {"action": action, "clips": clips, "code": code, "i": index, "n": 0,
		"lo": lo, "hi": hi})
	if not anim.has_meta("chain_hooked"):
		anim.animation_finished.connect(_finished.bind(anim))
		anim.set_meta("chain_hooked", true)
	_guard(anim, blend_s, rest_s(code, index, 0, 0.0, hi))


## Leaves a chain: the figure's own clip takes over (Map3DUnitRig.play).
static func stop(anim: AnimationPlayer) -> void:
	if anim.has_meta("chain"):
		anim.remove_meta("chain")


## Whether `anim` is still on the chain it was started on for `action`.
static func _on(anim: AnimationPlayer, action: String) -> bool:
	return is_instance_valid(anim) and anim.has_meta("chain") \
		and String(anim.get_meta("chain")["action"]) == action


static func _guard(anim: AnimationPlayer, blend_s: float, wait_s: float) -> void:
	var guard := Map3DUnits.clip_named(anim, "GARRISON")
	if guard != "" and anim.current_animation != guard:
		anim.play(guard, blend_s)
	var action := String(anim.get_meta("chain")["action"])
	if not anim.is_inside_tree():
		return
	anim.get_tree().create_timer(wait_s).timeout.connect(func() -> void:
		if _on(anim, action):
			_strike(anim))


static func _strike(anim: AnimationPlayer) -> void:
	var c: Dictionary = anim.get_meta("chain")
	var clips: Array = c["clips"]
	var clip := Map3DUnits.clip_named(anim, String(clips[pick(c["code"], c["i"], c["n"], clips.size())]))
	c["n"] = int(c["n"]) + 1
	if clip != "":
		anim.play(clip, 0.2)
		anim.seek(0.0, true)


## A strike played out: its guard, then the next after this figure's pause.
static func _finished(_clip: StringName, anim: AnimationPlayer) -> void:
	if not anim.has_meta("chain"):
		return
	var c: Dictionary = anim.get_meta("chain")
	_guard(anim, 0.25, rest_s(c["code"], c["i"], c["n"], c["lo"], c["hi"]))
