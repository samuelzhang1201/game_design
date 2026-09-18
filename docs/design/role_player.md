# Roles of the Court — Crown and Council

Design/persona layer for every role in the game, grounded in the story
background at [game_story/background/game_start.md](../../game_story/background/game_start.md).
**Numeric truth lives in the CSVs** (`data/founding_council.csv`,
`data/roles.csv`, `data/relationships.csv`, `data/character_traits.csv`) and is
loaded by the engine; this document is the human-readable view and the source
the LLM persona prompts are written from. Skills vocabulary:
[role_skills.md](role_skills.md). Personality vocabulary:
[role_personality.md](role_personality.md).

## The player

- **Title:** King Aldric Valorin, King of {player_realm}, Protector of the Northern Marches
- **Role played:** the newly crowned monarch (`id: you`), **age 40**, just
  ascended with grand ambitions — and a court already running with hidden
  currents. You never speak through the LLM — you type or click; every other
  role answers you in character.
- **Name:** the main menu's setup panel lets the player rename the king and
  the royal family (`GameState.apply_player_setup`); every role of the old
  family name follows, and `player_setup.house_was` keeps the old name so the
  crown's manors and arms still resolve. "Aldric Valorin" is the default.
- **Lord of one province** (owner 2026-09-13): besides the realm, the king
  personally controls the capital's province, with its own purse — see
  `MANOR_SYSTEM.md`.
- **House:** Valorin, the royal line of {player_realm}. Your first wife, of House
  O-kala, died years ago; your second marriage merged the crown with the
  Weighhouse banking clan.
- Portrait: `assets/portraits/you.png` (chip) / `assets/portraits/full/you.png` (full).

## Numeric attributes (all roles)

Stored in the CSVs, per role:

| Group | Metrics |
|---|---|
| Personality axes, 0–100 (drive engine formulas) | ambition, loyalty, integrity, boldness, piety, compassion, vanity, temper, pragmatism |
| Role-level metrics, 0–100 (stakes; engine-visible, wired post-MVP) | health, wealth, prestige, influence |
| Personal data | age (story-canonical where given: the king 40, Nora 19, Malvern 71) |

Skills are a separate 0–20 scale (`sk_admin`, `sk_martial`, `sk_intrigue`,
`sk_diplomacy`, `sk_steward`) — see [role_skills.md](role_skills.md).
Trait rows in `character_traits.csv` shift both at build time.

## The roster (21 roles)

### The royal family (category: player/family/relative)

| id | Name | Age | Station | Signature traits |
|---|---|---|---|---|
| `you` | King Aldric Valorin | 40 | The player — newly crowned | Vigorous |
| `char_queen` | Queen Victoria | 36 | Queen consort of the Weighhouse banking clan; oversees the kingdom's finances and steadily expands her family's reach | Merchant Family, Shrewd Trader, Silver Tongued, Patient |
| `char_princess` | Princess Nora O-kala | 19 | Your daughter by your late first wife — a fierce, formidable general serving with the army; your relationship is strained | Born Soldier, Bold, Master Duelist, Wrathful |
| `char_duke_tomas` | Duke Tomas Valorin | 44 | Your half-brother. Openly covets the throne — an open secret. Close to the great nobles; controls the kingdom's technology development | Royal Blood, Ruthlessly Ambitious, Learned, Silver Tongued |
| `char_lady_ysolde` | Lady Ysolde Valorin | 27 | Cousin; the court's social sun | Vain, Beloved of the Crowds, Trusting |

### Council of ministers (category: council)

| id | Name | Age | Seat | Story role |
|---|---|---|---|---|
| `char_chancellor` | Aldwin Reeve | 58 | Chancellor | The Chief Minister of Internal Affairs: greedy, cunning, devious — and something incriminating hangs over him | 
| `char_steward` | Mirella of the Weighhouse | 41 | Steward | The Minister of Finance — the queen's kinswoman. She knows the Chancellor's secret; the two are notoriously at odds |
| `char_marshal` | Ser Brandt of Harrow | 45 | Marshal | Nora's commander; House Harrow's sword |
| `char_spymaster` | Quill | 37 | Spymaster | Keeps a file on the Chancellor's appetites |
| `char_chaplain` | Father Odo | 63 | Chaplain | Losing his flock to a barefoot preacher |

