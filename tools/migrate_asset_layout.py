#!/usr/bin/env python3
"""Move a checkout's assets into the 2D / 3D layout (owner 2026-09-30).

The rule:
    assets/3D/{category}/{object}/      every 3D asset the game uses
    assets/3D/{category}/{object}/model_wip/
                                        what produced it: Comfy reference art,
                                        Tripo exports, .blend work files, CC0
                                        scans (git-ignored, .gdignore'd)
    assets/2D/{category}/{object}/      every 2D asset the game uses, one
                                        folder per SET (icons/resources, ...)
Fonts, audio, the map packs' data bitmaps (assets/maps) and the image-generation pipeline
(assets/imagegen) are neither and stay outside.

The tracked files moved with the branch that introduced this script; what git
cannot move is each checkout's git-ignored files — the Terrain3D build, the
packed ground textures, the model sources, the Comfy outputs, the textures
Godot extracts beside a .glb. Run this once in a checkout after merging:

    python3 tools/migrate_asset_layout.py            # dry run: print the moves
    python3 tools/migrate_asset_layout.py --apply

It moves every file still under an old folder (a tracked one with git mv),
rewrites each moved .import's source and cache names — and renames the cached
import under .godot/imported to match, so nothing re-imports but the .glb
files, which must re-extract their textures beside their new home — rewrites
the old paths inside the moved Terrain3D build (world.tscn,
terrain_assets.tres), and re-signs its manifest's steps_hash, since the house
table's paths moved but no bake input did. --refs rewrites the old paths in the
repository's text files as well (how the branch itself was made).
"""
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNIT_CODES = ("infantry", "cavalry", "courier")
HOUSE_TYPES = ("church_tower", "townhouse_a", "townhouse_b", "townhouse_c", "cottage_a",
               "cottage_b", "cottage_c", "longhouse", "workshop", "chapel", "church",
               "palace", "barn", "byre")  # longest first: church_tower before church
UI_PANELS = ("frame.png", "panel_ornament.png", "panel_vellum.png")
OLD_ROOTS = ("assets/units3d", "assets/map3d_houses", "assets/map3d_aerial", "assets/map3d_preview",
             "assets/map3d", "assets/icons", "assets/goods", "assets/portraits", "assets/manors",
             "assets/armies", "assets/couriers", "assets/arms", "assets/events", "assets/missives",
             "assets/ui", "assets/BGM.mp3", "assets/BGM.mp3.import",
             "assets/Sound FX Starter Pack Vol. 1", "assets/imagegen/out/house_ref",
             "assets/imagegen/out/infantry_kit", "assets/imagegen/out/cavalry_v2",
             "assets/imagegen/out/courier_designs", "assets/imagegen/out/courier_sheet")


def _unit_of(name: str) -> str:
    for code in UNIT_CODES:
        if name == code + ".glb" or name.startswith(code + ".glb.") or name.startswith(code + "_"):
            return code
    return ""


def _house_of(name: str) -> str:
    for t in HOUSE_TYPES:
        if name == t + ".glb" or name.startswith(t + ".glb.") or name.startswith(t + "_"):
            return t
    return ""


