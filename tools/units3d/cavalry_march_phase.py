"""Offline native-pose distance fit; UNKNOWN never enables a runtime consumer.

Reuses the accepted native audit, never the unmerged CERT implementation. Exact
rational atlas/constraint proofs and continuous platform arithmetic are separate
from physical E and from missing terrain/support context. No Godot is launched.
"""
import argparse
import ast
import csv
from bisect import bisect_right
from dataclasses import dataclass
from fractions import Fraction as Q
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess

import numpy as np

import check_cavalry_march_capture as native
import reacquire_cavalry_march_native as reacquired
from royal_native_arithmetic import prove as scalar

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT/'docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-native-contact.json'
MANIFEST_SHA = '37266c5097ee2f5b80dbdc35e41c4d4a612bc06f6715bfd26b31601143792843'
REVIEW_SHA = '408a3c381c1d1516eece628f8bb8d84bd0d761eecc885b1037121690a0407dc7'
VERDICT_SHA = 'e1e879d30471c1dcd4f53b3b369b6810664da1cc3fd1ea104fb00c395b32cab2'
# Computation limits, not design values, a physical tolerance, or project timeouts.
LIMITS = {'fit_trials': 24, 'fit_upper_expansions': 8, 'max_knots': 256,
          'max_constraints': 250000, 'refinement_splits': 32, 'continuous_boxes': 256,
          'float32_weight_values_total': 16384, 'float32_dot_values_per_track': 256,
          'proposal_evaluations': 1024, 'dense_native_capture_rows': 154,
          'rational_sqrt_denominator': 10**12,
          'strict_slope_floor_model_m_per_phase': [1, 10**9]}
GRID = LIMITS['rational_sqrt_denominator']


def require(condition, message):
    native.require(condition, message)


def rational(value):
    if type(value) in (np.float32, np.float64, np.int64):
        value = value.item()
    require(type(value) in (int, float, Q) and (not isinstance(value, float) or math.isfinite(value)),
            'Nonfinite/malformed rational input')
    return Q(value)


def make_atlas(phases, distances, digest, seconds):
    result = {'version': 1, 'input_sha256': digest, 'clip_seconds': seconds,
              'knots': [{'phase_num': p.numerator, 'phase_den': p.denominator,
                         'distance_num': d.numerator, 'distance_den': d.denominator}
                        for p, d in zip(map(rational, phases), map(rational, distances))]}
    require(len(phases) == len(distances), 'Atlas cardinality')
    validate_atlas(result)
    return result


def validate_atlas(atlas):
    require(type(atlas) is dict and set(atlas) == {'version', 'input_sha256', 'clip_seconds', 'knots'}, 'Atlas schema')
    require(type(atlas['version']) is int and atlas['version'] == 1, 'Atlas version')
    require(type(atlas['input_sha256']) is str and re.fullmatch('[0-9a-f]{64}', atlas['input_sha256']), 'Atlas digest')
    require(type(atlas['clip_seconds']) in (int, float) and math.isfinite(atlas['clip_seconds'])
            and atlas['clip_seconds'] > 0, 'Clip length')
    require(type(atlas['knots']) is list and 2 <= len(atlas['knots']) <= LIMITS['max_knots'], 'Knot count')
    phases, distances = [], []
    for k in atlas['knots']:
        require(type(k) is dict and set(k) == {'phase_num', 'phase_den', 'distance_num', 'distance_den'}, 'Knot schema')
        require(all(type(v) is int and abs(v) < 2**53 for v in k.values()), 'Inexact JSON integer')
        require(k['phase_den'] > 0 and k['distance_den'] > 0, 'Nonpositive denominator')
        require(math.gcd(k['phase_num'], k['phase_den']) == math.gcd(k['distance_num'], k['distance_den']) == 1,
                'Unreduced rational')
        phases.append(Q(k['phase_num'], k['phase_den']))
        distances.append(Q(k['distance_num'], k['distance_den']))
    require(phases[0] == distances[0] == 0 and phases[-1] == 1, 'Atlas endpoints')
    require(all(a < b for a, b in zip(phases, phases[1:]))
            and all(a < b for a, b in zip(distances, distances[1:])), 'Nonpositive slope')
    return phases, distances


def distance_at(atlas, z):
    phases, distances = validate_atlas(atlas)
    z = rational(z); cycle = z//1; p = z-cycle
    i = bisect_right(phases, p)-1
    return cycle*distances[-1]+distances[i]+(p-phases[i])*(distances[i+1]-distances[i])/(phases[i+1]-phases[i])


def sample(atlas, cycle, phase, distance):
    phases, distances = validate_atlas(atlas)
    phase, distance = rational(phase), rational(distance)
    require(type(cycle) is int and 0 <= cycle < 2**63 and 0 <= phase < 1 and distance >= 0, 'Sample domain')
    target = distance_at(atlas, phase)+distance
    loops = target//distances[-1]; residual = target-loops*distances[-1]
    require(cycle+loops < 2**63, 'Cycle overflow')
    i = bisect_right(distances, residual)-1
    derivative = (phases[i+1]-phases[i])/(distances[i+1]-distances[i])
    return cycle+loops, phases[i]+(residual-distances[i])*derivative, derivative


def compatible(atlas, entry, exit_, distance):
    entry, exit_, distance = map(rational, (entry, exit_, distance))
    require(exit_ >= entry and distance >= 0, 'Endpoint tuple domain')
    return distance_at(atlas, exit_)-distance_at(atlas, entry) == distance


