extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 2D
## map. A machine with a built 3D scene would otherwise load Terrain3D into
## every GameRoot a test makes and hide the WorldMapView the UI tests assert
## on; tests/map3d/test_map3d_tab.gd lifts this for itself. It also gives
## the suite its own settings file.

func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
	# The player's settings (music on/off) live in user://; the suite reads
	# its own file so a developer's choice never reaches a test.
	GameRoot.settings_path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))