def new_path(rel: str) -> str:
    """The new home of a repo-relative path, or "" when it stays (or is junk)."""
    parts = rel.split("/")
    if parts[-1] == ".DS_Store":
        return ""
    if rel.startswith("assets/units3d/"):
        rest = rel[len("assets/units3d/"):]
        if rest.startswith("ai_src/"):
            src = rest[len("ai_src/"):]
            for head, dest in (("tripo/", "infantry/model_wip/tripo/"),
                               ("mocap/", "infantry/model_wip/mocap/"),
                               ("courier/", "courier/model_wip/"),
                               ("cc0/infantry_", "infantry/model_wip/infantry_"),
                               ("cc0/", "cavalry/model_wip/cc0/")):
                if src.startswith(head):
                    return "assets/3D/units/" + dest + src[len(head):]
            code = _unit_of(src)
            return "assets/3D/units/%s/model_wip/%s" % (code or "infantry", src) if code else \
                "assets/3D/units/model_wip/" + src
        if rest.startswith("units3d.json"):
            return "assets/3D/units/" + rest
        code = _unit_of(rest)
        if code:
            return "assets/3D/units/%s/%s" % (code, rest)
        return "assets/3D/units/" + rest
    if rel.startswith("assets/map3d_houses/"):
        rest = rel[len("assets/map3d_houses/"):]
        t = _house_of(rest)
        return "assets/3D/buildings/%s/%s" % (t, rest) if t else "assets/3D/buildings/" + rest
    if rel.startswith("assets/imagegen/out/house_ref/"):
        name = rel.rsplit("/", 1)[1]
        stem, ext = os.path.splitext(name)
        t = stem if stem in HOUSE_TYPES else (_house_of(name) or stem)
        return "assets/3D/buildings/%s/model_wip/%s_ref%s" % (t, stem, ext)
    for old, new in (("assets/imagegen/out/infantry_kit/", "assets/3D/units/infantry/model_wip/infantry_kit/"),
                     ("assets/imagegen/out/cavalry_v2/", "assets/3D/units/cavalry/model_wip/cavalry_v2/"),
                     ("assets/imagegen/out/courier_designs/", "assets/3D/units/courier/model_wip/designs/"),
                     ("assets/imagegen/out/courier_sheet/", "assets/3D/units/courier/model_wip/sheet/"),
                     ("assets/map3d_aerial/", "assets/3D/terrain/model_wip/aerial/"),
                     ("assets/map3d_preview/", "assets/3D/terrain/textures_preview/"),
                     ("assets/map3d/sources/polyhaven/houses/", "assets/3D/buildings/model_wip/polyhaven/"),
                     ("assets/map3d/sources/polyhaven/church/", "assets/3D/buildings/church/model_wip/polyhaven/"),
                     ("assets/map3d/sources/house_backups/", "assets/3D/buildings/church/model_wip/"),
                     ("assets/map3d/sources/", "assets/3D/terrain/model_wip/"),
                     ("assets/map3d/", "assets/3D/terrain/"),
                     ("assets/icons/bld_", "assets/2D/icons/buildings/bld_"),
                     ("assets/icons/", "assets/2D/icons/resources/"),
                     ("assets/goods/colour/", "assets/2D/icons/goods/"),
                     ("assets/goods/", "assets/2D/goods/marks/"),
                     ("assets/portraits/", "assets/2D/portraits/cast/"),
                     ("assets/manors/paint/", "assets/2D/paintings/estates/"),
                     ("assets/armies/paint/", "assets/2D/paintings/armies/"),
                     ("assets/couriers/paint/", "assets/2D/paintings/couriers/"),
                     ("assets/arms/", "assets/2D/arms/"),
                     ("assets/events/", "assets/2D/events/illustrations/"),
                     ("assets/missives/", "assets/2D/ui/missive_board/"),
                     ("assets/ui/compass", "assets/2D/ui/compass/compass"),
                     ("assets/BGM.mp3", "assets/audio/BGM.mp3"),
                     ("assets/Sound FX Starter Pack Vol. 1/", "assets/audio/Sound FX Starter Pack Vol. 1/")):
        if rel.startswith(old):
            return new + rel[len(old):]
    if rel.startswith("assets/ui/") and rel.split("/")[2].split(".import")[0] in UI_PANELS:
        return "assets/2D/ui/panels/" + rel[len("assets/ui/"):]
    return ""


