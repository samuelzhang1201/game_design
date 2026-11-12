"""Per-arm locomotion certifier (owner rulings R-A, R-B, R-C, 2026-11-10).

Samples MARCH, PIVOT_LEFT and PIVOT_RIGHT densely in Godot (every key, the
quarter points between keys, a uniform grid and every boundary phase), skins
every equipped mesh with the native imported arrays and bone poses, and checks:

  1. penetration  any vertex below the rendered ground, every sample;
  2. hover        the planted material patch above the seated plane, stance only;
  3. slide        per foot vertex: while it lies within its foot's planting band b of
                  the seated plane it is planted, and its slide is its ground-
                  projected displacement from where it touched down (ruling
                  2026-11-11: the planted part of the sole; heel-to-toe roll is not
                  slide, skating is). Per foot, b = max(0.5 mm, H + 0.5 mm), H
                  inherited from the shipped native MARCH (`planting_band`); a
                  vertex belongs to the foot whose bone carries its largest skin
                  weight; a stance is where a foot's lowest vertex is within its b,
                  and hover is read there;
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

The seams are R-A row 4's whole list, built by the tool (`required_boundaries`):
the loop seam (its last pose sampled just before the wrap), MARCH -> pivot,
pivot -> MARCH, stop and start to the `hold_clip`, and the stationary pivot
from and to it, at the phases the config admits (`march_stop_phases`,
`march_start_phases`, `hold_phases`: a list, or '*' for any sampled phase,
i.e. a mid-stance cut). `hold_clip` "MARCH" holds the MARCH pose a unit stopped
in (owner ruling 2026-11-10: stop, start and hold only at the MARCH phases where
the pivots enter and leave MARCH); the certificate records these phases as
`consumer_requirements`. Every foot must stand at least once in every
locomotion clip, or hover and slide go unmeasured and the run fails. Hover is
the patch's LOWEST vertex above the seated plane. The ground is flat at the
seat lift below the origin unless `slope` (rise per run, applied at every yaw)
is set. MARCH carries the piece forward by the arm's army_art.csv `phase_map` when it
has one (the game's Map3DMarchPhase), else by `stride_m` per loop.

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
STANCE_BAND_M = 0.0005  # the planting band's floor and its allowance over native MARCH (ruling 2026-11-11)
TURN = 360_000_000
LOCO_Q = 1_000_000  # BodyMotion.LOCOMOTION_Q
UNIFORM = 512
LOOP_END = 1 - 1e-6  # last pose of a looping clip: seek(length) would wrap to phase 0


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
                if not len(tri):
                    raise ValueError(f"{mesh['name']} surface {index} has no index array: no edges for R-B")
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


def dominant_bones(joints, weights, binds):
    """Per vertex, the skeleton bone carrying its largest skin weight, summed over
    the slots that name the same bone; a tie goes to the lower bone index; a
    vertex with no weight at all has no bone (-1)."""
    bones = np.array([bone for bone, _ in binds])[joints]
    total = (weights[:, None, :] * (bones[:, None, :] == bones[:, :, None])).sum(axis=2)
    top = total.max(axis=1, keepdims=True)
    best = np.where(total == top, bones, np.iinfo(np.int64).max).min(axis=1)
    return np.where(top[:, 0] > 0, best, -1)


def patches(model, feet):
    """Ruling 2026-11-11: a vertex belongs to the foot whose bone carries its
    largest skin weight (ties to the lower bone index); vertices of no foot are
    never planted (penetration still covers the whole mesh)."""
    names = [b['name'] for b in model.dump['bones']]
    listed = [b for bones in feet.values() for b in bones]
    if len(listed) != len(set(listed)):
        raise ValueError('a bone is listed under two feet')
    dominant = np.concatenate([dominant_bones(m['j'], m['w'], m['binds']) for m in model.meshes])
    out = {}
    for foot, bones in feet.items():
        ids = np.flatnonzero(np.isin(dominant, [names.index(b) for b in bones]))
        if not len(ids):
            raise ValueError('no vertex belongs to foot ' + foot)
        out[foot] = ids
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
    """Index runs where `foot` stands: rule ('lowest', N) = among the N lowest
    feet at that sample; ('band', b) = its lowest sole vertex within b of the
    seated plane. A run crossing a looping clip's seam is ONE stance."""
    kind, value = rule
    if kind == 'lowest':
        names = sorted(heights)
        order = np.argsort(np.array([heights[f] for f in names]), axis=0, kind='stable')
        down = (order[:value] == names.index(foot)).any(axis=0)
    else:
        down = np.array(heights[foot]) <= value
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
        runs[0] = runs.pop() + runs[0]
    return [r for r in runs if r]


