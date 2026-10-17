class_name GameState
extends RefCounted

var tick: int = 0
## The day within the tick, 1..Calendar.DAYS_PER_TICK (owner 2026-09-13:
## the smallest unit of time is a day; the clock advances it, and the
## thirtieth day's end is the tick). Saved; an old save loads at day 1.
var day: int = 1
var rng: Rng
var metrics: Dictionary = {}
var characters: Dictionary = {}
var council: Dictionary = {}
## Role-to-role edges; shape and mutation API in RelationshipGraph.
var relationships: Array = []
## Facts and who knows them; shape and API in KnowledgeBase.
var knowledge: Dictionary = {}
## "speaker>listener" -> {"value", "log"}; API in SourceTrust.
var source_trust: Dictionary = {}
## Claim records; shape and API in ClaimLedger.
var claims: Array = []
## What each character remembers being told; shape and API in AgentMemory.
var agent_memory: Dictionary = {}
## A save's chosen identity from the days of character creation
## ({"first_name", "family_name", "house_was"}): the realm and the ruler are
## no longer customised (owner 2026-09-30), so a new reign leaves it empty,
## but an old save may carry it and HouseArms / MapManors still read
## house_was, the royal house's name before it was renamed.
var player_setup: Dictionary = {}
## The king's physical position and current journey (battle-system spec §11).
## This is separate from the royal regiment's piece and the prose location.
var king_state: Dictionary = {}
## Where the player stands (data/story/locations.csv). Moving within a region is
## free (LocationSystem); saved with everything else.
var current_location: String = LocationSystem.DEFAULT_LOCATION
var cooldowns: Dictionary = {}
var recent_outcomes: Array = []
var promises: Array = []
var event_state: Dictionary = {
	"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
	"flags": [], "last_action_tick": {},
}
var pending_event: Dictionary = {}

const SEASONS := ["spring", "summer", "autumn", "winter"]

## Every metric a campaign starts with, in one place: new_campaign seeds a
## fresh state from it and from_dict fills whatever an older save is missing,
## so nothing that reads `state.metrics` can meet an absent key. Called
## without a repository (from_dict has none at hand) every figure is 0 — the
## honest default for the pools, and an older save carries the rest.
static func default_metrics(data: DataRepository = null) -> Dictionary:
	var b := func(key: String) -> float: return 0.0 if data == null else data.bal(key)
	return {
		# The CROWN's pools — the realm's treasury and stores (owner
		# 2026-09-14: marked with the crown).
		"treasury": b.call("start_treasury"),
		"strategic": 0.0,
		"grain": 0.0,  # the CIVIL pool (spec 2026-09-14 §5); the key stays for its readers
		# The LORD's own purse — what the player's house holds as lord of its
		# own provinces and may spend freely (owner 2026-09-14: marked with
		# the family's arms). Its own manors pay into it; manors inside the
		# realm are bought from it.
		"lord_gold": 0.0,
		"lord_strategic": 0.0,
		"lord_civil": 0.0,
		"tax_rate": b.call("start_tax_rate"),
		"tariff_rate": b.call("start_tariff_rate"),
		"tax_income": 0.0,
		"admin_capacity": b.call("admin_base"),
		"legitimacy": b.call("start_metric_default"),
		"unrest": 0.0,
		"army_quality": b.call("start_metric_default"),
		"church_opinion": b.call("start_metric_default"),
		"peasant_contentment": b.call("start_metric_default"),
		"road_income_bonus": 0.0,
		"grain_ration": 0.0,
	}

static var campaign_error := ""

