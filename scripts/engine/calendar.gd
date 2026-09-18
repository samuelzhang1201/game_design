class_name Calendar
extends RefCounted
## Pure date math over the tick clock: 12 ticks/year, 30 days/tick — a tick
## is a MONTH (owner 2026-09-14) — 4 seasons x 90 days (a 360-day year).
## Presentation helper - no state, no RNG, single source of truth for
## season/year boundaries (tick 1..12 is year 1; each season spans exactly
## 3 ticks).

const DAYS_PER_TICK := 30
const TICKS_PER_YEAR := 12
const DAYS_PER_SEASON := 90
const DAYS_PER_YEAR := 360
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

static func absolute_day(tick: int, day_in_tick: int = DAYS_PER_TICK) -> int:
	var t := maxi(tick, 1)
	return (t - 1) * DAYS_PER_TICK + clampi(day_in_tick, 1, DAYS_PER_TICK)

static func year_of(tick: int) -> int:
	@warning_ignore("integer_division")  # whole years
	return (absolute_day(tick, 1) - 1) / DAYS_PER_YEAR + 1

static func season_name(tick: int) -> String:
	@warning_ignore("integer_division")  # whole seasons
	return SEASONS[((absolute_day(tick, 1) - 1) % DAYS_PER_YEAR) / DAYS_PER_SEASON]

static func day_of_season(tick: int, day_in_tick: int = DAYS_PER_TICK) -> int:
	return ((absolute_day(tick, day_in_tick) - 1) % DAYS_PER_SEASON) + 1

static func date_string(tick: int, day_in_tick: int = DAYS_PER_TICK) -> String:
	return "%s %d, Year %d" % [
		season_name(tick), day_of_season(tick, day_in_tick), year_of(tick)]
