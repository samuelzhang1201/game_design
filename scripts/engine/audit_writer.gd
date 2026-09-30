class_name AuditWriter
extends RefCounted
## An audit's letter (spec 2026-09-30-ledger-governors-design §3): the
## month's TRUE figures of a governed flow, one fact per instance keyed by
## its LEDGER node id, and the total. Each fact also carries `claimed`, what
## the governor reported for it on the audit day (final review I2): the
## LEDGER sets the audit beside his account only while his word still
## stands where the audit found it (Ledger._audit_figure).


static func facts(repo: DataRepository, state: GameState, flow: String) -> Array:
	var out: Array = []
	var total := 0
	var said := 0
	match flow:
		"workshop":
			for row: Dictionary in WorkshopSystem.plan(repo, state):
				out.append(_fact("workshop:%d" % int(row["cell"]),
					"War workshop at " + MapManors.label_of(repo, int(row["cell"])), int(row["make"]),
					int(row["claimed"])))
				total += int(row["make"])
				said += int(row["claimed"])
		"supply_line":
			for row: Dictionary in SupplySystem.plan(repo, state):
				var code := String(row["code"])
				out.append(_fact("supply_line:" + code,
					"To " + String(ArmySystem.regiment(repo, code).get("label", code)), int(row["delivered"]),
					int(row["claimed"])))
				total += int(row["delivered"])
				said += int(row["claimed"])
		"trade_route":
			# The true toll that reached the treasury, beside the steward's
			# word (the toll he collected, whole) — per route (M6).
			for row: Dictionary in MarketSystem.routes(repo, state):
				var k := String(row["kingdom"])
				out.append(_fact("trade_route:" + k, "Trade with " + MarketSystem.label_of(repo, k),
					int(row["toll"]), int(row["claimed"])))
				total += int(row["toll"])
				said += int(row["claimed"])
		_:
			# `works` never reaches here: it keeps no books, and LEDGER_AUDIT
			# refuses it (data/ledger_governance.csv `books`).
			push_error("AuditWriter: no books for flow '%s'" % flow)
			return []
	out.append(_fact("total", "In all, this month", total, said))
	return out


## MissiveLog.exact (the truth, which the Missive board reads) plus the
## governor's claim beside it.
static func _fact(key: String, label: String, truth: int, claimed: int) -> Dictionary:
	var f := MissiveLog.exact(key, label, truth)
	f["claimed"] = claimed
	return f
