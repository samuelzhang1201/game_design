extends GutTest
## Parent run_tests.sh owns the shared Godot lock; diagnostic children run serially.

const TOOL: String = "res://tools/units3d/royal_native_arithmetic/prove.py"
const PROOF_TESTS: String = "res://tools/units3d/royal_native_arithmetic/test_prove.py"


func test_exact_rational_hand_cases_and_tamper_controls() -> void:
	var output: Array = []
	var result: int = OS.execute("python3", [ProjectSettings.globalize_path(PROOF_TESTS)], output, true)
	assert_eq(result, 0, str(output))


func test_actual_selected_godot_process_math_imports_have_closed_proof() -> void:
	var base: String = ProjectSettings.globalize_path("res://.godot/royal-native-arithmetic-" + str(ResourceUID.create_id()))
	var output: Array = []
	var result: int = OS.execute("python3", [ProjectSettings.globalize_path(TOOL),
		"--capture", OS.get_executable_path(), "--scratch", base,
		"--receipt", base + "-receipt.json"], output, true)
	# An unknown CI/host profile fails with its native witness; it is never a skip.
	assert_eq(result, 0, str(output))
	if result != 0:
		return
	print("ROYAL_NATIVE_ARITHMETIC_CAPTURE ", FileAccess.get_file_as_string(base.path_join("capture.json")))
	print("ROYAL_NATIVE_ARITHMETIC_RECEIPT ", FileAccess.get_file_as_string(base + "-receipt.json"))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "-receipt.json"))
	assert_true(parsed is Dictionary)
	if parsed is Dictionary:
		assert_eq(parsed.get("status"), "closed_scalar_value_proof")
		assert_eq(parsed.get("schema"), "royal-native-arithmetic/1")
		assert_eq(parsed.get("engine_sha256"), FileAccess.get_sha256(OS.get_executable_path()))
