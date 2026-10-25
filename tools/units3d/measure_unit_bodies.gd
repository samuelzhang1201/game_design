extends RefCounted
## Offline measurement only. All meshes (including weapon protrusions) are
## retained unless fully weighted to explicitly named attack-weapon binds.

static func measure(scene: PackedScene, art: Dictionary) -> Dictionary:
	if scene == null:
		return {"status": "error", "error": "missing model"}
	for key: String in ["repo", "fov_deg", "view_h_px", "ref_m", "world_per_sim_m"]:
		if not art.has(key):
			return {"status": "error", "error": "missing calibration: " + key}
	if not art.repo is DataRepository:
		return {"status": "error", "error": "invalid calibration repository"}
	var repo: DataRepository = art.repo
	for key: String in ["fov_deg", "view_h_px", "ref_m", "world_per_sim_m"]:
		if not is_finite(float(art[key])) or float(art[key]) <= 0.0:
			return {"status": "error", "error": "invalid calibration: " + key}
	var size := float(art.get("size", 1.0))
	if not is_finite(size) or size <= 0.0:
		return {"status": "error", "error": "invalid size"}
	var stature := float(art.get("max_stature", 1.0))
	var tilt := float(art.get("max_tilt_deg", 0.0))
	if not is_finite(stature) or stature <= 0.0 or not is_finite(tilt) or tilt < 0.0 or tilt > 90.0:
		return {"status": "error", "error": "invalid stature/tilt calibration"}
	var attack_bones: Array = art.get("attack_bones", [])
	var instance := scene.instantiate()
	var node := instance as Node3D
	if node == null:
		instance.free()
		return {"status": "error", "error": "model root is not Node3D"}
	if Map3DUnits.meshes(node).is_empty():
		node.free()
		return {"status": "error", "error": "model has no meshes"}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		node.free()
		return {"status": "error", "error": "measurement requires SceneTree for animation evaluation"}
	tree.root.add_child(node)
	var span := Map3DUnits.model_size(node)
	var extent := Map3DUnits.stand_extent(node)
	var scale_world := Map3DUnits.scale_for(repo, float(art.fov_deg), float(art.view_h_px),
		float(art.ref_m), span.y, size)
	var scale_m := scale_world / float(art.world_per_sim_m)
	var bounds := _envelope(node, attack_bones, deg_to_rad(tilt))
	var radius := float(bounds.body)
	var all_radius := float(bounds.all_mesh)
	var clips: Array[Dictionary] = []
	for player: AnimationPlayer in _players(node):
		player.active = true
		for clip: String in player.get_animation_list():
			var animation := player.get_animation(clip)
			player.play(clip)
			# Sampling is evidence, not proof of continuous animation extrema.
			for i in 17:
				player.seek(animation.length * float(i) / 16.0, true)
				player.advance(0.0)
				var sampled := _envelope(node, attack_bones, deg_to_rad(tilt))
				radius = maxf(radius, float(sampled.body))
				all_radius = maxf(all_radius, float(sampled.all_mesh))
			clips.append({"player": str(node.get_path_to(player)), "clip": clip,
				"length_s": animation.length, "samples": 17})
		player.stop()
	if radius <= 0.0 or not is_finite(radius):
		node.free()
		return {"status": "error", "error": "model has no measurable body"}
	var inputs := {"fov_deg": art.fov_deg, "view_h_px": art.view_h_px,
		"ref_m": art.ref_m, "size": size, "model_height": span.y,
		"stand_extent": [extent.x, extent.y], "world_scale": scale_world,
		"world_per_sim_m": art.world_per_sim_m, "simulation_scale": scale_m,
		"ref_px": repo.bal("map3d_unit_ref_px"), "max_stature": stature,
		"max_tilt_deg": tilt, "attack_bones": attack_bones}
	var source := scene.resource_path
	var dependencies: Dictionary = {}
	_hash_dependencies(source, dependencies)
	var model_hash := JSON.stringify(dependencies, "", true).sha256_text() if source != "" else "synthetic"
	node.free()
	var r := radius * scale_m * stature
	# Five files x two ranks; a full body diameter is left as the passing lane.
	var bound := ceili(r)
	var pitch := 4 * bound
	return {"status": "ok", "model_hash": model_hash, "scale_inputs": inputs,
		"radius_m": r, "body_radius_m": ceili(r), "sampled_clips": clips,
		"all_mesh_radius_m": all_radius * scale_m * stature, "attack_only_vertices": bounds.excluded,
		"slot_pitch_m": pitch, "rank_pitch_m": pitch,
		"deploy_min_width_m": 4 * pitch + 2 * bound,
		"deploy_min_depth_m": pitch + 2 * bound,
		"uncovered": "Between samples, blend shapes, runtime IK/settling, multi-player pose combinations and future clips; unclassified carried geometry retained."}

static func _players(node: Node) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	if node is AnimationPlayer: out.append(node)
	for child: Node in node.get_children(): out.append_array(_players(child))
	return out

