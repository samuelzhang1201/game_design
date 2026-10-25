# CF01 evidence

Native PNGs are direct Godot window captures. The contact sheets only crop/enlarge the original pixels and add outside labels. `verification.json` hashes outputs and the frozen tool/test inputs; `measurements.json` contains GLB, inherited scene, texture, art-table and scale-source hashes plus per-arm calibration and clip samples. Exact model scale and fixture positions are retained in the capture text records.

For independent visual critique start with `comparison-full.png`, `comparison-crop3x.png`, `near-detail3x.png` and the original PNGs, then read the measurement report. The overview order is infantry upper left, archers upper right, cavalry lower left, artillery placeholder lower right. `near-cliff-rejected.png` is a rejected first placement with terrain occlusion; do not treat it as acceptance.

Reproduce from the repository root, with the project's shared Godot lock. Copy the archived `*.gd.txt` and shell scripts to `.superpowers/cluster-cf01/`, removing the `.txt` suffix. `export.gd` writes a fresh measurement JSON; `create_fixture.gd` creates a temporary root Node/PackedScene referencing the existing snapshot tool subclass, with no new static look. Run native captures as a **scene**, so project autoloads are initialized.

```sh
mkdir -p .superpowers/cluster-cf01
cp docs/reviews/cluster-formations/evidence/cf01/export.gd.txt .superpowers/cluster-cf01/export.gd
cp docs/reviews/cluster-formations/evidence/cf01/create_fixture.gd.txt .superpowers/cluster-cf01/create_fixture.gd
cp docs/reviews/cluster-formations/evidence/cf01/spacing.gd.txt .superpowers/cluster-cf01/spacing.gd
cp docs/reviews/cluster-formations/evidence/cf01/captures.sh.txt .superpowers/cluster-cf01/captures.sh
cp docs/reviews/cluster-formations/evidence/cf01/final_captures.sh.txt .superpowers/cluster-cf01/final_captures.sh
/Users/samuelzhang/game_design-wt/godot_lock.sh python3 tools/run_with_timeout.py 300 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s .superpowers/cluster-cf01/export.gd
/Users/samuelzhang/game_design-wt/godot_lock.sh sh .superpowers/cluster-cf01/captures.sh
/Users/samuelzhang/game_design-wt/godot_lock.sh sh .superpowers/cluster-cf01/final_captures.sh
```

`final_captures.sh` records all four open-field near shots in one native window via `--also`, then the smaller and far windows. It ends with the map3d regression category. CPU export and temporary scene packing may be headless; every PNG command uses the real Forward+ window. No timeout or missing screenshot counts as a pass. Model, art, calibration or measurement-source changes require new affected evidence.
