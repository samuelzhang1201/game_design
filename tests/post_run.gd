extends GutHookScript
## GUT post-run hook (run_tests.sh -gpost_run_script): the kept 3D world
## (Map3DWorldCache) is detached from every tree, so nothing frees it at exit
## — free it here, or the suite ends leaking a node.

func run() -> void:
	Map3DWorldCache.clear()