static func new_campaign(data: DataRepository, seed_value: int) -> GameState:
	campaign_error = ""
	var split := ArmySplit.split(data)
	if split.has("error"):
		campaign_error = String(split["error"])
		return null
	var s := GameState.new()
	s.map_id = data.map_id
	s.king_state = KingSystem.initial_state(data)
	s.rng = Rng.new(seed_value)
	s.metrics = default_metrics(data)
	s.characters = CharacterFactory.build_roster(data)
	# One truth (owner ruling 2026-09-09): the pack's economy row seeds the
	# player's treasury and rates over the balance defaults above — after the
	# roster, because the chest is the crown's own provinces' (2026-09-13)
	# and the crown is the player character's house.
	WorldLedger.seed_metrics(data, s)
	# The validated army as its units (spec 2026-10-07-army-split-and-ground §3).
	s.army_roster = split["roster"]
	s.town_seat = split["seats"]
	var personnel := MilitaryBootstrap.initialize(data, s)
	if personnel.has("error"):
		campaign_error = String(personnel["error"])
		return null
	ArmySystem.ensure(data, s)
	# The raid hosts stand at their assembly points until their day (spec
	# 2026-10-07-enemy-ai-and-battle §2): foes, not regiments.
	for host: Dictionary in data.raid_hosts:
		EnemyAi.spawn(data, s, host)
	# The pools as each town holds them (spec 2026-10-07-army-supply-lines §3.1).
	TownStores.seed_from_pools(data, s)
	# The laws start as the metrics and the pack's economy row left them.
	LawSystem.seed(data, s)
	DevelopmentSystem.seed(data, s)
	for id in s.characters:
		if s.characters[id].seat != "":
			s.council[s.characters[id].seat] = id
	# The prologue is a chain, not a pool: a chapter beat whose row names a
	# start_tick is scheduled here, so a new reign opens on the first council
	# rather than on whatever the random roll happens to pick
	# (data/story/chapter_events.csv, game_story/chapter_0/chapter_0_events.md).
	for row: Dictionary in data.chapter_events:
		var start := String(row.get("start_tick", "")).strip_edges()
		if start != "":
			s.event_state["scheduled"].append(
				{"event_id": String(row["event_id"]), "due_tick": int(start)})
	s.relationships = RelationshipGraph.init_from_data(data)
	s.knowledge = KnowledgeBase.init_from_data(data, s)
	s.source_trust = SourceTrust.init_from_relationships(data, s)
	# The pack's zones are the reign's opening hazards (spec 2026-10-07-war-room-p2 §2.2).
	Hazards.seed_pack(data, s, 0)
	# The reign opens with its provinces' wealth already settled (Ruling 15).
	Intel.settle_wealth_tiers(data, s)
	return s

## The day counted from the reign's first: what works in progress are
## measured against.
func absolute_day() -> int:
	return Calendar.absolute_day(tick, day)

func season() -> String:
	# Delegates to Calendar so tick 1..24 is year 1 with 6 ticks per season
	# (fixes the old 0-based off-by-one where tick 24 read as spring, year 2).
	return Calendar.season_name(tick).to_lower()

func year() -> int:
	return Calendar.year_of(tick)

## Godot 4.7.1 has a verified engine bug: JSON.parse_string(JSON.stringify(x,
## "", true, true)) mis-decodes a meaningful fraction of float64 values by
## exactly 1 ULP (independently confirmed: ~30% of a 10k-sample random-double
## corpus round-tripped to a different bit pattern). JSON's own float
## formatting/parsing cannot be trusted for save determinism, so every
## numeric leaf is instead round-tripped as a hex-encoded byte string
## (mirrors how Rng.to_dict already string-encodes its state "to preserve
## precision"), which IS bit-exact (0/10000 mismatches on the same corpus).
const _ENCODED_FLOAT_LEN := 17 # "f" + 16 hex nibbles of a float64

static func _float_to_hex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()

static func _hex_to_float(s: String) -> float:
	return s.hex_decode().decode_double(0)

## True iff s is "i" followed by the canonical rendering of a 64-bit int —
## the shape _encode_values gives ints. The check is a str() round trip, so
## it rejects "i007", "i+5", "i1e3" and any game content string that merely
## starts with an i: only what the encoder wrote ever decodes back.
static func _is_encoded_int(s: String) -> bool:
	if s.length() < 2 or s.unicode_at(0) != 105: # 'i'
		return false
	var body := s.substr(1)
	return body.is_valid_int() and str(body.to_int()) == body

## True iff s is exactly "f" followed by 16 lowercase hex digits — the shape
## produced by _encode_values below. Strict on purpose: game content strings
## (event ids, reasons, trait names) never accidentally match this 17-char
## shape, but the decoder checks anyway rather than assuming.
static func _is_encoded_float(s: String) -> bool:
	if s.length() != _ENCODED_FLOAT_LEN or s.unicode_at(0) != 102: # 'f'
		return false
	for i in range(1, _ENCODED_FLOAT_LEN):
		var c := s.unicode_at(i)
		var is_digit := c >= 48 and c <= 57 # '0'-'9'
		var is_lower_hex := c >= 97 and c <= 102 # 'a'-'f'
		if not (is_digit or is_lower_hex):
			return false
	return true

