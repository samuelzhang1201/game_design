"""The courier's horse from the cavalry's CC0 Hunt Museum scan (courier model v3): the
cavalry's own `horse_source()` (weld, cut the grass slab, stand it on z = 0 facing +Y),
at the brief's 2.45 m nose to tail."""
import sys
import os
WT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))) + "/"
sys.path.insert(0, WT + "tools/units3d")
import cavalry_scan as cs
cs.HORSE_LENGTH = 2.45


def horse_high():
    """The scan, re-centred: the cavalry centred it on the mean x of everything between
    0.95 and 1.5 m, which the head and the cocked hind leg pull 6 cm to the left; here the
    barrel's own middle (its widest x both sides, behind the withers) goes on x = 0."""
    from mathutils import Matrix
    ob = cs.horse_source()
    co = [v.co for v in ob.data.vertices if 1.05 < v.co.z < 1.25 and 0.0 < v.co.y < 0.4]
    cx = (max(c.x for c in co) + min(c.x for c in co)) / 2
    ob.data.transform(Matrix.Translation((-cx, 0, 0)))
    return ob


if __name__ == "__main__":
    import bpy
    ob = horse_high()
    me = ob.data
    co = [v.co for v in me.vertices]
    print("HORSE", len(me.vertices), len(me.polygons), [round(min(c[i] for c in co), 3) for i in range(3)],
          [round(max(c[i] for c in co), 3) for i in range(3)])
