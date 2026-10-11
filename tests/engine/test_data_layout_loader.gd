extends GutTest
## The data folders' loader (spec 2026-10-11-data-folders-by-scene): a table's
## folder comes from <dir>/tables.csv, and every indexed folder's balance.csv
## merges into the one balance dict — a key in two files fails, naming both.

const OK := "res://tests/fixtures/data_layout/ok"
const DUP := "res://tests/fixtures/data_layout/dup"
const CRLF := "res://tests/fixtures/data_layout/crlf"

func test_table_path_resolves_through_the_index() -> void:
	assert_eq(DataRepository.table_path(OK, "things"), OK + "/alpha/things.csv")
	assert_eq(DataRepository.table_path(OK, "others"), OK + "/beta/others.csv")

func test_unknown_table_sets_last_error() -> void:
	DataRepository.table_path(OK, "nope")
	assert_string_contains(DataRepository.last_error, "nope")

func test_table_folders_are_sorted_and_distinct() -> void:
	assert_eq(DataRepository.table_folders(OK), ["alpha", "beta", "gamma"])

func test_balance_merges_every_folder() -> void:
	assert_eq(DataRepository.load_balance(OK), {"k_one": 1.0, "k_two": 2.5})
	assert_eq(DataRepository.last_error, "")

func test_duplicate_key_fails_naming_both_files() -> void:
	assert_eq(DataRepository.load_balance(DUP), {})
	assert_string_contains(DataRepository.last_error, "alpha/balance.csv")
	assert_string_contains(DataRepository.last_error, "beta/balance.csv")
	assert_string_contains(DataRepository.last_error, "k_one")

func test_balance_reads_crlf_and_bom() -> void:
	# both files of this fixture are saved as a spreadsheet saves them
	assert_eq(DataRepository.table_path(CRLF, "things"), CRLF + "/alpha/things.csv")
	assert_eq(DataRepository.load_balance(CRLF), {"k_one": 1.0})

func test_missing_index_fails_naming_it() -> void:
	assert_eq(DataRepository.load_balance("res://tests/fixtures/data_layout"), {})
	assert_string_contains(DataRepository.last_error, "tables.csv")

func test_index_passes_when_every_table_is_on_disk() -> void:
	assert_true(DataRepository.check_index(OK), DataRepository.last_error)

## A table moved by hand (Finder) without its tables.csv row must fail the
## load by name, never load as an empty table.
func test_index_row_without_its_file_fails_naming_it() -> void:
	assert_false(DataRepository.check_index("res://tests/fixtures/data_layout/missing"))
	assert_string_contains(DataRepository.last_error, "ghost")
	assert_string_contains(DataRepository.last_error, "alpha/ghost.csv")

func test_folder_without_balance_is_skipped() -> void:
	# gamma is indexed but holds no balance.csv
	assert_false(FileAccess.file_exists(OK + "/gamma/balance.csv"))
	assert_eq(DataRepository.load_balance(OK).size(), 2)
