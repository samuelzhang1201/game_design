# AI Conversation, Knowledge, and Deception — Design

| | |
|---|---|
| **Status** | Design — approved decisions, awaiting spec review |
| **Date** | 2026-08-30 |
| **Author** | Yumeng Zhang (with Claude) |
| **Supersedes** | Nothing. Extends the existing `scripts/llm/` converse path. |
| **Related** | `CLAUDE.md` (architecture invariants), `PRD.md`, `COUNCIL_SYSTEM.md`, `role_player.md`, `game_story/chapter_0/game_start.md` |

## 1. Purpose

Give every character in the roster a believable conversational mind: their own
memory, their own knowledge (including secrets others lack), the ability to act
on what the player says, and the judgement to decide whether to believe it.
The player may lie; characters may be fooled; and lies eventually meet the truth.

Nothing here relaxes the project's core bet. The engine still owns every
consequence. What changes is that the LLM gains a bounded, audited ability to
*initiate* legal actions, and a voice in *plausibility* — with the engine
converting that voice into state.

## 2. Decisions (all approved 2026-08-30)

| # | Decision | Rejected alternative |
|---|---|---|
| D1 | Implement in-engine in GDScript. No LangGraph. | Python sidecar / hosted service — needs a bundled runtime, splits save state, breaks headless tests |
| D2 | A character's LLM may execute a tool immediately if it validates | Propose-and-confirm; menu-of-engine-options |
| D3 | Four guardrails, all of them: role scoping, per-tick budget, severity ceiling, chronicle | Any subset |
| D4 | Memory = engine facts filtered by knowledge + last N verbatim exchanges | Engine facts only; LLM summarisation; vector retrieval |
| D5 | Knowledge = public facts + secrets carrying knower lists, engine-propagated | Uniform shared state; full per-character world models |
| D6 | Off-screen social life is engine-simulated; the LLM voices only what the player witnesses | Live agent-to-agent banter; full autonomous simulation |
| D6a | *Amended 2026-08-30:* automatic gossip and off-screen opinion drift are **deferred**. Fact and secret propagation along relationship edges is **retained** — it is what D9's reckoning and the spy-laundering route run on | Deferring §7 entirely, which would have forced D9 down to private-only |
| D7 | The LLM judges claim plausibility | Engine keyword rules; LLM classifies + engine judges |
| D8 | Plausibility is judged in an isolated call, with a deterministic impossibility floor | Single combined call; no floor |
| D9 | Lies get a delayed reckoning that then spreads through the relationship graph | Private reckoning; no reckoning |

### 2.1 One derived decision, flagged for review

D7 says the model judges plausibility. It does **not** follow that the model
decides belief. This design splits them:

- The **model** returns *plausibility* — how credible this claim is in the
  abstract, for this world (0–100).
- The **engine** computes *belief* from plausibility, the speaker's source
  trust with this listener, the listener's traits, and corroboration.

This keeps relationship maths in testable engine code and prevents the model
from adjudicating its own trust in the player. If you would rather the model
return a final belief score directly, say so in review — it is a one-function
change, and everything downstream is unaffected.

## 3. Architecture

Eight new units. The five engine ones are `RefCounted` and Node-free, so GUT
runs them headless.

| Unit | File | Responsibility |
|---|---|---|
| `KnowledgeBase` | `scripts/engine/knowledge.gd` | Facts, who knows each, per-listener credibility, propagation |
| `ClaimLedger` | `scripts/engine/claims.gd` | Records player claims with ground truth; resolves the reckoning |
| `WorldRules` | `scripts/engine/world_rules.gd` | Deterministic impossibility floor (ontology, magnitude, era) |
| `Propagation` | `scripts/engine/propagation.gd` | Per-tick spread of facts and secrets along relationship edges, zero API cost |
| `AgentMemory` | `scripts/engine/agent_memory.gd` | Per-character memory assembly and exchange log |
| `AgentTools` | `scripts/llm/agent_tools.gd` | Builds per-character tool pools; enforces D3's guardrails |
| `CredibilityJudge` | `scripts/llm/credibility_judge.gd` | The isolated plausibility call |
| `ConversationAgent` | `scripts/llm/conversation_agent.gd` | The graph: gather → route → call → validate → execute → record |

`ConversationAgent` replaces what LangGraph would have orchestrated. It is an
explicit seven-node state machine, roughly 200 lines, with no framework.

### 3.1 Why no file grows too large

`PromptBuilder` today is 112 lines and already does persona, parse, converse,
and realm facts. Knowledge filtering and memory assembly go into their own
units rather than into `PromptBuilder`, which keeps prompt *composition*
separate from what a character is *allowed to know*. That boundary is the one
most likely to leak secrets if blurred.

## 4. Data model

All design values live in CSV per house rules. No constants in scripts.

### 4.1 New CSVs

**`data/facts.csv`** — seed knowledge, public and secret.

```
fact_code,kind,subject,claim_type,text,truth,base_credibility,initial_knowers,notes
```

