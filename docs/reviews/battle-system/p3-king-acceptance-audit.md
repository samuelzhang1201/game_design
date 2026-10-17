# P3.1 King and courier acceptance audit

**Scope:** P3.1 of `docs/superpowers/plans/2026-10-16-battle-system/03-king-and-camps.md`, checked against approved battle system design §11. This audit is limited to the king, courier, report, presence, and safe-departure behavior in that phase. P3.2 camp acceptance is outside scope.

**Code state audited:** commit `f966367e15d95fd99974ebab1c2191ae34644c49`, plus the audit document itself. The checkpoint-named `king-camp-preflight.md` could not be recovered from reachable Git history or the worktree; no conclusions depend on it.

## Results

| Requirement | Evidence | Result |
|---|---|---|
| King has an independent saved metre position initialized from the bound player capital. | `test_new_campaign_saves_the_kings_capital_position_in_metres`; `GameState` serialization. | Pass |
| King routes advance once per absolute day, use physical routes, and stop at the destination. | `test_route_advances_by_saved_day_and_stops_at_destination`; `test_tick_transaction_does_not_repeat_king_movement_after_encounter_pause`. | Pass |
| Following is for a friendly field regiment, requires rendezvous, follows its actual position and detaches when target is removed. | `test_follow_requires_rendezvous_and_then_tracks_actual_unit`; `test_follow_rejects_a_unit_in_town_and_clears_when_target_is_removed`. | Pass |
| Presence is determined by actual distance and configured radius, independent of selected battle/screen state. | `test_presence_uses_only_actual_battle_distance` hand-checks the boundary and rejects a nonexistent battle ID. | Partial: distance is verified; WAR ROOM/dialogue state isolation has no explicit assertion (and those UI states do not feed this pure engine predicate). |
| Dispatch starts at the king's saved actual position; later king movement does not reset an already dispatched courier's origin or journey. | `test_order_courier_starts_at_the_saved_king_position`; `test_losing_the_capital_does_not_teleport_the_king_or_courier_origin`; courier ride/save tests in `test_courier_ride.gd`. `CourierSystem.dispatch_to` snapshots `origin`, `x_m`, and `path`. | Pass |
| Supply points remain tied to their towns and do not follow king movement. | `CourierSystem.dispatch_to` is passed the explicit town destination by `ActionSystem._send_supply`; supply courier behavior is covered by `test_courier_orders.gd` and supply-line tests. No king-position lookup is used for the destination. | Pass by implementation and related tests |
| Local command execution creates no courier; remote order uses a real route and charges the applicable courier fee once. | Remote courier routing/fee assertions in `test_courier_orders.gd` and law courier tests; `test_actions_validate_cost_and_execute_physical_king_orders` checks king travel order cost. | Partial: the plan's paired local-no-courier acceptance assertion is not present as a dedicated test. |
| Report travels from the battle/event location, retargets the king from the courier's current location, survives save/load, and carries authored facts without an unauthorized automatic fee. | `test_king_report_courier_tracks_king_and_survives_save_restore`; `test_king_report_dispatch_uses_battle_event_after_battle_is_removed`; `test_king_report_carries_authored_facts_without_dispatch_fee`. | Pass |
| Route failure does not teleport king or army; safe departure without a reachable refuge leaves battle, army, and prior route unchanged. | `test_safe_departure_keeps_existing_route_when_no_reachable_refuge_exists`; `KingSystem.safe_departure` validates reachable path segments. | Pass |
| Passive morale support is derived from presence and does not accumulate; safe exit does not alter battle outcome or regiment state. | `test_passive_king_support_is_derived_and_disappears_when_out_of_range`; no-reachable-refuge case checks army and battle remain unchanged. | Partial: the successful safe-departure path lacks a before/after battle-winner assertion. |
| King movement/follow/action costs and invalid coordinate handling are checked. | `test_actions_validate_cost_and_execute_physical_king_orders`; action costs are read from the approved action/order-cost tables. | Pass |

## Verification to run for this acceptance checkpoint

- Targeted GUT: `test_king_system`, `test_courier_dispatch`, `test_courier_ride`, `test_law_couriers`, `test_courier_orders`.
- Full fast suite: `./run_tests.sh --fast`.
- `git diff --check`.

## Limits and follow-up

- There is no recovered preflight checklist, so this document records only requirements present in the approved plan/spec and evidence in the current code/tests.
- Supply-town anchoring is verified by the explicit town destination in `ActionSystem._send_supply` and related supply-line tests. Local-vs-remote courier creation, successful safe-departure battle invariance, and UI-state isolation remain targeted test gaps from the P3.1 plan; this audit does not claim those assertions are complete.
- P3.1 acceptance does not approve P3.3 visuals, remaining P2 work, or overall battle-system completion.
