"""Per-arm locomotion certifier (owner rulings R-A, R-B, R-C, 2026-11-10).

Samples MARCH, PIVOT_LEFT and PIVOT_RIGHT densely in Godot (every key, the
quarter points between keys, a uniform grid and every boundary phase), skins
every equipped mesh with the native imported arrays and bone poses, and checks:

  1. penetration  any vertex below the rendered ground, every sample;
  2. hover        the planted material patch above the seated plane, stance only;
  3. slide        the planted patch's ground-projected drift from touchdown, per stance;
  4. seam         any vertex jump at a clip boundary;
  plus the envelope against the arm's footprint radius and the skin diagnostic.

Each sampled maximum gets a sampling margin: the largest per-interval vertex
displacement of the quantity's own coordinate (measured velocity x spacing), a
full chord where the worst value between two samples needs half of the arc.
Bounds 1-3 are `contact_um`, 4 is the seam bound, both ceil(world_m / k * 1e6).

Turns come from the integer turn grid (+-1 microdegree, the 180 tie, the 359
wrap, ...): positive selects PIVOT_RIGHT, and the world yaw at operation phase
p is yaw0 - turn * p. With no provider the pose is the native clip at phase p.
An arm's provider script (config "provider": `static func pose(player,
skeleton, request)`) replaces that seek; it is then sampled per grid turn and
the native seek is kept beside it for the skin diagnostic (R-B).

Writes a digest-bound certificate JSON; exit 0 PASS, 1 FAIL, 2 error. A PASS is
the numeric half of R-C only: the real-window review is still required.

    python3 tools/units3d/certify_locomotion.py --config CFG.json --out CERT.json
"""
import argparse
import base64
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
CLIPS = ['PIVOT_LEFT', 'PIVOT_RIGHT', 'MARCH']  # BodyMotion._loco_policy's list
BOUND_WORLD_M = {'contact': 0.60, 'seam': 0.05}  # R-A
SKIN_RATIO, SKIN_MIN_M = 4.0, 0.03  # R-B, unchanged thresholds
TURN = 360_000_000
LOCO_Q = 1_000_000  # BodyMotion.LOCOMOTION_Q
UNIFORM = 512


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def um(metres):
    """Model metres to whole micrometres, rounded up (never flatters a residual)."""
    return math.ceil(round(metres * 1e6, 6))


def bounds_um(k):
    return {name: math.ceil(world / k * 1e6) for name, world in BOUND_WORLD_M.items()}


def shortest(start, finish):
    """BodyMotion._loco_turn: shortest signed turn, the 180 tie turns positive."""
    turn = (finish - start + 180_000_000) % TURN - 180_000_000
    return 180_000_000 if turn == -180_000_000 else turn


