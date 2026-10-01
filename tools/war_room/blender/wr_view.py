import bpy, math
from mathutils import Vector, Euler, Quaternion

def wr_view(names, yaw=35, pitch=25, dist_scale=1.25, shading='MATERIAL', only=True, center=None, dist=None):
    sc = bpy.context.scene
    obs = [bpy.data.objects[n] for n in names]
    for o in sc.objects:
        o.hide_set(only and o not in obs)
    pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = center or (lo + hi) / 2
    r = dist or (hi - lo).length * dist_scale
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type != 'VIEW_3D':
                continue
            sp = area.spaces.active
            sp.shading.type = shading
            sp.overlay.show_overlays = False
            r3 = sp.region_3d
            r3.view_perspective = 'PERSP'
            r3.view_location = c
            r3.view_distance = r
            r3.view_rotation = Euler((math.radians(90 - pitch), 0, math.radians(yaw)), 'XYZ').to_quaternion()
            sp.lens = 50
            sp.clip_start = 0.005
            area.tag_redraw()
    return (lo, hi)
