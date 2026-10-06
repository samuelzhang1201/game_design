extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The near look by the camera's distance (spec 2026-10-07-war-room-scale-hover §3).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_the_contours_halve_as_the_camera_halves_its_distance_past_far() -> void:
	var far := repo.bal("war_fine_far_m")
	var full := repo.bal("war_contour_m")
	var near := repo.bal("war_contour_near_m")
	assert_eq(WarNear.contour_m(repo, far * 2.0), full)
	assert_eq(WarNear.contour_m(repo, far), full)
	assert_eq(WarNear.contour_m(repo, far * 0.99), full * 0.5)
	assert_eq(WarNear.contour_m(repo, far * 0.49), maxf(full * 0.25, near))
	assert_eq(WarNear.contour_m(repo, 0.01), near, "never finer than the near contours")


func test_a_figure_level_is_always_on_a_drawn_index_line_while_fine_print_shows() -> void:
	var level := repo.bal("war_fine_contour_level_m")
	var every := repo.bal("war_contour_index_every")
	var d := repo.bal("war_fine_far_m") * 0.99
	while d > repo.bal("war_cam_min_m"):
		if WarNear.fine_alpha(repo, d) > 0.0:
			assert_almost_eq(fmod(level, WarNear.contour_m(repo, d) * every), 0.0, 0.001, "at %.2f m" % d)
		d *= 0.8


func test_fine_print_fades_in_from_far_to_near() -> void:
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_fine_far_m")), 0.0)
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_fine_near_m")), 1.0)
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_cam_min_m")), 1.0)
	var mid := (repo.bal("war_fine_far_m") + repo.bal("war_fine_near_m")) * 0.5
	assert_between(WarNear.fine_alpha(repo, mid), 0.01, 0.99)
