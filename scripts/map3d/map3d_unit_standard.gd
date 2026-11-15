class_name Map3DUnitStandard
extends RefCounted
## Exactly one bearer across an entire admitted unit, including physical groups.
static func first_figure(piece: Dictionary) -> Node3D:
	if piece.get("layout", "") == "physical_groups":
		for group: Dictionary in piece.get("groups", []):
			var fig := first_figure(group["piece"])
			if fig != null: return fig
		return null
	var figures: Array = piece.get("figs", [])
	return figures[0] as Node3D if not figures.is_empty() else null

static func sync(piece: Dictionary, texture: Texture2D, scene: PackedScene) -> void:
	var fig := first_figure(piece)
	var old: Map3DStandardBearer = piece.get("standard_bearer")
	if is_instance_valid(old) and old.figure != fig:
		if is_instance_valid(old.standard): old.standard.queue_free()
		old.queue_free()
		old = null
	if fig == null or texture == null or scene == null:
		if is_instance_valid(old):
			if is_instance_valid(old.standard): old.standard.queue_free()
			old.queue_free()
		piece.erase("standard_bearer")
		return
	if not is_instance_valid(old):
		var skel := Map3DUnitRig._skeleton(fig)
		if skel == null: return
		var standard := scene.instantiate() as Map3DNationalFlag
		fig.add_child(standard)
		standard.name = "NationalStandard"
		old = Map3DStandardBearer.new()
		old.name = "StandardBearerGrip"
		old.figure = fig
		old.animation = Map3DUnits.find_anim(fig)
		old.standard = standard
		skel.add_child(old)
		piece["standard_bearer"] = old
	old.standard.set_texture(texture)
