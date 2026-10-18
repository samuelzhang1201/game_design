"""exec() helper for MCP calls: run an operator inside the live 3D viewport."""
import bpy


def view3d():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == 'VIEW_3D':
                region = next(r for r in area.regions if r.type == 'WINDOW')
                return dict(window=win, screen=win.screen, area=area, region=region,
                            space_data=area.spaces.active)


def run(op, *args, **kw):
    with bpy.context.temp_override(**view3d()):
        return op(*args, **kw)


def reset_smart(body='Soldier_body'):
    """Undo a half-finished ARP Smart start (temp body, markers, locks)."""
    for o in list(bpy.data.objects):
        if o.name == 'body_temp' or o.name.endswith('_loc') or '_loc_' in o.name or o.name.startswith('arp_markers'):
            bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.data.objects:
        o.hide_set(False); o.hide_select = False
        for k in ('arp_smart_viz_state', 'arp_body_mesh'):
            if k in o: del o[k]
    o = bpy.data.objects[body]
    for x in bpy.context.selected_objects: x.select_set(False)
    bpy.context.view_layer.objects.active = o; o.select_set(True)