## Recursively encodes every int/float leaf in an arbitrarily-nested
## Dictionary/Array/scalar, replacing the old _normalize_ints (which only
## cast int->float and left the float encoding to JSON, exactly the code
## path the ULP bug lives in). Strings pass through unchanged.
##
## Ints and floats encode differently on purpose (save version 4): JSON.parse
## hands back EVERY number as a float — verified 4.7.2, and ints above 2^53
## come back rounded — so an int written as a bare number, or as the float
## hex the encoder used to give it, loaded as a float. Attributes, skills and
## ideology are ints, so a loaded campaign disagreed in type with a fresh one
## everywhere but `opinion`, which from_dict happened to cast back.
static func _encode_values(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _encode_values(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_encode_values(v))
		return out
	elif typeof(value) == TYPE_INT:
		return "i" + str(value)
	elif typeof(value) == TYPE_FLOAT:
		return "f" + _float_to_hex(value)
	return value

## A save written before skims were kept per flow (final review I1) holds
## one whole number per man: no one can say which flow it came from, so it
## is kept under "unknown" — his, but no audit of a flow will find it.
static func _migrate_skims(raw: Dictionary) -> Dictionary:
	var out := {}
	for gid in raw:
		var v: Variant = raw[gid]
		if v is Dictionary:
			out[gid] = v
		elif int(v) > 0:
			out[gid] = {"unknown": int(v)}
	return out

## Inverse of _encode_values: recursively decodes hex-encoded floats back to
## float and encoded ints back to int, leaving everything else (plain
## strings, bools, already-nested structures) untouched. Saves written before
## version 4 carry ints in the float encoding; those still load, as floats —
## the same values this build produced before, so no migration is needed.
## A plain JSON value with every number made whole again (JSON reads them as
## floats); strings untouched.
static func _whole(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _whole(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_whole(v))
		return out
	elif typeof(value) == TYPE_FLOAT:
		return int(round(value))
	return value

static func _decode_values(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _decode_values(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_decode_values(v))
		return out
	elif value is String and _is_encoded_float(value):
		return _hex_to_float(value.substr(1))
	elif value is String and _is_encoded_int(value):
		return value.substr(1).to_int()
	return value

## Bump when the save shape changes incompatibly; from_dict refuses saves
## newer than it knows (write the matching migration when bumping).
## The map pack this campaign is played on (data/world/maps.csv). Part of the
## world definition, so it is saved: reloading must restore the same world,
## not whichever map happens to be default.
var map_id: String = ""
## province_code -> kingdom_code, holding ONLY the provinces that have changed
## hands. An absent province still belongs to whoever the pack says, so an
## untouched campaign carries nothing here and a pack swap re-reads starting
## ownership. Read it through MapOwnership, never directly.
var province_owner: Dictionary = {}
## One entry per transfer: {tick, province, from, to, reason}. Same rule as
## opinion deltas — a border that moved must be able to say why.
var territory_log: Array = []
## The world ledger's overrides: resolved path -> value, holding ONLY fields
## that have moved (WorldLedger, spec 2026-09-09 §2). An absent path still
## reads the pack's starting value. Read and write it through WorldLedger,
## never directly.
var world: Dictionary = {}
## One entry per ledger write: {tick, path, delta, reason, source}.
var world_log: Array = []
## Manors (MANOR_SYSTEM.md): cell id (as a String, for JSON) -> the family
## holding it, ONLY for manors that changed hands — an absent manor still
## belongs to its province's house. Read through MapManors, never directly.
var manor_owner: Dictionary = {}
## cell id (String) -> [building codes] raised on it (data/economy/manor_buildings.csv).
var manor_buildings: Dictionary = {}
## cell id (String) -> [{building, start, days}]: works in progress on a
## manor (owner 2026-09-13: building takes time) — start is the absolute
## day the work began, days its build_days; MapManors.advance_works moves
## a finished one into manor_buildings.
var manor_works: Dictionary = {}
## cell id (String) -> {focus, since}: the chief good a manor was SET to
## work at (data/economy/manor_focus.csv) and the tick it was set, ONLY for manors
## whose focus was chosen — an absent manor works its terrain's default.
var manor_focus: Dictionary = {}
## cell id (String) -> permille (0 or 500) for each war workshop set away
## from full (spec 2026-09-30-ledger-supply-design §2); full is not stored.
var workshop_rate: Dictionary = {}
## cell id (String) -> [building codes] idle THIS month for want of inputs
## (spec 2026-09-30-ledger-industry-trade-design M5): a building whose
## inputs the lord's stores could not pay for makes and eats nothing.
## Rewritten whole by every settlement (IndustrySystem.settle_month).
var idle_buildings: Dictionary = {}
## Kingdom codes whose trade route the crown has closed (LEDGER M6): a
## closed route still carries its trade in the books, and pays no toll.
var closed_routes: Array = []
## flow type -> character id, only flows given away from their seat (M3).
var governors: Dictionary = {}
## character id -> {flow type -> whole gold skimmed on that flow since an
## audit of it last caught him} (M3; the truth). Per FLOW (final review I1):
## the audit of a flow reads that flow's books, whoever kept them.
var skims: Dictionary = {}
## character id -> [{flow, day, amount}] every time an audit caught him (M3).
var caught: Dictionary = {}
## character id -> [record lines], permanent, each a reason (M3; the debrief's data).
var records: Dictionary = {}
## cell id (String) -> province_code, ONLY for manors moved out of their pack
## province: a manor bought across the border joins the realm's province it
## borders (owner 2026-09-14). Read through MapManors.province_of, never directly.
var manor_province: Dictionary = {}
## One entry per transfer {tick, cell, from, to, reason} or building
## {tick, cell, building, reason}: a manor that changed must say why.
var manor_log: Array = []
## The player's regiments (owner 2026-09-17, ArmySystem): code ->
## {morale, wounded, dead, supplies, training, carry_days, the march fields
## x_m / y_m / dest_x_m / dest_y_m / order, the battle stance (a
## battle_stances.csv key) with a delivered stance_next / stance_order_id, and
## disengaging while it falls back from a battle, disengaged_until (the
## last absolute day of a pause with no contact) after a drawn battle}, whole numbers but the
## stance and order names. Only the
## player's realm's regiments; the pack's arms stay the headcount.
var regiments: Dictionary = {}
## The raider realm's regiments in the field (spec 2026-10-07-enemy-ai-and-
## battle §2): regiment code -> a state of the same shape as `regiments`, kept
## APART so the player-only iterations (supply lines, the LEDGER, hazards, the
## map) never see a foe. ArmySystem.state_of reads both.
var foes: Dictionary = {}
## The enemy hosts' minds (§2, EnemyAi): host code -> {mode, target_kind,
## target_id, think_day, plunder, siege_progress}, ints and strings.
var ai_hosts: Dictionary = {}
## The battles being fought (§4, BattleSystem): an Array of {id, att, def
## (regiment codes), start_day, rounds, place_x_m, place_y_m, town}.
var battles: Array = []
## Stable paid warrants and terminal results, retained after battlefield removal.
var battle_orders: Dictionary = {}
## Saved daily offers (including no-event), decisions and durable report receipts.
var battle_events: Dictionary = {}
## The towns lost to a siege (spec 2026-10-07-enemy-ai-and-battle §6,
## DefeatSystem): an Array of {town, host, day (absolute)}, one per loss; the
## key that makes a loss cost the crown once.
var town_losses: Array = []
## What the crown last knew of the enemy's men (spec 2026-10-10-player-sight-
## and-ghosts, Sighting): key (a foe unit's code, or Sighting.HOST_KEY + a host
## code for the border rumour) -> {kind ("unit" | "host"), code, x_m, y_m
## (whole metres), day (absolute), source ("seen" | "spy" | "rumour"), men
## (an estimate, 0 unknown)}. Ints and strings.
var sightings: Dictionary = {}
## The scouts' and contact letters already sent (spec 2026-10-14-unit-clearance-
## and-scouting-design §c, Sighting.scout_day): a foe unit's code -> {scout, contact}
## (the absolute day of the last letter of each kind; a key is absent until that
## kind has been sent). Ints. An old save has none.
var scout_log: Dictionary = {}
## The last id handed to a foe or a battle (a higher id is a newer one).
var foe_next_id := 0
## Every kingdom's army as UNITS (owner 2026-10-07, spec
## 2026-10-07-army-split-and-ground §2.1): unit code -> a row shaped as
## military/regiments.csv's, + parent_code, is_royal, camp_town. Split from
## the pack once, as the campaign starts (ArmySplit); read through
## ArmySystem.roster / regiment, never directly.
var army_roster: Dictionary = {}
## One personnel ledger: projects and prisoner batches reference these cohorts.
var military_rosters: Dictionary = {}
var military_cohorts: Dictionary = {}
var military_events: Dictionary = {}
var prisoner_batches: Dictionary = {}
var prisoner_events: Dictionary = {}
var battle_records: Dictionary = {}
var recruitment_projects: Dictionary = {}
var military_migration: Dictionary = {}
## town code -> the one unit holding its seat (ArmyGround, spec §4.4).
var town_seat: Dictionary = {}
## The couriers on the road (owner 2026-09-27, CourierSystem): an Array of
## Dictionaries in whole metres and ints, walked in ascending id order.
var couriers: Array = []
## The last courier id handed out; a higher id is a NEWER order.
var next_courier_id := 0
## The WAR ROOM's pencilled orders (spec 2026-10-02-war-room-v2 §3.1,
## WarDrafts): regiment code -> {order, dest_x_m, dest_y_m, tick, day, refused}.
var war_drafts: Dictionary = {}
## The WAR ROOM's plans (spec 2026-10-07-war-room-annotations-and-planning-
## pieces §1.1, WarPlans): the player's own paper — supposed enemy pieces and
## the staff's strokes, in whole metres; no engine rule reads them.
var war_plans: Dictionary = WarPlans.empty()
## The letters the crown has received (owner 2026-09-28, MissiveLog): an Array
## of Dictionaries, whole numbers and strings only.
var missives: Array = []
var next_missive_id := 0
## The highest missive id the player has SEEN (owner 2026-10-10: the MISSIVE
## tab counts only letters not yet seen): the board shown marks every letter
## seen; a letter above it is new unless its own `seen` is set (a spy's report
## opened in its dialog). MissiveLog.unseen reads it.
var missives_seen_id := 0
## Each province's wealth tier, 0 poor / 1 middling / 2 rich (Ruling 15,
## 2026-09-28): settled by TickEngine right after the month's economy
## (Intel.settle_wealth_tiers), so a card opened mid-month can never decide
## what a spy's saved report says. province_code -> int.
var wealth_tiers: Dictionary = {}
## Each realm town's strategic stores in SUPPLY UNITS (spec 2026-10-07-army-
## supply-lines §2.1, TownStores): burg -> {crown, lord, house}. crown and
## lord sum to metrics.strategic / lord_strategic; house is a house's stock
## the crown may buy.
var town_stock: Dictionary = {}
## The supply lines (spec 2026-10-07-army-supply-lines §2.1, SupplyLines):
## regiment code -> {town, rate, state, order_id, ready_day, cut_x_m, cut_y_m,
## cut_by, fee_milli, buy_milli, pending, warned, m_*}. Whole numbers only.
var supply_lines: Dictionary = {}
## The hazards that come and go (spec 2026-10-07-war-room-p2-tactical-layer §2,
## Hazards): id -> {kind, label, cells, start, end, source}, whole numbers;
## an ended one stays (end <= tick) as the record.
var hazards: Dictionary = {}
## True once the pack's zones were seeded (a new reign, or once for an old save).
var hazards_seeded := false
## Bumped by every change to `hazards` (Hazards' cell index); not saved.
var hazards_rev := 0
## The laws (spec 2026-10-08-laws-tab-design §2.2, LawSystem). Values are
## Strings ("on", a choice's name, a range's digits).
## law_code -> {value, decree_id, day}: what the crown has decreed.
var law_decree: Dictionary = {}
## The development axes (spec 2026-10-12-development-axes-design §2,
## DevelopmentSystem): realm code -> {renaissance, chivalry, tier_renaissance,
## tier_chivalry}, whole numbers; and every move with its reason.
var development: Dictionary = {}
var development_log: Array = []
## scope_key ("province:<code>", "town:<code>", "unit:<code>") -> {law_code ->
## {value, decree_id}}: what each place or unit follows. A place with no entry
## follows the law's default. Read it through LawSystem.value.
var law_in_force: Dictionary = {}
## law_code -> the tick until which the law is on cooldown.
var law_cooldown: Dictionary = {}
## Foraging and desertion (spec 2026-10-10-foraging-and-desertion §2). Whole
## numbers and plain Strings only. province code -> per mille of its stores
## stripped by foragers (non-zero entries only).
var forage_stripped: Dictionary = {}
## kingdom code -> grievance points the crown's foraging has stored there.
var grievance: Dictionary = {}
## conduct news key -> the month index it was last told (once-only marks).
var conduct_marks: Dictionary = {}

## An unfinished day, including its output journal and pending decision.
var day_resolution: Dictionary = {}

const SAVE_VERSION := 7
## The oldest save this build loads (spec 2026-10-07-army-split-and-ground
## §2.3): a save from before the split names regiments that no longer exist.
const MIN_SAVE_VERSION := 6

func to_dict() -> Dictionary:
	var chars := {}
	for id in characters:
		chars[id] = characters[id].to_dict()
	return {
		"version": SAVE_VERSION, "map_id": map_id,
		"tick": _encode_values(tick), "day": _encode_values(day), "rng": rng.to_dict(),
		"metrics": _encode_values(metrics.duplicate()),
		"characters": chars, "council": council.duplicate(),
		"relationships": _encode_values(relationships.duplicate(true)),
		"knowledge": _encode_values(knowledge.duplicate(true)),
		"source_trust": _encode_values(source_trust.duplicate(true)),
		"claims": _encode_values(claims.duplicate(true)),
		"agent_memory": _encode_values(agent_memory.duplicate(true)),
		"player_setup": player_setup.duplicate(true),
		"king_state": _encode_values(king_state.duplicate(true)),
		"current_location": current_location,
		"cooldowns": _encode_values(cooldowns.duplicate()),
		"recent_outcomes": _encode_values(recent_outcomes.duplicate(true)),
		"promises": _encode_values(promises.duplicate(true)),
		"event_state": _encode_values(event_state.duplicate(true)),
		"pending_event": _encode_values(pending_event.duplicate(true)),
		"province_owner": province_owner.duplicate(),
		"territory_log": _encode_values(territory_log.duplicate(true)),
		"world": _encode_values(world.duplicate()),
		"world_log": _encode_values(world_log.duplicate(true)),
		"manor_owner": manor_owner.duplicate(),
		"manor_province": manor_province.duplicate(),
		"manor_buildings": manor_buildings.duplicate(true),
		"manor_focus": manor_focus.duplicate(true),
		"workshop_rate": _encode_values(workshop_rate.duplicate(true)),
		"idle_buildings": idle_buildings.duplicate(true),
		"closed_routes": closed_routes.duplicate(),
		"governors": governors.duplicate(true),
		"skims": _encode_values(skims.duplicate(true)),
		"caught": _encode_values(caught.duplicate(true)),
		"records": records.duplicate(true),
		"manor_works": _encode_values(manor_works.duplicate(true)),
		"manor_log": _encode_values(manor_log.duplicate(true)),
		"regiments": _encode_values(regiments.duplicate(true)),
		"foes": _encode_values(foes.duplicate(true)),
		"ai_hosts": _encode_values(ai_hosts.duplicate(true)),
		"battles": _encode_values(battles.duplicate(true)),
		"battle_orders": battle_orders.duplicate(true),
		"battle_events": _encode_values(battle_events.duplicate(true)),
		"day_resolution": _encode_values(day_resolution.duplicate(true)),
		"military_rosters": military_rosters.duplicate(true),
		"military_cohorts": military_cohorts.duplicate(true),
		"military_events": military_events.duplicate(true),
		"prisoner_batches": prisoner_batches.duplicate(true),
		"prisoner_events": prisoner_events.duplicate(true),
		"battle_records": battle_records.duplicate(true),
		"recruitment_projects": recruitment_projects.duplicate(true),
		"military_migration": military_migration.duplicate(true),
		"town_losses": _encode_values(town_losses.duplicate(true)),
		"sightings": _encode_values(sightings.duplicate(true)),
		"scout_log": _encode_values(scout_log.duplicate(true)),
		"foe_next_id": _encode_values(foe_next_id),
		"army_roster": army_roster.duplicate(true), "town_seat": town_seat.duplicate(true),
		"couriers": _encode_values(couriers.duplicate(true)),
		"war_drafts": _encode_values(war_drafts.duplicate(true)),
		# whole numbers and the player's own words only: written plain, so a
		# name shaped like the codec's "i5" stays a name (_whole reads it back)
		"war_plans": war_plans.duplicate(true),
		"next_courier_id": _encode_values(next_courier_id),
		"missives": _encode_values(missives.duplicate(true)),
		"next_missive_id": _encode_values(next_missive_id),
		"missives_seen_id": _encode_values(missives_seen_id),
		"wealth_tiers": _encode_values(wealth_tiers.duplicate()),
		"town_stock": _encode_values(town_stock.duplicate(true)),
		"supply_lines": _encode_values(supply_lines.duplicate(true)),
		"hazards": _encode_values(hazards.duplicate(true)),
		"hazards_seeded": hazards_seeded,
		"law_decree": _encode_values(law_decree.duplicate(true)),
		"development": _encode_values(development.duplicate(true)),
		"development_log": _encode_values(development_log.duplicate(true)),
		"law_in_force": _encode_values(law_in_force.duplicate(true)),
		"law_cooldown": _encode_values(law_cooldown.duplicate(true)),
		"forage_stripped": _encode_values(forage_stripped.duplicate(true)),
		"grievance": _encode_values(grievance.duplicate(true)),
		"conduct_marks": _encode_values(conduct_marks.duplicate(true)),
	}

## `invalidate` false for a scratch copy of the live state (Game.review_drafts):
## the live border caches stay warm, since the copy changes no owner.
static func from_dict(d: Dictionary, invalidate := true) -> GameState:
	# Pre-versioning saves carry no field and count as version 1. A newer
	# save fails closed (null) rather than half-loading; push_warning (not
	# push_error) so the refusal path stays testable under run_tests.sh's
	# exact engine-error count.
	if int(d.get("version", 1)) > SAVE_VERSION:
		push_warning("GameState: save version %d is newer than this build's %d"
			% [int(d.get("version", 1)), SAVE_VERSION])
		return null
	var s := GameState.new()
	s.day_resolution = _decode_values(d.get("day_resolution", {}))
	s.military_rosters = _whole(d.get("military_rosters", {}))
	s.military_cohorts = _whole(d.get("military_cohorts", {}))
	s.military_events = _whole(d.get("military_events", {}))
	s.prisoner_batches = _whole(d.get("prisoner_batches", {}))
	s.prisoner_events = _whole(d.get("prisoner_events", {}))
	s.battle_records = _whole(d.get("battle_records", {}))
	s.recruitment_projects = _whole(d.get("recruitment_projects", {}))
	s.military_migration = _whole(d.get("military_migration", {}))
	s.map_id = String(d.get("map_id", ""))
	s.tick = int(_decode_values(d["tick"]))
	s.day = clampi(int(_decode_values(d.get("day", 1))), 1, Calendar.DAYS_PER_TICK)
	s.rng = Rng.from_dict(d["rng"])
	s.metrics = _decode_values(d["metrics"])
	# A save written before a metric existed carries no key for it — the
	# pools, strategic and civil, are the newest. The template fills them in,
	# so no reader (the top bar's strip, the tick's settlement) has to guard.
	for key: String in default_metrics().keys():
		if not s.metrics.has(key):
			s.metrics[key] = 0.0
	for id in d["characters"]:
		s.characters[id] = Character.from_dict(d["characters"][id])
	s.council = d["council"].duplicate()
	s.relationships = _decode_values(d.get("relationships", []))
	s.knowledge = _decode_values(d.get("knowledge", {}))
	s.source_trust = _decode_values(d.get("source_trust", {}))
	s.claims = _decode_values(d.get("claims", []))
	s.agent_memory = _decode_values(d.get("agent_memory", {}))
	s.player_setup = d.get("player_setup", {}).duplicate(true)
	# Saves before the king's physical journey carry no location; Game.load_campaign
	# seeds that missing state from the saved world's bound capital.
	s.king_state = _decode_values(d.get("king_state", {}))
	s.current_location = String(d.get("current_location", LocationSystem.DEFAULT_LOCATION))
	var decoded_cooldowns = _decode_values(d["cooldowns"])
	for k in decoded_cooldowns:
		s.cooldowns[k] = int(decoded_cooldowns[k])
	s.recent_outcomes = _decode_values(d["recent_outcomes"])
	s.promises = _decode_values(d["promises"])
	s.event_state = _decode_values(d.get("event_state", {
		"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
		"flags": [], "last_action_tick": {},
	}))
	s.pending_event = _decode_values(d.get("pending_event", {}))
	# Saves written before territory could move carry neither key; an empty
	# override dict is exactly "everything still belongs to the pack".
	s.province_owner = d.get("province_owner", {}).duplicate()
	s.territory_log = _decode_values(d.get("territory_log", []))
	# Saves from before the ledger carry neither key: nothing has moved.
	s.world = _decode_values(d.get("world", {}))
	s.world_log = _decode_values(d.get("world_log", []))
	# Saves from before the manor system carry none of these: nothing moved.
	s.manor_owner = d.get("manor_owner", {}).duplicate()
	s.manor_province = d.get("manor_province", {}).duplicate()
	s.manor_buildings = d.get("manor_buildings", {}).duplicate(true)
	s.manor_focus = d.get("manor_focus", {}).duplicate(true)
	# Saves from before the war workshops carry no key: every workshop runs
	# in full (WorkshopSystem.rate_of's own default).
	s.workshop_rate = _decode_values(d.get("workshop_rate", {}))
	# Saves from before governors could be reassigned or skim carry none of
	# these: every flow runs at its seat holder, honestly, with no record.
	s.governors = d.get("governors", {}).duplicate(true)
	s.skims = _migrate_skims(_decode_values(d.get("skims", {})))
	s.caught = _decode_values(d.get("caught", {}))
	s.records = d.get("records", {}).duplicate(true)
	s.manor_works = _decode_values(d.get("manor_works", {}))
	# Saves from before buildings ate (M5) carry none: nothing stands idle.
	s.idle_buildings = d.get("idle_buildings", {}).duplicate(true)
	# Saves from before the trade routes (M6) carry none: every route is open.
	s.closed_routes = (d.get("closed_routes", []) as Array).duplicate()
	s.manor_log = _decode_values(d.get("manor_log", []))
	s.regiments = _decode_values(d.get("regiments", {}))
	# Saves from before the raiders carry none of these: no foe in the field.
	s.foes = _decode_values(d.get("foes", {}))
	s.ai_hosts = _decode_values(d.get("ai_hosts", {}))
	s.battles = _decode_values(d.get("battles", []))
	s.battle_orders = _whole(d.get("battle_orders", {}))
	s.battle_events = _decode_values(d.get("battle_events", {}))
	# Saves from before defeat carry no losses.
	s.town_losses = _decode_values(d.get("town_losses", []))
	# Saves from before the crown's sight carry no ghosts.
	s.sightings = _decode_values(d.get("sightings", {}))
	s.scout_log = _decode_values(d.get("scout_log", {}))
	s.foe_next_id = int(_decode_values(d.get("foe_next_id", 0)))
	# CSV fields remain strings; provenance counts are whole save facts.
	s.army_roster = _whole(d.get("army_roster", {}))
	s.town_seat = (d.get("town_seat", {}) as Dictionary).duplicate(true)
	# Saves from before the couriers carry neither key: no one is on the road.
	s.couriers = _decode_values(d.get("couriers", []))
	# Saves from before a courier carried several orders (owner 2026-10-10)
	# hold one `order`: it becomes his `orders` of one.
	for c: Dictionary in s.couriers:
		if c.has("order") and not c.has("orders"):
			c["orders"] = [c["order"]]
		c.erase("order")
	s.war_drafts = _decode_values(d.get("war_drafts", {}))
	# Saves from before the plans carry none: an empty table.
	s.war_plans = _whole(d.get("war_plans", WarPlans.empty()))
	s.next_courier_id = int(_decode_values(d.get("next_courier_id", 0)))
	# Saves from before the Missive board carry neither key: an empty board.
	s.missives = _decode_values(d.get("missives", []))
	s.next_missive_id = int(_decode_values(d.get("next_missive_id", 0)))
	# Saves from before the seen mark: every letter they hold counts as seen.
	s.missives_seen_id = int(_decode_values(d.get("missives_seen_id", s.next_missive_id)))
	# Saves from before the tiers were state carry none: Game.load_campaign
	# computes them once from the loaded state (Intel.ensure_wealth_tiers).
	s.wealth_tiers = _decode_values(d.get("wealth_tiers", {}))
	# Saves from before the town stores carry none: TownStores.ensure seeds
	# them from the pools on load (Game.load_campaign).
	s.town_stock = _decode_values(d.get("town_stock", {}))
	# Saves from before the supply lines carry none.
	s.supply_lines = _decode_values(d.get("supply_lines", {}))
	# Saves from before the hazards were state carry neither key: Game.load_campaign
	# seeds them once at the save's own tick (Hazards.ensure).
	s.hazards = _decode_values(d.get("hazards", {}))
	s.hazards_seeded = bool(d.get("hazards_seeded", false))
	# Saves from before the laws carry none: Game.load_campaign seeds them from
	# the metrics (LawSystem.ensure).
	s.law_decree = _decode_values(d.get("law_decree", {}))
	s.development = _decode_values(d.get("development", {}))
	s.development_log = _decode_values(d.get("development_log", []))
	s.law_in_force = _decode_values(d.get("law_in_force", {}))
	s.law_cooldown = _decode_values(d.get("law_cooldown", {}))
	s.forage_stripped = _decode_values(d.get("forage_stripped", {}))
	s.grievance = _decode_values(d.get("grievance", {}))
	s.conduct_marks = _decode_values(d.get("conduct_marks", {}))
	if invalidate:
		MapOwnership.invalidate()
	return s
