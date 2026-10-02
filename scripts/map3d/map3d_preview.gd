@tool
class_name Map3DPreview
extends RefCounted
## What an EDITOR preview needs (spec 2026-09-20 §2, owner: "clicking a node
## in the editor shows the real picture"): a repository loaded straight from
## data/ — never the Game autoload, which does not exist in the editor — the
## built world's metadata, a blank GameState, and the high tier's row. Every
## layer of scenes/map3d/map3d_world.tscn is @tool with a `preview` switch
## that builds it as the game would, its children with NO owner (never saved).
##
## Pure and editor-only by use, not by guard: the tests drive preview_build
## headless, so nothing here asks Engine.is_editor_hint() — the layers' own
## `preview` setters do.

## The placeholder plane's side in metres: what a pack with no built world
## shows in the layer's own material, so a preview is never a blank screen.
## A scaffold, not a tuned look value (Global Constraints: no tuned number in
## a script) — nothing in the game draws it.
const PLACEHOLDER_M := 4000.0
## One repository per pack id, and one instanced world per 3D build: a
## preview is switched on and off over and over, and both are expensive.
static var _repos: Dictionary = {}
static var _worlds: Dictionary = {}
## Each Display's AUTHORED texture while a preview shows the live render
## instead (keyed by the TextureRect's instance id) — see show_live.
static var _authored_tex: Dictionary = {}


## The data for `pack_id` ("" = maps.csv's default), loaded once and kept.
static func repo(pack_id: String) -> DataRepository:
	if _repos.has(pack_id):
		return _repos[pack_id]
	var r := DataRepository.load_all("res://data")
	if r != null and pack_id != "":
		r.load_map(pack_id)
	_repos[pack_id] = r
	return r


## A build's `map3d_world` metadata: its manifest's copy (no scene to open),
## else the built scene's own root meta, else {} — a pack with no build.
static func meta_for(scene_dir: String) -> Dictionary:
	var manifest := scene_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if m is Dictionary and (m as Dictionary).get("meta", null) is Dictionary:
			return (m as Dictionary)["meta"]
	var scene := scene_dir.path_join("world.tscn")
	return Map3DWorldLoader.scene_meta(scene) if ResourceLoader.exists(scene) else {}


## The context a preview builds from: the pack's data, its build's metadata,
## a BLANK state (the starting border, never a campaign's), the high tier,
## and the map's own centre at the opening zoom so a layer that reads the
## pose has one. The terrain is instanced only when `with_terrain` — one
## world per pack, shared by every preview of it.
static func context(pack_id: String, with_terrain: bool = false) -> Map3DContext:
	var r: DataRepository = repo(pack_id)
	var dir: String = r.map3d_dir()
	var meta := meta_for(dir)
	var world: Node3D = world_of(dir) if with_terrain else null
	var ctx := Map3DContext.new(r, meta, world)
	var blank := GameState.new()
	ctx.state_fn = func() -> GameState: return blank
	ctx.quality = Map3DQuality.row(r, "high")
	ctx.target = ctx.bounds.get_center()
	ctx.distance = r.bal("map3d_bench_mid_m")
	return ctx


## `scene_dir`'s built world, instanced once and kept (a second preview of
## the same pack must not load a second terrain); null without a build.
static func world_of(scene_dir: String) -> Node3D:
	var path := scene_dir.path_join("world.tscn")
	# is_instance_valid FIRST: a scene reload frees the world under it, and
	# `is` on a freed instance is itself an error.
	var kept: Variant = _worlds.get(path)
	if is_instance_valid(kept):
		return kept as Node3D
	var w := Map3DWorldLoader.instance(path)
	_worlds[path] = w
	return w


## A pack with no build: the layer's own material on a plain plane, so the
## editor shows the look asset rather than nothing.
static func placeholder(mat: Material) -> Mesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLACEHOLDER_M, PLACEHOLDER_M)
	plane.material = mat
	return plane


## The placeholder as the layer's one unowned child, replacing whatever the
## preview drew.
static func show_placeholder(node: Node3D, mat: Material) -> void:
	clear_generated(node)
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	mi.mesh = placeholder(mat)
	node.add_child(mi)  # no owner: never saved


