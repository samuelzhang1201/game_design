class_name MilitaryMigration
extends RefCounted
## Compatibility name; Bootstrap alone imports historical personnel.
static func ensure(repo: DataRepository, state: GameState) -> Dictionary:
	var result := MilitaryBootstrap.migrate(repo, state)
	if result.has("error"):
		return result
	return MilitaryReorganization.reconcile(repo, state)
