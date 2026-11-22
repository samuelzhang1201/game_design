class_name Map3DImpact
extends RefCounted
## The felt contact of a duel's blow (spec 2026-11-21-infantry-melee-scrum-design.md;
## owner 2026-11-21: 交战的时候能够有碰撞感). Pure curves over the seconds since
## the contact instant (Map3DDuel.timing's `contact_at`): the hit-stop both
## figures hold, and the struck figure's knock-back out and back. View-only.


## Whether the pair still holds its hit-stop `since_contact` seconds after the blow met.
static func held(since_contact: float, hold_s: float) -> bool:
	return since_contact >= 0.0 and since_contact < hold_s


## The knock-back's share 0..1: eased out over `out_s` (ease-out), back over
## `back_s` (ease-in-out), 0 before the blow and after it settles.
static func knock(since_contact: float, out_s: float, back_s: float) -> float:
	if since_contact <= 0.0 or since_contact >= out_s + back_s:
		return 0.0
	if since_contact < out_s:
		var u := since_contact / out_s
		return 1.0 - (1.0 - u) * (1.0 - u)
	return 1.0 - smoothstep(0.0, 1.0, (since_contact - out_s) / back_s)


static func tune_of(repo: DataRepository) -> Dictionary:
	return {"hitstop": repo.bal("map3d_melee_hitstop_s"), "knock_h": repo.bal("map3d_melee_knock_h"),
		"knock_out": repo.bal("map3d_melee_knock_out_s"), "knock_back": repo.bal("map3d_melee_knock_back_s"),
		"block_knock": repo.bal("map3d_melee_block_knock")}