static func _envelope(root: Node3D, attack_bones: Array, tilt: float) -> Dictionary:
	var radius := 0.0
	var all_radius := 0.0
	var excluded := 0
	for mesh: MeshInstance3D in Map3DUnits.meshes(root):
		if mesh.mesh == null: continue
		var at := root.global_transform.affine_inverse() * mesh.global_transform
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var skin := mesh.skin
		var poses: Array[Transform3D] = []
		var attack: Array[bool] = []
		if skeleton != null and skin != null:
			skeleton.force_update_all_bone_transforms()
			at = root.global_transform.affine_inverse() * skeleton.global_transform
			for bind in skin.get_bind_count():
				var bone := skin.get_bind_bone(bind)
				if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
				assert(bone >= 0, "Unresolved skin bind")
				poses.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
				attack.append(String(skeleton.get_bone_name(bone)) in attack_bones)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var influences := bones.size() / maxi(vertices.size(), 1)
			for i in vertices.size():
				var p := vertices[i]
				var attack_weight := 0.0
				if not poses.is_empty() and not bones.is_empty():
					p = Vector3.ZERO
					for j in int(influences):
						var index := i * int(influences) + j
						if weights[index] > 0.0:
							p += (poses[bones[index]] * vertices[i]) * weights[index]
							if attack[bones[index]]: attack_weight += weights[index]
				p = at * p
				var horizontal := Vector2(p.x, p.z).length()
				var high := absf(p.y)
				var tilted := p.length() if atan2(high, horizontal) <= tilt else horizontal * cos(tilt) + high * sin(tilt)
				all_radius = maxf(all_radius, tilted)
				if attack_weight >= 1.0 - 0.000001:
					excluded += 1
				else:
					radius = maxf(radius, tilted)
	return {"body": radius, "all_mesh": all_radius, "excluded": excluded}

## Caller supplies the loaded pack; no production state is created or changed.
static func export_all(repo: DataRepository, out_path: String) -> Dictionary:
	var world_path := repo.map3d_scene()
	var meta := Map3DWorldLoader.scene_meta(world_path)
	if meta.is_empty(): return {"status": "error", "error": "missing built-world calibration"}
	var view_h := 1600.0
	var ref_m := Map3DGeometry.distance_for_bar(repo, meta, repo.bal("map3d_zoom_start_scale"), view_h)
	var ratio := float(meta.m_per_px) / float(ArmySystem.metres_per_pack_px(repo))
	var attack_bones := {"infantry": ["cc_weapon.r"], "artillery": ["cc_weapon.r"],
		"cavalry": ["Lance"], "royal": ["Sword"], "archers": ["DEF-weapon.R"]}
	var rows: Dictionary = {}
	var hashes: Dictionary = {}
	for path: String in [GameArt.ARMY_MODELS, world_path, "res://data/screens/map3d/army_art.csv",
		"res://scripts/map3d/map3d_units.gd", "res://scripts/map3d/map3d_geometry.gd",
		"res://scripts/map3d/map3d_formation.gd", "res://scripts/engine/army_system.gd",
		"res://data/screens/map3d/balance.csv", "res://data/world/maps.csv", "res://tools/units3d/measure_unit_bodies.gd"]:
		_hash_dependencies(path, hashes)
	for arm: String in ["infantry", "archers", "cavalry", "artillery", "royal"]:
		var path := GameArt.path(GameArt.ARMY_MODELS, arm)
		_hash_dependencies(path, hashes)
		var art: Dictionary = repo.army_art.get(arm, {}).duplicate(true)
		art.merge({"repo": repo, "fov_deg": repo.bal("map3d_fov_deg"), "view_h_px": view_h,
			"ref_m": ref_m, "world_per_sim_m": ratio, "attack_bones": attack_bones[arm],
			"max_stature": 1.0 + repo.bal("map3d_march_stature_spread") if String(art.get("exact_pace", "0")) == "1" else 1.0,
			"max_tilt_deg": repo.bal("map3d_unit_tilt_max_deg")}, true)
		rows[arm] = measure(load(path) as PackedScene, art)
		if rows[arm].get("status") != "ok": return rows[arm]
	var result := {"status": "ok", "models": rows, "input_hashes": hashes,
		"pack": repo.map_id, "map_info": repo.map_info, "meta": meta, "world_per_sim_m": ratio}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null: return {"status": "error", "error": "cannot write measurement output"}
	file.store_string(JSON.stringify(result, "\t", true))
	return result

static func _hash_dependencies(path: String, hashes: Dictionary) -> void:
	if hashes.has(path) or not FileAccess.file_exists(path): return
	hashes[path] = FileAccess.get_sha256(path)
	for dependency: String in ResourceLoader.get_dependencies(path):
		_hash_dependencies(dependency.get_slice("::", dependency.get_slice_count("::") - 1), hashes)