### Officers, nobles, and the trusted adviser

| id | Name | Age | Station | Signature traits |
|---|---|---|---|---|
| `char_lord_malvern` | Lord Malvern | 71 | Your most trusted adviser — instrumental in securing your throne, hugely influential at court, but aged and in failing health (health 20) | Devoted, Patient, Learned, Sickly |
| `char_captain_hale` | Captain Hale Fenwick | 52 | Captain of the royal guard; first put a sword in Nora's hand | War Veteran, Devoted, Blunt, Humble |
| `char_lady_corina` | Lady Corina Ashvale | 43 | High noble power broker — her parlors lean toward Duke Tomas | High Nobility, Silver Tongued, Schemer, Patient |
| `char_lord_edgar` | Lord Edgar Harrow | 49 | Head of House Harrow, the Marshal's elder brother | High Nobility, Blunt, Bold, War Veteran |

### Enemies within (category: enemy)

| id | Name | Age | Station |
|---|---|---|---|
| `char_prophet_cassian` | Cassian the Barefoot | 33 | The voice of the food crisis: rallies demonstrations demanding grain relief and the punishment of corrupt officials — the Chancellor by name |

### Foreign powers (category: foreign)

| id | Name | Age | Station | Realm |
|---|---|---|---|---|
| `char_king_osric` | Warchief Osric | 47 | Warchief of the western steppe riders — restless, preparing to raid east | {raider_realm} |
| `char_queen_isabeau` | Queen Isabeau | 45 | Queen of {neighbor_realm}: holds {empire_realm}'s Emperor as a puppet, annexes the minor city-states, openly hostile to {player_realm} | {neighbor_realm} |
| `char_envoy_petra` | Envoy Petra Kolev | 38 | {neighbor_realm}'s ambassador at your court — and quietly cultivating your greedy Chancellor | {neighbor_realm} |
| `char_emperor` | Emperor Constans | 24 | {empire_realm}'s young Emperor — a seal and a chair in Isabeau's hands (prestige 90, influence 15) | {empire_realm} |

### Public celebrities (category: celebrity)

| id | Name | Age | Station |
|---|---|---|---|
| `char_bard_corvin` | Master Corvin Lute | 31 | The realm's most sung bard; Lady Ysolde's protégé |
| `char_guildmaster_tessa` | Guildmaster Tessa Marden | 39 | Merchant princess of the weavers' guild — the Weighhouse squeezes guilds that will not kneel |

## Relationships

Starting edges live in `data/relationships.csv` (directed:
`from_id,to_id,rel_type,sentiment,reason` — every edge carries a reason, the
same rule as opinion deltas). At campaign start they are copied into the save
(`GameState.relationships`) and from then on the graph is **dynamic**:

- **Shocks** — event choices can carry a `rel:<from>:<to>:<delta>:<reason>`
  effect op (see `EventEffects`); each shock is clamped ±100 and logged with
  its reason.
- **Healing** — each tick every edge drifts `relationship_drift_per_tick`
  (balance.csv) back toward its founding baseline: grudges cool, honeymoons fade.
- **LLM feed** — `PromptBuilder.persona_context(id, …)` serializes a role's
  current strongest edges (via `RelationshipGraph.describe_for`) into that
  role's context window, so what the model roleplays always matches live state.
- **In-game visual** — the bottom bar's RELATIONSHIP toggle opens the live
  node-edge overlay (`RelationshipGraphScreen`): the king at center, the court ringed
  around him, kin edges gold, friendships green, feuds red, thickness =
  strength. It redraws on every state change.

### Starting graph

