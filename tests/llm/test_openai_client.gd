extends GutTest

# Direct unit tests of _extract_text — no network, no HTTPRequest involved.
# It must never crash on malformed-but-present "choices": a crash here would
# happen inside the request_completed callback, meaning `completed` never
# emits and the caller's cb never fires.

func test_extract_text_choice_missing_message_returns_empty() -> void:
	var raw := JSON.stringify({"choices": [{}]})
	assert_eq(OpenAIClient._extract_text(raw), "")

func test_extract_text_empty_choices_array_returns_empty() -> void:
	var raw := JSON.stringify({"choices": []})
	assert_eq(OpenAIClient._extract_text(raw), "")

func test_extract_text_missing_choices_key_returns_empty() -> void:
	var raw := JSON.stringify({})
	assert_eq(OpenAIClient._extract_text(raw), "")

func test_extract_text_valid_shape_returns_content() -> void:
	var raw := JSON.stringify({"choices": [{"message": {"content": "hear ye, taxes fall"}}]})
	assert_eq(OpenAIClient._extract_text(raw), "hear ye, taxes fall")
