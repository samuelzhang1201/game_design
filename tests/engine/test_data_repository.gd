extends GutTest

func test_loads_real_data_dir() -> void:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo)
	assert_eq(repo.bal("start_treasury"), 500.0)
	assert_true(repo.traits.has("venal"))
	assert_true(repo.seats.has("chancellor"))
	assert_true(repo.actions.has("COUNCIL_CONSULT"))

func test_malformed_row_fails_loud_with_location() -> void:
	var rows := DataRepository.parse_csv("res://tests/fixtures/bad_balance.csv", ["key", "value"])
	assert_eq(rows, [])
	assert_string_contains(DataRepository.last_error, "bad_balance.csv")
	assert_string_contains(DataRepository.last_error, "row 3")