def planting_band(heights, phases, loop):
    """Ruling 2026-11-11, inherited from the shipped native MARCH, PER FOOT: a
    foot's stances there are its maximal runs among the lower half of the feet;
    H_f is the highest of that foot's stance minimum sole heights above the seated
    plane and its band is max(STANCE_BAND_M, H_f + STANCE_BAND_M).
    Returns {foot: (H_f, b_f)}."""
    n = max(1, len(heights) // 2)
    out = {}
    for f in sorted(heights):
        lows = [min(heights[f][i] for i in run) for run in stance_runs(heights, phases, ('lowest', n), f, loop)]
        if not lows:
            raise ValueError(f'native MARCH has no stance of foot {f} to derive its planting band from')
        high = float(max(lows))
        out[f] = (high, max(STANCE_BAND_M, high + STANCE_BAND_M))
    return out


def vertex_slide(heights, xz, band):
    """heights (N, V) above the seated plane and world xz (N, V, 2), in time order.
    Each vertex is planted while its height <= band, anchored where it entered the
    band; returns (worst displacement from its anchor, margin, (sample, vertex,
    touchdown sample)). The margin is TWICE the largest one-step move of a vertex
    planted at either end of a step: a vertex entering between samples is
    anchored up to one step late and one leaving is measured up to one step early,
    and one slide can lose both."""
    anchor = np.zeros(xz.shape[1:])
    touch = np.full(heights.shape[1], -1)
    before = np.zeros(heights.shape[1], dtype=bool)
    value, margin, witness = 0.0, 0.0, None
    for i in range(len(heights)):
        planted = heights[i] <= band
        new = planted & ~before
        anchor[new], touch[new] = xz[i][new], i
        if planted.any():
            d = np.where(planted, np.linalg.norm(xz[i] - anchor, axis=1), -1.0)
            v = int(np.argmax(d))
            if witness is None or d[v] > value:
                value, witness = float(d[v]), (i, v, int(touch[v]))
        either = planted | before
        if i and either.any():
            margin = max(margin, float(np.linalg.norm(xz[i] - xz[i - 1], axis=1)[either].max()))
        before = planted
    return value, 2 * margin, witness


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


def phase_list(value, key):
    if value == '*':
        return '*'
    if not isinstance(value, list) or not value or not all(isinstance(p, (int, float)) and 0 <= p <= 1 for p in value):
        raise ValueError(f'{key} must be "*" or a non-empty list of phases')
    return [float(p) for p in value]


def required_boundaries(config):
    """R-A row 4's boundaries, built here so a config cannot leave one out: the
    loop seam, MARCH -> pivot (stop) and pivot -> MARCH (start), stop/start to
    the hold clip, and the stationary pivot from and to it. The config declares
    the phases its consumer admits ('*' = any sampled phase, i.e. mid-stance cuts);
    `boundaries` may only add more."""
    hold = config['hold_clip']
    stop = phase_list(config['march_stop_phases'], 'march_stop_phases')
    start = phase_list(config['march_start_phases'], 'march_start_phases')
    held = phase_list(config['hold_phases'], 'hold_phases')
    side = lambda v: ['*'] if v == '*' else v
    out = [['MARCH', LOOP_END, 'MARCH', 0.0]]
    for pivot in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
        out += [['MARCH', p, pivot, 0.0] for p in side(stop)] + [[pivot, 1.0, 'MARCH', p] for p in side(start)]
    if hold == 'MARCH':
        # The held pose IS the MARCH pose it stopped in (a stop phase) or the pivot
        # ended in (a start phase, whose PIVOT(1) -> MARCH(h) seam is above). A hold
        # is left by resuming at h (no seam) or by turning: MARCH(h) -> PIVOT(0).
        if held == '*' or not set(held) <= set(side(stop)) | set(side(start)):
            raise ValueError('a MARCH hold keeps a pose it stopped or turned into: hold_phases must be '
                             'admitted stop or start phases')
        for pivot in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
            out += [b for b in (['MARCH', h, pivot, 0.0] for h in held) if b not in out]
        return out + [b for b in config.get('boundaries', []) if b not in out]
    if held == '*' and '*' in (stop, start):
        raise ValueError('hold_phases and a MARCH phase list cannot both be "*" (declare one side)')
    for pivot in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
        out += [[hold, h, pivot, 0.0] for h in side(held)] + [[pivot, 1.0, hold, h] for h in side(held)]
    out += [['MARCH', p, hold, h] for p in side(stop) for h in side(held)]
    out += [[hold, h, 'MARCH', b] for h in side(held) for b in side(start)]
    return out + [b for b in config.get('boundaries', []) if b not in out]


def measure(dump, config, scale):
    """Pure measurement of a decoded capture against R-A / R-B. `scale` =
    {k, simulation_scale, lift_model_m}."""
    model = Model(dump)
    bounds = bounds_um(scale['k'])
    feet = patches(model, config['feet'])
    forward = np.array(config['forward'], dtype=float)
    stride = float(config['stride_m'])
    slope = float(config.get('slope', 0.0))
    ground = -float(scale['lift_model_m'])
    by = streams(model.samples)
    provider = bool(config.get('provider'))
    grid = turn_grid()
    boundaries = required_boundaries(config)

    def prov_of(clip):  # a provider poses the locomotion clips, MARCH (and so a MARCH hold) included;
        # a separate hold clip is native
        return provider and clip in CLIPS

    if provider:
        for g in grid:
            if not by.get((clip_for(g['turn_udeg']), g['turn_udeg'], True)):
                raise ValueError(f"no provider stream for turn {g['turn_udeg']}")
    pen, hov, sld, env = Worst(), Worst(), Worst(), Worst()
    # The planting band, from the native MARCH stream (never a provider's).
    native = by[('MARCH', None, False)]
    native_heights = {f: [] for f in feet}
    for s in native:
        p = model.points(s['_g'])
        for f, ids in feet.items():
            native_heights[f].append(float(p[ids, 1].min()))
    bands = planting_band(native_heights, [s['phase'] for s in native],
                          dump['clips']['MARCH']['loop_mode'] != 0)
    band_v = np.full(model.offsets[-1], -np.inf)  # a vertex of no foot is never planted
    for f, ids in feet.items():
        band_v[ids] = bands[f][1]
    slide_by_clip = {}
    missing = []  # a foot with no stance in a locomotion clip leaves hover and slide unmeasured

    travel = march_travel(config.get('phase_map'), stride)

    def world(clip, phase, points, turn, cycle=0):
        if clip == 'MARCH':
            return points + forward * travel(phase + cycle)
        return rot_y(points, -math.radians(turn / 1e6) * phase)

    def stream(clip, turn, prov=None):
        prov = prov_of(clip) if prov is None else prov
        return by.get((clip, turn if prov and clip != 'MARCH' else None, prov), [])

    def at(clip, phase, turn, prov=None):
        for s in stream(clip, turn, prov):
            if abs(s['phase'] - phase) <= 1e-12:
                return s
        raise ValueError(f'phase {phase} of {clip} was not sampled')

    # Penetration and envelope (every sample), hover and slide (stance), with margins.
    for (clip, turn, prov), rows in by.items():
        if prov != prov_of(clip):
            continue  # native twin of a provider stream: skin diagnostic only
        loop = clip == 'MARCH' and dump['clips']['MARCH']['loop_mode'] != 0
        phases = [s['phase'] for s in rows]
        heights = {f: [] for f in feet}
        patch_y = {f: [] for f in feet}
        reach = np.zeros(model.offsets[-1], dtype=bool)
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
                patch_y[f].append(p[ids, 1])
            reach |= p[:, 1] <= band_v
        if clip not in CLIPS:
            continue  # the hold clip: penetration and envelope only
        turns = [turn] if clip == 'MARCH' or turn is not None else \
            [g['turn_udeg'] for g in grid if clip_for(g['turn_udeg']) == clip]
        for f in feet:
            runs = stance_runs(heights, phases, ('band', bands[f][1]), f, loop)
            if not runs:
                missing.append({'clip': clip, 'turn_udeg': turn, 'foot': f, 'reason': 'no stance'})
            for run in runs:
                for k, i in enumerate(run):
                    hov.offer(heights[f][i], {'clip': clip, 'foot': f, 'phase': phases[i], 'turn_udeg': turn})
                    if k:
                        hov.widen(np.abs(patch_y[f][i] - patch_y[f][run[k - 1]]).max())
        # Slide, per foot vertex that reaches its foot's band:
        # skin again keeping only those. Heights are yaw-invariant. A looping MARCH
        # runs twice so a stance can cross the seam.
        ids = np.flatnonzero(reach)
        pts = np.array([model.points(s['_g'])[ids] for s in rows]) if len(ids) else np.zeros((len(rows), 0, 3))
        per_clip = slide_by_clip.setdefault(clip, Worst())
        frames = [(i, c) for c in range(2 if loop else 1) for i in range(len(rows))]
        for t in turns:
            w = np.array([world(clip, phases[i], pts[i], t, c)[:, [0, 2]] for i, c in frames])
            value, margin, hit = vertex_slide(pts[[i for i, _ in frames], :, 1], w, band_v[ids]) if pts.shape[1] \
                else (0.0, 0.0, None)
            if hit is not None:
                for worst in (sld, per_clip):
                    worst.offer(value, {'clip': clip, 'turn_udeg': t, 'touchdown_phase': phases[frames[hit[2]][0]],
                                        'phase': phases[frames[hit[0]][0]], **model.where(int(ids[hit[1]]))})
            sld.widen(margin)
            per_clip.widen(margin)

    # Seams: both one-sided values at every boundary, compared in the receiving
    # clip's model frame (the consumer's yaw and position are continuous there).
    # A '*' side sweeps every sample of that clip, with that side's chord as margin.
    seams, seam_worst = [], None
    for a_clip, a_ph, b_clip, b_ph in boundaries:
        if a_ph == '*' and b_ph == '*':
            raise ValueError('a boundary may sweep one side only')
        pivot = next((c for c in (a_clip, b_clip) if c in ('PIVOT_LEFT', 'PIVOT_RIGHT')), None)
        turns = [g['turn_udeg'] for g in grid if clip_for(g['turn_udeg']) == pivot] if provider and pivot else [None]
        for t in turns:
            star, fixed_clip, fixed_ph = (a_clip, b_clip, b_ph) if a_ph == '*' else (b_clip, a_clip, a_ph)
            fixed = model.points(at(fixed_clip, fixed_ph, t)['_g'])
            swept = stream(star, t) if '*' in (a_ph, b_ph) else [at(b_clip, b_ph, t)]
            if not swept:
                raise ValueError(f'no samples of {star} for a seam sweep')
            best, prev = Worst(), None
            for s in swept:
                moving = model.points(s['_g'])
                d = np.linalg.norm(moving - fixed, axis=1)
                i = int(np.argmax(d))
                best.offer(d[i], {'from': [a_clip, s['phase'] if a_ph == '*' else a_ph],
                                  'to': [b_clip, s['phase'] if b_ph == '*' else b_ph], 'turn_udeg': t,
                                  **model.where(i)})
                if '*' in (a_ph, b_ph) and prev is not None:
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
        if bool(s.get('provider')) != prov_of(s['clip']):
            continue
        base = natives[(s['clip'], s['phase'])]
        own = flags(s) if s.get('provider') else base
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
        'planting_band': {'feet': {f: {'H_m': h, 'band_m': b} for f, (h, b) in bands.items()},
                          'inherited_from': 'shipped native MARCH',
                          'rule': 'per foot: b_f = max(0.5 mm, H_f + 0.5 mm); H_f = highest of the foot\'s per-stance '
                                  'minimum sole heights, stances = runs among the lower half of the feet; a vertex '
                                  'belongs to the foot whose bone carries its largest skin weight (ties: lower bone index); '
                                  'vertices of no foot are never planted'},
        'slide': {**sld.report(bounds['contact']), 'band_m': {f: b for f, (_, b) in bands.items()},
                  'by_clip': {c: w.report(bounds['contact']) for c, w in sorted(slide_by_clip.items())}},
        # No boundary configured is a failure: every arm has at least its loop seam.
        'seam': {**(seam_worst or Worst().report(bounds['seam'])), 'pass': bool(seams) and all(s['pass'] for s in seams),
                 'boundaries': seams},
        'envelope': {'radius_model_um': um(env.value), 'margin_um': um(env.margin),
                     'radius_simulation_m': radius_sim, 'footprint_radius_m': int(config['radius_m']),
                     'pass': radius_sim <= int(config['radius_m']), 'witness': env.witness},
        'skin': {'flagged_pairs_inherited': inherited, 'flagged_pairs_introduced': introduced,
                 'pass': introduced == 0, 'introduced_witnesses': witnesses,
                 'rule': 'length > 4 x native-entry AND > 0.03 model m; fails unless the native seek at the same phase is flagged'},
        'stance': {'pass': not missing, 'missing': missing},
        'patches': {f: {'vertices': int(len(ids)), 'first': [model.where(int(i)) for i in ids[:4]]}
                    for f, ids in feet.items()},
        'turn_grid': [{**g, 'clip': clip_for(g['turn_udeg']), 'duration_q': duration_q(g['turn_udeg'], config['turn_q'])}
                      for g in grid],
        'sample_count': len(model.samples),
    }
    report['pass'] = all(report[q]['pass'] for q in ('penetration', 'hover', 'slide', 'seam', 'envelope', 'skin', 'stance')) \
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
		elif provider != null and clip.begins_with("PIVOT_"):
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
            # A path ending a comment's sentence carries its full stop; resource names never end in one.
            todo += [p.rstrip('.,;:') for p in re.findall(r'res://([^"\s)]+)', source.read_text(errors='replace'))]
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
    request = {'scene': 'res://' + config['scene'], 'clips': CLIPS + [c for c in [config['hold_clip']] if c not in CLIPS], 'uniform': UNIFORM,
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


def march_travel(phase_map, stride):
    """Model metres a MARCH has carried the piece at unwrapped phase z: the arm's
    army_art.csv `phase_map` (Map3DMarchPhase: F(z) = floor(z) S + f(frac z), f piecewise
    linear through [[phase, metres], ...] from (0, 0) to (1, S)) when it has one, else the
    constant stride (z x stride_m)."""
    if not phase_map:
        return lambda z: stride * z
    ph = np.array([float(p) for p, _ in phase_map])
    d = np.array([float(m) for _, m in phase_map])
    if ph[0] != 0 or d[0] != 0 or ph[-1] != 1 or np.any(np.diff(ph) <= 0) or np.any(np.diff(d) <= 0):
        raise ValueError('phase_map must rise strictly from (0, 0) to phase 1')
    return lambda z: math.floor(z) * d[-1] + float(np.interp(z - math.floor(z), ph, d))


def army_phase_map(arm):
    """The arm's army_art.csv `phase_map` as [[phase, metres], ...], or None."""
    with (ROOT / 'data/screens/map3d/army_art.csv').open() as stream:
        row = next((r for r in csv.DictReader(stream) if r['piece'] == arm), {})
    text = (row.get('phase_map') or '').strip()
    return [[float(a), float(b)] for a, b in (pair.split(':') for pair in text.split(';'))] if text else None


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
            'report': report,
            'consumer_requirements': {**{k: config[k] for k in ('hold_clip', 'march_stop_phases',
                                                               'march_start_phases', 'hold_phases')},
                                      'rule': 'stop, start and hold only at these MARCH phases; a MARCH hold '
                                              'resumes at the phase it holds'},
            'visual_review': 'PENDING: R-C requires the real-window review after this numeric pass'}
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
    for key in ('arm', 'scene', 'feet', 'forward', 'stride_m', 'turn_q', 'hold_clip',
                'march_stop_phases', 'march_start_phases', 'hold_phases'):
        if key not in config:
            raise SystemExit(f'config is missing {key}')
    # The MARCH travel the game plays (Map3DMarchPhase), bound into the certificate.
    # The certifier refuses a malformed map (the game would silently fall back to stride_m), before
    # any Godot run.
    csv_map = army_phase_map(config['arm'])
    if config.setdefault('phase_map', csv_map) != csv_map:
        raise SystemExit("config phase_map is not army_art.csv's")
    march_travel(csv_map, float(config['stride_m']))
    radius = footprint_radius(config['arm'])
    if config.setdefault('radius_m', radius) != radius:
        raise SystemExit(f"config radius_m {config['radius_m']} is not unit_footprints.csv's {radius}")
    # absolute: Godot reads --script relative to the isolated project, not to this cwd
    work = (args.work or ROOT / '.superpowers/loco-cert' / config['arm']).resolve()
    work.mkdir(parents=True, exist_ok=True)
    extra = [config.get('entry_phase', 0.0)] + [p for b in required_boundaries(config) for p in (b[1], b[3]) if p != '*']
    dump, inputs, capture_sha = capture(config, args.godot, work, extra)
    missing = check_coverage(dump, extra)
    if missing:
        raise SystemExit(f'sampling gap: {missing[:3]}')
    for rel in ('docs/reviews/cluster-formations/evidence/cf01/measurements.json', 'data/screens/map3d/balance.csv',
                'data/screens/map3d/army_art.csv',
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