def duration_q(turn, turn_q):
    """BodyMotion._loco_duration(|turn|, turn_q, TURN)."""
    return -(-abs(turn) * turn_q // TURN)


def turn_grid():
    """Signed turns sampled for every pivot: named edges of the integer domain."""
    pairs = {'+1 microdegree': (0, 1), '-1 microdegree': (1, 0),
             '359 to 1 wrap': (359_000_000, 1_000_000), '1 to 359 wrap': (1_000_000, 359_000_000),
             '+45': (0, 45_000_000), '-45': (45_000_000, 0), '+90': (0, 90_000_000),
             '-90': (90_000_000, 0), '+135': (0, 135_000_000), '-135': (135_000_000, 0),
             '+179.999999': (0, 179_999_999), '-179.999999': (179_999_999, 0),
             '180 tie': (0, 180_000_000), '180 tie reversed': (180_000_000, 0)}
    return [{'name': name, 'yaw0_udeg': a, 'turn_udeg': shortest(a, b)} for name, (a, b) in pairs.items()]


def clip_for(turn):
    return 'PIVOT_RIGHT' if turn > 0 else 'PIVOT_LEFT'


def rot_y(points, yaw):
    """Godot Basis(Vector3.UP, yaw) applied to row points."""
    c, s = math.cos(yaw), math.sin(yaw)
    out = points.copy()
    out[..., 0] = c * points[..., 0] + s * points[..., 2]
    out[..., 2] = -s * points[..., 0] + c * points[..., 2]
    return out


def skin(vertices, joints, weights, matrices):
    """Linear blend skinning with the raw packed weights (no normalization)."""
    if (not np.isfinite(weights).all() or (weights < 0).any() or not np.isfinite(vertices).all()
            or not np.isfinite(matrices).all() or joints.shape != weights.shape
            or len(vertices) != len(weights) or (joints < 0).any() or (joints >= len(matrices)).any()):
        raise ValueError('invalid native skin arrays')
    out = np.zeros_like(vertices, dtype=float)
    for slot in range(joints.shape[1]):
        m = matrices[joints[:, slot]]
        out += (np.einsum('nij,nj->ni', m[:, :3, :3], vertices) + m[:, :3, 3]) * weights[:, slot, None]
    return out


def matrix4(rows34):
    m = np.zeros(rows34.shape[:-2] + (4, 4))
    m[..., :3, :] = rows34
    m[..., 3, 3] = 1.0
    return m


def b64(text, dtype, width):
    return np.frombuffer(base64.b64decode(text, validate=True), dtype=dtype).reshape(-1, width)


class Model:
    """Decoded native dump: geometry, bind data and sampled bone poses."""

    def __init__(self, dump):
        self.dump = dump
        self.sk = np.array(dump['skeleton_to_model'], dtype=float)
        self.meshes = []
        for mesh in dump['meshes']:
            binds = [(b['bone'], np.array(b['pose'], dtype=float)) for b in mesh['skin']]
            for index, s in enumerate(mesh['surfaces']):
                v = b64(s['vertices_f32'], '<f4', 3).astype(float)
                j = b64(s['bones_i32'], '<i4', 1).reshape(len(v), -1)
                w = b64(s['weights_f32'], '<f4', 1).reshape(len(v), -1).astype(float)
                tri = b64(s['indices_i32'], '<i4', 3)
                edges = np.sort(np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=1)
                self.meshes.append({'mesh': mesh['name'], 'surface': index, 'v': v, 'j': j, 'w': w,
                                    'binds': binds, 'edges': np.unique(edges, axis=0)})
        self.offsets = np.cumsum([0] + [len(m['v']) for m in self.meshes])
        self.samples = dump['samples']
        for s in self.samples:
            s['_g'] = matrix4(b64(s['globals_f64'], '<f8', 12).reshape(-1, 3, 4))

    def points(self, globals_):
        out = []
        for m in self.meshes:
            mats = np.array([self.sk @ globals_[bone] @ pose for bone, pose in m['binds']])
            out.append(skin(m['v'], m['j'], m['w'], mats))
        return np.concatenate(out)

    def where(self, flat):
        part = int(np.searchsorted(self.offsets, flat, side='right') - 1)
        return {'mesh': self.meshes[part]['mesh'], 'surface': self.meshes[part]['surface'],
                'vertex': int(flat - self.offsets[part])}

    def rest_points(self):
        return self.points(matrix4(np.array([b['global_rest'] for b in self.dump['bones']])[:, :3, :]))


def patches(model, feet, band):
    """Material patch per foot, chosen ONCE in rest: the foot-bound vertices of the
    body mesh within `band` model metres of that foot's lowest rest vertex."""
    rest = model.rest_points()
    names = [b['name'] for b in model.dump['bones']]
    out = {}
    for foot, bones in feet.items():
        ids = {names.index(b) for b in bones}
        chosen = []
        for part, m in enumerate(model.meshes):
            bound = np.array([bone in ids for bone, _ in m['binds']])
            share = np.where(bound[m['j']], m['w'], 0).sum(axis=1)
            chosen.append(np.flatnonzero(share > .8) + model.offsets[part])
        chosen = np.concatenate(chosen)
        if not len(chosen):
            raise ValueError('no vertex bound to foot ' + foot)
        low = rest[chosen, 1].min()
        out[foot] = chosen[rest[chosen, 1] <= low + band]
    return out


def streams(samples):
    """{(clip, turn or None, provider): samples sorted by phase}."""
    out = {}
    for s in samples:
        out.setdefault((s['clip'], s.get('turn_udeg'), bool(s.get('provider'))), []).append(s)
    for rows in out.values():
        rows.sort(key=lambda s: s['phase'])
    return out


def check_coverage(dump, extra):
    """Every key time, every key-interval quarter, the uniform grid and every
    boundary phase must be sampled for every captured stream."""
    missing = []
    for (clip, turn, provider), rows in streams(dump['samples']).items():
        info = dump['clips'][clip]
        length = info['length_s']
        have = [s['phase'] for s in rows]
        keys = sorted({0.0, length, *[t for t in info['key_times'] if 0 <= t <= length]})
        need = [t / length for t in keys]
        need += [(a + (b - a) * f) / length for a, b in zip(keys, keys[1:]) for f in (.25, .5, .75)]
        need += [i / UNIFORM for i in range(UNIFORM + 1)] + list(extra)
        for p in need:
            if not any(abs(p - h) <= 1e-12 for h in have):
                missing.append({'clip': clip, 'turn_udeg': turn, 'phase': p})
    return missing


def stance_runs(heights, phases, rule, foot, loop):
    """Index runs where `foot` stands. rule 'lowest:N' = among the N lowest
    patches at that sample; {foot: [[p0, p1], ...]} = authored intervals."""
    if isinstance(rule, dict):
        return [[i for i, p in enumerate(phases) if a <= p <= b] for a, b in rule.get(foot, [])]
    n = int(rule.split(':')[1])
    names = sorted(heights)
    order = np.argsort(np.array([heights[f] for f in names]), axis=0, kind='stable')
    down = (order[:n] == names.index(foot)).any(axis=0)
    runs, current = [], []
    for i, d in enumerate(down):
        if d:
            current.append(i)
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)
    if loop and len(runs) > 1 and runs[0][0] == 0 and runs[-1][-1] == len(phases) - 1:
        runs[0] = runs.pop() + runs[0]  # the stance crossing the loop seam is ONE stance
    return [r for r in runs if r]


