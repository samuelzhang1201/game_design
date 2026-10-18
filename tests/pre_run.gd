extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 3D
## map UNLOADED (map3d_default 0). A machine with a built scene would
## otherwise load Terrain3D into every GameRoot a test makes, and a headless
## run cannot render it; tests/map3d/test_map3d_tab.gd lifts this for itself.
## It also gives the suite its own settings file.

const RunDir := preload("res://tests/run_dir.gd")
const SuiteData := preload("res://tests/suite_data.gd")


func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
	# every Game.start_campaign copies a cached campaign of the same data
	Game.campaign_maker = SuiteData.campaign
	# Reuse snapshots within a script without accumulating every seed/data pair.
	if not gut.end_script.is_connected(SuiteData.clear_campaigns):
		gut.end_script.connect(SuiteData.clear_campaigns)
	# the suite runs at high, today's look (Ruling 7)
	Map3DQuality.forced = "high"
	# never a frame-rate cap: it would slow every wait in a headless run
	FrameCap.forced = 0
	# The player's settings (music on/off) live in user://; the suite reads
	# its own file so a developer's choice never reaches a test — in this
	# run's own directory (tests/run_dir.gd), which no other suite running
	# at the same time can delete.
	RunDir.sweep()  # a crashed run with this pid may have left it
	# the overlays are made in _ready, not a frame apiece (a test reads them at once)
	GameRoot.stepwise_overlays = false
	GameRoot.settings_path = RunDir.dir("suite").path_join("test_settings.cfg")
	# the pause menu's Save / Load Game, never the player's own save
	Game.save_path = RunDir.dir("suite").path_join("save.json")
