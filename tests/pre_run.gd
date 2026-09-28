extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 3D
## map UNLOADED (map3d_default 0). A machine with a built scene would
## otherwise load Terrain3D into every GameRoot a test makes, and a headless
## run cannot render it; tests/map3d/test_map3d_tab.gd lifts this for itself.
## It also gives the suite its own settings file.

const RunDir := preload("res://tests/run_dir.gd")


func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
	# the suite runs at high, today's look (Ruling 7)
	Map3DQuality.forced = "high"
	# The player's settings (music on/off) live in user://; the suite reads
	# its own file so a developer's choice never reaches a test — in this
	# run's own directory (tests/run_dir.gd), which no other suite running
	# at the same time can delete.
	RunDir.sweep()  # a crashed run with this pid may have left it
	GameRoot.settings_path = RunDir.dir("suite").path_join("test_settings.cfg")
	# the pause menu's Save / Load Game, never the player's own save
	Game.save_path = RunDir.dir("suite").path_join("save.json")