class Worst:
    def __init__(self):
        self.value, self.margin, self.witness = 0.0, 0.0, None

    def offer(self, value, witness):
        if self.witness is None or value > self.value:
            self.value, self.witness = float(value), witness

    def widen(self, margin):
        self.margin = max(self.margin, float(margin))

    def report(self, bound_um):
        total = um(self.value + self.margin)
        return {'sampled_um': um(self.value), 'margin_um': um(self.margin), 'total_um': total,
                'bound_um': bound_um, 'pass': total <= bound_um, 'witness': self.witness}


def measure(dump, config, scale):
    """Pure measurement of a decoded capture against R-A / R-B. `scale` =
    {k, simulation_scale, lift_model_m}."""
    model = Model(dump)
    bounds = bounds_um(scale['k'])
    feet = patches(model, config['feet'], config.get('patch_band_m', .005))
    forward = np.array(config['forward'], dtype=float)
    stride = float(config['stride_m'])
    slope = float(config.get('slope', 0.0))
    ground = -float(scale['lift_model_m'])
    by = streams(model.samples)
    provider = bool(config.get('provider'))
    grid = turn_grid()
    pen, hov, sld, env = Worst(), Worst(), Worst(), Worst()

    def world(clip, phase, points, turn, cycle=0):
        if clip == 'MARCH':
            return points + forward * stride * (phase + cycle)
        return rot_y(points, -math.radians(turn / 1e6) * phase)

    def stream(clip, turn, prov=provider):
        return by.get((clip, turn if prov and clip != 'MARCH' else None, prov), [])

    def at(clip, phase, turn, prov=provider):
        for s in stream(clip, turn, prov):
            if abs(s['phase'] - phase) <= 1e-12:
                return s
        raise ValueError(f'phase {phase} of {clip} was not sampled')

    # Penetration and envelope (every sample), hover and slide (stance), with margins.
    for (clip, turn, prov), rows in by.items():
        if prov != provider:
            continue  # native twin of a provider stream: skin diagnostic only
        loop = clip == 'MARCH' and dump['clips']['MARCH']['loop_mode'] != 0
        phases = [s['phase'] for s in rows]
        heights = {f: [] for f in feet}
        patch_pts = {f: [] for f in feet}
        prev = None
        for s in rows:
            p = model.points(s['_g'])
            r = np.linalg.norm(p[:, [0, 2]], axis=1)
            depth = ground + slope * r - p[:, 1]
            i = int(np.argmax(depth))
            pen.offer(max(depth[i], 0.0), {'clip': clip, 'phase': s['phase'], 'turn_udeg': turn, **model.where(i)})
            i = int(np.argmax(r))
            env.offer(r[i], {'clip': clip, 'phase': s['phase'], 'turn_udeg': turn, **model.where(i)})
            if prev is not None:
                moved = np.linalg.norm((p - prev)[:, [0, 2]], axis=1)
                pen.widen((np.abs(p[:, 1] - prev[:, 1]) + slope * moved).max())
                env.widen(moved.max())
            prev = p
            for f, ids in feet.items():
                heights[f].append(p[ids, 1].min())
                patch_pts[f].append(p[ids])
        rule = config['stance'][clip]
        turns = [turn] if clip == 'MARCH' or turn is not None else \
            [g['turn_udeg'] for g in grid if clip_for(g['turn_udeg']) == clip]
        for f in feet:
            for run in stance_runs(heights, phases, rule, f, loop):
                cycles = np.cumsum([0] + [1 if b < a else 0 for a, b in zip(run, run[1:])])
                for k, i in enumerate(run):
                    hov.offer(heights[f][i], {'clip': clip, 'foot': f, 'phase': phases[i], 'turn_udeg': turn})
                    if k:
                        hov.widen(np.abs(patch_pts[f][i][:, 1] - patch_pts[f][run[k - 1]][:, 1]).max())
                for t in turns:
                    anchor = world(clip, phases[run[0]], patch_pts[f][run[0]], t)[:, [0, 2]]
                    last = None
                    for k, i in enumerate(run):
                        w = world(clip, phases[i], patch_pts[f][i], t, cycles[k])[:, [0, 2]]
                        sld.offer(np.linalg.norm(w - anchor, axis=1).max(),
                                  {'clip': clip, 'foot': f, 'turn_udeg': t, 'touchdown_phase': phases[run[0]],
                                   'phase': phases[i]})
                        if last is not None:
                            sld.widen(np.linalg.norm(w - last, axis=1).max())
                        last = w

    # Seams: both one-sided values at every configured boundary, compared in the
    # receiving clip's model frame (the consumer's yaw and position are continuous
    # there). A '*' phase sweeps every sample of that side: a cut from any phase.
    seams, seam_worst = [], None
    for a_clip, a_ph, b_clip, b_ph in config['boundaries']:
        pivot = next((c for c in (a_clip, b_clip) if c != 'MARCH'), None)
        turns = [g['turn_udeg'] for g in grid if clip_for(g['turn_udeg']) == pivot] if provider and pivot else [None]
        for t in turns:
            if a_ph == '*':
                pairs = [(s['phase'], b_ph) for s in stream(a_clip, t)]
            elif b_ph == '*':
                pairs = [(a_ph, s['phase']) for s in stream(b_clip, t)]
            else:
                pairs = [(a_ph, b_ph)]
            fixed = {}
            best, prev = Worst(), None
            for pa_ph, pb_ph in pairs:
                pa = fixed.setdefault('a', model.points(at(a_clip, pa_ph, t)['_g'])) if a_ph != '*' \
                    else model.points(at(a_clip, pa_ph, t)['_g'])
                pb = fixed.setdefault('b', model.points(at(b_clip, pb_ph, t)['_g'])) if b_ph != '*' \
                    else model.points(at(b_clip, pb_ph, t)['_g'])
                d = np.linalg.norm(pa - pb, axis=1)
                i = int(np.argmax(d))
                best.offer(d[i], {'from': [a_clip, pa_ph], 'to': [b_clip, pb_ph], 'turn_udeg': t, **model.where(i)})
                moving = pa if a_ph == '*' else pb
                if prev is not None:
                    best.widen(np.linalg.norm(moving - prev, axis=1).max())
                prev = moving
            seams.append(best.report(bounds['seam']))
            if seam_worst is None or seams[-1]['total_um'] >= seam_worst['total_um']:
                seam_worst = seams[-1]

    # Skin diagnostic (R-B): an edge longer than 4x its native-entry length AND
    # 0.03 m fails, unless the native seek at the same clip and phase is flagged.
    entry = model.points(at('MARCH', config.get('entry_phase', 0.0), None, False)['_g'])
    entry_len = [np.linalg.norm(entry[m['edges'][:, 0] + o] - entry[m['edges'][:, 1] + o], axis=1)
                 for m, o in zip(model.meshes, model.offsets)]

    def flags(s):
        p = model.points(s['_g'])
        out = set()
        for part, (m, o) in enumerate(zip(model.meshes, model.offsets)):
            length = np.linalg.norm(p[m['edges'][:, 0] + o] - p[m['edges'][:, 1] + o], axis=1)
            out.update((part, int(e)) for e in
                       np.flatnonzero((length > SKIN_RATIO * entry_len[part]) & (length > SKIN_MIN_M)))
        return out

    natives = {(s['clip'], s['phase']): flags(s) for s in model.samples if not s.get('provider')}
    inherited, introduced, witnesses = 0, 0, []
    for s in model.samples:
        if bool(s.get('provider')) != provider:
            continue
        base = natives[(s['clip'], s['phase'])]
        own = flags(s) if provider else base
        new = own - base
        inherited += len(own & base)
        introduced += len(new)
        for part, e in sorted(new)[:max(0, 20 - len(witnesses))]:
            witnesses.append({'clip': s['clip'], 'phase': s['phase'], 'turn_udeg': s.get('turn_udeg'),
                              'mesh': model.meshes[part]['mesh'], 'edge': model.meshes[part]['edges'][e].tolist()})
    radius_sim = math.ceil((env.value + env.margin) * scale['simulation_scale'])
    report = {
        'bounds_um': bounds,
        'penetration': pen.report(bounds['contact']),
        'hover': hov.report(bounds['contact']),
        'slide': sld.report(bounds['contact']),
        # No boundary configured is a failure: every arm has at least its loop seam.
        'seam': {**(seam_worst or Worst().report(bounds['seam'])), 'pass': bool(seams) and all(s['pass'] for s in seams),
                 'boundaries': seams},
        'envelope': {'radius_model_um': um(env.value), 'margin_um': um(env.margin),
                     'radius_simulation_m': radius_sim, 'footprint_radius_m': int(config['radius_m']),
                     'pass': radius_sim <= int(config['radius_m']), 'witness': env.witness},
        'skin': {'flagged_pairs_inherited': inherited, 'flagged_pairs_introduced': introduced,
                 'pass': introduced == 0, 'introduced_witnesses': witnesses,
                 'rule': 'length > 4 x native-entry AND > 0.03 model m; fails unless the native seek at the same phase is flagged'},
        'patches': {f: {'vertices': int(len(ids)), 'first': [model.where(int(i)) for i in ids[:4]]}
                    for f, ids in feet.items()},
        'turn_grid': [{**g, 'clip': clip_for(g['turn_udeg']), 'duration_q': duration_q(g['turn_udeg'], config['turn_q'])}
                      for g in grid],
        'sample_count': len(model.samples),
    }
    report['pass'] = all(report[q]['pass'] for q in ('penetration', 'hover', 'slide', 'seam', 'envelope', 'skin')) \
        and all(0 < g['duration_q'] <= LOCO_Q for g in report['turn_grid'])
    return report


