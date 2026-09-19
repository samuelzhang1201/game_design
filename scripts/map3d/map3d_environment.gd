class_name Map3DEnvironment
extends RefCounted
## The Sun's shadow LOOK, applied at load (spec 2026-09-20 §1; owner fix
## round 1, 2026-09-18): a code-review + independent-critic pass on Task 9
## found the shipped cloud shadows read as pitch-black holes with knife
## edges, burying the settlement rings — `shadow_enabled` alone leaves
## Godot's default full black, full crisp shadow. `shadow_opacity` blends the
## shadowed pixel with its lit colour instead of replacing it (so a shadow
## reads as a COOL WASH of blocked light, never a hole) and `shadow_blur`
## softens every cast shadow's edge — both apply to the terrain's own
## self-shadowing too (accepted: the mountains read softer with it, see the
## fix report). The sea never receives shadows (`disable_receive_shadows` on
## its own material, set at build time) — untouched here.

static func apply_sun_look(repo: DataRepository, sun: DirectionalLight3D) -> void:
	sun.shadow_opacity = repo.bal("map3d_sun_shadow_opacity")
	sun.shadow_blur = repo.bal("map3d_sun_shadow_blur")
