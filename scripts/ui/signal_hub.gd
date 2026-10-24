extends Node
## Global presentation notifications only; Game owns state and commands.
## Keep instance-local signals on their components. See guide/signals.md.

signal report_ready(report: TickReport)
signal battle_decision_requested(decision: Dictionary)
@warning_ignore("unused_signal")
signal battle_view_requested(regiment: String)
## A letter was read on the Missive board (final review M7): the read flag
## is saved state, so only Game changes it.
signal missive_read(id: int)
## Letters were marked seen (the board shown, a spy's report opened): the
## MISSIVE tab's count is redrawn from MissiveLog.unseen.
signal missives_seen
## Emitted after any mutation of Game.state (orders, event choices, court
## reactions, tick advance, load). UI that mirrors live state (e.g. the
## TopBar) subscribes to this instead of refreshing at call sites.
signal state_changed
## The WAR ROOM's plans changed (WarPlans): only the room's plan layer
## listens, so a crayon stroke refreshes nothing else (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.1).
signal plans_changed
## Cross-cutting UI signal: the TopBar's MENU button asks for the pause
## menu; GameRoot (the flow owner) listens and shows it.
@warning_ignore("unused_signal")
signal menu_requested
## A chronicle headline for the persistent bottom news strip (user request
## 2026-08-31). Emitted via publish_news — GameRoot feeds it as works
## progress and the month closes; the NewsTicker (GameRoot-owned) displays it.
signal news_published(text: String)
## The clock's speed changed (owner 2026-09-13): 0 paused, 1, 2 or 4.
signal clock_changed(speed: int)
## The clock was held still, or let go (the LEDGER: owner 2026-10-01).
signal clock_held_changed(held: bool)
signal battle_decision_changed(decision: Dictionary)