def sqrt_bounds(value, denominator=GRID):
    value = rational(value)
    require(value >= 0, 'Negative square root')
    n = math.isqrt(value.numerator*denominator**2//value.denominator)
    lo = Q(n, denominator)
    return lo, lo if lo*lo == value else Q(n+1, denominator)


def endpoint_floor(delta):
    x, y, z = map(rational, delta)
    # Translation is along +Z and nonnegative. An adverse positive Z cannot be undone.
    horizontal = sqrt_bounds(x*x+max(Q(0), z)**2)
    spatial = sqrt_bounds(x*x+y*y+max(Q(0), z)**2)
    return {'entry_drift_xz': horizontal, 'free_anchor_xz': tuple(v/2 for v in horizontal),
            'entry_drift_xyz': spatial}


def allowed_distance(error, xlo, xhi, zlo, zhi, *, inner):
    """Integer-grid disk: robust inner satisfaction vs existential outer relaxation."""
    require(all(type(v) is int for v in (error, xlo, xhi, zlo, zhi))
            and error >= 0 and xlo <= xhi and zlo <= zhi, 'Constraint domain')
    lateral = max(abs(xlo), abs(xhi)) if inner else (0 if xlo <= 0 <= xhi else min(abs(xlo), abs(xhi)))
    square = error*error-lateral*lateral
    if square < 0:
        return None
    radius = math.isqrt(square)
    if not inner and radius*radius != square:
        radius += 1
    return (-radius-zlo, radius-zhi) if inner else (-radius-zhi, radius-zlo)


def feasible(count, rows, error, increments, *, inner):
    """Exact integer difference constraints; None only proves the specified system infeasible."""
    require(count >= 2 and len(increments) == count-1 and all(v > 0 for v in increments), 'Monotonic increments')
    edges = [(i+1, i, -v) for i, v in enumerate(increments)]
    grouped = {}
    for i, j, xlo, xhi, zlo, zhi in rows:
        require(0 <= i < j < count, 'Constraint knot index')
        interval = allowed_distance(error, xlo, xhi, zlo, zhi, inner=inner)
        if interval is None or interval[0] > interval[1]:
            return None
        lo, hi = grouped.get((i, j), interval)
        lo, hi = max(lo, interval[0]), min(hi, interval[1])
        if lo > hi:
            return None
        grouped[i, j] = lo, hi
    for (i, j), (lo, hi) in sorted(grouped.items()):
        edges.extend([(i, j, hi), (j, i, -lo)])
    values = [0]*count
    for _ in range(count):
        changed = False
        for i, j, upper in edges:
            if values[j] > values[i]+upper:
                values[j] = values[i]+upper; changed = True
        if not changed:
            return [v-values[0] for v in values]
    return None


def exact_vertex(vertex, joints, weights, globals_, binds):
    """Exact real LBS of the captured binary inputs, retaining every raw influence."""
    p = list(map(rational, vertex))+[Q(1)]
    answer = [Q(0)]*3
    for joint, weight in zip(joints, weights):
        require(type(joint) in (int, np.int64) and 0 <= joint < len(globals_), 'Skin joint')
        w = rational(weight)
        require(w >= 0, 'Negative weight')
        if not w:
            continue
        bind = [[rational(v) for v in row] for row in binds[joint]]
        g = [[rational(v) for v in row] for row in globals_[joint]]
        bound = [sum(row[k]*p[k] for k in range(4)) for row in bind]
        for c in range(3):
            answer[c] += w*sum(g[c][k]*bound[k] for k in range(4))
    return answer


class Unclosed(ValueError):
    def __init__(self, reason, **detail):
        super().__init__(reason)
        self.detail = {'reason': reason, **detail}


@dataclass
class Budget:
    weight_values: int = LIMITS['float32_weight_values_total']
    used: int = 0
    planning: bool = False
    arithmetic: object = None


BASELINE_SHA = '2d7ebd7ba5c2c6e3127c9f94fb2b1c5b775c76b6b3eb95a8568bc376d7648e67'
ARITHMETIC_VERIFIER_SHA = '37f34e84334c12ed9194539d4e16505e461927ad17fd84553931f2e60ff9dc4f'


def rounded_interval(lo, hi, bits):
    # The accepted basic-operation bound includes every IEEE direction and FTZ.
    error = scalar.rnd(max(abs(lo), abs(hi)), bits)
    return lo-error, hi+error


def interval_product(a, b, bits):
    values = [x*y for x in a for y in b]
    return rounded_interval(min(values), max(values), bits)


def interval_quotient(a, b, bits):
    if b[0] <= 0 <= b[1]:
        raise Unclosed('slerp_denominator_contains_zero', denominator=json_value(b))
    values = [x/y for x in a for y in b]
    return rounded_interval(min(values), max(values), bits)


def float_box(interval):
    # One extra directed binary32 step dominates the rational->binary64 rounding.
    return native.Float32Box.outward(float(interval[0]), float(interval[1]))


def box_interval(box):
    return rational(box.lo.item()), rational(box.hi.item())


@lru_cache(maxsize=8192)
def taylor_endpoint(x, sine):
    # |x|<=1/2: Lagrange remainder, with exact rational coefficients/operations.
    require(abs(x) <= Q(1, 2), 'Taylor endpoint domain')
    start = 1 if sine else 0
    polynomial = sum((-1)**k*x**(2*k+start)/math.factorial(2*k+start) for k in range(11))
    degree = 23 if sine else 22
    remainder = abs(x)**degree/math.factorial(degree)
    return polynomial-remainder, polynomial+remainder


@lru_cache(maxsize=8192)
def acos_endpoint(cosine):
    require(Q(9, 10) <= cosine <= 1, 'acos theorem domain')
    if cosine == 1:
        return Q(0), Q(0)
    lo, hi = Q(0), Q(1, 2)
    # cos decreases on [0,1/2]; its Taylor brackets prove both cuts.
    for _ in range(32):
        mid = (lo+hi)/2
        lower, upper = taylor_endpoint(mid, False)
        if lower > cosine:
            lo = mid
        elif upper < cosine:
            hi = mid
        else:
            break
    require(taylor_endpoint(lo, False)[0] >= cosine and
            taylor_endpoint(hi, False)[1] <= cosine, 'Unclosed ideal acos bracket')
    return lo, hi


class ScalarAuthority:
    """Consumer composition of accepted244; never extends a scalar theorem domain.

    Fixed-dot enumeration is phase independent. Native acos outside [.9,1] has
    no all-rounding constant-point receipt here, so those exact states stay UNKNOWN.
    The point-only fit keeps its accepted platform replay and is not refitted.
    """
    def __init__(self, capture, receipt, native_capture, platform_math):
        require(native.sha256(scalar.__file__) == ARITHMETIC_VERIFIER_SHA, 'Arithmetic verifier changed')
        scalar.verify_receipt(receipt, capture)
        require(receipt['engine_sha256'] == native_capture['engine_executable_sha256']
                and capture['engine']['version'] == native_capture['engine']
                and native_capture['runtime']['double_precision'] is False, 'Arithmetic/native engine or format mismatch')
        require(capture['native']['platform'] == 'macos-arm64', 'Native dataset requires its Mac arithmetic profile')
        for name, slots in zip(('sin', 'sinf', 'acosf'), capture['native']['imports']):
            require(all(platform_math['functions'][name] == {'image': slot['image_path'],
                    'mach_o_uuid': slot['image_id']} for slot in slots), 'Arithmetic/native profile mismatch')
        self.receipt = receipt
        self.binding = {'kind': 'accepted244-scalar-composition-v1', 'receipt': receipt,
                        'capture_sha256': scalar.digest(scalar.canonical(capture)),
                        'verifier_sha256': native.sha256(scalar.__file__)}
        self.cache = {}
        self.domains = {}
        self.weight_domains = {}
        self.work = {'fixed_dot_states': 0, 'weight_interval_compositions': 0,
                     'sine_ranges': 0, 'basic_interval_operations': 0}

    def sine(self, interval, name):
        lo, hi = interval
        domain = tuple(map(Q, self.receipt['theorems'][name]['domain']))
        if not (domain[0] <= lo <= hi <= domain[1]):
            raise Unclosed('sine_argument_domain', operation=name, argument=json_value(interval), domain=json_value(domain))
        # cos(x)>=1-x²/2>=7/8 on this interval, so sine is increasing throughout.
        error = Q(self.receipt['theorems'][name]['outward_absolute_error'])
        self.work['sine_ranges'] += 1
        return taylor_endpoint(lo, True)[0]-error, taylor_endpoint(hi, True)[1]+error

    def key_domain(self, a, b, track, key_index):
        cache_key = (tuple(a.lo), tuple(a.hi), tuple(b.lo), tuple(b.hi))
        if cache_key not in self.cache:
            dot = native.box_dot(a, b, 4)
            first, last = float_key(dot.lo), float_key(dot.hi)
            count = last-first+1
            require(0 < count <= LIMITS['float32_dot_values_per_track'], 'Slerp dot domain exceeds declared cap')
            states = [key_float(k) for k in range(first, last+1)]
            groups = {}
            for value in states:
                cosine = abs(np.float32(value))
                nonlinear = np.float32(1)-cosine > np.float32(1e-5)
                groups.setdefault((value < 0, bool(nonlinear)), []).append(float(cosine))
            result = []
            for (negative, nonlinear), cosines in sorted(groups.items()):
                record = {'negative': negative, 'nonlinear': nonlinear,
                          'cosine_interval': [min(cosines), max(cosines)]}
                if nonlinear:
                    low, high = map(Q, record['cosine_interval'])
                    if low < Q(9, 10) or high > 1:
                        record['unknown'] = 'acos_constant_authority_missing'
                    else:
                        error = Q(self.receipt['theorems']['acosf']['outward_absolute_error'])
                        omega = float_box((acos_endpoint(high)[0]-error, acos_endpoint(low)[1]+error))
                        record['omega_interval'] = list(box_interval(omega))
                        record['denominator_interval'] = list(self.sine(box_interval(omega), 'sinf'))
                result.append(record)
            self.cache[cache_key] = {'dot_states': states, 'branches': result}
            self.work['fixed_dot_states'] += count
        record = self.cache[cache_key]
        self.domains.setdefault(track+':'+str(key_index), {'track': track, 'key_index': key_index, **record})
        return record

    def prepare(self, capture):
        # Inspect every fixed key pair, including states behind an earlier UNKNOWN.
        for track in capture['tracks']:
            if track['type'] == 2 and track['interpolation'] != 0:
                for i in range(len(track['keys'])-1):
                    self.key_domain(native.Float32Box(track['keys'][i]['value']),
                                    native.Float32Box(track['keys'][i+1]['value']), track['path'], i)
                    self.domains[track['path']+':'+str(i)]['key_seconds'] = [track['keys'][i]['time'], track['keys'][i+1]['time']]

    def slerp(self, a, b, weight, track, key_index):
        f, outputs = native.Float32Box, []
        record = self.key_domain(a, b, track, key_index)
        for branch in record['branches']:
            target = -b if branch['negative'] else b
            if not branch['nonlinear']:
                outputs.append(a*(f(1)-weight)+target*weight)
                continue
            if 'unknown' in branch:
                raise Unclosed(branch['unknown'], track=track, key_index=key_index,
                               cosine_interval=branch['cosine_interval'], dot_states=record['dot_states'],
                               next_input='Existing accepted constant-point authority covering actual acosf result/rounding for these fixed states; [.9,1] scalar theorem cannot be extended.')
            omega, denominator = map(tuple, (branch['omega_interval'], branch['denominator_interval']))
            wlo, whi = box_interval(weight)
            # Godot scale0 is DOUBLE sin((1.-double(w))*omega)/double(sinf(omega)).
            argument0 = interval_product(rounded_interval(1-whi, 1-wlo, 53), omega, 53)
            scale0 = interval_quotient(self.sine(argument0, 'sin'), denominator, 53)
            scale0 = float_box(rounded_interval(*scale0, 24))
            # scale1 keeps the FLOAT multiplication, sinf and division path.
            argument1 = box_interval(float_box(interval_product((wlo, whi), omega, 24)))
            scale1 = float_box(interval_quotient(self.sine(argument1, 'sinf'), denominator, 24))
            identity = (track, key_index, branch['negative'])
            ranges = {'weight': (wlo, whi), 'double_sin_argument': argument0, 'float_sinf_argument': argument1}
            previous = self.weight_domains.setdefault(identity, {'track': track, 'key_index': key_index,
                'negative': branch['negative'], **ranges})
            for name, (low, high) in ranges.items():
                previous[name] = (min(low, previous[name][0]), max(high, previous[name][1]))
            outputs.append(a*scale0+target*scale1)
            self.work['weight_interval_compositions'] += 1
            self.work['basic_interval_operations'] += 6
        return hull(outputs)


def float_key(value):
    bits = struct.unpack('<I', struct.pack('<f', value))[0]
    return (~bits & 0xffffffff) if bits >> 31 else bits | 0x80000000


def key_float(key):
    bits = (key & 0x7fffffff) if key >> 31 else (~key & 0xffffffff)
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def hull(boxes):
    return native.Float32Box(np.minimum.reduce([b.lo for b in boxes]), np.maximum.reduce([b.hi for b in boxes]))


def track_span_box(track, lo, hi, length, functions, budget):
    """Enclose every native search branch and finite binary32 interpolation state.

    Legacy mode enumerates finite weights. Explicit scalar-proof mode composes
    accepted native errors with exact ideal ranges over the full weight interval.
    """
    f = native.Float32Box
    require(0 <= lo <= hi <= length, 'Continuous time domain')
    times = [k['time'] for k in track['keys']]
    require(times[0] == 0 and (len(times) == 1 or times[-1] == length)
            and all(a < b for a, b in zip(times, times[1:])), 'Incomplete search keys')
    if lo == hi and budget.arithmetic is None:
        if track['type'] == 2:
            if budget.used == budget.weight_values:
                raise Unclosed('platform_point_weight_budget', required_weight_values=1,
                               next_input='Evaluate the exact point with the pinned platform operations under a new declared work budget.')
            budget.used += 1
        if budget.planning:
            return f(track['keys'][0]['value'])
        return native.native_track_box(track, lo, length, functions)
    if len(times) == 1:
        return f(track['keys'][0]['value'])
    outputs = []
    for i, key in enumerate(track['keys']):
        # Since length < 1, CMP_EPSILON is constant. Widen the binary64
        # threshold arithmetic, including the one-sided early-key region.
        lower = np.nextafter(times[i]-1e-5, -np.inf) if i else 0.
        upper = np.nextafter(times[i+1]+1e-5, np.inf) if i+1 < len(times) else length
        if hi < lower or lo > upper:
            continue
        a = f(key['value']); b = f(track['keys'][(i+1) % len(times)]['value'])
        if track['interpolation'] == 0 or i == len(times)-1:
            outputs.append(a); continue
        require(length <= 1, 'Variable native search epsilon needs a separate branch proof')
        delta = np.float32(times[i+1]-times[i])
        weight = f.outward(max(lo, lower)-times[i], min(hi, upper)-times[i])/f(delta)
        if track['type'] != 2:
            outputs.append(a+(b-a)*weight); continue
        dot = native.box_dot(a, b, 4)
        # The whole near-identical-key branch is affine in weight.
        if dot.lo*dot.hi > 0 and np.float32(1)-np.float32(min(abs(float(dot.lo)), abs(float(dot.hi)))) <= np.float32(1e-5):
            target = -b if dot.hi < 0 else b
            outputs.append(a*(f(1)-weight)+target*weight); continue
        if budget.arithmetic is not None:
            outputs.append(budget.arithmetic.slerp(a, b, weight, track['path'], i)); continue
        first, last = float_key(weight.lo), float_key(weight.hi)
        required = last-first+1
        if required > budget.weight_values-budget.used:
            raise Unclosed('platform_slerp_weight_enumeration_budget', key_index=i,
                           weight_bits=[first, last], weight_interval=[float(weight.lo), float(weight.hi)],
                           required_weight_values=required, remaining_weight_values=budget.weight_values-budget.used,
                           next_input='Complete pinned-libm enumeration of these binary32 weights (including double scale0 sin), or a proved range enclosure for this exact platform binary.')
        budget.used += required
        if budget.planning:
            outputs.append(a); continue
        for bits in range(first, last+1):
            outputs.append(native.slerp_box(a, b, np.float32(key_float(bits)), functions))
    require(outputs, 'No native search branch')
    return hull(outputs)


def mixer_span_box(rest, target):
    f = native.Float32Box
    rest = f(rest)
    relative = native.quaternion_product_box(rest*f([-1, -1, -1, 1]), target)
    # Only Basis consumes this representative. At mixer weight 1, the two
    # short-arc branches are q and -q: IEEE sign symmetry and Basis(q)=Basis(-q)
    # permit one representative without destroying its correlated norm.
    q = native.quaternion_product_box(rest, relative)
    norm_squared = native.box_dot(q, q, 4)
    if norm_squared.lo <= 0:
        raise Unclosed('mixer_quaternion_norm_contains_zero',
                       norm_squared_interval=[float(norm_squared.lo), float(norm_squared.hi)],
                       quaternion_interval=[q.lo.tolist(), q.hi.tolist()],
                       next_input='Correlated native quaternion/norm enclosure for this exact box; a zero-crossing interval is not an actual zero or a physical impossibility.')
    return q*(f(1)/norm_squared.sqrt())


def basis_span_box(position, q, scale):
    f = native.Float32Box
    x, y, z, w = [q[i] for i in range(4)]
    s = f(2)/native.box_dot(q, q, 4)
    xs, ys, zs = x*s, y*s, z*s
    wx, wy, wz, xx, xy, xz, yy, yz, zz = w*xs, w*ys, w*zs, x*xs, x*ys, x*zs, y*ys, y*zs, z*zs
    b = native.box_stack([native.box_stack([f(1)-(yy+zz), xy-wz, xz+wy]),
                          native.box_stack([xy+wz, f(1)-(xx+zz), yz-wx]),
                          native.box_stack([xz-wy, yz+wx, f(1)-(xx+yy)])])
    diagonal = f(np.diag(scale))
    return native.box_stack([native.box_dot(b, diagonal[:, i], 3) for i in range(3)]+[position], axis=1)


def surface_span_box(capture, surface, binds, lo, hi, functions, budget):
    f = native.Float32Box
    require(len(capture['bones']) == len(binds), 'Bind cardinality')
    if lo < hi and budget.arithmetic is None:
        # Count the whole box before spending finite libm work on an early
        # track that leaves no budget for the remaining native hierarchy.
        plan = Budget(weight_values=2**63, planning=True)
        costs = []
        for track in capture['tracks']:
            before = plan.used
            track_span_box(track, lo, hi, capture['length'], functions, plan)
            costs.append({'track': track['path'], 'required_weight_values': plan.used-before})
        if plan.used > budget.weight_values-budget.used:
            raise Unclosed('platform_box_weight_enumeration_budget', required_weight_values=plan.used,
                           remaining_weight_values=budget.weight_values-budget.used,
                           track_costs=costs,
                           next_input='Subdivide this exact seconds interval until all track weight domains fit the remaining declared finite enumeration budget, or supply a proved enclosure for the pinned libm binary.')
    tracks = {}
    for track in capture['tracks']:
        key = track['path'].split(':')[-1], track['type']
        require(key not in tracks, 'Duplicate native track')
        try:
            tracks[key] = track_span_box(track, lo, hi, capture['length'], functions, budget)
        except Unclosed as error:
            error.detail['track'] = track['path']; raise
    globals_ = []
    for i, bone in enumerate(capture['bones']):
        position = f(bone['default_position'])
        rotation = f(bone['default_rotation'])
        if (bone['name'], 1) in tracks:
            rest = f(native.matrix(bone['rest'])[:3, 3])
            position = rest+(tracks[bone['name'], 1]-rest)
        if (bone['name'], 2) in tracks:
            try:
                rotation = mixer_span_box(bone['rest_rotation'], tracks[bone['name'], 2])
            except Unclosed as error:
                if budget.arithmetic is None:
                    raise ValueError('Negative sqrt enclosure' if error.detail['norm_squared_interval'][0] < 0
                                     else 'Division enclosure contains zero') from error
                error.detail['bone'] = bone['name']; raise
        require((bone['name'], 3) not in tracks, 'Animated scale mixer unaccounted')
        local = basis_span_box(position, rotation, bone['default_scale'])
        parent = bone['parent']
        require(-1 <= parent < i, 'Bone hierarchy')
        globals_.append(local if parent < 0 else native.affine_box(globals_[parent], local))
    transforms = native.box_stack([native.affine_box(g, f(b[:3])) for g, b in zip(globals_, binds)])
    vertices, weights = f(surface['vertices']), f(surface['weights'])
    joints = np.asarray(surface['joints'])
    require(joints.shape == weights.lo.shape == (len(vertices.lo), 4) and np.isfinite(joints).all()
            and (joints == np.floor(joints)).all() and (joints >= 0).all() and (joints < len(binds)).all()
            and (weights.lo >= 0).all(), 'Skin dimensions/domain')
    joints = joints.astype(int)
    result = f(np.zeros((len(joints), 3)))
    for i in range(4):
        transform = transforms[joints[:, i]]
        point = native.box_dot(transform[:, :, :3], vertices[:, None, :], 3)+transform[:, :, 3]
        result = result+point*weights[:, i, None]
    if hi == capture['length']:
        # Player fposmod owns the exact terminal as zero; direct queries also
        # expose the terminal key. Keep both, without assuming their equality.
        result = hull([result, surface_span_box(capture, surface, binds, 0., 0., functions, budget)])
    return result


def json_value(value):
    if isinstance(value, Q):
        return [value.numerator, value.denominator]
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {str(k): json_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(v) for v in value]
    return value


def canonical_digest(value):
    return hashlib.sha256(json.dumps(json_value(value), sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def load_inputs(review_path, *, native_manifest=None, bundle_root=None):
    require((native_manifest is None) == (bundle_root is None), 'Native manifest and bundle root required together')
    fresh = native_manifest is not None
    context = None
    if fresh:
        accepted = reacquired.load_accepted(native_manifest, bundle_root, review_path)
        manifest, capture, accounting = (accepted[k] for k in ('manifest', 'native', 'accounting'))
        roles = reacquired.check_index(bundle_root, manifest['bundle_index'], manifest['bundle_sha256'])
        receipt = reacquired.read_json(review_path)
        # Bind verdict identity/body, not mutable reaction/profile metadata or transport roots.
        comment = receipt['comment']
        binding = {'version': 1, 'kind': 'native-reacquired-v1',
                   'manifest_sha256': native.sha256(native_manifest), 'bundle_sha256': manifest['bundle_sha256'],
                   'verdict': receipt['binding'], 'comment': {k: comment[k] for k in
                       ('id', 'node_id', 'html_url', 'issue_url', 'created_at')},
                   'comment_author': {k: comment['user'][k] for k in ('id', 'node_id')},
                   'body_sha256': receipt['body_sha256'],
                   'role_sha256': {r['role']: r['sha256'] for r in manifest['bundle_index']},
                   'platform_math': accepted['component_result']['numerical_accounting']['platform_math'],
                   'algorithm_sha256': {path: native.sha256(ROOT/path) for path in [
                       'tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py',
                       'tools/units3d/check_cavalry_march_capture.py', 'tools/units3d/measure_unit_bodies.gd',
                       'docs/reviews/cluster-formations/cavalry-march-contact-prerequisite.md']}}
        context = {'binding': binding, 'roles': roles,
                   'locations': {'native_manifest': str(native_manifest), 'bundle_root': str(bundle_root),
                                 'review_record': str(review_path)}}
    else:
        manifest = native.read_bound(MANIFEST, MANIFEST_SHA)
        require(len(manifest['inputs']) == 298, 'Incomplete accepted input set')
        for path, digest in manifest['inputs'].items():
            require(native.sha256(path) == digest, f'Accepted input changed: {path}')
        review = native.read_bound(review_path, REVIEW_SHA)
        verdict = review_path.parent/'round2.md'
        require(native.sha256(verdict) == VERDICT_SHA and review['accepted'] is True
                and review['manifest_sha256'] == MANIFEST_SHA and review['pr']['state'] == 'MERGED'
                and review['review_session_id'] == '01a19ca8-5995-7bb2-b666-b3fbf29fb47d', 'Missing bound sole anatomical verdict')
        capture_path = Path(manifest['capture_directory'])/'native.json'
        capture = native.read_bound(capture_path, manifest['inputs'][str(capture_path)])
        accounting = native.read_bound(manifest['accounting_payload'], manifest['inputs'][manifest['accounting_payload']])
    require(capture['version'] == 2 and 0 < capture['length'] < 1 and len(capture['bones']) == 53
            and len(capture['skin']) == 53 and len(capture['surfaces']) == 1, 'Native domain')
    for path, digest in capture['input_hashes'].items():
        if path != 'project.godot':
            require(native.sha256(ROOT/path) == digest, f'Installed input changed: {path}')
    require(np.array_equal(native.matrix(capture['mesh_to_skeleton']), np.eye(4)), 'Mesh conversion changed')
    surface = dict(capture['surfaces'][0])
    surface['joints'] = np.asarray(surface['joints']).reshape(-1, 4)
    surface['weights'] = np.asarray(surface['weights']).reshape(-1, 4)
    require(len(surface['vertices']) == 21175 and len(surface['indices']) == 57141, 'Incomplete full geometry')
    binds = [native.matrix(b['pose']) for b in capture['skin']]
    require([b['name'] for b in capture['skin']] == [b['name'] for b in capture['bones']]
            and [b['resolved_bone'] for b in capture['skin']] == list(range(53)), 'Native bind mapping')
    patches = accounting['patches']
    require({h: len(v['native_sole_triangles']) for h, v in patches.items()} ==
            {'FrontHoof.L': 31, 'FrontHoof.R': 69, 'HindHoof.L': 46, 'HindHoof.R': 48}, 'Incomplete accepted patches')
    for patch in patches.values():
        triangles = np.asarray(surface['indices']).reshape(-1, 3)[patch['native_sole_triangles']]
        require(sorted(set(triangles.ravel().tolist())) == patch['native_sole_vertices'], 'Material patch vertex coverage')
    actions = roles['resource:tools/units3d/cavalry_rig/actions.py'] if fresh else ROOT/'tools/units3d/cavalry_rig/actions.py'
    actions_sha = (binding['role_sha256']['resource:tools/units3d/cavalry_rig/actions.py'] if fresh else
                   next(v for k, v in manifest['inputs'].items() if k.endswith('/cavalry_rig/actions.py')))
    require(native.sha256(actions) == actions_sha, 'Support source changed')
    constants = {n.targets[0].id: ast.literal_eval(n.value) for n in ast.parse(actions.read_text()).body
                 if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                 and n.targets[0].id in ('CANTER', 'DUTY')}
    supports = {name: (Q(str(start)), Q(str(start))+Q(str(constants['DUTY'])))
                for name, start in sorted(constants['CANTER'].items())}
    require(set(supports) == set(patches), 'All four source episodes required')
    functions = native.system_math()
    runtime = native.math_runtime_identity(functions)
    accepted_math = binding['platform_math'] if fresh else manifest['numerical_accounting']['platform_math']
    require(runtime['functions'] == accepted_math['functions'] and runtime['platform'] == accepted_math['platform']
            and subprocess.check_output(['/usr/bin/sw_vers', '-buildVersion'], text=True).strip() == accepted_math['os_build'],
            'Unproved native platform math mismatch')
    if fresh:
        witness = reacquired.read_json(roles['witness'])
    else:
        witness_path = Path(manifest['frozen_paths']['witness'])
        witness = native.read_bound(witness_path, manifest['inputs'][str(witness_path)])
        require(native.sha256(witness_path.parent/'accepted234-disposition.md') ==
                'f54da8c9105721029a0aed93dad6ecf2341ebf87cd55ec239401f6c3113db4ad', 'Frozen phase proposal changed')
    for path, digest in witness['current_inputs'].items():
        require(native.sha256(ROOT/path) == digest, f'Frozen observation input changed: {path}')
    return manifest, capture, surface, binds, patches, supports, functions, witness, context


def sampled_points(capture, surface, binds, time):
    """Independent binary64 reconstruction for adversarial comparisons, never a bound."""
    _, globals_ = native.pose(capture['bones'], native.native_tracks(capture), time, capture['length'])
    return native.skin(surface, np.asarray([g@b for g, b in zip(globals_, binds)]))


def fit_rows(phases, boxes, patches, supports):
    rows = []
    counts = {}
    for hoof, (start, end) in supports.items():
        active = [i for i, p in enumerate(phases) if start <= p <= end]
        count = 0
        for ia, i in enumerate(active):
            a = boxes[i]
            for j in active[ia+1:]:
                b = boxes[j]
                # Outward integer conversion makes the disk constraints exact.
                ids = patches[hoof]['native_sole_vertices']
                lo = np.floor(np.nextafter((b.lo[ids]-a.hi[ids])*GRID, -np.inf)).astype(np.int64)
                hi = np.ceil(np.nextafter((b.hi[ids]-a.lo[ids])*GRID, np.inf)).astype(np.int64)
                rows.extend((i, j, int(l[0]), int(u[0]), int(l[2]), int(u[2])) for l, u in zip(lo, hi))
                count += len(ids)
        counts[hoof] = count
    require(len(rows) <= LIMITS['max_constraints'], 'Declared fit constraint budget exhausted')
    return rows, counts


def fit(phases, rows):
    increments = [max(1, math.ceil((b-a)*Q(*LIMITS['strict_slope_floor_model_m_per_phase'])*GRID))
                  for a, b in zip(phases, phases[1:])]
    # Start from a data-derived numerical objective, never from either observed stride.
    upper = max([max(abs(r[2]), abs(r[3]), abs(r[4]), abs(r[5])) for r in rows]+[1])
    values = None
    for _ in range(LIMITS['fit_upper_expansions']):
        values = feasible(len(phases), rows, upper, increments, inner=True)
        if values is not None:
            break
        upper *= 2
    require(values is not None, 'No finite sampled inner candidate within declared expansion budget')
    lower, trials, unknown = 0, [], []
    best = values
    for _ in range(LIMITS['fit_trials']):
        trial = (lower+upper)//2
        inner = feasible(len(phases), rows, trial, increments, inner=True)
        if inner is not None:
            upper, best = trial, inner
            trials.append({'error_grid': trial, 'result': 'INNER_FEASIBLE'})
        elif feasible(len(phases), rows, trial, increments, inner=False) is None:
            lower = trial
            trials.append({'error_grid': trial, 'result': 'OUTER_INFEASIBLE'})
        else:
            unknown.append([lower, upper]); break
    # Contact imposes no final airborne travel. Continue the preceding slope;
    # this uniquely minimizes squared slope change over the trailing empty region.
    last_constrained = max(r[1] for r in rows)
    for i in range(last_constrained+1, len(phases)):
        slope = Q(best[last_constrained]-best[last_constrained-1], 1)/(phases[last_constrained]-phases[last_constrained-1])
        best[i] = best[last_constrained]+math.ceil(slope*(phases[i]-phases[last_constrained]))
    require(all(best[i+1]-best[i] >= increments[i] for i in range(len(increments))), 'Lost strict monotonicity')
    require(all((lambda r: r is not None and r[0] <= best[j]-best[i] <= r[1])
                (allowed_distance(upper, xl, xh, zl, zh, inner=True)) for i, j, xl, xh, zl, zh in rows),
            'Independent rational coefficient verification failed')
    return [Q(v, GRID) for v in best], {'lower_m': Q(lower, GRID), 'upper_m': Q(upper, GRID),
            'trials': trials, 'unclosed_fit_grid_brackets': unknown,
            'scope': 'Necessary outer / sufficient inner all-vertex, all-pair sampled native-operation boxes in this rational knot family and declared positive slope floor only; not a global scalar-map impossibility.',
            'tie_rule_status': 'Squared native-departure / lexicographic secondary optimization not certified. Exact Bellman-Ford coefficients are a feasible proposal, not an optimizer proof.'}


def captured_obstructions(capture, surface, binds, patches, supports, samples_path, witness):
    samples, points = [], []
    with samples_path.open() as file:
        for line in file:
            require(len(samples) < LIMITS['dense_native_capture_rows'], 'Native capture row budget')
            row = json.loads(line)
            globals_ = [native.matrix(g) for g in row['globals']]
            # Recompute actual captured-matrix LBS, independently of the saved CPU positions.
            p = native.skin(surface, np.asarray([g@b for g, b in zip(globals_, binds)]))
            samples.append(row); points.append(p)
    best, chosen = -1., None
    for hoof, (start, end) in supports.items():
        active = [i for i, s in enumerate(samples) if float(start) <= s['time']/capture['length'] <= float(end)]
        ids = patches[hoof]['native_sole_vertices']
        for ia, a in enumerate(active):
            for b in active[ia+1:]:
                dx = np.abs(points[b][ids, 0]-points[a][ids, 0]); local = int(np.argmax(dx))
                if dx[local] > best:
                    best, chosen = float(dx[local]), (hoof, ids[local], a, b)
    hoof, vertex, a, b = chosen
    def exact_at(index, v):
        return exact_vertex(surface['vertices'][v], surface['joints'][v].tolist(), surface['weights'][v].tolist(),
                            [native.matrix(g) for g in samples[index]['globals']], binds)
    pa, pb = exact_at(a, vertex), exact_at(b, vertex)
    delta = [y-x for x, y in zip(pa, pb)]
    obstruction = {'hoof': hoof, 'vertex': vertex, 'times_seconds': [samples[a]['time'], samples[b]['time']],
                   'native_points_exact': [pa, pb], 'delta_exact': delta, 'bounds_m': endpoint_floor(delta),
                   'scope': 'Every nonnegative scalar distance map with these required native endpoints; exact real raw LBS of captured native globals/binds. Model XZ/XYZ necessary conditions, not terrain contact or chosen E.'}
    frozen_rows = [next(i for i, s in enumerate(samples) if abs(s['time']/capture['length']-p) < 1e-12) for p in [.137, .25]]
    fa, fb = [exact_at(i, 16496) for i in frozen_rows]
    d = [y-x for x, y in zip(fa, fb)]
    observations = {}
    for name, stride in [('retained_5.9', Q('5.9')), ('nominal_2.4', Q('2.4'))]:
        travel = stride*(Q('.25')-Q('.137'))
        observations[name] = {'travel_model_m': travel, 'entry_drift_xz_m': sqrt_bounds(d[0]**2+(d[2]+travel)**2),
                              'free_anchor_radius_xz_m': tuple(v/2 for v in sqrt_bounds(d[0]**2+(d[2]+travel)**2)),
                              'status': 'PRESERVED_OBSERVATION_NOT_CANDIDATE_NOT_POLICY_E'}
    require(abs(float(observations['retained_5.9']['entry_drift_xz_m'][0])-.3919376776925641) < 1e-11
            and abs(float(observations['nominal_2.4']['entry_drift_xz_m'][0])-.0037417885450576) < 1e-11,
            'Frozen native witness changed')
    return samples, points, {'strongest_sampled_transverse_endpoint': obstruction,
                             'original_vertex': 16496, 'original_delta_exact': d, 'observations': observations,
                             'original_scale_observation': witness['scale']}


def continuous_domains(capture, phases):
    # Imported key, epsilon-search, support, rational-fit and loop boundaries.
    cuts = {0., capture['length']}
    cuts.update(float(p)*capture['length'] for p in phases)
    cuts.update(capture['native_search_boundaries_seconds'])
    cuts.update(k['time'] for t in capture['tracks'] for k in t['keys'])
    return [(a, b, 0) for a, b in zip(sorted(cuts), sorted(cuts)[1:]) if a < b]


def continuous_verify(capture, surface, binds, atlas, functions, budget=None):
    phases, _ = validate_atlas(atlas)
    pending = continuous_domains(capture, phases)
    budget, closed, unclosed = budget or Budget(), [], []
    attempts = splits = independent_evaluations = 0
    while pending and attempts < LIMITS['continuous_boxes']:
        lo, hi, depth = pending.pop(0); attempts += 1
        try:
            box = surface_span_box(capture, surface, binds, lo, hi, functions, budget)
            # Independent dense/adversarial arithmetic comparison on the full mesh.
            outside = []
            for time in [lo, (lo+hi)/2, hi]:
                independent_evaluations += 1
                points = sampled_points(capture, surface, binds, time)
                indices = np.argwhere(~box.contains(points))
                if len(indices):
                    outside.append({'seconds': time, 'vertex_components': indices[:16].tolist()})
            if outside:
                raise Unclosed('independent_interior_outside_enclosure', violations=outside,
                               next_input='Resolve concrete native-interpolation/mixer or search-branch counterexample before using this box.')
            closed.append({'seconds': [lo, hi], 'vertex_bounds': box, 'depth': depth})
        except (ValueError, FloatingPointError) as error:
            detail = error.detail if isinstance(error, Unclosed) else {'reason': str(error), 'next_input': 'A tighter native-operation interval proving this denominator/branch, retaining all influences.'}
            if splits < LIMITS['refinement_splits'] and hi-lo > 1e-9:
                mid = (lo+hi)/2
                pending[0:0] = [(mid, hi, depth+1), (lo, mid, depth+1)]
                splits += 1
            else:
                unclosed.append({'seconds': [lo, hi], 'depth': depth, **detail})
    unclosed.extend({'seconds': [a, b], 'depth': depth, 'reason': 'continuous_box_budget',
                     'next_input': 'Continue the declared operation enclosure on this exact pending interval under a newly declared finite work budget.'}
                    for a, b, depth in pending)
    verify_partition(closed, unclosed, capture['length'])
    return closed, unclosed, {'attempts': attempts, 'refinement_splits': splits, 'float32_weight_values': budget.used,
                              'independent_track_evaluations': independent_evaluations}


def verify_partition(closed, unclosed, length):
    cursor = 0.
    for a, b in sorted(item['seconds'] for item in closed+unclosed):
        require(math.isfinite(a) and math.isfinite(b) and a == cursor and a < b <= length,
                'Missing, overlapping or malformed continuous domain interval')
        cursor = b
    require(cursor == length, 'Continuous domain not completely accounted for')


def validate_diagnostic(report):
    require(type(report['version']) is int and report['version'] in (1, 2, 3), 'Report version')
    if report['version'] in (2, 3):
        binding = report['input_binding']
        require(binding['kind'] == 'native-reacquired-v1' and type(binding['version']) is int
                and binding['version'] == 1, 'Input binding version')
        require(report['step_id'] == ('CAV-CONTACT-PHASE-SLERP-BOUNDS' if report['version'] == 3 else 'CAV-CONTACT-PHASE-INPUT-BINDING')
                and report['atlas_input_packet']['input_binding'] == binding
                and report['atlas']['input_sha256'] == canonical_digest(report['atlas_input_packet'])
                and report['inputs']['manifest'] == binding['manifest_sha256']
                and report['inputs']['verdict_body'] == binding['body_sha256']
                and all(report['inputs']['role:'+k] == v for k, v in binding['role_sha256'].items())
                and all(report['inputs'][k] == v for k, v in binding['algorithm_sha256'].items()),
                'Report/atlas input binding differs')
    else:
        require(not any(k in report for k in ('input_binding', 'atlas_input_packet', 'input_locations')),
                'Mixed legacy/new provenance')
    if report['version'] == 3:
        require('arithmetic_proof' in report and report['atlas_input_packet'].get('arithmetic_proof') == report['arithmetic_proof']
                and report['arithmetic_proof']['verifier_sha256'] == ARITHMETIC_VERIFIER_SHA
                and report['inputs']['arithmetic_capture'] == report['arithmetic_proof']['capture_file_sha256']
                and report['inputs']['arithmetic_receipt'] == report['arithmetic_proof']['receipt_file_sha256']
                and report['inputs']['arithmetic_verifier'] == ARITHMETIC_VERIFIER_SHA
                and report['inputs']['baseline_report'] == BASELINE_SHA
                and report['atlas_input_packet']['baseline_report_sha256'] == BASELINE_SHA,
                'Arithmetic proof/atlas binding differs')
        require(len(report['baseline_accounting']['coordinate_boxes']) == 69
                and len(report['baseline_accounting']['shape_cases']) == 18, 'Incomplete prior unknown accounting')
    require(report['status'] == 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY', 'Diagnostic status changed')
    validate_atlas(report['atlas'])
    require(canonical_digest(report['atlas']) == report['atlas_sha256'], 'Atlas coefficients/digest changed')
    claims = report['claims']
    require(all(claims[k] is False for k in ['success_dependency', 'verified_physical_candidate',
            'phase_runtime_unblocked', 'surface_unblocked', 'contact_certificate'])
            and claims['policy_E'] is None and claims['original_12_gates_preserved'] is True,
            'Diagnostic cannot grant physical acceptance or select E')
    require(report['missing_physical_context'], 'Missing physical context silently erased')
    verify_partition(report['continuous_native']['closed_boxes'], report['continuous_native']['unclosed_boxes'],
                     report['atlas']['clip_seconds'])


def reject_captured_boxes(closed, comparisons):
    rejected = {}
    for row in comparisons:
        for box in row['violated_boxes']:
            rejected.setdefault(tuple(box['seconds']), []).append({'seconds': row['seconds'],
                'vertex_components': box['vertex_components']})
    failed = [{'seconds': list(span), 'reason': 'native_capture_outside_continuous_box',
               'native_captures': points, 'next_input': 'Resolve these exact native capture/vertex violations before certifying this box.'}
              for span, points in sorted(rejected.items())]
    return [box for box in closed if tuple(box['seconds']) not in rejected], failed


def norm_upper(box, axes):
    """Outward sum of squares, including each multiply/add and square root."""
    f = native.Float32Box
    maximum = np.maximum(abs(box.lo[:, axes]), abs(box.hi[:, axes]))
    square = f(maximum)*f(maximum)
    total = square[:, 0]
    for i in range(1, len(axes)):
        total = total+square[:, i]
    return native.Float32Box(np.maximum(total.lo, 0), total.hi).sqrt().hi


def triangle_shape(triangles, birth_triangles):
    def cross_of_edges(points):
        a, b = points[:, 1]-points[:, 0], points[:, 2]-points[:, 0]
        return native.box_stack([a[:, 1]*b[:, 2]-a[:, 2]*b[:, 1],
                                 a[:, 2]*b[:, 0]-a[:, 0]*b[:, 2],
                                 a[:, 0]*b[:, 1]-a[:, 1]*b[:, 0]], axis=1)
    cross, birth = cross_of_edges(triangles), cross_of_edges(birth_triangles)
    minimum = np.where((cross.lo <= 0) & (cross.hi >= 0), 0., np.minimum(abs(cross.lo), abs(cross.hi)))
    square = native.Float32Box.outward(minimum*minimum, minimum*minimum)
    total = square[:, 0]+square[:, 1]+square[:, 2]
    area = native.Float32Box(np.maximum(total.lo, 0), np.maximum(total.hi, 0)).sqrt()
    orientation = native.box_dot(cross, birth, 3)
    return {'min_twice_area_lower_m2': float(np.min(area.lo)),
            'unclosed_area_or_orientation': np.flatnonzero((area.lo <= 0) | (orientation.lo <= 0)).tolist(),
            'opposite_orientation': np.flatnonzero(orientation.hi < 0).tolist(),
            'scope': 'Native material triangle area and orientation against actual birth triangles in model space; no ground normal inferred.'}


def closed_metrics(closed, atlas, patches, supports, birth_boxes, body_mask, scale):
    records, patch_union = [], {}
    for item in closed:
        lo, hi = item['seconds']; box = item['vertex_bounds']
        length = atlas['clip_seconds']
        p, q = Q(lo)/Q(length), Q(hi)/Q(length)
        start, end = distance_at(atlas, p), distance_at(atlas, q)
        translated = native.Float32Box.outward(box.lo, box.hi)
        travel = native.Float32Box.outward([0., 0., float(start)], [0., 0., float(end)])
        translated = translated+travel
        body_upper = float(np.max(norm_upper(box[body_mask], [0, 1, 2])))
        all_upper = float(np.max(norm_upper(box, [0, 1, 2])))
        record = {'seconds': [lo, hi], 'entry_drift_upper_m': {}, 'triangle_shape': {},
                  'body_sphere_upper_model_m': body_upper, 'all_mesh_sphere_upper_model_m': all_upper,
                  'sphere_scope': 'All native horse/rider/gear vertices, every ideal rigid yaw/tilt; world renderer multiplication still needs its own enclosure.'}
        for hoof, (a, b) in supports.items():
            if q < a or p > b:
                continue
            ids = patches[hoof]['native_sole_vertices']
            birth_travel = [0., 0., float(distance_at(atlas, a))]
            anchor = birth_boxes[hoof]+native.Float32Box.outward(birth_travel, birth_travel)
            drift = translated[ids]-anchor
            record['entry_drift_upper_m'][hoof] = float(np.max(norm_upper(drift, [0, 2])))
            current = translated[ids]
            patch_union[hoof] = hull([patch_union[hoof], current]) if hoof in patch_union else current
            if 'native_triangles' in patches[hoof]:
                local_index = {v: i for i, v in enumerate(ids)}
                local_triangles = np.array([[local_index[v] for v in face] for face in patches[hoof]['native_triangles']])
                record['triangle_shape'][hoof] = triangle_shape(current[local_triangles], anchor[local_triangles])
                record['triangle_shape'][hoof]['native_triangle_ids'] = patches[hoof]['native_sole_triangles']
        records.append(record)
    diameter = {hoof: float(np.max(norm_upper(box-box, [0, 2]))) for hoof, box in patch_union.items()}
    # Positive exact captured scale retained; no fitted/resized scene or new R.
    maximum = max([r['body_sphere_upper_model_m'] for r in records], default=None)
    world = None if maximum is None else sqrt_bounds(Q(maximum)**2*Q(scale)**2)[1]
    return records, diameter, world


def baseline_accounting(baseline, closed, unclosed):
    def overlaps(span, rows):
        return [([max(span[0], row['seconds'][0]), min(span[1], row['seconds'][1])], row)
                for row in rows if max(span[0], row['seconds'][0]) < min(span[1], row['seconds'][1])]
    coordinates, shapes = [], []
    for old in baseline['continuous_native']['unclosed_boxes']:
        span = old['seconds']
        proved, unknown = overlaps(span, closed), overlaps(span, unclosed)
        require(sum(Q(b)-Q(a) for (a, b), _ in proved+unknown) == Q(span[1])-Q(span[0]),
                'Prior coordinate interval not completely accounted for')
        coordinates.append({'original_seconds': span, 'original_reason': old['reason'],
                            'closed_seconds': [s for s, _ in proved],
                            'unclosed_seconds': [s for s, _ in unknown],
                            'remaining_reasons': sorted({r['reason'] for _, r in unknown})})
    for old in baseline['continuous_native']['closed_boxes']:
        for hoof, shape in old.get('triangle_shape', {}).items():
            for index in shape['unclosed_area_or_orientation']:
                face = shape['native_triangle_ids'][index]
                rows = overlaps(old['seconds'], closed)
                reasons = []
                require(sum(Q(b)-Q(a) for (a, b), _ in rows+overlaps(old['seconds'], unclosed)) ==
                        Q(old['seconds'][1])-Q(old['seconds'][0]), 'Prior shape interval not completely accounted for')
                if overlaps(old['seconds'], unclosed):
                    reasons.append('coordinate_interval_unclosed')
                for _, row in rows:
                    current = row.get('triangle_shape', {}).get(hoof)
                    if current is None or face not in current['native_triangle_ids']:
                        reasons.append('material_triangle_unaccounted')
                    elif current['native_triangle_ids'].index(face) in current['unclosed_area_or_orientation']:
                        reasons.append('area_or_orientation_interval_crosses_zero')
                shapes.append({'original_seconds': old['seconds'], 'hoof': hoof,
                               'original_local_triangle_index': index, 'native_triangle_id': face,
                               'outcome': 'UNKNOWN' if reasons else 'CLOSED', 'reasons': sorted(set(reasons))})
    return {'coordinate_boxes': coordinates, 'shape_cases': shapes,
            'scope': 'Every original69 weight-budget box and18 material shape cases retained; uncertainty is not an inversion/impossibility witness.'}


def build(review_path, *, native_manifest=None, bundle_root=None,
          arithmetic_capture=None, arithmetic_receipt=None, baseline_report=None):
    proof_mode = arithmetic_capture is not None
    require((arithmetic_capture is None) == (arithmetic_receipt is None) == (baseline_report is None),
            'Arithmetic capture, receipt and baseline required together')
    require(not proof_mode or native_manifest is not None, 'Arithmetic mode requires explicit accepted native inputs')

    manifest, capture, surface, binds, patches, supports, functions, witness, context = load_inputs(
        review_path, native_manifest=native_manifest, bundle_root=bundle_root)
    arithmetic = baseline = None
    if proof_mode:
        baseline = native.read_bound(baseline_report, BASELINE_SHA)
        validate_diagnostic(baseline)
        require(baseline['version'] == 2, 'Expected accepted252 baseline')
        arithmetic = ScalarAuthority(reacquired.read_json(arithmetic_capture), reacquired.read_json(arithmetic_receipt),
                                     capture, context['binding']['platform_math'])
        arithmetic.binding.update(capture_file_sha256=native.sha256(arithmetic_capture),
                                  receipt_file_sha256=native.sha256(arithmetic_receipt))
        context['locations'].update(arithmetic_capture=str(arithmetic_capture), arithmetic_receipt=str(arithmetic_receipt),
                                    baseline_report=str(baseline_report))
    phases = sorted({Q(0), Q(1), Q('.137'), Q('.25')}
                    | {Q(k['time'])/Q(capture['length']) for t in capture['tracks'] for k in t['keys']}
                    | {v for pair in supports.values() for v in pair})
    require(len(phases) <= LIMITS['max_knots'], 'Declared knot budget')
    budget = Budget()
    boxes = [surface_span_box(capture, surface, binds, float(z)*capture['length'], float(z)*capture['length'], functions, budget)
             for z in phases]
    rows, counts = fit_rows(phases, boxes, patches, supports)
    distances, fit_result = fit(phases, rows)
    data_packet = {'supports': supports, 'full_material_patches': patches, 'native_surface': surface,
                   'bones': capture['bones'], 'binds': capture['skin'], 'tracks': capture['tracks']}
    if context is None:
        input_packet = {'manifest_sha256': MANIFEST_SHA, 'review_sha256': REVIEW_SHA, 'verdict_sha256': VERDICT_SHA,
                        'native_sha256': manifest['inputs'][str(Path(manifest['capture_directory'])/'native.json')],
                        'accounting_sha256': manifest['inputs'][manifest['accounting_payload']], **data_packet}
        samples_path = Path(manifest['capture_directory'])/'samples.jsonl'
    else:
        input_packet = {'input_binding': context['binding'], 'data_sha256': canonical_digest(data_packet)}
        samples_path = context['roles']['samples']
    if arithmetic is not None:
        input_packet.update(arithmetic_proof=arithmetic.binding, baseline_report_sha256=BASELINE_SHA)
    atlas = make_atlas(phases, distances, canonical_digest(input_packet), capture['length'])
    samples, sampled, obstruction = captured_obstructions(capture, surface, binds, patches, supports,
                                                         samples_path, witness)
    if arithmetic is not None:
        require(atlas['knots'] == baseline['atlas']['knots'] and json_value(fit_result) == {k: v for k, v in baseline['fit'].items()
                if k not in ('constraint_count', 'all_vertex_pair_counts_by_hoof', 'inner_verification', 'secondary_objective_unclosed_domain')},
                'Frozen point-fit coefficients/result changed')
        # Compare exact scientific data; only provenance/algorithm binding may change.
        require(input_packet['data_sha256'] == baseline['atlas_input_packet']['data_sha256'], 'Frozen native data changed')
        arithmetic.prepare(capture)
        budget.arithmetic = arithmetic
    closed, unclosed, used = continuous_verify(capture, surface, binds, atlas, functions, budget)
    birth_boxes = {hoof: boxes[phases.index(start)][patches[hoof]['native_sole_vertices']]
                   for hoof, (start, _) in supports.items()}
    names = [b['name'] for b in capture['bones']]
    lance_weight = np.sum(surface['weights']*(np.array(names)[surface['joints']] == 'Lance'), axis=1)
    # Same classification and threshold as measure_unit_bodies.gd, without dropping gear.
    body_mask = lance_weight < 1.-.000001
    footprint_path = (context['roles']['resource:data/army/unit_footprints.csv'] if context else
                      ROOT/'data/army/unit_footprints.csv')
    with footprint_path.open() as file:
        footprint = next(r for r in csv.DictReader(file) if r['arm'] == 'cavalry')
    scale = witness['scale']['ordinary_world_scale']
    for patch in patches.values():
        patch['native_triangles'] = np.asarray(surface['indices']).reshape(-1, 3)[patch['native_sole_triangles']].tolist()
    # Every retained native capture is an independent adversarial observation;
    # samples not covered by a closed box remain visible, not silently discarded.
    comparisons = []
    worst_sample_error = 0.
    for sample_, actual in zip(samples, sampled):
        time = sample_['time']
        proposal = sampled_points(capture, surface, binds, time)
        error = float(np.max(abs(proposal-actual)))
        worst_sample_error = max(worst_sample_error, error)
        matching = [c for c in closed if c['seconds'][0] <= time <= c['seconds'][1]]
        outside = []
        for c in matching:
            bad = np.argwhere(~c['vertex_bounds'].contains(np.asarray(sample_['skinned_skeleton_local'][0])))
            if len(bad):
                outside.append({'seconds': c['seconds'], 'vertex_components': bad[:16].tolist()})
        comparisons.append({'seconds': time, 'covered_by_continuous_box': bool(matching), 'violated_boxes': outside,
                            'independent_track_vs_captured_matrix_lbs_max_abs_m': error})
    closed, rejected = reject_captured_boxes(closed, comparisons)
    unclosed.extend(rejected)
    verify_partition(closed, unclosed, capture['length'])
    records, diameter, body_world = closed_metrics(closed, atlas, patches, supports, birth_boxes, body_mask, scale)
    evaluations = len(phases)+used['independent_track_evaluations']+len(samples)
    require(evaluations <= LIMITS['proposal_evaluations'], 'Declared proposal evaluation budget exhausted')
    lower = obstruction['strongest_sampled_transverse_endpoint']['bounds_m']['entry_drift_xz'][0]
    physical_unknowns = [
        {'metric': 'penetration_m,hover_m,normal_rad', 'phase_domain': [[0, 1]],
         'missing_input': 'Actual admitted terrain triangles/LOD and rendered-surface uncertainty; unchanged root seat/pose-to-world frame and terrain normal domain. Model Y or a fitted plane is not ground.'},
        {'metric': 'material_entry_drift_m', 'phase_domain': [[0, 1]],
         'missing_input': 'Physical validity of all four source support episodes, actual material touchdown/carried-in birth records, actual heading/path deviation and admitted operation context. Source labels remain required constraints.'},
        {'metric': 'real_time_velocity', 'phase_domain': [[0, 1]],
         'missing_input': 'Actual admitted duration T / nonzero 1/T domain bound; this verifier encloses normalized native pose only.'},
        {'metric': 'world_envelope_m', 'phase_domain': [[0, 1]],
         'missing_input': 'Closed native boxes, admitted world_per_sim_m and actual renderer world-transform operation enclosure at unchanged scale/seat/R. Full mesh and body/weapon split retained.'}]
    if context:
        inputs = {'role:'+k: v for k, v in context['binding']['role_sha256'].items()}
        inputs['manifest'] = context['binding']['manifest_sha256']
        inputs['verdict_body'] = context['binding']['body_sha256']
    else:
        inputs = {str(MANIFEST): MANIFEST_SHA, **manifest['inputs'], str(review_path): REVIEW_SHA,
                  str(review_path.parent/'round2.md'): VERDICT_SHA,
                  str(Path(manifest['frozen_paths']['witness']).parent/'accepted234-disposition.md'):
                      'f54da8c9105721029a0aed93dad6ecf2341ebf87cd55ec239401f6c3113db4ad',
                  str(footprint_path): native.sha256(footprint_path)}
    if arithmetic is not None:
        inputs.update(arithmetic_capture=arithmetic.binding['capture_file_sha256'],
                      arithmetic_receipt=arithmetic.binding['receipt_file_sha256'], baseline_report=BASELINE_SHA,
                      arithmetic_verifier=ARITHMETIC_VERIFIER_SHA)
        key_pairs = sum(len(t['keys'])-1 for t in capture['tracks'] if t['type'] == 2 and t['interpolation'] != 0)
        bound = LIMITS['continuous_boxes']*key_pairs*4
        require(arithmetic.work['weight_interval_compositions'] <= bound
                and arithmetic.work['sine_ranges'] <= 3*bound+2*key_pairs
                and arithmetic.work['basic_interval_operations'] <= 6*bound, 'Interval composition work bound')
        used['scalar_composition'] = {**arithmetic.work, 'fixed_key_pairs': key_pairs,
            'dot_states_across_all_key_pairs': sum(len(r['dot_states']) for r in arithmetic.domains.values()),
            'finite_composition_bound': bound,
            'finite_sine_range_bound': 3*bound+2*key_pairs,
            'finite_basic_interval_operation_bound': 6*bound,
            'scope': 'Separate fixed-key/branch range work; original finite-weight counters and all LIMITS unchanged.'}
    for path in ['tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py',
                 'tools/units3d/check_cavalry_march_capture.py', 'tools/units3d/measure_unit_bodies.gd',
                 'docs/reviews/cluster-formations/cavalry-march-contact-prerequisite.md']:
        inputs[path if context else str(ROOT/path)] = native.sha256(ROOT/path)
    return json_value({
        **({'input_binding': context['binding'], 'input_locations': context['locations'],
            'atlas_input_packet': input_packet} if context else {}),
        'version': 3 if arithmetic else (2 if context else 1), 'step_id': 'CAV-CONTACT-PHASE-SLERP-BOUNDS' if arithmetic else ('CAV-CONTACT-PHASE-INPUT-BINDING' if context else 'CAV-CONTACT-PHASE'), 'status': 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY',
        **({'arithmetic_proof': arithmetic.binding, 'baseline_accounting': baseline_accounting(baseline, records, unclosed)} if arithmetic else {}),
        'inputs': inputs, 'work_budget_declared_before_fit': LIMITS, 'work_used': {**used, 'proposal_evaluations': evaluations},
        'accepted_anatomy': {'manifest_status_preserved': manifest['status'], 'independent_component_verdict': context['binding']['verdict'] if context else str(review_path),
                             'four_patches': {h: {'vertices': len(p['native_sole_vertices']), 'triangles': len(p['native_sole_triangles'])} for h, p in patches.items()}},
        'source_support_constraints': supports,
        'atlas': atlas, 'atlas_sha256': canonical_digest(atlas),
        'atlas_status': 'ALL_SAMPLED_PATCH_CONSTRAINTS_VERIFIED_PROPOSAL_ONLY',
        'coefficient_domain': 'Exact rational periodic F(z)=floor(z)*S+f(frac(z)); strict positive slopes, all imported keys/source boundaries. No altered native locals/root/seat/clock.',
        'fit': {**fit_result, 'constraint_count': len(rows), 'all_vertex_pair_counts_by_hoof': counts,
                'inner_verification': True, 'secondary_objective_unclosed_domain': {'knots': len(phases),
                   'reason': 'Finite inner/outer minimax gap and secondary squared-departure/lexicographic optimum unproved; no optimizer or physical candidate claim.'}},
        'finite_endpoint_necessary_conditions': obstruction,
        'metric_bounds': {
            'entry_drift_m': {'lower': lower, 'upper': None, 'scope': 'Model XZ necessary floor for every scalar map; continuous physical upper bound unknown.'},
            'diameter_m': {'lower': lower, 'upper': None, 'scope': 'Two required endpoints; free-anchor radius lower is half, never entry drift.'},
            'penetration_m': None, 'hover_m': None, 'normal_rad': None, 'envelope_m': None},
        'continuous_native': {**({'scalar_domain_records': list(arithmetic.domains.values()),
                                  'weight_domain_records': list(arithmetic.weight_domains.values())} if arithmetic else {}),
                              'closed_boxes': records, 'unclosed_boxes': unclosed,
                              'closed_subset_diameter_upper_m': diameter, 'closed_subset_body_world_sphere_upper_m': body_world,
                              'method': ('Exact rational monotone Taylor sine/acos ranges plus recomputed accepted244 scalar errors, binary64 scale0/binary32 scale1 rounding and FTZ; fixed-dot states all enumerated, full weights enclosed through mixer/Basis/FK/true-bind/raw LBS. Out-of-domain constant acos stays UNKNOWN.' if arithmetic else 'Outward binary32 track/search/mixer/Basis/FK/true-bind/unnormalized LBS boxes; every finite binary32 slerp weight is enumerated with pinned acosf/sinf/double sin. Exhausted domains stay UNKNOWN. No assumed libm ULP bound, sampled residual allowance, or fast-math reassociation.'),
                              'loop': 'Player exact terminal maps to phase 0; direct terminal query and one-sided epsilon-search branches remain separate in closed interval checks.'},
        'full_geometry': {'vertices': len(surface['vertices']), 'triangles': len(surface['indices'])//3,
                          'body_vertices': int(np.count_nonzero(body_mask)), 'attack_only_vertices': int(np.count_nonzero(~body_mask)),
                          'all_gear_retained': True, 'raw_weight_sum_range': [float(np.min(surface['weights'].sum(axis=1))), float(np.max(surface['weights'].sum(axis=1)))],
                          'ordinary_world_scale_retained_observation': scale, 'unchanged_footprint': footprint,
                          'R_comparison': 'For each closed model body sphere B: k*B <= R_sim_m*world_per_sim_m is sufficient for every ideal rigid yaw/tilt. No global comparison passes while any native/world-operation box is unclosed.'},
        'dense_native_comparison': {'rows': comparisons, 'max_track_reconstruction_discrepancy_m': worst_sample_error,
                                    'scope': 'Independent accepted native captures and binary64 track reconstruction are adversarial checks, never a universal numerical allowance.'},
        'missing_physical_context': physical_unknowns,
        'claims': {'verified_physical_candidate': False, 'success_dependency': False, 'contact_certificate': False,
                   'policy_E': None, 'phase_runtime_unblocked': False, 'surface_unblocked': False,
                   'original_12_gates_preserved': True, 'native_recapture': False, 'live_window_or_FPS_acceptance': False},
        'reproduction': ({'build': 'python3 tools/units3d/cavalry_march_phase.py build --native-manifest MANIFEST_JSON --bundle-root BUNDLE_ROOT --review-record ACTUAL_RECEIPT_JSON --out REPORT_JSON'+(' --arithmetic-capture SCALAR_CAPTURE --arithmetic-receipt SCALAR_RECEIPT --baseline-report ACCEPTED252_REPORT' if arithmetic else ''),
                          'verify': 'python3 tools/units3d/cavalry_march_phase.py verify REPORT_JSON --native-manifest MANIFEST_JSON --bundle-root BUNDLE_ROOT --review-record ACTUAL_RECEIPT_JSON'+(' --arithmetic-capture SCALAR_CAPTURE --arithmetic-receipt SCALAR_RECEIPT --baseline-report ACCEPTED252_REPORT' if arithmetic else ''),
                          'exit_status': '2 is diagnostic/unknown, never physical acceptance; malformed/tampered input exits 1.'} if context else {'build': 'python3 tools/units3d/cavalry_march_phase.py build --review-record REVIEW_COMPLETE_JSON --out REPORT_JSON',
                         'verify': 'python3 tools/units3d/cavalry_march_phase.py verify REPORT_JSON --review-record REVIEW_COMPLETE_JSON',
                         'exit_status': '2 is the expected truthful diagnostic/unknown result, never physical acceptance. A malformed/tampered input exits 1.'})})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    build_parser = sub.add_parser('build'); build_parser.add_argument('--out', type=Path, required=True)
    verify_parser = sub.add_parser('verify'); verify_parser.add_argument('report', type=Path)
    for p in [build_parser, verify_parser]:
        p.add_argument('--review-record', type=Path, required=True)
        p.add_argument('--native-manifest', type=Path)
        p.add_argument('--bundle-root', type=Path)
        p.add_argument('--arithmetic-capture', type=Path)
        p.add_argument('--arithmetic-receipt', type=Path)
        p.add_argument('--baseline-report', type=Path)
    args = parser.parse_args()
    try:
        existing = None
        if args.command == 'verify':
            existing = json.loads(args.report.read_text())
            validate_diagnostic(existing)
        fresh = args.native_manifest is not None
        require(fresh == (args.bundle_root is not None), 'Native manifest and bundle root required together')
        proof_mode = args.arithmetic_capture is not None
        require(proof_mode == (args.arithmetic_receipt is not None) == (args.baseline_report is not None),
                'Arithmetic capture, receipt and baseline required together')
        if existing is not None:
            require(existing['version'] == (3 if proof_mode else (2 if fresh else 1)), 'Report/input mode mismatch')
        report = build(args.review_record.resolve(),
                       native_manifest=args.native_manifest.resolve() if fresh else None,
                       bundle_root=args.bundle_root.resolve() if fresh else None,
                       arithmetic_capture=args.arithmetic_capture.resolve() if proof_mode else None,
                       arithmetic_receipt=args.arithmetic_receipt.resolve() if proof_mode else None,
                       baseline_report=args.baseline_report.resolve() if proof_mode else None)
        validate_diagnostic(report)
        if args.command == 'build':
            args.out.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False)+'\n')
        else:
            require({k: v for k, v in existing.items() if k != 'input_locations'} ==
                    {k: v for k, v in report.items() if k != 'input_locations'}, 'Report differs from independent replay')
        print(json.dumps({'status': report['status'], 'atlas_sha256': report['atlas_sha256'],
                          'closed_boxes': len(report['continuous_native']['closed_boxes']),
                          'unclosed_boxes': len(report['continuous_native']['unclosed_boxes'])}))
        return 2
    except (ValueError, OSError, KeyError, StopIteration, subprocess.SubprocessError) as error:
        print(f'Invalid input or unclosed construction: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