## The references: old path text -> new, most specific first. Every new path
## is out of reach of every old pattern, so a second run changes nothing.
REFS = [
    ("assets/units3d/ai_src/tripo", "assets/3D/units/infantry/model_wip/tripo"),
    ("assets/units3d/ai_src/mocap", "assets/3D/units/infantry/model_wip/mocap"),
    ("assets/units3d/ai_src/cc0/infantry_", "assets/3D/units/infantry/model_wip/infantry_"),
    ("assets/units3d/ai_src/cc0", "assets/3D/units/cavalry/model_wip/cc0"),
    ("assets/units3d/ai_src/courier/", "assets/3D/units/courier/model_wip/"),
    ("assets/units3d/ai_src/courier", "assets/3D/units/courier/model_wip"),
    ("assets/units3d/ai_src", "assets/3D/units/<code>/model_wip"),
    ("assets/units3d/units3d.json", "assets/3D/units/units3d.json"),
    ("assets/units3d/<code>.glb", "assets/3D/units/<code>/<code>.glb"),
    ("assets/units3d/*.glb", "assets/3D/units/*/*.glb"),
] + [("assets/units3d/" + c, "assets/3D/units/%s/%s" % (c, c)) for c in UNIT_CODES] + [
    ("assets/units3d", "assets/3D/units"),
    ("assets/map3d_houses/<type>.glb", "assets/3D/buildings/<type>/<type>.glb"),
    ("assets/map3d_houses/*.glb", "assets/3D/buildings/*/*.glb"),
] + [("assets/map3d_houses/" + t, "assets/3D/buildings/%s/%s" % (t, t)) for t in HOUSE_TYPES] + [
    ("assets/map3d_houses", "assets/3D/buildings"),
    ("assets/imagegen/out/house_ref/<type>.png", "assets/3D/buildings/<type>/model_wip/<type>_ref.png"),
    ("assets/imagegen/out/house_ref", "assets/3D/buildings/<type>/model_wip"),
    ("assets/imagegen/out/infantry_kit", "assets/3D/units/infantry/model_wip/infantry_kit"),
    ("assets/imagegen/out/cavalry_v2", "assets/3D/units/cavalry/model_wip/cavalry_v2"),
    ("assets/imagegen/out/courier_designs", "assets/3D/units/courier/model_wip/designs"),
    ("assets/imagegen/out/courier_sheet", "assets/3D/units/courier/model_wip/sheet"),
    ("assets/map3d_aerial", "assets/3D/terrain/model_wip/aerial"),
    ("assets/map3d_preview", "assets/3D/terrain/textures_preview"),
    ("assets/map3d/sources/polyhaven/houses", "assets/3D/buildings/model_wip/polyhaven"),
    ("assets/map3d/sources", "assets/3D/terrain/model_wip"),
    (re.compile(r"assets/map3d(?![\w])"), "assets/3D/terrain"),
    ("assets/icons/bld_", "assets/2D/icons/buildings/bld_"),
    (re.compile(r"assets/icons(?![\w])"), "assets/2D/icons/resources"),
    ("assets/goods/colour", "assets/2D/icons/goods"),
    (re.compile(r"assets/goods(?![\w])"), "assets/2D/goods/marks"),
    ("assets/portraits/full", "assets/2D/portraits/cast/full"),
    (re.compile(r"assets/portraits(?![\w])"), "assets/2D/portraits/cast"),
    ("assets/manors/paint", "assets/2D/paintings/estates"),
    ("assets/armies/paint", "assets/2D/paintings/armies"),
    ("assets/couriers/paint", "assets/2D/paintings/couriers"),
    (re.compile(r"assets/arms(?![\w])"), "assets/2D/arms"),
    (re.compile(r"assets/events(?![\w])"), "assets/2D/events/illustrations"),
    (re.compile(r"assets/missives(?![\w])"), "assets/2D/ui/missive_board"),
    ("assets/ui/compass.png", "assets/2D/ui/compass/compass.png"),
] + [("assets/ui/" + p, "assets/2D/ui/panels/" + p) for p in UI_PANELS] + [
    ("assets/BGM.mp3", "assets/audio/BGM.mp3"),
    ("assets/Sound FX Starter Pack Vol. 1", "assets/audio/Sound FX Starter Pack Vol. 1"),
]


def rewrite_refs(text: str) -> str:
    for old, new in REFS:
        if isinstance(old, str):
            text = text.replace(old, new)
        else:
            text = old.sub(new, text)
    return text


def _tag(res_path: str) -> str:
    """Godot's cache name for an imported file: <file>-<md5 of its res:// path>."""
    return "%s-%s" % (res_path.rsplit("/", 1)[1], hashlib.md5(res_path.encode()).hexdigest())


def _tracked(rel: str) -> bool:
    return subprocess.run(["git", "ls-files", "--error-unmatch", rel], cwd=ROOT,
                          capture_output=True).returncode == 0


def moves() -> list:
    out = []
    for root in OLD_ROOTS:
        full = os.path.join(ROOT, root)
        if os.path.isfile(full):
            files = [root]
        else:
            files = []
            for d, _, names in os.walk(full):
                files += [os.path.relpath(os.path.join(d, n), ROOT) for n in names]
        for rel in sorted(files):
            dst = new_path(rel)
            out.append((rel, dst))
    return out


