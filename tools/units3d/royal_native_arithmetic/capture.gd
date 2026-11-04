extends SceneTree
## Explicit scratch-project diagnostic; never loaded by the game.


func _initialize() -> void:
	var output_path: String = OS.get_environment("ROYAL_NATIVE_CAPTURE")
	var descriptor: String = OS.get_environment("ROYAL_NATIVE_EXTENSION")
	if output_path.is_empty() or descriptor.is_empty():
		printerr("native arithmetic: missing explicit diagnostic paths")
		quit(2)
		return
	# Force the engine's double and real_t quaternion math imports before reading GOTs.
	var argument: float = float(OS.get_process_id() % 8 + 1) / 32.0
	var sine: float = sin(argument)
	var rotation: Quaternion = Quaternion(Vector3.UP, argument)
	var interpolated: Quaternion = Quaternion.IDENTITY.slerp(rotation, 0.25)
	if not is_finite(sine) or not interpolated.is_finite():
		quit(2)
		return
	var status: int = GDExtensionManager.load_extension(descriptor)
	if status != GDExtensionManager.LOAD_STATUS_OK:
		printerr("native arithmetic: collector load failed: ", status)
		quit(2)
		return
	var file: FileAccess = FileAccess.open(output_path + ".engine.json", FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({"pid": OS.get_process_id(),
		"executable": OS.get_executable_path(),
		"executable_sha256": FileAccess.get_sha256(OS.get_executable_path()),
		"version": Engine.get_version_info(), "architecture": Engine.get_architecture_name(),
		"collector_sha256": FileAccess.get_sha256(OS.get_environment("ROYAL_NATIVE_LIBRARY")),
		"warmup": [sine, interpolated.x, interpolated.y, interpolated.z, interpolated.w]}))
	file.close()
	quit(0)