## A layer node of `node`'s own kind, added under it WITHOUT an owner, for a
## preview to build into: a mesh or a material written onto the AUTHORED node
## would be saved into the scene as a sub-resource (Ruling: nothing generated
## is ever saved). Replaces any preview before it.
static func proxy(node: Node3D, script: Script, proxy_name: String) -> Node3D:
	clear_generated(node)
	var p: Node3D = script.new()
	p.name = proxy_name
	node.add_child(p)  # no owner: never saved
	if p is GeometryInstance3D:
		(p as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the vertex shaders grow the geometry far past its own AABB
		(p as GeometryInstance3D).extra_cull_margin = 16384.0
	return p


## Frees every child a preview (or a runtime build) added — the ones with no
## owner. An authored child (the clouds' Shadows) is left alone.
static func clear_generated(node: Node) -> void:
	for c: Node in node.get_children():
		if c.owner == null:
			node.remove_child(c)
			c.free()


## The view root a layer hangs under (the node carrying `preview_pack`), or
## null for a layer standing on its own in a test.
static func root_of(node: Node) -> Node:
	var n: Node = node.owner if node.owner != null else node.get_parent()
	while n != null and not ("preview_pack" in n):
		n = n.get_parent()
	return n


## The context for the layer `node`: its view root's chosen pack and terrain.
static func context_for(node: Node) -> Map3DContext:
	var r := root_of(node)
	if r == null:
		return context("")
	return context(String(r.get("preview_pack")), bool(r.get("preview_terrain")))


## Every preview's common start: the SubViewport the layer draws into (its
## size drives every screen-px uniform) and the built world under WorldSlot
## when the terrain is on.
static func prepare(node: Node, ctx: Map3DContext) -> void:
	var vp := viewport_of(node)
	if vp != null:
		ctx.viewport = vp
		ctx.view_size = Vector2(vp.size)
	elif Map3DWorld.editor_viewport_3d() != null:
		# the world on its own: the editor's 3D view draws it (read, never driven)
		ctx.view_size = Vector2(Map3DWorld.editor_viewport_3d().size)
	attach_world(node, ctx)


## The built world under the world's WorldSlot (Map3DWorld), so a preview
## with the terrain on shows the ground too; unowned, so it is never saved.
static func attach_world(node: Node, ctx: Map3DContext) -> void:
	if ctx.world == null or ctx.world.get_parent() != null:
		return
	var r := root_of(node)
	var slot := r.get_node_or_null("WorldSlot") if r != null else null
	if slot != null:
		slot.add_child(ctx.world)  # no owner: never saved


## The SubViewport `node` draws into, or null.
static func viewport_of(node: Node) -> SubViewport:
	var n: Node = node
	while n != null and not (n is SubViewport):
		n = n.get_parent()
	return n as SubViewport


## The SubViewport over `node` renders while ANY layer under it previews, and
## goes back to the authored UPDATE_DISABLED — and gives the built world back —
## when the last one is switched off.
static func sync_viewport(node: Node) -> void:
	var vp := viewport_of(node)
	if vp == null:
		var w := root_of(node)  # the world on its own: give its terrain back with the last preview
		if w != null and Engine.is_editor_hint() and not _any_preview(w):
			Map3DWorld.give_back(w.get_node_or_null("WorldSlot"))
		return
	var on := _any_preview(vp)
	vp.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if on
		else SubViewport.UPDATE_DISABLED)
	show_live(display_of(vp), vp, on)
	# Only the editor's preview hands the world back; at runtime the view owns
	# what stands under WorldSlot.
	if on or not Engine.is_editor_hint():
		return
	for w: Node in authored(vp):
		if w is Map3DWorld:
			Map3DWorld.give_back(w.get_node_or_null("WorldSlot"))


## The view's Display beside `vp`, or null.
static func display_of(vp: SubViewport) -> TextureRect:
	var root := vp.get_parent()
	return root.get_node_or_null("Display") as TextureRect if root != null else null


