"""Install build of the town militia figure: the infantry's export (tools/units3d/infantry_arp/game_export.py)
run on the militia source with the militia's names (README beside this file).

Source (git-ignored): assets/3D/model_wip/blender_output/militia/militia_parts_11_hem.blend (rig `rig`, body
`Militia_body`, the infantry's ShortSword `Weapon` / RoundShield `Shield` on cc_weapon.r / .l).
Headless, nothing saved:
  Blender -b -y SOURCE.blend --python tools/units3d/militia_arp/game_export.py -- ROOT [OUT.json]
Writes ROOT/assets/3D/units/militia/: militia.glb (armature `mil_rig`, one skinned mesh `militia`) and
militia_militia_atlas{,_mr,_n}.jpg. The ten clips are named as the infantry's first ten (MARCH ... SLASH_3) and
get the same loop closing, in-place lunges, MARCH contact lock and shield-hand thumb; the body has no authored
material classes, so its baked atlas goes in as it is and no tunic mask is written.
Then check what was written: check_glb.py (leg through skirt in the installed file must be none).
"""
import importlib.util
import json
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("infantry_game_export", HERE.parent / "infantry_arp/game_export.py")
inf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inf)

FIRST_TEN = ("WALK", "IDLE", "STANDBY", "DEFEND", "ATTACK", "SLASH", "ATTACK_VAR1", "ATTACK_2", "SLASH_2", "SLASH_3")
FPS = 30
inf.UNIT = "militia"
inf.RIG_NAME = "mil_rig"
inf.BODY = "Militia_body"
inf.BODY_CLASSES = False
inf.GAME = {k: inf.GAME[k] for k in FIRST_TEN}


def install(root):
    # the clips are authored at 30 a second (the infantry's); the source's scene was left at Blender's 24, and
    # the glTF exporter times keys by the scene: at 24 every clip played a fifth slow
    scn = bpy.context.scene
    scn.render.fps, scn.render.fps_base = FPS, 1.0
    return inf.install(root)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("MILITIA_EXPORT", text)
