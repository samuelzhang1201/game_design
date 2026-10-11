extends GutTest
## WarFront.posts (spec 2026-10-11-front-line-design §1), hand-computed:
## a straight 30 km front for three regiments posts them 5, 15 and 25 km
## along, facing the teeth's side; a bent front follows its bend.


func test_a_straight_front_posts_three_regiments_at_equal_lengths() -> void:
	var pts := PackedVector2Array([Vector2(10000, 10000), Vector2(40000, 10000)])
	var posts := WarFront.posts(pts, 3, 0)
	assert_eq(posts.size(), 3)
	assert_eq(posts[0]["mid"], Vector2i(15000, 10000))
	assert_eq(posts[1]["mid"], Vector2i(25000, 10000))
	assert_eq(posts[2]["mid"], Vector2i(35000, 10000))
	for p: Dictionary in posts:
		assert_eq(p["facing_deg"], 90, "flip 0: the drawer's right, +y (south) on a west-to-east line")
	var left := WarFront.posts(pts, 3, 1)
	assert_eq(left[1]["facing_deg"], 270, "flip 1: the left, -y (north)")
	assert_eq(left[1]["mid"], Vector2i(25000, 10000))


func test_one_regiment_stands_at_the_middle() -> void:
	var posts := WarFront.posts(PackedVector2Array([Vector2(0, 0), Vector2(0, 8000)]), 1, 0)
	assert_eq(posts.size(), 1)
	assert_eq(posts[0]["mid"], Vector2i(0, 4000))
	assert_eq(posts[0]["facing_deg"], 180, "drawn southward, the right hand is west (-x)")


func test_a_bent_front_follows_its_bend() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10000, 0), Vector2(10000, 10000)])
	var posts := WarFront.posts(pts, 2, 0)
	assert_eq(posts[0]["mid"], Vector2i(5000, 0))
	assert_eq(posts[0]["facing_deg"], 90)
	assert_eq(posts[1]["mid"], Vector2i(10000, 5000))
	assert_eq(posts[1]["facing_deg"], 180)


func test_a_post_falls_on_a_vertex_without_overrunning() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10000, 0), Vector2(20000, 0)])
	var posts := WarFront.posts(pts, 1, 1)
	assert_eq(posts[0]["mid"], Vector2i(10000, 0))
	assert_eq(posts[0]["facing_deg"], 270)


func test_degenerate_input_posts_nothing() -> void:
	assert_eq(WarFront.posts(PackedVector2Array([Vector2(1, 1)]), 2, 0).size(), 0)
	assert_eq(WarFront.posts(PackedVector2Array([Vector2(1, 1), Vector2(1, 1)]), 2, 0).size(), 0)
	assert_eq(WarFront.posts(PackedVector2Array([Vector2(0, 0), Vector2(5, 0)]), 0, 0).size(), 0)
