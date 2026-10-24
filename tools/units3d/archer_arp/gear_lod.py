"""Build both archer gear candidates without touching the installed assets.

python3 gear_lod.py WORK --blender BLENDER --decikit DECIKIT_PATH
Requires the existing NumPy/PyMeshLab tool environment; Blender does the bake.
"""
import argparse
import csv
from pathlib import Path
import subprocess
import sys

import numpy as np
import pymeshlab as ml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from data_index import table_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--source", required=True, type=Path, help="original high-poly gear GLB directory")
    parser.add_argument("--blender", required=True)
    parser.add_argument("--decikit", required=True, type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    assert not work.is_relative_to(ROOT / "assets"), "retain the installed originals"
    work.mkdir(parents=True, exist_ok=True)
    bake = Path(__file__).with_name("gear_bake.py")

    def blender(stage, variant):
        subprocess.run([args.blender, "-b", "--factory-startup", "--python-exit-code", "1", "--python", str(bake),
                        "--", stage, str(ROOT), str(work), variant, str(args.decikit.resolve()), str(args.source.resolve())], check=True)

    blender("extract", "source")
    with open(table_path("archer_gear_lod"), newline="") as file:
        settings = list(csv.DictReader(file))
    assert [row["part"] for row in settings] == ["bow", "arrow", "quiver"]
    for variant in ("conservative", "proposed"):
        output = work / variant
        output.mkdir(exist_ok=True)
        for row in settings:
            part = row["part"]
            source = np.load(work / (part + ".npz"))
            mesh = ml.MeshSet()
            mesh.add_mesh(ml.Mesh(vertex_matrix=source["v"], face_matrix=source["f"]))
            mesh.meshing_remove_duplicate_faces()
            mesh.meshing_remove_null_faces()
            mesh.meshing_repair_non_manifold_edges(method="Remove Faces")
            mesh.meshing_repair_non_manifold_vertices()
            mesh.meshing_remove_unreferenced_vertices()
            prefix = "conservative_" if variant == "conservative" else ""
            mesh.meshing_isotropic_explicit_remeshing(
                iterations=int(row["iterations"]), adaptive=False,
                targetlen=ml.PureValue(float(row[prefix + "edge_m"])),
                featuredeg=float(row[prefix + "feature_deg"]), checksurfdist=True,
                maxsurfdist=ml.PercentageValue(float(row["surface_percent"])))
            mesh.meshing_repair_non_manifold_edges(method="Remove Faces")
            mesh.meshing_repair_non_manifold_vertices()
            mesh.meshing_remove_unreferenced_vertices()
            result = mesh.current_mesh()
            vertices, faces = result.vertex_matrix(), result.face_matrix()
            assert np.isfinite(vertices).all() and faces.shape[1] == 3
            assert faces.min() >= 0 and faces.max() < len(vertices)
            np.savez(output / (part + ".npz"), v=vertices, f=faces)
            print(variant, part, len(faces), flush=True)
        blender("bake", variant)


if __name__ == "__main__":
    main()
