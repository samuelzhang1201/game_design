#!/usr/bin/env python3
"""Closes the seam of a looped clip in a unit .glb, in place.

A clip whose last frame is not its first jumps once per loop (owner 2026-10-14:
步兵最后驻防动画会有跳帧卡顿 — the knight's GARRISON ended 11 degrees and 2.6 cm
off its first frame). This cuts the clip `--blend-s` seconds shorter and
crossfades its head from the tail it lost: for a key at time t inside the
window, v'(t) = mix(v(t + L'), v(t), smoothstep(t / W)), L' = L - W. The new
first key equals the new last one and the motion through the seam keeps the
tail's speed, so nothing pops; past the window the clip is untouched.

Run it after every re-export of the clip (Blender writes the raw take):
    python3 tools/units3d/loop_seam.py assets/3D/units/infantry/infantry.glb GARRISON --blend-s 1.0
`--report` prints every clip's seam (degrees / metres) and changes nothing.
The replaced keys are dropped and the buffer repacked (`compact`), so the .glb only shrinks.
"""
import argparse
import struct
import sys

import numpy as np
from pygltflib import GLTF2, Accessor, BufferView

FLOAT = 5126
COMPONENTS = {"translation": 3, "scale": 3, "rotation": 4}
TYPES = {1: "SCALAR", 3: "VEC3", 4: "VEC4"}


def read(g: GLTF2, blob: bytes, index: int) -> np.ndarray:
    acc = g.accessors[index]
    view = g.bufferViews[acc.bufferView]
    width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc.type]
    start = (view.byteOffset or 0) + (acc.byteOffset or 0)
    stride = view.byteStride or width * 4
    if stride == width * 4:
        return np.frombuffer(blob, np.float32, acc.count * width, start).reshape(acc.count, width).copy()
    return np.array([struct.unpack_from("<%df" % width, blob, start + i * stride) for i in range(acc.count)],
                    np.float32)


def append(g: GLTF2, blob: bytearray, data: np.ndarray) -> int:
    data = np.ascontiguousarray(data, np.float32)
    while len(blob) % 4:
        blob.append(0)
    g.bufferViews.append(BufferView(buffer=0, byteOffset=len(blob), byteLength=data.nbytes))
    blob.extend(data.tobytes())
    width = 1 if data.ndim == 1 else data.shape[1]
    flat = data.reshape(len(data), width)
    g.accessors.append(Accessor(bufferView=len(g.bufferViews) - 1, componentType=FLOAT,
                                count=len(data), type=TYPES[width],
                                min=[float(x) for x in flat.min(0)], max=[float(x) for x in flat.max(0)]))
    return len(g.accessors) - 1


def compact(g: GLTF2, blob: bytearray) -> bytes:
    """Drops the accessors and buffer views nothing references, and repacks the buffer."""
    used_acc = set()
    for mesh in g.meshes:
        for prim in mesh.primitives:
            used_acc.update(v for v in vars(prim.attributes).values() if isinstance(v, int))
            if prim.indices is not None:
                used_acc.add(prim.indices)
            for target in prim.targets or []:
                used_acc.update(v for v in (target if isinstance(target, dict) else vars(target)).values()
                                if isinstance(v, int))
    for skin in g.skins:
        if skin.inverseBindMatrices is not None:
            used_acc.add(skin.inverseBindMatrices)
    for anim in g.animations:
        for sampler in anim.samplers:
            used_acc.update([sampler.input, sampler.output])
    acc_map = {old: new for new, old in enumerate(sorted(used_acc))}
    used_views = {g.accessors[i].bufferView for i in used_acc if g.accessors[i].bufferView is not None}
    used_views.update(img.bufferView for img in g.images if img.bufferView is not None)
    view_map, out = {}, bytearray()
    for new, old in enumerate(sorted(used_views)):
        view = g.bufferViews[old]
        while len(out) % 4:
            out.append(0)
        start = view.byteOffset or 0
        chunk = blob[start:start + view.byteLength]
        view.byteOffset = len(out)
        out.extend(chunk)
        view_map[old] = new
    g.bufferViews = [g.bufferViews[old] for old in sorted(used_views)]
    g.accessors = [g.accessors[old] for old in sorted(used_acc)]
    for acc in g.accessors:
        if acc.bufferView is not None:
            acc.bufferView = view_map[acc.bufferView]
    for img in g.images:
        if img.bufferView is not None:
            img.bufferView = view_map[img.bufferView]
    for mesh in g.meshes:
        for prim in mesh.primitives:
            for k, v in vars(prim.attributes).items():
                if isinstance(v, int):
                    setattr(prim.attributes, k, acc_map[v])
            if prim.indices is not None:
                prim.indices = acc_map[prim.indices]
    for skin in g.skins:
        if skin.inverseBindMatrices is not None:
            skin.inverseBindMatrices = acc_map[skin.inverseBindMatrices]
    for anim in g.animations:
        for sampler in anim.samplers:
            sampler.input, sampler.output = acc_map[sampler.input], acc_map[sampler.output]
    return bytes(out)


