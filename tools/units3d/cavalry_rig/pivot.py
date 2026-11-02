"""Author cavalry pivots on a COPY of the original source chain.

Prepare canonical 4s source fixtures (not a gameplay duration policy):
  python3 pivot.py prepare SOURCE_DIR cases.json [--cycles 3|4]
Solve those inputs with the accepted Map3DCavalryPivot provider, then bake:
  Blender --factory-startup -b COPY.blend --python-exit-code 1 --python pivot.py -- \
    bake SOURCE_DIR OUTPUT_PREFIX --solved solved.json
Install with install.py --pivots BASE_INSTALLED.glb OUTPUT_PREFIX.glb.

SOURCE_DIR retains cavalry_rigged.glb, source-inspection.json (original bone
landmarks), provider-probe/godot-imported-geometry.json (actual mesh), and
provider-probe/godot-imported-native-v3.json (original native MARCH components).
parameter_inputs accepts full parent-relative native entry/exit poses converted
to source Z-up coordinates, plus the unchanged committed operation. It supplies
contacts and authored poses to the accepted solver, never body yaw or timing.
Run `check SOURCE_DIR report.json` for endpoint/operation/C1 self-checks.
Map an arbitrary receipt with `map SOURCE_DIR output.json --input request.json`;
the request contains operation, entry and exit (source-coordinate 3x4 locals).
Only the new pair is installed; the original five actions are immutable.
Finite source fixtures do not certify continuous contact/envelope or visuals.
"""

import argparse
import hashlib
import json
import math
import pathlib
import struct
import sys
from itertools import pairwise

import numpy as np

_parser = argparse.ArgumentParser(description=__doc__)
_parser.add_argument("stage", choices=["prepare", "bake", "map", "check"])
_parser.add_argument("source_dir", type=pathlib.Path)
_parser.add_argument("output", type=pathlib.Path)
_parser.add_argument("--solved", type=pathlib.Path)
_parser.add_argument("--input", type=pathlib.Path)
_parser.add_argument("--cycles", type=int, choices=[3, 4], default=3)
_args = _parser.parse_args(
    sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else None
)
D = _args.source_dir.resolve()
RAW = (D / "cavalry_rigged.glb").read_bytes()
N = struct.unpack_from("<I", RAW, 12)[0]
J = json.loads(RAW[20 : 20 + N])
B = RAW[28 + N :]
C = np.array([[1.0, 0, 0, 0], [0, 0, -1.0, 0], [0, 1.0, 0, 0], [0, 0, 0, 1.0]])
P = {c: i for i, n in enumerate(J["nodes"]) for c in n.get("children", [])}
IDS = {n["name"]: i for i, n in enumerate(J["nodes"])}
SKIN = J["skins"][0]


def acc(k):
    a = J["accessors"][k]
    v = J["bufferViews"][a["bufferView"]]
    cols = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    sz = struct.calcsize(fmt) * cols
    return np.array(
        [
            struct.unpack_from("<" + fmt * cols, B, off + i * v.get("byteStride", sz))
            for i in range(a["count"])
        ]
    )


def quat(q):
    x, y, z, w = np.asarray(q) / np.linalg.norm(q)
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def slerp(a, b, t):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    dot = np.dot(a, b)
    if dot < 0:
        b = -b
        dot = -dot
    if dot > 0.9995:
        return (a * (1 - t) + b * t) / np.linalg.norm(a * (1 - t) + b * t)
    angle = math.acos(min(1, dot))
    return (a * math.sin((1 - t) * angle) + b * math.sin(t * angle)) / math.sin(angle)


def trs(n):
    m = np.eye(4)
    m[:3, :3] = quat(n.get("rotation", [0, 0, 0, 1])) @ np.diag(
        n.get("scale", [1, 1, 1])
    )
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


ORDER = []


def visit(i):
    if i in SKIN["joints"]:
        ORDER.append(i)
    for c in J["nodes"][i].get("children", []):
        visit(c)


visit(IDS["root"])


ANIMS = {a["name"]: a for a in J["animations"]}


