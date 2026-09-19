class_name Map3DHudBackdrop
extends Map3DHudPiece
## A soft dark vignette behind the compass wheel (fix round 1: map symbols at
## 24 km tangled with its spokes): a few concentric filled circles layered
## from a pale wide one to a small one at map3d_compass_backdrop_alpha —
## normal alpha blending stacks them into a radial fade with no gradient
## texture. Drawn before the wheel, so it sits behind it with no z_index.


func _draw() -> void:
	if not bound():
		return
	var hud := get_parent() as Map3DHud
	if hud == null:
		return
	var r := hud.compass_rect()
	if r.size.x <= 0.0:
		return
	var peak := ctx.repo.bal("map3d_compass_backdrop_alpha")
	if peak <= 0.0:
		return
	var c := r.get_center()
	var radius := r.size.x * 0.58
	var rings := 6
	for i in rings:
		var t := float(i + 1) / float(rings)
		draw_circle(c, radius * (1.0 - t), Color(0.0, 0.0, 0.0, peak * t))
