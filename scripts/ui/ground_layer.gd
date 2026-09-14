class_name GroundLayer
extends Node2D
## The ground under the biomes layer (experiment 2026-09-14): the terrain
## mesh and the political wash, which WorldMapView used to draw first in its
## own _draw. A CanvasItem's children draw either all behind it or all in
## front, so for the biome tiles (BiomeLayer, a child behind the view) to
## lie OVER the wash and UNDER the water and the roads, the wash and the
## terrain moved here — a child behind the view, ordered before BiomeLayer.
## The view still owns the drawing: it hands `draw_with` a callable that
## takes this node as the target, and queues this node's redraw from its
## own _draw, so the ground repaints whenever the view does.
##
## Part of the BIOMES LAYER experiment: to remove it, give the terrain and
## the wash back to WorldMapView._draw and delete this file.

var draw_with: Callable = Callable()

func _draw() -> void:
	if draw_with.is_valid():
		draw_with.call(self)
