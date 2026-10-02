class_name GameArt
extends RefCounted
## Where each key → art table lives (ArtTable .tres, edited in the inspector;
## owner 2026-10-02). Pure: a table loads once and is kept.

## The army card's paintings by piece (library B-37..B-42).
const ARMY_PAINTINGS := "res://assets/2D/paintings/armies/army_paintings.tres"
## The .glb each arm's 3D piece wears (a fleet has none: its flat counter).
const ARMY_MODELS := "res://assets/3D/units/army_models.tres"
## The couriers' paintings by kind, and the scenes a courier's card or the
## Missive desk may wear (foul weather, delivered).
const COURIER_PAINTINGS := "res://assets/2D/paintings/couriers/courier_paintings.tres"
## The model each kind of courier rides.
const COURIER_MODELS := "res://assets/3D/units/courier_models.tres"

static var _tables: Dictionary = {}


static func table(path: String) -> ArtTable:
	if not _tables.has(path):
		_tables[path] = load(path) as ArtTable if ResourceLoader.exists(path) else ArtTable.new()
	return _tables[path]


## `key`'s art path in the table at `path`, or "".
static func path(table_path: String, key: String) -> String:
	return table(table_path).path_of(key)
