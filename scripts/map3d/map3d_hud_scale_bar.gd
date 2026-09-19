class_name Map3DHudScaleBar
extends Map3DHudPiece
## The scale bar, bottom-right (owner 2026-09-18): ScaleBar, the 2D map's own
## drawing, in the 2D map's own measure (Map3DView.map_units_per_metre), over
## a pale halo so it reads over snow and sea.


func _draw() -> void:
	if not bound():
		return
	ScaleBar.draw(self, Map3DHud.scale_bar_for(ctx.metres_per_pixel() * view.map_units_per_metre(),
		ctx.repo.bal("map_scale_bar_max_px"), view.map_unit()), size, Map3DHud.halo(ctx.repo))
