class_name WarNear
extends RefCounted
## The near look by the camera's distance (spec 2026-10-07-war-room-scale-hover
## §3): the contour interval steps down a nice number at a time (200, 100,
## 50 m) and the fine print fades in. Pure.


## war_contour_m at war_fine_far_m and beyond; halved for each halving of the
## distance past it; never below war_contour_near_m.
static func contour_m(repo: DataRepository, distance_m: float) -> float:
	var far := repo.bal("war_fine_far_m")
	var full := repo.bal("war_contour_m")
	if distance_m >= far:
		return full
	var halvings := floori(log(far / maxf(distance_m, 1e-4)) / log(2.0)) + 1
	return maxf(full / pow(2.0, float(halvings)), repo.bal("war_contour_near_m"))


## 0 at war_fine_far_m and beyond, 1 at war_fine_near_m and nearer, smooth between.
static func fine_alpha(repo: DataRepository, distance_m: float) -> float:
	var far := repo.bal("war_fine_far_m")
	var near := repo.bal("war_fine_near_m")
	return smoothstep(far, near, distance_m) if far > near else (1.0 if distance_m <= near else 0.0)