def sample(name, phase):
    a = ANIMS["cavalry_" + name]
    channels = {}
    duration = max(acc(s["input"])[-1, 0] for s in a["samplers"])
    time = phase * duration
    for ch in a["channels"]:
        s = a["samplers"][ch["sampler"]]
        ts = acc(s["input"])[:, 0]
        vs = acc(s["output"])
        i = max(0, min(int(np.searchsorted(ts, time, side="right") - 1), len(ts) - 2))
        t = max(0, min(1, (time - ts[i]) / (ts[i + 1] - ts[i]))) if len(ts) > 1 else 0
        value = (
            slerp(vs[i], vs[i + 1], t)
            if ch["target"]["path"] == "rotation"
            else vs[i] * (1 - t) + vs[min(i + 1, len(vs) - 1)] * t
        )
        channels.setdefault(ch["target"]["node"], {})[ch["target"]["path"]] = value
    out = {}
    for i in ORDER:
        n = dict(J["nodes"][i])
        n.update(channels.get(i, {}))
        m = trs(n)
        if i == IDS["root"]:
            m = C @ m
        out[n["name"]] = m
    return out


STANDING_POSE = sample("STANDBY", 0.0)


def standing_pose():
    return {name: matrix.copy() for name, matrix in STANDING_POSE.items()}


IB = acc(SKIN["inverseBindMatrices"])
GLOBALS = {
    J["nodes"][i]["name"]: C @ np.linalg.inv(IB[k].reshape((4, 4), order="F"))
    for k, i in enumerate(SKIN["joints"])
}
SOURCE = json.loads((D / "source-inspection.json").read_text())
ANATOMY = {b["name"]: b for b in SOURCE["bones"]}
REST = []
for i in ORDER:
    name = J["nodes"][i]["name"]
    parent = J["nodes"][P[i]]["name"] if i != IDS["root"] else ""
    g = GLOBALS[name]
    local = np.linalg.inv(GLOBALS[parent]) @ g if parent else g
    invg = np.linalg.inv(g)
    REST.append(
        {
            "name": name,
            "parent": parent,
            "bind": local,
            "bind_global": g,
            "head": (invg @ np.r_[ANATOMY[name]["head"], 1.0])[:3],
            "tail": (invg @ np.r_[ANATOMY[name]["tail"], 1.0])[:3],
        }
    )
BY = {b["name"]: b for b in REST}
HOOFS = ["FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R"]


def fk(locals):
    g = {}
    for b in REST:
        g[b["name"]] = (
            g[b["parent"]] @ locals[b["name"]] if b["parent"] else locals[b["name"]]
        )
    return g


def yaw(angle):
    a = math.radians(-angle)
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    m[:2, :2] = [[c, -s], [s, c]]
    return m


def flatten(m):
    return m[:3, :].reshape(-1).tolist()


def posejson(p):
    return {n: flatten(m) for n, m in p.items()}


def fixture():
    # Raw immutable bind frames/true local landmarks; no posed-rest substitution.
    bones = [
        {
            k: (flatten(v) if k.startswith("bind") else v.tolist())
            if isinstance(v, np.ndarray)
            else v
            for k, v in b.items()
        }
        for b in REST
    ]
    chains = {}
    for h in HOOFS:
        side = h[-2:]
        names = [
            n + side
            for n in (
                [
                    "FrontScapula",
                    "FrontUpperArm",
                    "FrontForearm",
                    "FrontCannon",
                    "FrontHoof",
                ]
                if h.startswith("Front")
                else ["HindThigh", "HindShin", "HindCannon", "HindHoof"]
            )
        ]
        parent = BY[names[0]]["parent"]
        normals = []
        for i in range(1, len(names) - 1):
            a = GLOBALS[names[i]][:3, 3] - GLOBALS[names[i - 1]][:3, 3]
            b = GLOBALS[names[i + 1]][:3, 3] - GLOBALS[names[i]][:3, 3]
            n = np.linalg.solve(GLOBALS[parent][:3, :3], np.cross(a, b))
            n /= np.linalg.norm(n)
            normals.append(n.tolist())
        chains[h] = {
            "bones": names,
            "rotation_limits": [math.pi] * len(names),
            "bend_limits": [[-math.pi, math.pi]] * (len(names) - 2),
            "bend_normals": normals,
        }
    return {
        "version": 1,
        "turn_axis": [0.0, 0.0, -1.0],
        "bones": bones,
        "chains": chains,
    }


