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

## The season of an absolute day, lower case ("spring".."winter") — the
## weather's odds are keyed by it.
static func season_of_day(abs_day: int) -> String:
	@warning_ignore("integer_division")  # whole seasons
	return String(SEASONS[((maxi(abs_day, 1) - 1) % DAYS_PER_YEAR) / DAYS_PER_SEASON]).to_lower()

static func day_of_season(tick: int, day_in_tick: int = DAYS_PER_TICK) -> int:
	return ((absolute_day(tick, day_in_tick) - 1) % DAYS_PER_SEASON) + 1

## date_string's words for an absolute day.
static func date_of_day(abs_day: int) -> String:
	var d := maxi(abs_day, 1) - 1
	@warning_ignore("integer_division")  # whole months
	return date_string(d / DAYS_PER_TICK + 1, d % DAYS_PER_TICK + 1)

static func date_string(tick: int, day_in_tick: int = DAYS_PER_TICK) -> String:
	return "%s %d, Year %d" % [
		season_name(tick), day_of_season(tick, day_in_tick), year_of(tick)]

const MONTH_ORDINALS := ["I", "II", "III"]

## A tick's place among its season's three months, 1..3 (fix round 1 finding
## 3: the steward's report needs a title unique to its month, not just its
## season).
static func month_ordinal_in_season(tick: int) -> int:
	return ((maxi(tick, 1) - 1) % 3) + 1

## "Spring II" — the season plus its month's ordinal in Roman numerals, since
## Calendar names no month of its own. Unique across the whole year (unlike
## season_name alone), used by the steward's report title.
static func month_label(tick: int) -> String:
	return "%s %s" % [season_name(tick), MONTH_ORDINALS[month_ordinal_in_season(tick) - 1]]
