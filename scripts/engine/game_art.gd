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
## Saved field-camp stages on the 3D map: building/camped/packing.
## The editor table supplies the scene; snapshot progress stages its facilities.
const CAMP_MODELS := "res://assets/3D/buildings/camp_models.tres"
## The WAR ROOM's tool roll: each slot's painted ink glyph by WarToolSlot.art_key
## (library W-61..W-68), and the resolutions' rolled scroll (U-61).
const WAR_TOOL_ART := "res://assets/2D/war_room/tools/war_tool_art.tres"
## The couriers' paintings by kind, and the scenes a courier's card or the
## Missive desk may wear (foul weather, delivered).
const COURIER_PAINTINGS := "res://assets/2D/paintings/couriers/courier_paintings.tres"
## The model each kind of courier rides.
const COURIER_MODELS := "res://assets/3D/units/courier_models.tres"
## The loop each arm's piece marches to on the 3D map (Map3DUnitSound), by
## army_art.csv `piece`; an arm with none marches silent.
const UNIT_SOUNDS := "res://assets/audio/units/unit_sounds.tres"
## The sound each arm's piece settles into its GARRISON with, on its last
## step off the march (Map3DUnitSettle); an arm with none settles silent.
const UNIT_SETTLE_SOUNDS := "res://assets/audio/units/settle_sounds.tres"

## Each estate's painting by its industry and size, "<focus>_<tier>"
## (library B-01..B-36; manor_estates.csv keeps the tiers' numbers).
const ESTATE_PAINTINGS := "res://assets/2D/paintings/estates/estate_paintings.tres"
## A good's mark on the map's badges, and its colour icon on the cards.
const GOODS_MARKS := "res://assets/2D/goods/marks/goods_marks.tres"
const GOODS_ICONS := "res://assets/2D/icons/goods/goods_icons.tres"
## The .glb each house type is drawn with (map3d_houses.csv keeps its sizes).
const HOUSE_MODELS := "res://assets/3D/buildings/house_models.tres"

const BATTLE_EVENTS := "res://assets/2D/events/battle/battle_events.tres"

static var _tables: Dictionary = {}


static func table(table_path: String) -> ArtTable:
	if not _tables.has(table_path):
		_tables[table_path] = load(table_path) as ArtTable if ResourceLoader.exists(table_path) else ArtTable.new()
	return _tables[table_path]


## `key`'s art path in the table at `path`, or "".
static func path(table_path: String, key: String) -> String:
	return table(table_path).path_of(key)