def fix_import(dst_rel: str, src_rel: str, apply: bool) -> None:
    """A moved .import names its new source and cache; its cache follows it."""
    path = os.path.join(ROOT, dst_rel)
    old_res, new_res = "res://" + src_rel[:-len(".import")], "res://" + dst_rel[:-len(".import")]
    old_tag, new_tag = _tag(old_res), _tag(new_res)
    text = open(path, encoding="utf-8").read()
    text = text.replace('source_file="%s"' % old_res, 'source_file="%s"' % new_res).replace(old_tag, new_tag)
    if apply:
        open(path, "w", encoding="utf-8").write(text)
    if new_res.endswith(".glb"):
        return  # re-imported on purpose: it must re-extract its textures beside its new home
    cache = os.path.join(ROOT, ".godot", "imported")
    if os.path.isdir(cache):
        for name in os.listdir(cache):
            if name.startswith(old_tag + ".") and apply:
                os.replace(os.path.join(cache, name), os.path.join(cache, new_tag + name[len(old_tag):]))


def _md5_file(path: str) -> str:
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def resign_builds(apply: bool) -> None:
    """The moved Terrain3D builds: the old paths inside, and the manifest's
    steps_hash (Map3DWorldLoader.steps_hash) over the tables as they are now."""
    terrain = os.path.join(ROOT, "assets", "3D", "terrain")
    if not os.path.isdir(terrain):
        return
    steps = hashlib.md5("".join(_md5_file(os.path.join(ROOT, "data", t)) for t in
                                ("map3d_bake.csv", "map3d_fields.csv", "map3d_houses.csv")).encode()).hexdigest()
    for pack in sorted(os.listdir(terrain)):
        manifest = os.path.join(terrain, pack, "manifest.json")
        if not os.path.isfile(manifest):
            continue
        for name in ("world.tscn", "terrain_assets.tres"):
            p = os.path.join(terrain, pack, name)
            if os.path.isfile(p):
                text = open(p, encoding="utf-8").read()
                new = rewrite_refs(text)
                if new != text:
                    print("  rewrite", os.path.relpath(p, ROOT))
                    if apply:
                        open(p, "w", encoding="utf-8").write(new)
        m = json.load(open(manifest))
        if m.get("steps_hash") != steps:
            print("  re-sign", os.path.relpath(manifest, ROOT), m.get("steps_hash"), "->", steps)
            if apply:
                m["steps_hash"] = steps
                with open(manifest, "w") as f:
                    json.dump(m, f, indent=2, sort_keys=True)
                    f.write("\n")


def rewrite_repo_refs(apply: bool) -> None:
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split("\n")
    skip = ("docs/superpowers/", "tools/migrate_asset_layout.py", ".claude/settings", ".gitignore")
    for rel in files:
        if not rel or rel.startswith(skip) or rel.endswith(".import"):
            continue
        p = os.path.join(ROOT, rel)
        try:
            text = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        new = rewrite_refs(text)
        if new != text:
            print("  refs", rel)
            if apply:
                open(p, "w", encoding="utf-8").write(new)


def main() -> None:
    apply = "--apply" in sys.argv
    todo = moves()
    moved = 0
    for src, dst in todo:
        if not dst:
            print("  drop", src)
            if apply:
                os.remove(os.path.join(ROOT, src))
            continue
        full_dst = os.path.join(ROOT, dst)
        if os.path.exists(full_dst):
            if _md5_file(full_dst) == _md5_file(os.path.join(ROOT, src)) and not _tracked(src):
                print("  duplicate", src)
                if apply:
                    os.remove(os.path.join(ROOT, src))
            else:
                print("  EXISTS, left in place:", src, "->", dst)
            continue
        if apply:
            os.makedirs(os.path.dirname(full_dst), exist_ok=True)
            if _tracked(src):
                subprocess.run(["git", "mv", src, dst], cwd=ROOT, check=True)
            else:
                os.replace(os.path.join(ROOT, src), full_dst)
            if dst.endswith(".import"):
                fix_import(dst, src, apply)
        moved += 1
    if apply:
        for root in OLD_ROOTS:  # the emptied folders
            full = os.path.join(ROOT, root)
            for d, _, _ in sorted(os.walk(full), key=lambda w: -len(w[0])):
                try:
                    os.rmdir(d)
                except OSError:
                    pass
    print("%d files %s" % (moved, "moved" if apply else "to move (dry run: --apply)"))
    if "--refs" in sys.argv:
        rewrite_repo_refs(apply)
    resign_builds(apply)


if __name__ == "__main__":
    main()
