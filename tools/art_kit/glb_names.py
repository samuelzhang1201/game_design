"""The names a shipped .glb carries that the game's model scene depends on.

Each house and regiment is a scene (scenes/models/...) inheriting its .glb:
it finds the mesh by its NODE name, hangs its materials on the surfaces in
ORDER, and points at the textures Godot extracts beside the .glb, named
<glb>_<IMAGE name>.jpg. A new delivery that keeps these names overwrites the
.glb and the scene follows; one that changes them leaves the scene's
materials hanging. extract_specs.py copies them into the add-on's specs.json
so its export writes them and checks them. Stdlib only.
"""
import json
import struct


def read(path):
    """{"roots", "meshes", "images", "materials"} of the .glb at `path`."""
    with open(path, "rb") as f:
        blob = f.read()
    size = struct.unpack_from("<I", blob, 12)[0]
    gltf = json.loads(blob[20:20 + size])
    nodes = gltf.get("nodes", [])
    return {
        "roots": [nodes[i].get("name", "") for s in gltf.get("scenes", []) for i in s.get("nodes", [])],
        "meshes": [n.get("name", "") for n in nodes if "mesh" in n],
        "images": [i.get("name", "") for i in gltf.get("images", [])],
        "materials": [m.get("name", "") for m in gltf.get("materials", [])],
    }