def seam(path: str, values: np.ndarray) -> float:
    a, b = values[0], values[-1]
    if path == "rotation":
        return float(np.degrees(2.0 * np.arccos(min(1.0, abs(float(np.dot(a, b)))))))
    return float(np.linalg.norm(a - b))


def blend(path: str, tail: np.ndarray, head: np.ndarray, s: float) -> np.ndarray:
    if path == "rotation":
        if float(np.dot(tail, head)) < 0.0:
            head = -head
        q = tail * (1.0 - s) + head * s
        return q / np.linalg.norm(q)
    return tail * (1.0 - s) + head * s


def clip_of(g: GLTF2, name: str):
    for anim in g.animations:
        if anim.name.upper().endswith(name.upper()):
            return anim
    sys.exit("no clip ending in %s" % name)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("clip", nargs="?", default="")
    ap.add_argument("--blend-s", type=float, default=1.0)
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    g = GLTF2().load(args.glb)
    blob = bytearray(g.binary_blob())
    if args.report or not args.clip:
        for anim in g.animations:
            worst = {"rotation": 0.0, "translation": 0.0}
            for ch in anim.channels:
                if ch.target.path in worst:
                    out = read(g, blob, anim.samplers[ch.sampler].output)
                    worst[ch.target.path] = max(worst[ch.target.path], seam(ch.target.path, out))
            print("%-10s seam %.2f deg, %.4f m" % (anim.name, worst["rotation"], worst["translation"]))
        return
    anim = clip_of(g, args.clip)
    times = read(g, blob, anim.samplers[anim.channels[0].sampler].input)[:, 0]
    dt = float(times[1] - times[0])
    w = int(round(args.blend_s / dt))
    keep = len(times) - w
    if w < 2 or keep <= w:
        sys.exit("blend window %d keys does not fit a %d-key clip" % (w, len(times)))
    new_times = append(g, blob, times[:keep])
    for ch in anim.channels:
        sampler = anim.samplers[ch.sampler]
        if sampler.interpolation != "LINEAR" or ch.target.path not in COMPONENTS:
            sys.exit("only LINEAR TRS channels are handled (%s %s)" % (ch.target.path, sampler.interpolation))
        out = read(g, blob, sampler.output)
        new = out[:keep].copy()
        for k in range(w + 1):
            x = k / w
            new[k] = blend(ch.target.path, out[k + keep - 1], out[k], x * x * (3.0 - 2.0 * x))
        sampler.input = new_times
        sampler.output = append(g, blob, new)
    packed = compact(g, blob)
    g.buffers[0].byteLength = len(packed)
    g.set_binary_blob(packed)
    g.save(args.glb)
    print("%s: %d keys -> %d (%.3f s), head crossfaded over %d keys" % (anim.name, len(times), keep,
                                                                         float(times[keep - 1]), w))


if __name__ == "__main__":
    main()
