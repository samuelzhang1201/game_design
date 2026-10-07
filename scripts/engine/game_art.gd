class_name GameArt
extends RefCounted
## Where each key → art table lives (ArtTable .tres, edited in the inspector;
## owner 2026-10-02). Pure: a table loads once and is kept.

## The army card's paintings by piece (library B-37..B-42).
const ARMY_PAINTINGS := "res://assets/2D/paintings/armies/army_paintings.tres"
## The .glb each arm's 3D piece wears (a fleet has none: its flat counter).
const ARMY_MODELS := "res://assets/3D/units/army_models.tres"
## The WAR ROOM's wooden piece by art piece key (MapObjects.army_piece; a
## fleet has none: its tin token). Spec 2026-10-06-war-room-wooden-pieces.
const WAR_PIECES := "res://assets/3D/war_room/war_pieces.tres"
## The WAR ROOM's plan layer: the wax crayon's tooth (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §2.5).
const WAR_PLAN_ART := "res://assets/2D/war_room/plan/war_plan_art.tres"
## The couriers' paintings by kind, and the scenes a courier's card or the
## Missive desk may wear (foul weather, delivered).
const COURIER_PAINTINGS := "res://assets/2D/paintings/couriers/courier_paintings.tres"
## The model each kind of courier rides.
const COURIER_MODELS := "res://assets/3D/units/courier_models.tres"

## Each estate's painting by its industry and size, "<focus>_<tier>"
## (library B-01..B-36; manor_estates.csv keeps the tiers' numbers).
const ESTATE_PAINTINGS := "res://assets/2D/paintings/estates/estate_paintings.tres"
## A good's mark on the map's badges, and its colour icon on the cards.
const GOODS_MARKS := "res://assets/2D/goods/marks/goods_marks.tres"
const GOODS_ICONS := "res://assets/2D/icons/goods/goods_icons.tres"
## The .glb each house type is drawn with (map3d_houses.csv keeps its sizes).
const HOUSE_MODELS := "res://assets/3D/buildings/house_models.tres"

static var _tables: Dictionary = {}


static func table(path: String) -> ArtTable:
	if not _tables.has(path):
		_tables[path] = load(path) as ArtTable if ResourceLoader.exists(path) else ArtTable.new()
	return _tables[path]


## `key`'s art path in the table at `path`, or "".
static func path(table_path: String, key: String) -> String:
	return table(table_path).path_of(key)