def mix_pose(first, last, t):
    """Native affine interpolation with polar rotation and separate stretch."""
    out = {}
    for name in first:
        a, b = first[name], last[name]
        ua, _sa, va = np.linalg.svd(a[:3, :3])
        ub, _sb, vb = np.linalg.svd(b[:3, :3])
        ra = ua @ va
        rb = ub @ vb
        # Source skeleton is positive parity. Quaternion conversion stays deterministic.
        assert np.linalg.det(ra) > 0 and np.linalg.det(rb) > 0

        def rotq(m):
            # Robust symmetric eigensystem, XYZW quaternion.
            x = (
                np.array(
                    [
                        [
                            m[0, 0] - m[1, 1] - m[2, 2],
                            m[1, 0] + m[0, 1],
                            m[2, 0] + m[0, 2],
                            m[2, 1] - m[1, 2],
                        ],
                        [
                            m[1, 0] + m[0, 1],
                            m[1, 1] - m[0, 0] - m[2, 2],
                            m[2, 1] + m[1, 2],
                            m[0, 2] - m[2, 0],
                        ],
                        [
                            m[2, 0] + m[0, 2],
                            m[2, 1] + m[1, 2],
                            m[2, 2] - m[0, 0] - m[1, 1],
                            m[1, 0] - m[0, 1],
                        ],
                        [
                            m[2, 1] - m[1, 2],
                            m[0, 2] - m[2, 0],
                            m[1, 0] - m[0, 1],
                            np.trace(m),
                        ],
                    ]
                )
                / 3
            )
            w, v = np.linalg.eigh(x)
            q = v[:, np.argmax(w)]
            return q if q[3] >= 0 else -q

        stretch_a = ra.T @ a[:3, :3]
        stretch_b = rb.T @ b[:3, :3]
        m = np.eye(4)
        m[:3, :3] = quat(slerp(rotq(ra), rotq(rb), t)) @ (
            stretch_a * (1 - t) + stretch_b * t
        )
        m[:3, 3] = a[:3, 3] * (1 - t) + b[:3, 3] * t
        out[name] = m
    return out


def smooth(t):
    return t * t * (3 - 2 * t)


def _body_inputs(angle, phase, entry_pose=None, exit_pose=None, cycles=3):
    """Author body motion while retaining exact entry/exit locals."""
    entry = standing_pose() if entry_pose is None else entry_pose
    exit = standing_pose() if exit_pose is None else exit_pose
    neutral = standing_pose()
    lower = {k: v.copy() for k, v in neutral.items()}
    lower["root"][2, 3] -= 0.075 * min(1.0, abs(angle) / 30.0)
    # Load the fore contacts twice per stepping cycle; settle before native exit.
    weight = min(1.0, abs(angle) / 30.0) * smooth(
        min(1.0, max(0.0, (phase - 0.125) / 0.125))
    ) * smooth(min(1.0, max(0.0, (0.875 - phase) / 0.125)))
    beat = (phase - 0.125) * cycles / 0.75
    lower["root"][2, 3] -= 0.008 * weight * (1 + math.cos(4 * math.pi * beat))
    # Existing source rig uses local X for pitch; rider response trails the saddle.
    for name, amplitude, lag in [
        ("Spine1", 1.5, 0.0),
        ("Neck1", -1.0, 0.04),
        ("R_Hips", -1.2, 0.08),
        ("R_Spine", -0.6, 0.13),
    ]:
        half = math.radians(amplitude * weight * math.sin(2 * math.pi * (beat - lag))) / 2
        lower[name][:3, :3] = lower[name][:3, :3] @ quat(
            [math.sin(half), 0.0, 0.0, math.cos(half)]
        )
    # Authored internal vertical motion, no heading or ground-plane translation.
    if phase == 0.0:
        locals = entry
    elif phase == 1.0:
        locals = exit
    elif phase <= 0.125:
        locals = entry
    elif phase < 0.25:
        locals = mix_pose(entry, lower, smooth((phase - 0.125) / 0.125))
    elif phase > 0.875:
        locals = mix_pose(lower, exit, smooth((phase - 0.875) / 0.125))
    else:
        locals = lower
    return {
        "authored_pose": {
            key: posejson(value)
            for key, value in [("locals", locals), ("entry", entry), ("exit", exit)]
        },
        "operation": {
            "start_heading": 0.0,
            "end_heading": angle % 360.0,
            "turn_degrees": float(angle),
            "duration": 4.0,
            "phase": float(phase),
            "entry_phase": 0.0,
            "exit_phase": 0.0,
        },
        "contacts": {},
    }


