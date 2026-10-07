class_name WarSupplyFlow
extends RefCounted
## The crown's supply lines on the WAR ROOM's table (owner 2026-10-07: 补给线
## 变成实心的金色线，带流动感，实时跟随军队移动): only a FLOWING line, our own,
## a solid gold ribbon laid on the sheet from its town along the road to where
## the piece stands NOW, its streaks flowing toward the army in the shader
## (`war_supply_flow.gdshader`, its look `scenes/war_room/materials/war_supply_flow.tres`).
## Out of the baked intel ink so it can move: the roads are found when the
## state changes (`routes`), the ends follow the pieces every frame they move
## (`lines`), and the mesh is rebuilt from those (`ribbon`). Reads no autoload.


## Each FLOWING line of the player's realm whose road touches `rect` (pack
## px): [{code, route}], the route from its town to the column (the courier's
## road, SupplySystem.route_px), in code order.
static func routes(repo: DataRepository, state: GameState, rect: Rect2) -> Array:
	var out: Array = []
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(x: Dictionary) -> String: return String(x["regiment_code"]))
	ours.sort()
	for code: String in ours:
		# only the wagons rolling are a road (as the 3D map): no ordered, riding or cut line
		if String(SupplyLines.line(state, code).get("state", "")) != SupplyLines.FLOWING:
			continue
		var route := SupplySystem.route_px(repo, state, code)
		if route.size() >= 2 and rect.grow(rect.size.x * 0.05).intersects(_box(route)):
			out.append({"code": code, "route": route})
	return out


## The routes ended where each piece is drawn now (`ends`: code -> pack px; a
## code it lacks ends where its road does), clipped to the sheet: [{code,
## poly}], a line leaving and re-entering the sheet in pieces.
static func lines(routes_: Array, ends: Dictionary, rect: Rect2) -> Array:
	var out: Array = []
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])
	for r: Dictionary in routes_:
		var route: PackedVector2Array = (r["route"] as PackedVector2Array).duplicate()
		var code := String(r["code"])
		if ends.has(code):
			var end: Vector2 = ends[code]
			if route[route.size() - 1].distance_to(end) <= 0.01:
				route[route.size() - 1] = end
			else:
				route.append(end)   # the road ends at the column; the piece may stand a step on
		for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(route, box):
			if piece.size() >= 2:
				out.append({"code": code, "poly": piece})
	return out


## A ribbon down each line (table metres, the town first): two vertices at
## each point ON the line, NORMAL the side each grows toward (the shader
## widens them by its own width_m), UV.x the metres run from the line's
## start, UV.y 0 / 1 across. Null when there is nothing to draw.
static func ribbon(lines_: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for pts: PackedVector3Array in lines_:
		var n := pts.size()
		if n < 2:
			continue
		var base := verts.size()
		var run := 0.0
		for i in n:
			if i > 0:
				run += pts[i].distance_to(pts[i - 1])
			var dir := Vector3.ZERO
			if i > 0:
				dir += (pts[i] - pts[i - 1]).normalized()
			if i < n - 1:
				dir += (pts[i + 1] - pts[i]).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x).normalized() if Vector2(dir.x, dir.z).length_squared() > 0.0 else Vector3.RIGHT
			for s: float in [1.0, -1.0]:
				verts.append(pts[i])
				normals.append(side * s)
				uvs.append(Vector2(run, 0.0 if s > 0.0 else 1.0))
		for i in n - 1:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _box(poly: PackedVector2Array) -> Rect2:
	var b := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		b = b.expand(p)
	return b
