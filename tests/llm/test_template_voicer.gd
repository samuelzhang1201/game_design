extends GutTest

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

## A trait-tinted line beats the generic one for a speaker who has the trait
## (the council's concern and pitch lines go through line_for).
func test_trait_variant_preferred() -> void:
	var bold := TemplateVoicer.line_for(data, "pitch_raise_levies", ["bold"], 3, {"tradeoff": ""})
	assert_string_contains(bold, "worth fearing", "the bold variant wins")
	var plain := TemplateVoicer.line_for(data, "pitch_raise_levies", [], 3, {"tradeoff": ""})
	assert_false(plain.contains("worth fearing"), "a speaker without the trait gets the generic line")

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