## The Display's texture at load (the view's _ready): at RUNTIME the
## SubViewport's own live texture; in the EDITOR the scene's own one is KEPT —
## Viewport.get_texture()'s viewport_path is EMPTY, so binding it there would
## save an unbound texture over the authored `viewport_path` (Task 22 review).
static func bind_display(display: TextureRect, vp: SubViewport) -> void:
	if not Engine.is_editor_hint() or not (display.texture is ViewportTexture):
		display.texture = vp.get_texture()


## While a preview runs, the Display shows the SubViewport's LIVE texture; its
## authored one is kept aside and put back when the last preview goes off (and
## before any save). Viewport.get_texture()'s own viewport_path is EMPTY, so a
## scene saved with it on the Display would open with an unbound picture
## (Task 22 review).
static func show_live(display: TextureRect, vp: SubViewport, on: bool) -> void:
	if display == null:
		return
	if not on:
		display.texture = authored_texture(display, vp)
		return
	if not _authored_tex.has(display.get_instance_id()):
		_authored_tex[display.get_instance_id()] = display.texture
	display.texture = vp.get_texture()


## The texture a SAVE must find on `display`: the one it was authored with,
## else a fresh ViewportTexture carrying the path to `vp`. A kept texture with
## no path is no better than the live one, so it is rebuilt too. The path is
## the SCENE ROOT's to the viewport ("Viewport"), which is what
## ViewportTexture resolves against, not the Display's own.
static func authored_texture(display: TextureRect, vp: SubViewport) -> Texture2D:
	var key := display.get_instance_id()
	var kept := _authored_tex.get(key) as ViewportTexture
	_authored_tex.erase(key)
	if kept != null and not kept.get_viewport_path_in_scene().is_empty():
		return kept
	var showing := display.texture as ViewportTexture
	if showing != null and not showing.get_viewport_path_in_scene().is_empty():
		return showing  # nothing was ever swapped in: the authored one is still there
	var made := ViewportTexture.new()
	var root := vp.get_parent()
	made.set_viewport_path_in_scene(root.get_path_to(vp) if root != null else NodePath("Viewport"))
	return made


## Everything a preview touched, put back — the ROOT's own preview switches,
## the layers' switches, the SubViewport, the built world and the Display's
## texture. The view calls it on NOTIFICATION_EDITOR_PRE_SAVE, so a save can
## never write preview state.
static func reset(root: Node) -> void:
	# the world's exported switches would otherwise be SAVED (final review
	# 2026-09-20): back to the scene's defaults, wherever the world stands
	for w: Node in [root] + authored(root):
		if w is Map3DWorld:
			(w as Map3DWorld).preview_pack = ""
			(w as Map3DWorld).preview_terrain = true
	for c: Node in authored(root):
		# a layer switched off frees what it drew: the scene's own, still alive
		if is_instance_valid(c) and "preview" in c and bool(c.get("preview")):
			c.set("preview", false)
	var vp := root.get_node_or_null("Viewport") as SubViewport
	if vp != null:
		sync_viewport(vp)
	else:
		Map3DWorld.give_back(root.get_node_or_null("WorldSlot"))
	# `current` is the authored camera's own saved property: the scene has none.
	for cam: Node in root.find_children("*", "Camera3D", true, false):
		if cam.owner != null:
			(cam as Camera3D).current = false


static func _any_preview(vp: Node) -> bool:
	for c: Node in authored(vp):
		if "preview" in c and bool(c.get("preview")):
			return true
	return false


## The scene's own nodes under `node` (an owner: never what a preview built).
static func authored(node: Node) -> Array[Node]:
	return node.find_children("*", "", true, false).filter(
		func(c: Node) -> bool: return c.owner != null)


## Forgets the loaded repositories and worlds (a pack's data changed on disk).
static func forget() -> void:
	for path: String in _worlds:
		var w: Variant = _worlds[path]
		if is_instance_valid(w) and (w as Node3D).get_parent() == null:
			(w as Node3D).free()
	_worlds.clear()
	_repos.clear()