# Measured static geometry from the actual Godot import, not nominal bone length.
_geo = json.loads((D / "provider-probe/godot-imported-geometry.json").read_text())
assert (
    np.max(np.abs(np.array(_geo["mesh_transform"]).reshape(3, 4) - np.eye(4)[:3, :]))
    == 0
)
_sole_points = (
    C
    @ np.c_[
        np.array(_geo["surfaces"][0]["vertices"]),
        np.ones(len(_geo["surfaces"][0]["vertices"])),
    ].T
).T[:, :3]
_sole_homes = np.array([ANATOMY[h]["tail"] for h in HOOFS])
_sole_owner = np.argmin(
    np.linalg.norm(_sole_points[:, :, None] - _sole_homes.T[None, :, :], axis=1), axis=1
)
SOLE_FRAMES = {}
for _i, _h in enumerate(HOOFS):
    _region = _sole_points[_sole_owner == _i]
    _z = _region[:, 2].min()
    _bottom = _region[_region[:, 2] == _z]
    _frame = np.eye(4)
    _frame[:3, 3] = _bottom.mean(axis=0)
    SOLE_FRAMES[_h] = _frame
SOLE_GROUND = min(f[2, 3] for f in SOLE_FRAMES.values())


def _contact_inputs(angle, phase, entry_pose=None, exit_pose=None, cycles=3):
    case = _body_inputs(angle, phase, entry_pose, exit_pose, cycles)
    entry = standing_pose() if entry_pose is None else entry_pose
    exit = standing_pose() if exit_pose is None else exit_pose
    neutral = standing_pose()
    eg, xg, ng = fk(entry), fk(exit), fk(neutral)
    zero = np.zeros((4, 4))
    contacts = {}
    order = ["HindHoof.L", "FrontHoof.L", "HindHoof.R", "FrontHoof.R"]
    # Transition order lands airborne hooves before lifting the native support.
    initial_order = (
        sorted(order, key=lambda h: -(eg[h] @ np.r_[BY[h]["tail"], 1.0])[2])
        if entry_pose is not None
        else order
    )
    final_order = (
        sorted(order, key=lambda h: -(xg[h] @ np.r_[BY[h]["tail"], 1.0])[2])
        if exit_pose is not None
        else order
    )
    for h in order:
        sole = SOLE_FRAMES[h].copy()
        offset = np.linalg.inv(GLOBALS[h]) @ sole
        source = eg[h] @ offset
        end = yaw(angle) @ xg[h] @ offset
        home = ng[h] @ offset
        home[2, 3] = SOLE_GROUND
        windows = [
            (initial_order.index(h) * 0.03125, (initial_order.index(h) + 1) * 0.03125)
        ]
        period = 0.75 / cycles
        swing = period / 4
        windows += [
            (
                0.125 + order.index(h) * swing + k * period,
                0.125 + order.index(h) * swing + k * period + swing,
            )
            for k in range(cycles)
        ]
        windows += [
            (
                0.875 + final_order.index(h) * 0.03125,
                0.875 + (final_order.index(h) + 1) * 0.03125,
            )
        ]
        pieces = []
        cursor = 0.0
        target = source

        def add(a, b, mode, x, y, dx=None, dy=None, _pieces=pieces):
            _pieces.append(
                {
                    "start": float(a),
                    "end": float(b),
                    "mode": mode,
                    "from": flatten(x),
                    "to": flatten(y),
                    "from_derivative": flatten(zero if dx is None else dx),
                    "to_derivative": flatten(zero if dy is None else dy),
                }
            )

        for i, (start, stop) in enumerate(windows):
            if start > cursor:
                # Native entry can be airborne; only acquired home anchors claim stance.
                mode = "swing" if i == 0 else "stance"
                add(cursor, start, mode, target, target)
            next_start = windows[i + 1][0] if i + 1 < len(windows) else 1.0
            dest = (
                end
                if i == len(windows) - 1
                else yaw(angle * (stop + next_start) * 0.5) @ home
            )
            mid = (start + stop) / 2
            ap = mix_pose({"hoof": target}, {"hoof": dest}, 0.5)["hoof"]
            ap[:3, 3] = (target[:3, 3] + dest[:3, 3]) / 2
            ap[2, 3] += min(0.085, 0.085 * abs(angle) / 180.0)
            derivative = zero.copy()
            derivative[:3, 3] = (dest[:3, 3] - target[:3, 3]) / (stop - start)
            add(start, mid, "swing", target, ap, dy=derivative)
            add(mid, stop, "swing", ap, dest, dx=derivative)
            cursor = stop
            target = dest
        if cursor < 1.0:
            add(
                cursor,
                1.0,
                "swing",
                target,
                target,
            )
        contacts[h] = {"offset": flatten(offset), "segments": pieces}
    case["contacts"] = contacts
    return case