- `kind`: `public` | `secret` | `rumor` | `common_sense`
- `truth`: `true` | `false` (the engine's ground truth; never shown to the model)
- `base_credibility`: 100 for `common_sense`, low for `rumor`
- `initial_knowers`: `|`-separated character ids

Seeded from `game_start.md`: the Chancellor's embezzlement (secret, known to
Mirella and Quill), Duke Tomas's designs on the throne (public — "an open
secret"), Malvern's failing health, the food shortage, Doncaster's massing.

**`data/world_rules.csv`** — the deterministic floor that overrides the model.

```
rule_code,kind,pattern,bound_min,bound_max,verdict,notes
```

- `kind`: `ontology` (dragons, resurrection, magic), `magnitude` (army sizes,
  treasury scale), `era` (gunpowder, telescopes, germ theory)
- `verdict`: `impossible` forces credibility to 0 regardless of model output

**`data/claim_types.csv`** — the taxonomy the judge returns and magnitude rules
key off (`army_size`, `treasury`, `identity`, `intent`, `event_report`, …).

### 4.2 Extended CSVs

- `data/roles.csv` — new `tool_pool` column so non-council characters get pools.
  Seats keep using `council_seats.csv`'s existing `advises_on` column.
- `data/policy_actions_*.csv` — new `severity` column driving D3's confirm ceiling.
- `data/balance.csv` — new keys: `agent_tools_per_tick`, `agent_confirm_severity`,
  `memory_exchanges_kept`, `belief_threshold`, `lie_caught_trust_penalty`,
  `truth_told_trust_gain`, `lie_relationship_penalty`, `gossip_chance_per_edge`,
  `secret_spread_sentiment_min`.

### 4.3 GameState additions

```gdscript
var knowledge: Dictionary = {}      # fact_code -> {knowers, credibility_by_char}
var claims: Array = []              # ClaimLedger records
var source_trust: Dictionary = {}   # "speaker>listener" -> float 0..100
var agent_memory: Dictionary = {}   # character_id -> [exchanges]
```

**Initial source trust** is derived, not authored: at campaign start,
`source_trust[A>B] = clamp(50 + sentiment(B→A) / 2, 0, 100)`, so Malvern
(+75 toward the king) starts near 87 and Duke Tomas (−45) near 27. Pairs with
no relationship edge start at 50. Thereafter it moves only through §6's
reckoning, which keeps it auditable.

All four serialize through the existing hex-encoding walkers. Every field reads
through `d.get(..., default)` in `from_dict`, so **`SAVE_VERSION` stays at 1** —
old saves load with empty knowledge and default trust rather than being refused.

## 5. Conversation flow

One player utterance walks seven nodes:

1. **Gather** — persona sheet, the character's *known* facts only, their memory,
   current realm facts, their 1-hop relationships.
2. **Judge** (only if the utterance asserts something) — isolated
   `CredibilityJudge` call. Player text is passed as quoted data, never as
   instruction; the schema permits only a claim type, a plausibility score, and
   a short reason. `WorldRules.veto()` then overrides to 0 for the impossible.
   The engine combines plausibility with source trust, listener traits
   (`paranoid` lowers, `trusting` raises), and corroboration into a belief
   score, clamps it, and writes it to the `ClaimLedger` with ground truth.
   *Corroboration* is defined narrowly: the count of facts this listener
   already knows that share the claim's `claim_type` and `subject` and agree
   with it, each adding a fixed bonus from `balance.csv`. A claim that
   contradicts something they already believe takes the same value as a
   penalty. This is why laundering through a spy works — the listener has
   independent-looking support for the lie.
3. **Route** — build the tool pool: the character's role pool, minus
   unaffordable actions, minus everything if their per-tick budget is spent.
4. **Call** — one roleplay request with those tools and the belief verdict in
   context ("you doubt this because …").
5. **Validate** — existing `ResponseValidator`, then guardrails: authority,
   budget, severity.
6. **Execute** — `ActionSystem` runs it, or it becomes a confirm prompt above
   the severity ceiling, or it is speech-only.
7. **Record** — chronicle line, memory entry, opinion and relationship deltas,
   each carrying an engine-written reason.

Cost ceiling: **two API calls per utterance**, one when nothing is asserted.
Clicked options remain zero, unchanged.

## 6. Deception and the reckoning

The mechanic that makes lying a wager rather than a free action.

**Telling.** Any assertion becomes a `ClaimLedger` record: claimant, listener,
claim type, text, belief score, engine ground truth, tick. A believed claim
also becomes a fact the listener knows, at the belief score's credibility — so
a swallowed lie behaves exactly like knowledge until it is contradicted.

**Laundering.** Because credibility is a property of `(fact, listener, source)`,
the spy route works without special-casing: convince Quill your army is vast,
Quill believes it, propagation carries it to Petra, and Petra weighs it against
*Quill's* source trust with her, not yours. This is the design's centrepiece and
falls out of D5 plus source trust rather than needing its own system.

**The reckoning.** Each tick, for every open claim, the engine checks whether
the listener has since learned the contradicting true fact through normal
propagation. On resolution:

- **Truth told** → `source_trust[claimant>listener]` rises by
  `truth_told_trust_gain`.
- **Lie caught** → source trust drops by `lie_caught_trust_penalty` (durable),
  relationship sentiment drops by `lie_relationship_penalty` with a reason
  string, and the engine creates a **new secret fact** — "the king lied about
  X" — whose initial knower is the wronged character.

That betrayal fact then spreads through the ordinary secret-propagation rules,
so the court learns the king lies at the speed of its own gossip. No new
machinery: the consequence of lying is expressed in the knowledge system itself.

## 7. Propagation (narrowed 2026-08-30)

Each tick, `Propagation` walks the relationship graph using the seeded RNG and
does exactly two things:

- Edges above `secret_spread_sentiment_min` may carry a fact or secret to a new
  knower, at a credibility discounted by the receiver's trust in the teller.
- Claims come due for reckoning (§6).

Zero API calls. Fully reproducible from a seed. The LLM is invoked only when
the player is present to witness a scene.

**Deferred, by decision D6a:** automatic gossip and off-screen opinion and
relationship drift between characters. Those are additive — they would extend
this same per-tick walk with deltas rather than change its shape — so picking
them up later requires no rework here. What is retained is strictly the
information channel, because §6 and the spy-laundering route are built on it:
without propagation, a lie can only ever be exposed by the player confessing it.

## 8. Error handling

| Condition | Behaviour |
|---|---|
| Offline / API failure | Existing trait-tinted template fallback |
| No tool matches the request | Spoken reply plus template line (the user's point 7) |
| Invalid or off-menu tool call | Rejected and logged; reply degrades to speech-only |
| Per-tick tool budget spent | Tools go dark; the character can still talk |
| Action over severity ceiling | Becomes a proposal awaiting player confirmation |
| Judge call fails | Claim defaults to *disbelieved*, recorded as unresolved |
| Speaker not co-located | No call at all; existing herald note |

Failing closed to disbelief matters: an API outage must never make the player
more persuasive.

## 9. Testing

Every formula gets a GUT test with hand-computed values before UI work uses it.

- **WorldRules** — dragon, resurrection, and anachronism claims veto to 0
  whatever score the (faked) model returns.
- **Belief formula** — hand-computed combinations of plausibility × source
  trust × traits; `paranoid` and `trusting` move it in the expected directions.
- **Knowledge isolation** — the highest-value test in this document: build a
  non-knower's prompt and assert the secret's text is absent. Asserted on the
  prompt string, never on model behaviour.
- **ClaimLedger** — a believed lie resolves when the truth propagates; source
  trust drops; the betrayal fact is created with the wronged character as its
  first knower.
- **Propagation** — identical seeds spread identical facts to identical
  knowers; a fact arriving second-hand carries lower credibility than
  first-hand; nothing crosses an edge below `secret_spread_sentiment_min`.
- **AgentTools** — the Marshal's pool never contains `TAX_RATE_ADJUST`; budget
  exhaustion darkens tools; severity gating routes to confirm.
- **Cost** — at most two API calls per utterance; zero for clicked options.
- **Save** — knowledge, claims, trust, and memory round-trip bit-exactly; a
  pre-feature save still loads.

## 10. Build order

Five phases, each independently testable and each leaving the game playable.

1. **Knowledge core** — `KnowledgeBase`, `WorldRules`, `facts.csv`,
   `world_rules.csv`, source trust, save wiring. No LLM involvement.
2. **Claims and reckoning** — `ClaimLedger`, resolution rules, betrayal facts.
   Still no LLM: driven by tests and hand-made claims.
3. **Propagation** — `Propagation` per-tick fact and secret spread. Narrowed by
   D6a: no gossip, no off-screen drift. The smallest phase of the five.
4. **Tools and guardrails** — `AgentTools`, role pools, budget, severity,
   chronicle. Wired to the existing typed-order path first.
5. **LLM integration** — `CredibilityJudge`, `ConversationAgent`, `AgentMemory`,
   prompt assembly.

Phases 1–4 add no API cost at all, which means most of this system can be built
and tested offline.

## 11. Explicit non-goals

- No vector store or embedding retrieval.
- No live agent-to-agent banter (addable later on top of §7 without rework).
- No automatic gossip or off-screen opinion drift between characters (D6a).
  Deferred, not cancelled — §7 is the extension point.
- No per-character model selection.
- No LLM-written opinion or relationship deltas — reasons stay engine-authored.

## 12. Known risks

**Models reach for tools when tools are offered.** Expect a first build where
ministers muster levies because you said good morning. Contained by severity
ceiling and budget; plan a prompt-tuning pass, and consider attaching tools
only when the utterance reads as a request.

**Two calls per utterance doubles conversational cost.** `prompt_calls_per_tick`
is 6 today, so a chatty turn hits the cap fast. Tune after measuring.

**Authoring load.** `world_rules.csv` and `facts.csv` are content, not code.
The system is only as good as the rules and secrets authored into it.

**Belief tuning is a feel problem, not a correctness problem.** Expect several
balance passes before "would they believe this?" matches player intuition.
