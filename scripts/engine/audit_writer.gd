class_name AuditWriter
extends RefCounted
## An audit's letter (spec 2026-09-30-ledger-governors-design §3): the
## month's TRUE figures of a governed flow, one fact per instance keyed by
## its LEDGER node id, and the total.


static func facts(repo: DataRepository, state: GameState, flow: String) -> Array:
	var out: Array = []
	var total := 0
	match flow:
		"workshop":
			for row: Dictionary in WorkshopSystem.plan(repo, state):
				out.append(MissiveLog.exact("workshop:%d" % int(row["cell"]),
					"War workshop at " + MapManors.label_of(repo, int(row["cell"])), int(row["make"])))
				total += int(row["make"])
		"supply_line":
			for row: Dictionary in SupplySystem.plan(repo, state):
				var code := String(row["code"])
				out.append(MissiveLog.exact("supply_line:" + code,
					"To " + String(ArmySystem.regiment(repo, code).get("label", code)), int(row["delivered"])))
				total += int(row["delivered"])
	out.append(MissiveLog.exact("total", "In all, this month", total))
	return out