# ---- Godot capture: isolated copy of the scene's dependency closure. ----------

CAPTURE = r'''extends SceneTree

func rows(t: Transform3D) -> PackedFloat64Array:
	return PackedFloat64Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,
		t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z])

func matrix(t: Transform3D) -> Array:
	var r := rows(t)
	return [[r[0],r[1],r[2],r[3]],[r[4],r[5],r[6],r[7]],[r[8],r[9],r[10],r[11]],[0.0,0.0,0.0,1.0]]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var req: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var model: Node3D = load(req.scene).instantiate()
	root.add_child(model)
	await process_frame
	var sk: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	var provider: Variant = load(req.provider) if req.provider != "" else null
	player.stop(true)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var data := {"pid":OS.get_process_id(),"godot":Engine.get_version_info(),
		"skeleton_to_model":matrix(model.global_transform.affine_inverse()*sk.global_transform),
		"bones":[],"meshes":[],"clips":{},"samples":[]}
	for bone: int in sk.get_bone_count():
		data.bones.append({"name":sk.get_bone_name(bone),"parent":sk.get_bone_parent(bone),
			"global_rest":matrix(sk.get_bone_global_rest(bone))})
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.skin == null or mesh.get_node(mesh.skeleton) != sk:
			push_error("unskinned or foreign mesh " + str(mesh.name))
			quit(3)
			return
		var row := {"name":mesh.name,"skin":[],"surfaces":[]}
		for bind: int in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(bind))
			row.skin.append({"bone":bone,"name":sk.get_bone_name(bone),"pose":matrix(mesh.skin.get_bind_pose(bind))})
		for surface: int in mesh.mesh.get_surface_count():
			var a: Array = mesh.mesh.surface_get_arrays(surface)
			row.surfaces.append({"vertices_f32":Marshalls.raw_to_base64((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array()),
				"bones_i32":Marshalls.raw_to_base64((a[Mesh.ARRAY_BONES] as PackedInt32Array).to_byte_array()),
				"weights_f32":Marshalls.raw_to_base64((a[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).to_byte_array()),
				"indices_i32":Marshalls.raw_to_base64((a[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())})
		data.meshes.append(row)
	for clip: String in req.clips:
		var name := ""
		for candidate: String in player.get_animation_list():
			if candidate.get_file() == clip: name = candidate
		if name.is_empty():
			push_error("missing clip " + clip)
			quit(3)
			return
		var anim := player.get_animation(name)
		var keys: Array[float] = [0.0, anim.length]
		for track: int in anim.get_track_count():
			for key: int in anim.track_get_key_count(track):
				var t := anim.track_get_key_time(track, key)
				if t >= 0.0 and t <= anim.length and not t in keys: keys.append(t)
		keys.sort()
		var times: Array[float] = []
		times.append_array(keys)
		for i: int in range(1, keys.size()):
			for f: float in [0.25, 0.5, 0.75]: times.append(keys[i-1] + (keys[i] - keys[i-1]) * f)
		var uniform := int(req.uniform)
		for i: int in range(uniform + 1): times.append(anim.length * float(i) / float(uniform))
		for p: float in req.extra_phases: times.append(anim.length * p)
		times.sort()
		data.clips[clip] = {"length_s":anim.length,"key_times":keys,"loop_mode":anim.loop_mode,"tracks":anim.get_track_count()}
		var variants: Array = [[null, false]]
		if provider != null and clip == "MARCH":
			variants.append([null, true])
		elif provider != null:
			for value: float in req.turns:
				var turn := int(value)
				if (turn > 0) == (clip == "PIVOT_RIGHT"): variants.append([turn, true])
		for variant: Array in variants:
			var previous := -1.0
			for t: float in times:
				if t == previous: continue
				previous = t
				player.stop(true)
				sk.reset_bone_poses()
				var request := {"clip":clip,"time_s":t,"phase":t / anim.length,"turn_udeg":variant[0]}
				if variant[1]:
					provider.pose(player, sk, request)
				else:
					player.play(name, 0.0)
					player.seek(t, true)
				sk.force_update_all_bone_transforms()
				var g := PackedFloat64Array()
				for bone: int in sk.get_bone_count(): g.append_array(rows(sk.get_bone_global_pose(bone)))
				data.samples.append({"clip":clip,"time_s":t,"phase":t / anim.length,
					"turn_udeg":variant[0],
					"provider":variant[1],"globals_f64":Marshalls.raw_to_base64(g.to_byte_array())})
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("LOCO_CERT_CAPTURE ", data.samples.size(), " samples")
	quit(0)
'''


