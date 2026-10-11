class_name Map3DPriority
extends RefCounted
## THE RENDER-PRIORITY TABLE (final review, owner 2026-09-18; the realm band
## and halo 2026-09-19) — the one place the see-through layers' draw order is
## set; higher draws over lower. The house APRONS under everything, the sea
## just over them; the river water
## under every line; the roads (a bridge over the water, under every border);
## the MANORS cell edges; the realm band, the seams, the kingdom border's pale
## halo, its ink, the hovered kingdom's outline, the clicked province's gold;
## then the CLOUDS — over the lines, under the settlement rings — then the
## rings by tier from RING_BASE up, and the gold selection ring over all.
const SEA := -1
const RIVERS := 0
## The aprons at the houses' feet (Map3DLayerAprons): its own row below the sea,
## so it never ties with the rivers or the march dust (equal-priority transparents
## sort by distance and would flip as the camera moves); under the roads too.
const APRONS := -2
const ROADS := 1
const MANOR_EDGES := 2
## A selected regiment's glow (Map3DUnitGlow): over the roads it stands on, so a
## road never covers it; under the borders and every ring.
const UNIT_GLOW := 2
## A flowing supply line (Map3DSupplyLines): faint, over the roads, under the borders.
const SUPPLY_LINES := 2
const KINGDOM_BAND := 3
## A broken supply line's dark dashes and tick (Map3DSupplyBroken), over its
## pale halo (SUPPLY_LINES); the realm band's row — a band is a faint wash.
const SUPPLY_BROKEN := 3
const SEAMS := 4
const KINGDOM_HALO := 5
const KINGDOMS := 6
const HOVER := 7
const SELECTION := 8
const CLOUDS := 9
## The lowest ring tier; the tiers (village lowest, capital highest — see
## Map3DLayerSettlements.build) and then the selection ring count up from here,
## one step each (data/screens/map3d/map3d_settlements.csv's groups).
const RING_BASE := 10
