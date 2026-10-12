extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The honour bound (spec 2026-10-12-development-axes-design §4): at the
## Chivalry tier carrying the `honour_bound` flag the crown may not decree the
## two ways of denying a beaten foe mercy.

var repo: DataRepository
var s: GameState
var actions: ActionSystem
var realm: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	actions = ActionSystem.new(repo)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	DevelopmentSystem.seed(repo, s)


func _law(law: String, value: String) -> ActionRequest:
	return ActionRequest.make("LAW_SET", {"law": law, "value": value})


func _tier(t: int) -> void:
	s.development[realm]["tier_chivalry"] = t


func _word() -> String:
	return String(repo.law_words["honour_bound_refusal"])


func test_flag_off_below_tier() -> void:
	_tier(0)
	assert_false(DevelopmentSystem.flag(repo, s, realm, "honour_bound"))
	_tier(1)
	assert_false(DevelopmentSystem.flag(repo, s, realm, "honour_bound"))
	_tier(2)
	assert_true(DevelopmentSystem.flag(repo, s, realm, "honour_bound"))


func test_executing_prisoners_refused_at_honour_bound() -> void:
	_tier(1)
	assert_eq(actions.validate(_law("ransom", "execute"), s), "", "tier 1 may")
	_tier(2)
	assert_eq(actions.validate(_law("ransom", "execute"), s), _word())
	assert_eq(LawSystem.refusal_of(repo, s, "ransom", "execute")["key"], "honour_bound")
	assert_ne(_word(), "")


func test_quarter_refuse_refused_at_honour_bound() -> void:
	_tier(1)
	assert_eq(actions.validate(_law("quarter", "refuse"), s), "")
	_tier(2)
	assert_eq(actions.validate(_law("quarter", "refuse"), s), _word())
	assert_eq(actions.validate(_law("quarter", "give"), s), "Quarter is already give", "the other option is not bound")


func test_other_laws_unaffected() -> void:
	_tier(2)
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	assert_eq(actions.validate(_law("tax_rate", str(now + 1 if now < 10 else now - 1)), s), "")
	assert_eq(actions.validate(_law("tolerance", "edict"), s), "")
