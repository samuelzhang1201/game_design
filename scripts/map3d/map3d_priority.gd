class_name Map3DPriority
extends RefCounted
## THE RENDER-PRIORITY TABLE (final review, owner 2026-09-18; the realm band
## and halo 2026-09-19) — the one place the see-through layers' draw order is
## set; higher draws over lower. The sea under everything; the river water
## under every line; the roads (a bridge over the water, under every border);
## the MANORS cell edges; the realm band, the seams, the kingdom border's pale
## halo, its ink, the hovered kingdom's outline, the clicked province's gold;
## then the CLOUDS — over the lines, under the settlement rings — then the
## rings by tier from RING_BASE up, and the gold selection ring over all.
const SEA := -1
const RIVERS := 0
const ROADS := 1
const MANOR_EDGES := 2
const KINGDOM_BAND := 3
const SEAMS := 4
const KINGDOM_HALO := 5
const KINGDOMS := 6
const HOVER := 7
const SELECTION := 8
const CLOUDS := 9
## The lowest ring tier; the tiers (village lowest, capital highest — see
## Map3DLayerSettlements.build) and then the selection ring count up from here,
## one step each (data/map3d_settlements.csv's groups).
const RING_BASE := 10