```mermaid
graph TD
    YOU[King Aldric, 40]
    VICTORIA[Queen Victoria]
    NORA[Princess Nora O-kala]
    TOMAS[Duke Tomas]
    YSOLDE[Lady Ysolde]
    MALVERN[Lord Malvern]
    ALDWIN[Aldwin Reeve - Chancellor]
    BRANDT[Ser Brandt - Marshal]
    MIRELLA[Mirella - Steward]
    QUILL[Quill - Spymaster]
    ODO[Father Odo - Chaplain]
    HALE[Captain Hale]
    CORINA[Lady Corina Ashvale]
    EDGAR[Lord Edgar Harrow]
    CASSIAN[Cassian the Barefoot]
    OSRIC[Warchief Osric of {raider_realm}]
    ISABEAU[Queen Isabeau of {neighbor_realm}]
    PETRA[Envoy Petra]
    CONSTANS[Emperor Constans]
    CORVIN[Master Corvin]
    TESSA[Guildmaster Tessa]

    YOU ---|marriage +55| VICTORIA
    YOU -.-|kin +35/-10 strained| NORA
    YOU -.-|kin -35/-45| TOMAS
    YOU ---|ally +70/+75| MALVERN
    VICTORIA -.-|kin -15/-25 stepmother| NORA
    VICTORIA ---|kin +45/+50| MIRELLA
    TOMAS -.-|rival -35/-40| NORA
    TOMAS -.-|rival -35/-40| MALVERN
    TOMAS ---|ally +40| CORINA
    ALDWIN -.-|grudge -55/-60 the ledger| MIRELLA
    ALDWIN -.-|rival -20| VICTORIA
    ALDWIN ---|ally +20/+25| PETRA
    QUILL -.-|rival -30| ALDWIN
    BRANDT ---|kin +35| EDGAR
    BRANDT ---|ally +30| NORA
    EDGAR -.-|rival -30| CORINA
    HALE ---|liege +65| YOU
    HALE ---|ally +30| BRANDT
    NORA ---|admires +40| HALE
    CASSIAN -.-|grudge -40 food crisis| YOU
    CASSIAN -.-|grudge -55 corruption| ALDWIN
    ODO -.-|rival -45| CASSIAN
    OSRIC -.-|rival -60 raid coming| YOU
    ISABEAU -.-|rival -50 annexations| YOU
    PETRA ---|liege +60| ISABEAU
    ISABEAU ---|puppet +20/-60| CONSTANS
    MIRELLA ---|ally +40| TESSA
    TESSA -.-|rival -20| VICTORIA
    CORVIN ---|admires +50| YSOLDE
```

(Solid = positive/kin, dotted = negative. Numbers are starting sentiments;
the live values are in the save and on the RELATIONS screen.)

## Story tensions the graph encodes

1. **The succession** — Tomas covets the throne; Nora (19, a general, no
   brothers) stands between him and it; the dying Malvern is the wall that
   blocked him once.
2. **The purse** — Victoria and her Weighhouse kin (Mirella at the treasury)
   expand clan power; the guilds (Tessa) chafe; the Chancellor fears the
   queen's audits.
3. **The scandal** — Mirella holds proof that could hang the Chancellor;
   Quill keeps the file; Petra buys the leaks; Cassian shouts it in the square.
4. **The food crisis** — Cassian's demonstrations demand grain relief and
   corrupt heads; unrest is already smoldering (engine metrics: grain, unrest).
5. **Two borders** — {raider_realm} sharpens spears in the west; {neighbor_realm}
   annexes toward you in the north with a puppet Emperor's seal.

## Locations and regions

`data/regions.csv` and `data/locations.csv` place the roster in the world.
One region for now — **The Crown District**: Falconspire Keep (the royal
home) and the capital around it. Its locations and who is found there:
Council Chamber (the five ministers), War Room (Brandt, Hale), Falconspire
Keep (Victoria, Ysolde), Envoys' Wing (Petra), Malvern's Study, Duke Tomas's
Manor, Ashvale Parlor (Corina, Edgar), The Guildhall (Tessa), The High
Street (Cassian, Corvin), The Mustering Field (Nora).

- Each location is a scene (`scenes/locations/<code>.tscn`, CustomArt
  override pattern like character portraits).