def parameter_inputs(operation, entry_pose, exit_pose, cycles=3):
    """Return solver inputs; preserve the supplied operation and endpoint locals."""
    assert cycles in (3, 4)
    case = _contact_inputs(
        operation["turn_degrees"], operation["phase"], entry_pose, exit_pose, cycles
    )
    case["operation"] = dict(operation)
    return case


if _args.stage == "prepare":
    assert not _args.output.exists(), "Retain previous variant evidence"
    cases = []
    for angle in [180.0, -179.999999]:
        for frame in range(961):
            case = _contact_inputs(angle, frame / 960.0, cycles=_args.cycles)
            case["tag"] = {"canonical": True, "frame": frame}
            cases.append(case)
    inputs = [
        "cavalry_rigged.glb",
        "source-inspection.json",
        "provider-probe/godot-imported-geometry.json",
    ]
    _args.output.write_text(
        json.dumps(
            {
                "rest": fixture(),
                "cases": cases,
                "source_sha256": {
                    p: hashlib.sha256((D / p).read_bytes()).hexdigest() for p in inputs
                },
                "tool_sha256": hashlib.sha256(
                    pathlib.Path(__file__).read_bytes()
                ).hexdigest(),
                "cycles": _args.cycles,
                "fps": 240,
            }
        )
    )
    print(
        "Prepared",
        len(cases),
        "canonical source poses; solve with the accepted provider",
    )
elif _args.stage == "map":
    assert _args.input is not None and not _args.output.exists()
    request = json.loads(_args.input.read_text())
    poses = {}
    for key in ["entry", "exit"]:
        assert set(request[key]) == set(BY)
        poses[key] = {}
        for name, value in request[key].items():
            assert len(value) == 12 and all(math.isfinite(x) for x in value)
            poses[key][name] = np.vstack(
                [np.array(value).reshape(3, 4), [0.0, 0.0, 0.0, 1.0]]
            )
    case = parameter_inputs(
        request["operation"], poses["entry"], poses["exit"], _args.cycles
    )
    _args.output.write_text(json.dumps({"rest": fixture(), "cases": [case]}))
    print("Mapped unchanged receipt and actual endpoint locals")
