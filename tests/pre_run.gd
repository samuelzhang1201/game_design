extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 3D
## map UNLOADED (map3d_default 0). A machine with a built scene would
## otherwise load Terrain3D into every GameRoot a test makes, and a headless
## run cannot render it; tests/map3d/test_map3d_tab.gd lifts this for itself.
## It also gives the suite its own settings file.

func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
	# the suite runs at high, today's look (Ruling 7)
	Map3DQuality.forced = "high"
	# The player's settings (music on/off) live in user://; the suite reads
	# its own file so a developer's choice never reaches a test.
	GameRoot.settings_path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))