- The council column on the right shows where you stand and who is
  present; click a face to seek them out, MOVE to go elsewhere. The talk
  itself opens in the **audience window** over the map (owner 2026-09-15,
  after Crusader Kings III): the person's portrait, name plate, seat,
  opinion with its reasons, traits and skill badges on the left; the speech,
  the BIO / SKILLS / TIES pages, the options and the talk box on the right.
- **Movement within a region costs no time** (`Game.move_to`, no day passes);
  travel between regions is post-MVP and will cost time. The current
  location rides the save.

## Knowledge, belief, and deception

`data/facts.csv` seeds what each character knows — public facts, secrets with
knower lists, and common sense everyone holds at credibility 100. Knowledge is
per-character: the Chancellor's graft is one fact known only to Mirella and
Quill. `KnowledgeBase.knows` is the single authority on who knows what, and the
prompt builder is wired to it (`KnowledgeBase.describe_for` in
`PromptBuilder.persona_context`), so no character is shown a fact they were
never told.

Anyone may assert anything. `Belief` scores an assertion from its plausibility,
the listener's trust in the speaker (derived from how the listener feels about
them), the listener's traits, and corroboration with what they already know.
`data/world_rules.csv` vetoes the impossible outright — no one believes you are
a dragon, whatever else is true.

A believed claim becomes a fact the listener knows, so a swallowed lie behaves
exactly like knowledge. `ClaimLedger` keeps the engine's ground truth beside it;
when the listener later learns a contradicting truth, the reckoning fires: a
truth told earns a little trust, a lie caught costs a lot of it, costs
relationship sentiment, and mints a secret — "the king lied about X" — that the
wronged character knows and the court will eventually learn.

## When the player meets these roles

Time runs by the top bar's clock (a tick is a month of 30 days; play/pause,
no End Turn — owner 2026-09-14). Roles interact with the player through two
loops, both in the audience window:

1. **The council:** at the month's end ministers brief, warn, and pitch real
   `action_code` suggestions (template-voiced, no API call). Typed words —
   an order or plain talk — are ONE model call returning `{narrative,
   impacts}` in the voice of a speaker the engine picks beforehand; any role
   can be a `target` or be `addressed` in the court reaction (every
   character id is in the order prompt).
2. **Events:** an event stops the clock and opens the council. Its story is
   fixed authored prose from `RANDOM_EVENTS.md`, never model-written; the
   pool casts non-council roles via `opinion:` and `rel:` effect ops — a
   demand from Tomas, a sermon by Cassian, an embassy from Petra, ill news
   of Malvern's health (designed; the current pool is the 20 starter
   events).

## LLM context contract

The engine decides; the LLM only performs. For any speaking role the prompt
contains, in order:

1. `PromptBuilder.persona_context(id)` — identity (with age), house, kingdom,
   the numeric attributes, skills, trait labels, opinion of the ruler, their
   live relationship lines (strongest first, capped at 6), what they remember
   being said (`AgentMemory`), and what they know and believe
   (`KnowledgeBase`).
2. The realm facts (engine truth) — the model may quote only these numbers.
3. The legal-options menu — action codes, event choice ids, the world fields
   it may move with their caps (`data/world_schema.csv`), tone enum. The
   model *chooses among them* and writes dialogue; `ResponseValidator` rejects
   anything off-menu and clamps tone, and `WorldLedger` clamps world deltas. That is the whole extent of "LLM directs
   behaviour."

## Portraits

Portraits come from the art library's `K-` chapter (one entry per character
id, looks and clothing from its `**外貌**` line), mapped by
`assets/flux/cast_art.csv` and installed by `assets/flux/install_map_art.py
cast` into `assets/portraits/<id>.png` (96 px chip, `[C-BUST]`) and
`assets/portraits/full/<id>.png` (660 px figure, `[C-FULL]`). They keep their
colour. Roles without art render as seat-coloured initial chips. (Superseded:
deriving chips from provided full-body art with `tools/make_portrait_chips.gd`;
the tool is still in the repo.) The audience window cuts the full figure head
to waist before the room's backdrop.
