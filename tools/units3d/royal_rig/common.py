"""Shared helpers for the royal (king on horseback) rig, built by the blender-auto-rig skill's
phases in the owner's open Blender (owner 2026-10-06: 用 blender-auto-rig 技能重新操作).
Every phase script execs this file first: MCP namespaces do not persist between calls.

Sources (git-ignored, assets/3D/units/royal/model_wip/tripo/): the Tripo generation from
REF_royal_qwenfast_s1.png on the owner's paid plan --
  medieval+knight+on+horse+3d+model.glb   the textured fused mesh: THE DELIVERABLE
  medieval+knight+3d+model+parts.glb      47 untextured parts: a LABEL SOURCE only (Phase 1d)
"""
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector, Matrix

ROOT = "/Users/samuelzhang/game_design/"
SRC = ROOT + "assets/3D/units/royal/model_wip/tripo/"
TEX_FILE = SRC + "medieval+knight+on+horse+3d+model.glb"
PARTS_FILE = SRC + "medieval+knight+3d+model+parts.glb"
WORK = SRC + "royal_rig_work.blend"
SHOTS = SRC + "shots/"
SCENE = "Royal_Rig"


def scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    sc.sync_mode = "NONE"
    sc.unit_settings.system = "METRIC"
    if bpy.context.window:
        bpy.context.window.scene = sc
    return sc


def coll(name):
    sc = scene()
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in sc.collection.children:
        sc.collection.children.link(c)
    return c


def import_into(path, cname):
    c = coll(cname)
    for o in list(c.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    bpy.context.view_layer.update()
    for o in new:                      # parents baked into the meshes
        if o.type == "MESH":
            mw = o.matrix_world.copy()
            o.parent = None
            o.data.transform(mw)
            o.matrix_world = Matrix.Identity(4)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return [o for o in c.objects if o.type == "MESH"]


def co(o):
    n = len(o.data.vertices)
    a = np.empty(n * 3)
    o.data.vertices.foreach_get("co", a)
    return (np.array(o.matrix_world)[:3, :3] @ a.reshape(n, 3).T).T + np.array(o.matrix_world)[:3, 3]


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def activate(o):
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def parts():
    return sorted((o for o in bpy.data.collections["Royal_Parts"].objects if o.type == "MESH"),
                  key=lambda o: int(o.name.split("_")[-1]))


def mesh():
    return bpy.data.objects["royal"]


# ---- Phase 2c: gridded orthographic renders (pixel <-> world) ----
GRID_R, GRID_S, GRID_C = 1400, 2.7, (0.0, 0.0, 1.25)
VIEWS = {"side": ((6, 0, 0), 1, 2), "front": ((0, -6, 0), 0, 2)}   # cam offset, screen-right axis, up axis


def grid_render(view, path, objs, xray=0.35):
    """Workbench ortho render of `objs` (x-ray) from `view`; returns the mapping so
    world = C + (px - R/2) * S / R on the screen-right axis, and the same upward."""
    sc = scene()
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type = "STUDIO", "TEXTURE"
    sh.show_xray, sh.xray_alpha = xray is not None, xray or 1.0
    sc.render.resolution_x = sc.render.resolution_y = GRID_R
    keep = set(objs)
    hidden = []
    for o in sc.objects:
        if o.type == "MESH" and o not in keep and not o.hide_render:
            o.hide_render = True; hidden.append(o)
    cam = bpy.data.objects.get("grid_cam") or bpy.data.objects.new("grid_cam", bpy.data.cameras.new("grid_cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    off, _, _ = VIEWS[view]
    C = Vector(GRID_C)
    cam.data.type, cam.data.ortho_scale, cam.data.clip_end = "ORTHO", GRID_S, 50
    cam.location = C + Vector(off)
    cam.rotation_euler = (C - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in hidden:
        o.hide_render = False
    sh.show_xray = False
    return path


def world_to_px(p, view):
    """A world point to (px, py) on a grid_render of `view` (also usable without bpy)."""
    _, h, v = VIEWS[view]
    R, S, C = GRID_R, GRID_S, GRID_C
    return (R / 2 + (p[h] - C[h]) / S * R, R / 2 - (p[v] - C[v]) / S * R)


def shot(path, centre, look, size, res=700, objs=None):
    """A Workbench (textured) ortho close-up of `objs` (default: the mesh) about `centre`,
    looking along `look`."""
    sc = scene()
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light, sc.display.shading.color_type = "STUDIO", "TEXTURE"
    sc.display.shading.show_xray = False
    sc.render.resolution_x = sc.render.resolution_y = res
    keep = set(objs or [mesh()])
    hidden = []
    for o in sc.objects:
        if o.type == "MESH" and o not in keep and not o.hide_render:
            o.hide_render = True; hidden.append(o)
    cam = bpy.data.objects.get("shot_cam") or bpy.data.objects.new("shot_cam", bpy.data.cameras.new("shot_cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.hide_set(True)
    L = Vector(look).normalized()
    cam.data.type, cam.data.ortho_scale, cam.data.clip_end = "ORTHO", size, 50
    cam.location = Vector(centre) - L * 10
    cam.rotation_euler = L.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in hidden:
        o.hide_render = False
    return path
