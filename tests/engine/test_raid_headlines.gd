extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The news bar's raid lines (owner 2026-10-11: 加一行劫掠进 Log):
## RaidSystem.headlines turns the day's raid_begin and raid_spoils events into
## one line each from templates.csv raid_news_*, with the bound raider realm
## filled in, and says nothing for the quiet raid_day or a host_mode event.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_a_raid_begun_and_spoils_make_one_line_each() -> void:
	var raider := String(repo.realm_vars()["raider_realm"])
	var lines := RaidSystem.headlines(repo, [
		{"kind": "raid_begin", "host": "H1", "day": 40, "cell": 7, "place": "Walbover"},
		{"kind": "raid_day", "host": "H1", "day": 40, "cell": 7, "take": 12},
		{"kind": "host_mode", "type": "host_mode", "host": "H1", "mode": "ADVANCE"},
		{"kind": "raid_spoils", "host": "H2", "day": 40, "spoils": 340, "plunder": 500, "place": "Treton"},
	])
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], "%s's raiders are stripping Walbover." % raider)
	assert_eq(lines[1], "Spoils at Treton: 340 in strategic goods come into the stores.")


func test_no_raid_event_makes_no_line() -> void:
	assert_eq(RaidSystem.headlines(repo, []).size(), 0)
	assert_eq(RaidSystem.headlines(repo, [{"kind": "raid_day", "host": "H1"}]).size(), 0)