elif _args.stage == "bake":
    import bpy
    from mathutils import Matrix

    assert _args.solved is not None
    source = pathlib.Path(bpy.data.filepath).resolve()
    assert source.parent == D and source.name == "cavalry_rig_work.blend"
    out = _args.output.resolve()
    assert out.with_suffix(".blend") != source and all(
        not out.with_suffix(suffix).exists() for suffix in [".blend", ".glb", ".json"]
    )
    rows = json.loads(_args.solved.read_text())
    assert len(rows) == 1922 and all(r["ok"] and r["tag"]["canonical"] for r in rows)
    rig = bpy.data.objects["cavalry_rig"]
    mesh = bpy.data.objects["cavalry"]
    bpy.context.window.scene = bpy.data.scenes["Cavalry_Rig"]

    def curves(action):
        return [
            f
            for layer in action.layers
            for strip in layer.strips
            for bag in strip.channelbags
            for f in bag.fcurves
        ]

    def action_hashes():
        return {
            a.name: hashlib.sha256(
                json.dumps(
                    [
                        (
                            f.data_path,
                            f.array_index,
                            [
                                (
                                    list(p.co),
                                    list(p.handle_left),
                                    list(p.handle_right),
                                    p.interpolation,
                                )
                                for p in f.keyframe_points
                            ],
                        )
                        for f in curves(a)
                    ]
                ).encode()
            ).hexdigest()
            for a in bpy.data.actions
            if a.name
            in [
                "cavalry_ATTACK",
                "cavalry_DEFEND",
                "cavalry_GARRISON",
                "cavalry_MARCH",
                "cavalry_STANDBY",
            ]
        }

    old = action_hashes()
    assert len(old) == 5
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    local_rest = {
        b.name: (
            b.parent.matrix_local.inverted() @ b.matrix_local
            if b.parent
            else b.matrix_local.copy()
        )
        for b in rig.data.bones
    }
    # Only the appended pair uses this bake timebase; original installed clips stay byte-exact.
    bpy.context.scene.render.fps = 240
    native = json.loads(
        (D / "provider-probe/godot-imported-native-v3.json").read_text()
    )
    aliases = {"head": "R_Head", "head_h": "Head"}
    properties = {1: "location", 2: "rotation_quaternion", 3: "scale"}
    owned_components = {name: set() for name in rest}
    for track in native["old_animations"]["MARCH"]["tracks"]:
        name = track["path"].rsplit(":", 1)[1]
        owned_components[aliases.get(name, name)].add(properties[track["type"]])
    assert {"root"} | {
        bone for chain in fixture()["chains"].values() for bone in chain["bones"]
    } <= {name for name, props in owned_components.items() if props}
    error = 0.0
    for angle, name in [(180.0, "PIVOT_RIGHT"), (-179.999999, "PIVOT_LEFT")]:
        assert "cavalry_" + name not in bpy.data.actions
        action = bpy.data.actions.new("cavalry_" + name)
        action.use_fake_user = True
        rig.animation_data.action = action
        selected = [r for r in rows if r["operation"]["turn_degrees"] == angle]
        assert len(selected) == 961 and {
            int(r["tag"]["frame"]) for r in selected
        } == set(range(961))
        for row in selected:
            frame = row["tag"]["frame"]
            assert not isinstance(frame, bool) and frame == int(frame)
            frame = int(frame)
            assert (
                abs(row["operation"]["phase"] - frame / 960.0) < 1e-12
                and row["operation"]["duration"] == 4.0
            )
            assert set(row["locals"]) == set(rest)
            bpy.context.scene.frame_set(frame)
            for bone in rig.pose.bones:
                v = row["locals"][bone.name]
                assert len(v) == 12 and all(math.isfinite(x) for x in v)
                local = Matrix((v[0:4], v[4:8], v[8:12], [0.0, 0.0, 0.0, 1.0]))
                bone.rotation_mode = "QUATERNION"
                bone.matrix_basis = local_rest[bone.name].inverted() @ local
                props = owned_components[bone.name]
                # Preserve native rest bits for components MARCH never writes.
                if "location" not in props:
                    bone.location = (0.0, 0.0, 0.0)
                if "rotation_quaternion" not in props:
                    bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                if "scale" not in props:
                    bone.scale = (1.0, 1.0, 1.0)
                for prop in sorted(props):
                    bone.keyframe_insert(prop, frame=frame)
            bpy.context.view_layer.update()
            for bone in rig.pose.bones:
                got = (
                    bone.parent.matrix.inverted() @ bone.matrix
                    if bone.parent
                    else bone.matrix
                )
                error = max(
                    error,
                    max(
                        abs(got[i][j] - row["locals"][bone.name][i * 4 + j])
                        for i in range(3)
                        for j in range(4)
                    ),
                )
        for curve in curves(action):
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
    assert error < 1e-5 and action_hashes() == old
    assert all(rig.data.bones[n].matrix_local == matrix for n, matrix in rest.items())
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.wm.save_as_mainfile(filepath=str(out.with_suffix(".blend")), compress=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out.with_suffix(".glb")),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_force_sampling=True,
        export_optimize_animation_keep_anim_armature=False,
        export_apply=False,
        export_yup=True,
    )
    out.with_suffix(".json").write_text(
        json.dumps(
            {
                "source_blend_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "solved_sha256": hashlib.sha256(_args.solved.read_bytes()).hexdigest(),
                "old_action_hashes": old,
                "rest_unchanged": True,
                "pose_bake_max_abs": error,
                "fps": 240,
                "duration": 4.0,
            },
            indent=2,
        )
        + "\n"
    )
    print("Baked new pair; unchanged old actions/rest; max local error", error)
