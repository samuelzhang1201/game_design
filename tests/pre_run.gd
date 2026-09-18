extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 2D
## map. A machine with a built 3D scene would otherwise load Terrain3D into
## every GameRoot a test makes and hide the WorldMapView the UI tests assert
## on; tests/map3d/test_map3d_tab.gd lifts this for itself.

func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
