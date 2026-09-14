extends GutTest

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

func test_briefing_has_opener_and_pitches() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := engine.advance(s)
	# The month's settlement fills the civil pool (spec 2026-09-14 §5); it
	# is emptied after it and the concerns rescanned, so the steward has
	# his grain line to speak.
	s.metrics["grain"] = 10.0
	r.concerns = ConcernScanner.scan(s, data)
	r.suggestions = engine.suggestions.generate(s, r.concerns)
	var lines := TemplateVoicer.render_briefing(r, s, data)
	assert_gt(lines.size(), 1)
	assert_eq(lines[0]["speaker"], "Aldwin Reeve")  # chancellor opens
	assert_string_contains(lines[0]["text"], "year 1")
	var joined := ""
	for l in lines:
		joined += l["text"] + "\n"
		assert_false("{" in l["text"], "unfilled placeholder in: " + l["text"])
	assert_string_contains(joined, "Grain")

func test_trait_variant_preferred() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["army_quality"] = 30.0
	var r := engine.advance(s)
	var lines := TemplateVoicer.render_briefing(r, s, data)
	var brandt_lines := ""
	for l in lines:
		if l["speaker"] == "Ser Brandt of Harrow":
			brandt_lines += l["text"]
	# Brandt is `bold`; the bold pitch variant must win over the generic one
	assert_string_contains(brandt_lines, "worth fearing")

func test_outcomes_narrated_deterministically() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var r := engine.advance(s)
	var a := TemplateVoicer.render_outcomes(r, s, data)
	var b := TemplateVoicer.render_outcomes(r, s, data)
	assert_eq(a.size(), 1)
	assert_string_contains(a[0]["text"], "muster")
	assert_eq(a, b)