else:
    capture = json.loads(
        (D / "provider-probe/godot-imported-native-v3.json").read_text()
    )
    aliases = {"head": "R_Head", "head_h": "Head"}

    def native_pose(phase):
        row = next(r for r in capture["samples"] if r["phase"] == phase)
        result = {}
        for name, v in row["bone_poses"].items():
            name = aliases.get(name, name)
            matrix = np.vstack([np.array(v).reshape(3, 4), [0.0, 0.0, 0.0, 1.0]])
            result[name] = C @ matrix if name == "root" else matrix
        return result

    entry = native_pose(0.37)
    exit = native_pose(0.81)
    # A turn must not freeze the horse's upper body and rider between footfalls.
    holds = [
        _body_inputs(180.0, phase)["authored_pose"]["locals"]
        for phase in [0.3, 0.35, 0.4]
    ]
    for name in ["root", "Spine1", "R_Hips", "R_Spine"]:
        assert np.max(np.ptp([pose[name] for pose in holds], axis=0)) > 1e-6, name
    count = 0
    for angle in [180.0, -179.999999, 90.0, -90.0, 1e-6, -1e-6]:
        for phase in [0.0, 1e-6, 0.125, 0.25, 0.37, 0.5, 0.875, 1.0 - 1e-6, 1.0]:
            op = {
                "turn_degrees": angle,
                "start_heading": 359.0,
                "end_heading": (359.0 + angle) % 360.0,
                "phase": phase,
                "duration": 7.25,
                "entry_phase": 0.37,
                "exit_phase": 0.81,
            }
            case = parameter_inputs(op, entry, exit)
            assert case["operation"] == op and case["operation"] is not op
            assert case["authored_pose"]["entry"] == posejson(entry) and case[
                "authored_pose"
            ]["exit"] == posejson(exit)
            if phase == 0.0:
                assert case["authored_pose"]["locals"] == posejson(entry)
            if phase == 1.0:
                assert case["authored_pose"]["locals"] == posejson(exit)
            for contact in case["contacts"].values():
                segments = contact["segments"]
                for segment in segments:
                    if segment["mode"] == "stance":
                        assert segment["from"] == segment["to"]
                        assert abs(segment["from"][11] - SOLE_GROUND) < 1e-12
                assert segments[0]["start"] == 0.0 and segments[-1]["end"] == 1.0
                for a, b in pairwise(segments):
                    assert (
                        a["end"] == b["start"]
                        and a["to"] == b["from"]
                        and a["to_derivative"] == b["from_derivative"]
                    )
            count += 1
    _args.output.write_text(
        json.dumps(
            {
                "cases": count,
                "operation_and_native_endpoint_preservation": True,
                "full_affine_contact_partition_C1": True,
                "note": "Source mapping self-check; no continuous contact/envelope/visual certification.",
            },
            indent=2,
        )
        + "\n"
    )
    print("Mapping self-check:", count, "cases")