def closure(paths):
    """res:// dependency closure of the scene (and provider), with .import sidecars."""
    seen, todo = set(), list(paths)
    while todo:
        rel = todo.pop()
        if rel in seen or rel.startswith('.godot/'):
            continue
        source = ROOT / rel
        if not source.is_file():
            raise FileNotFoundError(rel)
        seen.add(rel)
        sidecar = rel + '.import'
        if (ROOT / sidecar).is_file():
            todo.append(sidecar)
        if source.suffix in ('.tscn', '.tres', '.import', '.gd'):
            todo += re.findall(r'res://([^"\s)]+)', source.read_text(errors='replace'))
    return sorted(seen)


def wait_for_godot(poll=15):
    """Never overlap a GUT run or another certifier's Godot."""
    while True:
        out = subprocess.run(['pgrep', '-fl', 'Godot'], capture_output=True, text=True).stdout
        busy = [line for line in out.splitlines() if 'gut_cmdln' in line or 'loco-cert' in line]
        if not busy:
            return
        print('waiting for', busy[0][:120], file=sys.stderr)
        time.sleep(poll)


def capture(config, godot, work, extra):
    project = work / 'project'
    if project.exists():
        shutil.rmtree(project)
    files = closure([config['scene']] + ([config['provider']] if config.get('provider') else []))
    inputs = {}
    for rel in files:
        (project / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, project / rel)
        inputs[rel] = sha(ROOT / rel)
    (project / 'project.godot').write_text(
        'config_version=5\n[application]\nconfig/name="loco-cert numeric extraction"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (project / 'capture.gd').write_text(CAPTURE)
    request = {'scene': 'res://' + config['scene'], 'clips': CLIPS, 'uniform': UNIFORM,
               'extra_phases': sorted(set(extra)), 'turns': [g['turn_udeg'] for g in turn_grid()],
               'provider': 'res://' + config['provider'] if config.get('provider') else ''}
    (work / 'request.json').write_text(json.dumps(request))
    dump = work / 'native.json'
    timeout = [sys.executable, str(ROOT / 'tools/run_with_timeout.py'), str(config.get('timeout_s', 1800))]
    # Numeric resource extraction only: nothing is rendered, so --headless is safe.
    for index, cmd in enumerate([[godot, '--headless', '--path', str(project), '--import'],
                                 [godot, '--headless', '--path', str(project), '--script',
                                  str(project / 'capture.gd'), '--', str(work / 'request.json'), str(dump)]]):
        wait_for_godot()
        log = work / f'capture-{index}.log'
        with log.open('w') as stream:
            code = subprocess.call(timeout + cmd, stdout=stream, stderr=subprocess.STDOUT)
        if code or re.search(r'SCRIPT ERROR|Parse Error|^ERROR:', log.read_text(), re.M):
            raise RuntimeError(f'Godot stage {index} failed (exit {code}): {log}')
    if any(sha(ROOT / rel) != digest for rel, digest in inputs.items()):
        raise RuntimeError('a capture input changed during the run')
    return json.loads(dump.read_text()), inputs, sha(dump)


def balance(path, key):
    with (ROOT / path).open() as stream:
        for row in csv.reader(stream):
            if row and row[0] == key:
                return float(row[1])
    raise KeyError(key)


def arm_scale(arm):
    m = json.loads((ROOT / 'docs/reviews/cluster-formations/evidence/cf01/measurements.json').read_text())
    s = m['models'][arm]['scale_inputs']
    lift = balance('data/screens/map3d/balance.csv', 'map3d_unit_seat_clear') * s['model_height'] \
        - balance('data/screens/map3d/balance.csv', 'map3d_unit_sink_m') / s['world_scale']
    return {'k': s['world_scale'], 'simulation_scale': s['simulation_scale'],
            'model_height_m': s['model_height'], 'lift_model_m': lift}


def footprint_radius(arm):
    with (ROOT / 'data/army/unit_footprints.csv').open() as stream:
        return int(next(r for r in csv.DictReader(stream) if r['arm'] == arm)['radius_m'])


def certificate(config, report, scale, inputs, capture_sha, dump):
    body = {'schema': 1, 'arm': config['arm'], 'status': 'NUMERIC_PASS' if report['pass'] else 'FAIL',
            'ruling': 'docs/reviews/cluster-formations/owner-rulings-2026-11-10.md R-A R-B R-C',
            'tool_sha256': sha(Path(__file__)), 'config': config, 'scale': scale,
            'input_sha256': inputs, 'capture': {'sha256': capture_sha, 'godot': dump['godot'],
                                                'clips': dump['clips'], 'uniform': UNIFORM},
            'report': report, 'visual_review': 'PENDING: R-C requires the real-window review after this numeric pass'}
    digest = hashlib.sha256(canonical(body)).hexdigest()
    body['payload_sha256'] = digest
    body['digest_rule'] = 'sha256 of canonical JSON (sorted keys, no spaces) of every field except payload_sha256, digest_rule and locomotion_certificate'
    body['locomotion_certificate'] = {'digest': digest, 'turn_q': int(config['turn_q']),
                                      'contact_um': report['bounds_um']['contact'], 'radius_m': int(config['radius_m']),
                                      'clips': CLIPS, 'all_turns': True} if report['pass'] else None
    return body


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--work', type=Path, help='scratch folder (default .superpowers/loco-cert/<arm>)')
    args = parser.parse_args(argv)
    config = json.loads(args.config.read_text())
    for key in ('arm', 'scene', 'feet', 'forward', 'stride_m', 'stance', 'boundaries', 'turn_q'):
        if key not in config:
            raise SystemExit(f'config is missing {key}')
    config.setdefault('radius_m', footprint_radius(config['arm']))
    work = args.work or ROOT / '.superpowers/loco-cert' / config['arm']
    work.mkdir(parents=True, exist_ok=True)
    extra = [config.get('entry_phase', 0.0)] + [p for b in config['boundaries'] for p in (b[1], b[3]) if p != '*']
    dump, inputs, capture_sha = capture(config, args.godot, work, extra)
    missing = check_coverage(dump, extra)
    if missing:
        raise SystemExit(f'sampling gap: {missing[:3]}')
    for rel in ('docs/reviews/cluster-formations/evidence/cf01/measurements.json', 'data/screens/map3d/balance.csv',
                'data/army/unit_footprints.csv', 'data/army/balance.csv'):
        inputs[rel] = sha(ROOT / rel)
    scale = arm_scale(config['arm'])
    cert = certificate(config, measure(dump, config, scale), scale, inputs, capture_sha, dump)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(cert, indent=1, sort_keys=True, allow_nan=False) + '\n')
    r = cert['report']
    print(cert['status'], {q: r[q].get('total_um', r[q].get('radius_simulation_m')) for q in
                           ('penetration', 'hover', 'slide', 'seam', 'envelope')}, 'skin introduced',
          r['skin']['flagged_pairs_introduced'], 'bounds', r['bounds_um'])
    return 0 if r['pass'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, FileNotFoundError, KeyError) as error:
        print('ERROR:', error, file=sys.stderr)
        sys.exit(2)
