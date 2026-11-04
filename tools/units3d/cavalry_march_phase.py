"""Offline native-pose distance fit; UNKNOWN never enables a runtime consumer.

Reuses the accepted native audit, never the unmerged CERT implementation. Exact
rational atlas/constraint proofs and continuous platform arithmetic are separate
from physical E and from missing terrain/support context. No Godot is launched.
"""
import argparse
import ast
import csv
from bisect import bisect_right
from dataclasses import dataclass, field
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
    norm_records: dict = field(default_factory=dict)


NORM_BASELINE_SHA = '17c771a3d3254557c5663e169d53ad46129e3a730505b2a7b37ba5da948fcc07'
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


@dataclass(frozen=True)
class QuaternionBranch:
    box: object
    norm_squared: tuple
    certificate: dict
    binding: str

    def validate(self):
        require(self.binding == canonical_digest((self.box.lo, self.box.hi,
                self.norm_squared, self.certificate)), 'Corrupted quaternion certificate/component identity')
        require(0 <= self.norm_squared[0] <= self.norm_squared[1], 'Invalid quaternion norm certificate')


class QuaternionSpan(native.Float32Box):
    """Branches are hulled for linear consumers only, never before a denominator."""
    def __init__(self, branches):
        require(branches, 'Missing quaternion certificate branches')
        self.branches = tuple(branches)
        for branch in self.branches:
            branch.validate()
        super().__init__(np.minimum.reduce([b.box.lo for b in branches]),
                         np.maximum.reduce([b.box.hi for b in branches]))

    def validate(self):
        require(self.branches, 'Missing quaternion certificate branches')
        for branch in self.branches:
            branch.validate()
        require(np.array_equal(self.lo, np.minimum.reduce([b.box.lo for b in self.branches]))
                and np.array_equal(self.hi, np.maximum.reduce([b.box.hi for b in self.branches])),
                'Quaternion branch hull changed')


def norm_branch(box, norm, certificate):
    require(certificate['norm_squared'] == norm, 'Quaternion certificate norm differs')
    lower = sum(Q(0) if x <= 0 <= y else min(abs(rational(x)), abs(rational(y)))**2
                for x, y in zip(box.lo, box.hi))
    upper = sum(max(abs(rational(x)), abs(rational(y)))**2 for x, y in zip(box.lo, box.hi))
    require(max(lower, norm[0]) <= min(upper, norm[1]), 'Inconsistent quaternion norm/component intervals')
    return QuaternionBranch(box, norm, certificate,
        canonical_digest((box.lo, box.hi, norm, certificate)))


def perturbed_norm(norm, error):
    # ||e||_2 <= ||e||_1. Never replace an unproved lower bound by epsilon.
    radius = sum(error)
    lo, hi = sqrt_bounds(norm[0])[0], sqrt_bounds(norm[1])[1]
    return max(Q(0), lo-radius)**2, (hi+radius)**2


def affine_quaternion(a, b, weight, error, identity, component_box=None):
    a, b, weight, error = [tuple(map(rational, values)) for values in (a, b, weight, error)]
    require(len(a) == len(b) == len(error) == 4 and len(weight) == 2
            and weight[0] <= weight[1] and all(e >= 0 for e in error), 'Affine quaternion domain')
    A, B, C = sum(v*v for v in a), sum(v*v for v in b), sum(x*y for x, y in zip(a, b))
    curvature = A-2*C+B
    require(A >= 0 and B >= 0 and C*C <= A*B and curvature >= 0, 'Invalid finite Gram matrix')
    points = list(weight)
    if curvature and weight[0] <= (A-C)/curvature <= weight[1]:
        points.append((A-C)/curvature)
    values = [A*(1-w)**2+2*C*w*(1-w)+B*w*w for w in points]
    norm = perturbed_norm((min(values), max(values[:2])), error) if any(error) else (min(values), max(values[:2]))
    endpoints = [[x+(y-x)*w for x, y in zip(a, b)] for w in weight]
    box = native.Float32Box.outward([float(min(x, y)-e) for x, y, e in zip(*endpoints, error)],
                                     [float(max(x, y)+e) for x, y, e in zip(*endpoints, error)])
    if component_box is not None:
        lower, upper = np.maximum(box.lo, component_box.lo), np.minimum(box.hi, component_box.hi)
        require((lower <= upper).all(), 'Inconsistent quaternion certificate/component intervals')
        box = native.Float32Box(lower, upper)
    certificate = {'identity': identity, 'a': a, 'b': b, 'weight': weight, 'component_error': error,
                   'gram': (A, B, C), 'norm_squared': norm}
    return QuaternionSpan([norm_branch(box, norm, certificate)])


def roundoff_sum(magnitudes):
    """Every source term ordering, with optional multiply-add contraction and FTZ."""
    total = sum(magnitudes)
    error = sum(scalar.rnd(magnitude, 24) for magnitude in magnitudes)
    # Source Hamilton rows add their terms in different orders. Each partial
    # sum is bounded by the full absolute sum, including contracted FMAs.
    for _ in range(len(magnitudes)-1):
        error += scalar.rnd(total+error, 24)
    return error


def box_magnitudes(box):
    return tuple(max(abs(rational(x)), abs(rational(y))) for x, y in zip(box.lo, box.hi))


def hamilton_coefficients(rest):
    x, y, z, w = map(rational, rest)
    return ((w, -z, y, x), (z, w, -x, y), (-y, x, w, z), (-x, -y, -z, w))


def hamilton_branch(rest, branch):
    branch.validate()
    coefficients = hamilton_coefficients(rest)
    cert = branch.certificate
    require('normalization_inverse' not in cert, 'Normalized quaternion is not an affine input')
    magnitudes = box_magnitudes(branch.box)
    errors = tuple(sum(abs(c)*e for c, e in zip(row, cert['component_error']))
                   +roundoff_sum([abs(c)*v for c, v in zip(row, magnitudes)]) for row in coefficients)
    a, b = [tuple(sum(c*v for c, v in zip(row, key)) for row in coefficients)
            for key in (cert['a'], cert['b'])]
    # The exact-real component expression is enclosed before its explicit rounding budget.
    raw = native.quaternion_product_box(native.Float32Box(rest), branch.box)
    rounding = [roundoff_sum([abs(c)*v for c, v in zip(row, magnitudes)]) for row in coefficients]
    component = native.Float32Box.outward(raw.lo-np.array(list(map(float, rounding))),
                                          raw.hi+np.array(list(map(float, rounding))))
    result = affine_quaternion(a, b, cert['weight'], errors, cert['identity'], component).branches[0]
    certificate = {**result.certificate,
        'hamilton_roundoff': cert.get('hamilton_roundoff', [])+[{'rest': tuple(map(rational, rest)),
            'operation_error': tuple(rounding), 'propagated_component_error': errors}]}
    return norm_branch(result.box, result.norm_squared, certificate)


def rounded_norm(branch, stage):
    branch.validate()
    magnitudes = box_magnitudes(branch.box)
    error = roundoff_sum([v*v for v in magnitudes])
    lo, hi = branch.norm_squared
    rounded = (lo-error, hi+error)
    if rounded[0] <= 0:
        raise Unclosed(stage+'_quaternion_norm_contains_zero', norm_squared_interval=json_value(rounded),
                       certificate=json_value(branch.certificate), quaternion_interval=[branch.box.lo.tolist(), branch.box.hi.tolist()])
    return rounded, error


def normalize_branch(branch, rest_norm):
    rounded, dot_error = rounded_norm(branch, 'mixer')
    sqrt_interval = (sqrt_bounds(rounded[0])[0], sqrt_bounds(rounded[1])[1])
    sqrt_error = scalar.rnd(sqrt_interval[1], 24)
    root = (sqrt_interval[0]-sqrt_error, sqrt_interval[1]+sqrt_error)
    inverse = interval_quotient((Q(1), Q(1)), root, 24)
    if root[0] <= 0 or inverse[0] <= 0:
        raise Unclosed('mixer_normalization_rounding_contains_zero', root=json_value(root), inverse=json_value(inverse))
    # D=N+delta: retain the N/D correlation rather than multiplying unrelated ranges.
    lower = branch.norm_squared[0]
    ratio = (lower/(lower+dot_error), lower/(lower-dot_error))
    inv_error = sqrt_error/(sqrt_interval[0]*root[0])+scalar.rnd(1/root[0], 24)
    magnitudes = box_magnitudes(branch.box)
    mul_error = tuple(scalar.rnd(v*max(map(abs, inverse)), 24) for v in magnitudes)
    radial_error = sqrt_bounds(branch.norm_squared[1])[1]*inv_error+sum(mul_error)
    norm = perturbed_norm(ratio, (radial_error,))
    components = [interval_product(box_interval(branch.box[i]), inverse, 24) for i in range(4)]
    box = native.Float32Box.outward([float(v[0]) for v in components], [float(v[1]) for v in components])
    certificate = {**branch.certificate, 'rest_squared_norm': rest_norm,
        'mixer_real_norm_squared': branch.norm_squared, 'mixer_dot_error': dot_error,
        'mixer_rounded_norm_squared': rounded, 'normalization_sqrt': root,
        'normalization_inverse': inverse, 'normalization_radial_error': radial_error, 'norm_squared': norm}
    return norm_branch(box, norm, certificate)


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


# Finite captured instruction results, not an extension of the ideal-acos theorem.
ACOS_WORDS = {('cavalry_rig/Skeleton3D:HindHoof.L', 7): ('3f60e5c3', '3f60e5c4', '3f60e5c5'),
              ('cavalry_rig/Skeleton3D:HindHoof.R', 11): ('3f61a824', '3f61a825', '3f61a826')}
ACOS_KEY_SHA = {'cavalry_rig/Skeleton3D:HindHoof.L': 'efe7d7c47258a786ef9cbb800c9187a07e4c2b68de3d2882f538da41021b8439',
                'cavalry_rig/Skeleton3D:HindHoof.R': '082a661c34fb3987fde982e5e5e453bb6743185eea2dc1581be74577fe1e870d'}
ACOS_BASELINE_SHA = '88e4105d141a055e52737ffe2e6f8e312b37718e69db988d1a6e8db51e0c8947'
ACOS_ENGINE_SHA = 'c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf'


def binary32_word(value):
    return struct.pack('>f', value).hex()


def finite_acos_constant(profile, word, binding):
    require(word in {w for words in ACOS_WORDS.values() for w in words}, 'Uncovered acos constant word')
    require(all(profile.get(k) == v for k, v in scalar.MAC_PROFILE['acosf'].items()),
            'Finite acos instruction/constant profile mismatch')
    # Source instruction words are fixed separately from the receipt's generic theorem.
    recipe = [
        (0xbb3c, '01c0201e', 'fabs s1,s0'), (0xbb40, '02102e1e', 'fmov s2,1'),
        (0xbb44, '2020221e', 'fcmp s1,s2'), (0xbb48, '02102c1e', 'fmov s2,1/2'),
        (0xbb4c, 'c5060054', 'b.pl 0xbc24 (not taken)'), (0xbb50, '2020221e', 'fcmp s1,s2'),
        (0xbb54, '6208001c', 'ldr s2,0xbc60 (flags unchanged)'), (0xbb58, '2c010054', 'b.gt 0xbb7c (taken)'),
        (0xbb7c, '02102e1e', 'fmov s2,1'), (0xbb80, '4138211e', 'fsub s1,s2,s1 (Sterbenz exact)'),
        (0xbb84, '21c0221e', 'fcvt d1,s1 (exact widening)'), (0xbb88, '40080010', 'adr x0,0xbc90'),
        (0xbb8c, '020c406d', 'ldp d2,d3,[x0]'), (0xbb90, '0414416d', 'ldp d4,d5,[x0,16]'),
        (0xbb94, '061c426d', 'ldp d6,d7,[x0,32]'), (0xbb98, '30c0611e', 'fsqrt d16,d1'),
        (0xbb9c, '230c421f', 'fmadd d3,d1,d2,d3'), (0xbba0, '2514441f', 'fmadd d5,d1,d4,d5'),
        (0xbba4, '271c461f', 'fmadd d7,d1,d6,d7'), (0xbba8, '2208611e', 'fmul d2,d1,d1'),
        (0xbbac, '4514431f', 'fmadd d5,d2,d3,d5'), (0xbbb0, '471c451f', 'fmadd d7,d2,d5,d7'),
        (0xbbb4, '0820201e', 'fcmp s0,0'), (0xbbb8, '8c000054', 'b.gt 0xbbc8 (taken)'),
        (0xbbc8, 'e008701e', 'fmul d0,d7,d16'), (0xbbcc, '0040621e', 'fcvt s0,d0')]
    for pc, raw, _ in recipe:
        require(scalar.read_memory(profile, pc, 4).hex() == raw, 'Finite acos branch/instruction mismatch')
    cosine = Q(struct.unpack('>f', bytes.fromhex(word))[0])
    require(Q(1, 2) < cosine < 1, 'Finite acos positive branch predicate')
    t = 1-cosine
    require(Q(np.float32(float(t)).item()) == t and Q(float(t)) == t, 'Inexact Sterbenz subtraction/widening')
    cs = scalar.coefficients(profile, 0xbc90, 6)
    nodes = []

    def node(pc, exact, bits=53):
        lo, hi = exact
        require(scalar.minnormal(bits) <= lo <= hi < 2**100, 'Finite acos intermediate range')
        rounded = rounded_interval(lo, hi, bits)
        require(scalar.minnormal(bits) <= rounded[0] <= rounded[1] < 2**100, 'Finite acos rounded range')
        nodes.append({'pc': hex(pc), 'precision': bits, 'exact_interval': exact, 'rounded_interval': rounded})
        return rounded

    def fma(pc, a, b, c):
        values = [x*y+z for x in a for y in b for z in c]
        return node(pc, (min(values), max(values)))

    # isqrt proves the bracket; this denominator is proof precision, not a tolerance.
    root_exact = sqrt_bounds(t, 2**96)
    require(root_exact[0]**2 <= t <= root_exact[1]**2, 'Finite acos sqrt bracket')
    root = node(0xbb98, root_exact)
    point = lambda x: (x, x)
    a = fma(0xbb9c, point(t), point(cs[0]), point(cs[1]))
    b = fma(0xbba0, point(t), point(cs[2]), point(cs[3]))
    d = fma(0xbba4, point(t), point(cs[4]), point(cs[5]))
    t2 = node(0xbba8, point(t*t))
    h1 = fma(0xbbac, t2, a, b)
    h = fma(0xbbb0, t2, h1, d)
    products = [x*y for x in h for y in root]
    product = node(0xbbc8, (min(products), max(products)))
    output = node(0xbbcc, product, 24)
    record = {'method': 'six-finite-native-acosf-instruction-results-v1', 'input_word': word,
        'input_rational': cosine, 'sterbenz_t': t, 'exact_binary64_widening': t,
        'branch_path': [{'pc': hex(pc), 'bytes': raw, 'instruction': meaning} for pc, raw, meaning in recipe],
        'profile': 'macos-arm64/'+scalar.MAC_ID, 'code_sha256': hashlib.sha256(bytes.fromhex(profile['code'])).hexdigest(),
        'coefficient_bytes': scalar.read_memory(profile, 0xbc90, 48).hex(),
        'coefficient_sha256': hashlib.sha256(scalar.read_memory(profile, 0xbc90, 48)).hexdigest(),
        'coefficients': cs, 'sqrt_rational_bracket': root_exact, 'nodes': nodes, 'omega_interval': output,
        'assumptions': 'IEEE binary32/binary64; every rounding direction; fused fmadd (one rounding); normal positive operands/results make FTZ inactive; no reassociation',
        'binding': dict(binding), 'consumer_algorithm_sha256': native.sha256(__file__)}
    record['sha256'] = canonical_digest(record)
    return record


class ScalarAuthority:
    """Consumer composition of accepted244; never extends a scalar theorem domain.

    Fixed-dot enumeration is phase independent. Only six actual native states
    outside [.9,1] can use finite captured-instruction proofs, bound to their keys.
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
        self.acos_profile = capture['native']['imports'][2][0]
        self.constant_keys = {}
        self.constant_records = {}
        self.constant_digests = {}
        if receipt['engine_sha256'] == ACOS_ENGINE_SHA:
            for track in native_capture.get('tracks', []):
                for index in range(len(track['keys'])-1):
                    identity = (track['path'], index)
                    if identity in ACOS_WORDS:
                        require(track['type'] == 2 and track['interpolation'] != 0, 'Finite acos native key type')
                        keys = tuple(tuple(np.float32(v).item() for v in key['value'])
                                     for key in track['keys'][index:index+2])
                        if canonical_digest(keys) == ACOS_KEY_SHA[track['path']]:
                            self.constant_keys[identity] = keys
        self.binding = {'kind': 'accepted244-scalar-composition-v1', 'receipt': receipt,
                        'capture_sha256': scalar.digest(scalar.canonical(capture)),
                        'verifier_sha256': native.sha256(scalar.__file__)}
        self.cache = {}
        self.cache_digests = {}
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
        cache_key = (track, key_index, tuple(a.lo), tuple(a.hi), tuple(b.lo), tuple(b.hi))
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
                        identity = (track, key_index)
                        words = tuple(binary32_word(c) for c in sorted(set(cosines)))
                        keys = (tuple(a.lo), tuple(b.lo))
                        if (not negative and words == ACOS_WORDS.get(identity)
                                and keys == self.constant_keys.get(identity)
                                and np.array_equal(a.lo, a.hi) and np.array_equal(b.lo, b.hi)):
                            proofs = [finite_acos_constant(self.acos_profile, word, self.binding) for word in words]
                            record['constant_proof_sha256'] = [p['sha256'] for p in proofs]
                            for proof in proofs:
                                self.constant_records[proof['input_word']] = {**proof, 'track': track, 'key_index': key_index,
                                    'source_keys': keys}
                                self.constant_digests[proof['input_word']] = canonical_digest(self.constant_records[proof['input_word']])
                            omega = float_box((min(p['omega_interval'][0] for p in proofs),
                                               max(p['omega_interval'][1] for p in proofs)))
                            record['omega_interval'] = list(box_interval(omega))
                            record['denominator_interval'] = list(self.sine(box_interval(omega), 'sinf'))
                        else:
                            record['unknown'] = 'acos_constant_authority_missing'
                    else:
                        error = Q(self.receipt['theorems']['acosf']['outward_absolute_error'])
                        omega = float_box((acos_endpoint(high)[0]-error, acos_endpoint(low)[1]+error))
                        record['omega_interval'] = list(box_interval(omega))
                        record['denominator_interval'] = list(self.sine(box_interval(omega), 'sinf'))
                result.append(record)
            self.cache[cache_key] = {'dot_states': states, 'branches': result}
            self.cache_digests[cache_key] = canonical_digest(self.cache[cache_key])
            self.work['fixed_dot_states'] += count
        record = self.cache[cache_key]
        require(canonical_digest(record) == self.cache_digests[cache_key], 'Stale/corrupted scalar domain cache')
        for word in ACOS_WORDS.get((track, key_index), ()):
            if word in self.constant_records:
                require(canonical_digest(self.constant_records[word]) == self.constant_digests[word],
                        'Stale/corrupted finite acos proof cache')
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

    def quaternion(self, a, b, weight, scale0, scale1, branch, track, key_index):
        """Native scales differ from (1-w,w) by proved Taylor + machine residuals.

        |sin(v*omega)-v*sin(omega)| <= (|v|^3+|v|)*|omega|^3/6.
        This retains ONE w in the fixed-key Gram polynomial even when the scale
        rectangles independently contain zero. No unit-key or norm=1 assumption.
        """
        wlo, whi = box_interval(weight)
        vmag, wmag = max(abs(1-whi), abs(1-wlo)), max(abs(wlo), abs(whi))
        if not branch['nonlinear']:
            errors = (scalar.rnd(vmag, 24), Q(0))
        else:
            omega = max(map(abs, branch['omega_interval']))
            denominator = branch['denominator_interval'][0]
            require(denominator > 0, 'Nonpositive scalar denominator')
            den_error = Q(self.receipt['theorems']['sinf']['outward_absolute_error'])
            v_error = scalar.rnd(vmag, 53)
            arg_errors = (omega*v_error+scalar.rnd((vmag+v_error)*omega, 53),
                          scalar.rnd(wmag*omega, 24))
            errors = []
            for index, (magnitude, arg_error, scale) in enumerate(zip((vmag, wmag), arg_errors, (scale0, scale1))):
                sine_error = Q(self.receipt['theorems']['sin' if index == 0 else 'sinf']['outward_absolute_error'])
                remainder = (magnitude**3+magnitude)*omega**3/6
                error = (arg_error+sine_error+remainder+magnitude*den_error)/denominator
                # Division then (for scale0) binary64->binary32 conversion.
                quotient_bound = max(map(abs, box_interval(scale)))
                if index == 0:
                    division_error = scalar.rnd(quotient_bound, 53)
                    error += division_error+scalar.rnd(quotient_bound+division_error, 24)
                else:
                    error += scalar.rnd(quotient_bound, 24)
                errors.append(error)
        alpha, beta = max(map(abs, box_interval(scale0))), max(map(abs, box_interval(scale1)))
        av, bv = tuple(map(rational, a.lo)), tuple(map(rational, b.lo))
        require(np.array_equal(a.lo, a.hi) and np.array_equal(b.lo, b.hi), 'Nonconstant quaternion keys')
        rounding = tuple(roundoff_sum([abs(x)*alpha, abs(y)*beta]) for x, y in zip(av, bv))
        residual = tuple(abs(x)*errors[0]+abs(y)*errors[1]+r for x, y, r in zip(av, bv, rounding))
        raw = a*scale0+b*scale1
        component = native.Float32Box.outward(raw.lo-np.array(list(map(float, rounding))),
                                              raw.hi+np.array(list(map(float, rounding))))
        identity = {'track': track, 'key_index': key_index, 'negative': branch['negative'],
                    'nonlinear': branch['nonlinear'], 'scalar_branch': branch, 'source_keys': (av, bv),
                    'scale_error_from_shared_affine_weight': tuple(errors)}
        return affine_quaternion(av, bv, (wlo, whi), residual, identity, component)

    def slerp(self, a, b, weight, track, key_index):
        f, outputs = native.Float32Box, []
        record = self.key_domain(a, b, track, key_index)
        for branch in record['branches']:
            target = -b if branch['negative'] else b
            if not branch['nonlinear']:
                outputs.append(self.quaternion(a, target, weight,
                    float_box(rounded_interval(1-box_interval(weight)[1], 1-box_interval(weight)[0], 24)),
                    weight, branch, track, key_index))
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
            outputs.append(self.quaternion(a, target, weight, scale0, scale1, branch, track, key_index))
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
    if all(isinstance(b, QuaternionSpan) for b in boxes):
        return QuaternionSpan([branch for b in boxes for branch in b.branches])
    require(not any(isinstance(b, QuaternionSpan) for b in boxes), 'Lost quaternion branch certificate')
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
        if track['type'] == 2 and budget.arithmetic is not None:
            value = f(track['keys'][0]['value']).lo
            return affine_quaternion(value, value, (Q(0), Q(0)), (Q(0),)*4,
                                     {'track': track['path'], 'key_index': 0, 'direct_key': True})
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
            outputs.append(affine_quaternion(a.lo, a.lo, (Q(0), Q(0)), (Q(0),)*4,
                {'track': track['path'], 'key_index': i, 'direct_key': True})
                if track['type'] == 2 and budget.arithmetic is not None else a)
            continue
        require(length <= 1, 'Variable native search epsilon needs a separate branch proof')
        delta = np.float32(times[i+1]-times[i])
        weight = f.outward(max(lo, lower)-times[i], min(hi, upper)-times[i])/f(delta)
        if track['type'] != 2:
            outputs.append(a+(b-a)*weight); continue
        if budget.arithmetic is not None:
            outputs.append(budget.arithmetic.slerp(a, b, weight, track['path'], i)); continue
        dot = native.box_dot(a, b, 4)
        # The whole near-identical-key branch is affine in weight.
        if dot.lo*dot.hi > 0 and np.float32(1)-np.float32(min(abs(float(dot.lo)), abs(float(dot.hi)))) <= np.float32(1e-5):
            target = -b if dot.hi < 0 else b
            outputs.append(a*(f(1)-weight)+target*weight); continue
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
    if isinstance(target, QuaternionSpan):
        target.validate()
        rest = tuple(map(rational, f(rest).lo))
        conjugate = tuple(-v if i < 3 else v for i, v in enumerate(rest))
        rest_norm = sum(v*v for v in rest)
        outputs = []
        for branch in target.branches:
            relative = hamilton_branch(conjugate, branch)
            signs = [-1] if relative.box.hi[3] < 0 else ([1] if relative.box.lo[3] >= 0 else [1, -1])
            for sign in signs:
                cert = relative.certificate
                signed = affine_quaternion([sign*v for v in cert['a']], [sign*v for v in cert['b']],
                    cert['weight'], cert['component_error'], {**cert['identity'], 'mixer_sign': sign},
                    relative.box if sign == 1 else -relative.box).branches[0]
                signed = norm_branch(signed.box, signed.norm_squared,
                    {**signed.certificate, 'hamilton_roundoff': cert['hamilton_roundoff']})
                mixed = hamilton_branch(rest, signed)
                require(mixed.certificate['a'] == tuple(sign*rest_norm*v for v in branch.certificate['a'])
                        and mixed.certificate['b'] == tuple(sign*rest_norm*v for v in branch.certificate['b']),
                        'Two-Hamilton exact identity changed')
                outputs.append(normalize_branch(mixed, rest_norm))
        return QuaternionSpan(outputs)
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
    if isinstance(q, QuaternionSpan):
        q.validate()
        return hull([basis_span_box(position, b, scale) for b in q.branches])
    f = native.Float32Box
    if isinstance(q, QuaternionBranch):
        denominator, _ = rounded_norm(q, 'basis')
        components, denominator = q.box, float_box(denominator)
    else:
        components, denominator = q, native.box_dot(q, q, 4)
    q = components
    x, y, z, w = [q[i] for i in range(4)]
    s = f(2)/denominator
    xs, ys, zs = x*s, y*s, z*s
    wx, wy, wz, xx, xy, xz, yy, yz, zz = w*xs, w*ys, w*zs, x*xs, x*ys, x*zs, y*ys, y*zs, z*zs
    b = native.box_stack([native.box_stack([f(1)-(yy+zz), xy-wz, xz+wy]),
                          native.box_stack([xy+wz, f(1)-(xx+zz), yz-wx]),
                          native.box_stack([xz-wy, yz+wx, f(1)-(xx+yy)])])
    diagonal = f(np.diag(scale))
    return native.box_stack([native.box_dot(b, diagonal[:, i], 3) for i in range(3)]+[position], axis=1)



SHAPE_BASELINE_SHA = '10608d454ec204b92433d33e8149e561ef1289bb3f87eb4e6510006e73e290cd'
SHAPE_METHOD = 'shared-native-skin-signed-homogeneous-wedge-with-ordered-lbs-residual-v1'


class SkinSpan(native.Float32Box):
    """Coordinate enclosure plus the actual shared rounded skin matrices."""
    def __init__(self, box, contexts):
        super().__init__(box.lo, box.hi)
        self.skin_contexts = contexts

    outward = staticmethod(native.Float32Box.outward)

    def __getitem__(self, key):
        result = super().__getitem__(key)
        if not isinstance(key, tuple) and np.asarray(result.lo).ndim == 2:
            ids = self.skin_contexts[0]['vertex_ids'][key]
            return SkinSpan(result, [{**c, 'vertex_ids': ids} for c in self.skin_contexts])
        return result


def skin_context(transforms, surface, binds, lo, hi):
    raw = tuple((tuple(map(float, p)), tuple(map(int, j)), tuple(map(float, w)))
                for p, j, w in zip(native.Float32Box(surface['vertices']).lo, surface['joints'], native.Float32Box(surface['weights']).lo))
    identity = {'method': SHAPE_METHOD, 'seconds': [lo, hi],
                'source_sha256': canonical_digest((raw, binds)),
                'matrix_interval': [transforms.lo, transforms.hi]}
    return {'transforms': transforms, 'raw': raw, 'identity': identity,
            'sha256': canonical_digest(identity), 'vertex_ids': np.arange(len(raw)), 'cache': {}}


def validate_skin_context(context):
    require(context['identity']['method'] == SHAPE_METHOD
            and context['sha256'] == canonical_digest(context['identity'])
            and np.array_equal(context['transforms'].lo, context['identity']['matrix_interval'][0])
            and np.array_equal(context['transforms'].hi, context['identity']['matrix_interval'][1]),
            'Stale shared skin correlation certificate')


def skin_vertex_residual(context, vertex_id):
    """Native ordered dot+origin, weight and four accumulations minus exact LBS.

    Matrix entries are the actual already-rounded native values. roundoff_sum
    covers every term ordering/contraction; rnd includes directed rounding/FTZ.
    """
    if vertex_id in context['cache']:
        return context['cache'][vertex_id]
    position, joints, weights = context['raw'][vertex_id]
    position, weights = tuple(map(rational, position)), tuple(map(rational, weights))
    matrices = context['transforms']
    answer = []
    tiny = scalar.minnormal(24)
    for axis in range(3):
        magnitudes, errors = [], []
        for joint, weight in zip(joints, weights):
            row = box_magnitudes(matrices[joint][axis])
            terms = [row[k]*abs(position[k]) for k in range(3)]+[row[3]]
            # Input flushing precedes multiplication; result-only FTZ misses
            # a tiny matrix operand multiplied by a large source coordinate.
            point_error = roundoff_sum(terms)+tiny*(sum(row[:3])+sum(map(abs, position))+6)
            magnitude = sum(terms)*weight
            error = (weight*point_error+scalar.rnd((sum(terms)+point_error)*weight, 24)
                     +tiny*(sum(terms)+point_error+weight))
            magnitudes.append(magnitude); errors.append(error)
        error = sum(errors)
        for _ in range(4):
            error += scalar.rnd(sum(magnitudes)+error, 24)+2*tiny
        answer.append(error)
    context['cache'][vertex_id] = tuple(answer)
    return tuple(answer)


@lru_cache(maxsize=LIMITS['max_constraints'])
def triangle_coefficients(raw):
    influences = []
    for position, joints, weights in raw:
        row = {}
        h = tuple(map(rational, position))+(Q(1),)
        for joint, weight in zip(joints, weights):
            previous = row.setdefault(joint, [Q(0)]*4)
            for k in range(4):
                previous[k] += rational(weight)*h[k]
        influences.append(row)
    edges = []
    for target in (1, 2):
        edges.append(tuple((joint, tuple(influences[target].get(joint, (Q(0),)*4)[k]
            -influences[0].get(joint, (Q(0),)*4)[k] for k in range(4)))
            for joint in sorted(set(influences[0]) | set(influences[target]))))
    return tuple(edges)



@lru_cache(maxsize=LIMITS['max_constraints'])
def triangle_wedge(coefficients):
    maps = [dict(e) for e in coefficients]
    variables = sorted({(joint, k) for e in coefficients for joint, h in e for k, c in enumerate(h) if c})
    terms = []
    for j, k in variables:
        for l, m in variables:
            coefficient = (maps[0].get(j, (Q(0),)*4)[k]*maps[1].get(l, (Q(0),)*4)[m]
                           -maps[1].get(j, (Q(0),)*4)[k]*maps[0].get(l, (Q(0),)*4)[m])
            if coefficient:
                terms.append((j, k, l, m, coefficient))
    return tuple(terms)

def cross_box(a, b):
    return native.box_stack([a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2],
                             a[0]*b[1]-a[1]*b[0]])


def correlated_triangle(box, surface, face):
    require(isinstance(box, SkinSpan), 'Missing shared native skin matrices')
    contexts, crosses, edges_output, residual_output = [], [], [], []
    ids = [int(box.skin_contexts[0]['vertex_ids'][i]) for i in face]
    raw = tuple(box.skin_contexts[0]['raw'][i] for i in ids)
    if surface is not None:
        supplied = tuple((tuple(map(float, native.Float32Box(surface['vertices'][i]).lo)), tuple(map(int, surface['joints'][i])),
                          tuple(map(float, native.Float32Box(surface['weights'][i]).lo))) for i in ids)
        require(supplied == raw, 'Source/bind/raw influence differs from correlation certificate')
    require(len(raw) == 3 and all(len(p) == 3 and len(j) == len(w) == 4
            and np.isfinite(p).all() and np.isfinite(w).all() and min(w) >= 0
            for p, j, w in raw), 'Missing/invalid native triangle influence')
    coefficients = triangle_coefficients(raw)
    for context in box.skin_contexts:
        validate_skin_context(context)
        require(tuple(context['raw'][i] for i in ids) == raw, 'Loop source influence mismatch')
    cache_key = ('triangle', tuple(ids), tuple(c['sha256'] for c in box.skin_contexts))
    cache = box.skin_contexts[0]['cache']
    if cache_key in cache:
        return cache[cache_key]
    for context in box.skin_contexts:
        validate_skin_context(context)
        require(tuple(context['raw'][i] for i in ids) == raw, 'Loop source influence mismatch')
        matrices = context['transforms']; f = native.Float32Box
        require(all(type(joint) is int and 0 <= joint < len(matrices.lo) for _, joints, _ in raw for joint in joints),
                'Missing native bind influence')
        residuals = [skin_vertex_residual(context, i) for i in ids]
        errors = [tuple(residuals[0][k]+residuals[e][k] for k in range(3)) for e in (1, 2)]
        references = []
        for edge in coefficients:
            value = f([0., 0., 0.])
            for joint, h in edge:
                for k, coefficient in enumerate(h):
                    if coefficient:
                        value = value+matrices[joint][:, k]*float_box((coefficient, coefficient))
            references.append(value)
        # Expand the wedge BEFORE interval evaluation. Both edge terms use the
        # same matrix variable; antisymmetric exact coefficients cancel first.
        terms = triangle_wedge(coefficients)
        if terms:
            j, k, l, m, coefficients_ = zip(*terms)
            a, b = np.array([1, 2, 0])[:, None], np.array([2, 0, 1])[:, None]
            first = f(matrices.lo[np.array(j)[None, :], a, np.array(k)[None, :]],
                      matrices.hi[np.array(j)[None, :], a, np.array(k)[None, :]])
            second = f(matrices.lo[np.array(l)[None, :], b, np.array(m)[None, :]],
                       matrices.hi[np.array(l)[None, :], b, np.array(m)[None, :]])
            exact_coefficients = np.asarray(list(map(float, coefficients_)))
            products = first*second*f.outward(exact_coefficients, exact_coefficients)
            reference_cross = f([0., 0., 0.])
            for i in range(len(terms)):
                reference_cross = reference_cross+products[:, i]
        else:
            reference_cross = f([0., 0., 0.])
        delta = [native.Float32Box.outward(-np.array(list(map(float, e))), np.array(list(map(float, e)))) for e in errors]
        cross = reference_cross+cross_box(references[0], delta[1])+cross_box(delta[0], references[1])+cross_box(delta[0], delta[1])
        actual_edges = [r+d for r, d in zip(references, delta)]
        direct = cross_box(*actual_edges)
        cross = f(np.maximum(cross.lo, direct.lo), np.minimum(cross.hi, direct.hi))
        crosses.append(cross)
        contexts.append(context['sha256'])
        edges_output.append([{'interval': [e.lo, e.hi], 'native_residual_absolute': error}
                             for e, error in zip(actual_edges, errors)])
        residual_output.append(residuals)
    cross = hull(crosses)
    minimum = np.where((cross.lo <= 0) & (cross.hi >= 0), 0., np.minimum(abs(cross.lo), abs(cross.hi)))
    maximum = np.maximum(abs(cross.lo), abs(cross.hi))
    squares = native.Float32Box.outward(minimum*minimum, maximum*maximum)
    total = squares[0]+squares[1]+squares[2]
    area = native.Float32Box(np.maximum(total.lo, 0), total.hi).sqrt()
    result = {'method': SHAPE_METHOD, 'vertex_ids': ids, 'raw_vertices_joints_weights': raw,
            'shared_transform_certificates': contexts,
            'edge_coefficients': [[{'bind_index': joint, 'homogeneous': h} for joint, h in edge] for edge in coefficients],
            'branches': [{'edges': edges, 'vertex_native_residual_absolute': residual}
                         for edges, residual in zip(edges_output, residual_output)],
            'edges': edges_output[0], 'cross_interval': [cross.lo, cross.hi],
            'twice_area_interval': [float(max(area.lo, 0)), float(area.hi)]}
    cache[cache_key] = result
    return result




def shape_refutation(proofs, vertices, faces):
    """Actual rows/interiors can refute a bound; they never establish it."""
    triangles = np.asarray(vertices)[np.asarray(faces)]
    crosses = np.cross(triangles[:, 1]-triangles[:, 0], triangles[:, 2]-triangles[:, 0])
    lo = np.asarray([p['cross_interval'][0] for p in proofs])
    hi = np.asarray([p['cross_interval'][1] for p in proofs])
    return np.flatnonzero(np.any((crosses < lo) | (crosses > hi), axis=1)).tolist()

def validate_shape_certificate(proof, certificates):
    """Replay signed coefficients, all native residuals and the normal enclosure."""
    require(proof['method'] == SHAPE_METHOD and len(proof['vertex_ids']) == 3,
            'Shape method/source cardinality')
    raw = [tuple(tuple(v) for v in row) for row in proof['raw_vertices_joints_weights']]
    require(len(raw) == 3, 'Missing raw triangle influences')
    contexts = []
    for digest in proof['shared_transform_certificates']:
        require(digest in certificates, 'Missing shared skin certificate')
        identity = certificates[digest]
        require(canonical_digest(identity) == digest, 'Forged shared skin certificate')
        contexts.append({'identity': identity, 'sha256': digest,
            'transforms': native.Float32Box(*identity['matrix_interval']),
            'raw': dict(zip(proof['vertex_ids'], raw)), 'cache': {},
            'vertex_ids': np.asarray(proof['vertex_ids'])})
    require(1 <= len(contexts) <= 2, 'Missing/extra terminal shape branch')
    box = SkinSpan(native.Float32Box(np.zeros((3, 3))), contexts)
    expected = correlated_triangle(box, None, [0, 1, 2])
    require(json_value(expected) == json_value(proof), 'Shape certificate differs from native residual/wedge replay')

def correlated_shape(current, birth, triangles):
    proofs, unknown, opposite = [], [], []
    for i, face in enumerate(triangles):
        now, anchor = correlated_triangle(current, None, face), correlated_triangle(birth, None, face)
        normal = native.Float32Box(*now['cross_interval'])
        birth_normal = native.Float32Box(*anchor['cross_interval'])
        orientation = native.box_dot(normal, birth_normal, 3)
        proof = {'current': now, 'birth': anchor,
                 'orientation_interval': [float(orientation.lo), float(orientation.hi)]}
        if now['twice_area_interval'][0] <= 0 or orientation.lo <= 0:
            unknown.append(i)
        if orientation.hi < 0:
            opposite.append(i)
        proofs.append(proof)
    return {'min_twice_area_lower_m2': min(p['current']['twice_area_interval'][0] for p in proofs),
            'unclosed_area_or_orientation': unknown, 'opposite_orientation': opposite, 'certificates': proofs,
            'scope': 'Actual rounded native raw-LBS vertices; real model-space triangle area and unchanged birth-normal dot. Common exact proof travel cancels; no world/support/contact inference.'}


TRIANGLE_BASELINE_SHA = 'f7c2a10788370071578b831aa44d4bc63ed49bd27a8d70b1028e3f6449d36188'
REFINEMENT_PARENT = [0.2666666805744171, 0.29999001192092895]


def aggregate_refined_shape(parent, children):
    """Compose closed child bounds before any normal hull, retaining parent proofs."""
    a, b = parent['seconds']; mid = (a+b)/2
    require(len(children) == 2 and [c['seconds'] for c in children] == [[a, mid], [mid, b]],
            'Missing, overlapping or non-midpoint shape children')
    areas, births = [], []
    for child in children:
        if 'reason' not in child:
            require(set(child['triangle_area']) == set(parent['triangle_area'])
                    and set(child['triangle_shape']) == set(parent['triangle_shape']), 'Missing child material patch')
    for hoof, area in parent['triangle_area'].items():
        for index, face in enumerate(area['native_triangle_ids']):
            original = area['certificates'][index]
            bounds, dots, reasons = [], [], []
            birth = parent['triangle_shape'].get(hoof)
            for child in children:
                if 'reason' in child:
                    bounds.append(None); dots.append(None); reasons.append(child['reason']); continue
                current = child['triangle_area'][hoof]
                require(current['native_triangle_ids'] == area['native_triangle_ids']
                        and len(current['certificates']) == len(area['certificates']), 'Changed child material face')
                child_proof = current['certificates'][index]
                require(all(json_value(child_proof.get(k)) == json_value(original.get(k))
                            for k in ('vertex_ids', 'raw_vertices_joints_weights', 'edge_coefficients')),
                        'Changed child raw influence or original face')
                bounds.append(child_proof['twice_area_interval'][0])
                if birth is not None:
                    shape = child['triangle_shape'][hoof]
                    require(shape['native_triangle_ids'] == birth['native_triangle_ids']
                            and len(shape['certificates']) == len(birth['certificates'])
                            and json_value(shape['certificates'][index]['birth']) == json_value(birth['certificates'][index]['birth'])
                            and json_value(shape['certificates'][index]['current']) == json_value(current['certificates'][index]),
                            'Changed original birth anchor or child face')
                    dots.append(shape['certificates'][index]['orientation_interval'][0])
            lower = max(original['twice_area_interval'][0], min(bounds) if None not in bounds else 0.)
            identity = {'hoof': hoof, 'native_triangle_id': face, 'original_local_triangle_index': index}
            area_result = {**identity, 'before': 'CLOSED' if original['twice_area_interval'][0] > 0 else 'UNKNOWN',
                'child_lower_bounds': bounds, 'lower_bound': lower, 'outcome': 'CLOSED' if lower > 0 else 'UNKNOWN',
                'reasons': sorted(set(reasons+(['area_interval_contains_zero'] if lower <= 0 else [])))}
            areas.append(area_result)
            if birth is not None:
                anchor = birth['certificates'][index]
                dot = max(anchor['orientation_interval'][0], min(dots) if None not in dots else anchor['orientation_interval'][0])
                births.append({**identity, 'original_birth_sha256': canonical_digest(anchor['birth']),
                    'before': 'CLOSED' if min(original['twice_area_interval'][0], anchor['orientation_interval'][0]) > 0 else 'UNKNOWN',
                    'child_area_lower_bounds': bounds, 'child_dot_lower_bounds': dots,
                    'area_lower_bound': lower, 'dot_lower_bound': dot,
                    'outcome': 'CLOSED' if min(lower, dot) > 0 else 'UNKNOWN',
                    'reasons': sorted(set(area_result['reasons']+(['birth_dot_interval_nonpositive'] if dot <= 0 else [])))})
    return {'area_targets': areas, 'birth_targets': births}


def refine_selected_shape(capture, surface, binds, functions, budget, used, parent, patches, birth_boxes, samples, matrices):
    require(parent['seconds'] == REFINEMENT_PARENT, 'Wrong selected shape parent')
    require(used['attempts']+2 <= LIMITS['continuous_boxes']
            and used['refinement_splits']+1 <= LIMITS['refinement_splits']
            and used['proposal_evaluations']+6 <= LIMITS['proposal_evaluations'], 'Shape refinement shared budget exhausted')
    before = json_value(used)
    used['refinement_splits'] += 1
    a, b = parent['seconds']; mid = (a+b)/2
    children, refutations = [], []
    for lo, hi in [(a, mid), (mid, b)]:
        used['attempts'] += 1
        try:
            box = surface_span_box(capture, surface, binds, lo, hi, functions, budget)
        except Unclosed as error:
            require('budget' not in error.detail['reason'], 'Shape refinement shared budget exhausted')
            children.append({'seconds': [lo, hi], **error.detail}); continue
        points = []
        for time in [lo, (lo+hi)/2, hi]:
            used['independent_track_evaluations'] += 1; used['proposal_evaluations'] += 1
            value = sampled_points(capture, surface, binds, time)
            require(box.contains(value).all(), 'Shape child interior refutes coordinate enclosure')
            points.append(('adversarial_binary64_interior', time, value))
        points += [('frozen_native_ordered_vertices', s['time'], s['skinned_skeleton_local'][0])
                   for s in samples if lo <= s['time'] <= hi]
        child = {'seconds': [lo, hi], 'triangle_area': {}, 'triangle_shape': {}}
        for hoof, patch in patches.items():
            proofs = [correlated_triangle(box, surface, face) for face in patch['native_triangles']]
            child['triangle_area'][hoof] = {'native_triangle_ids': patch['native_sole_triangles'], 'certificates': proofs,
                'unclosed_area': [i for i, p in enumerate(proofs) if p['twice_area_interval'][0] <= 0]}
            if hoof in parent['triangle_shape']:
                ids = patch['native_sole_vertices']; local = {v: i for i, v in enumerate(ids)}
                faces = [[local[v] for v in face] for face in patch['native_triangles']]
                child['triangle_shape'][hoof] = {**correlated_shape(box[ids], birth_boxes[hoof], faces),
                    'native_triangle_ids': patch['native_sole_triangles']}
            for kind, time, vertices in points:
                require(box.contains(np.asarray(vertices)).all(), 'Shape child native row refutes coordinate enclosure')
                bad = shape_refutation(proofs, vertices, patch['native_triangles'])
                require(not bad, f'Shape child native cross refutation: {hoof} {time} {bad}')
                refutations.append({'kind': kind, 'seconds': time, 'box_seconds': [lo, hi], 'hoof': hoof,
                    'faces_checked': len(proofs), 'violated_native_triangle_ids': []})
        for context in box.skin_contexts:
            validate_skin_context(context); matrices[context['sha256']] = context['identity']
        children.append(child)
    used['float32_weight_values'] = budget.used
    used['scalar_composition'].update(budget.arithmetic.work)
    used['quaternion_norm'].update(bone_span_records=len(budget.norm_records),
        branches=sum(len(v) for v in budget.norm_records.values()))
    used['correlated_triangles'].update(
        child_area_targets=sum(len(a['certificates']) for c in children for a in c.get('triangle_area', {}).values()),
        child_birth_orientation_targets=sum(len(a['certificates']) for c in children for a in c.get('triangle_shape', {}).values()))
    used['correlated_triangles']['cross_refutation_faces'] += sum(r['faces_checked'] for r in refutations)
    require(used['float32_weight_values'] <= LIMITS['float32_weight_values_total'], 'Shape refinement weight budget exhausted')
    return {'parent_seconds': parent['seconds'], 'parent_sha256': canonical_digest(parent),
        'children': children, **aggregate_refined_shape(parent, children),
        'work_before': before, 'native_cross_refutations': refutations}


def validate_refined_shape(report):
    refinement = report['shape_refinement']
    require(report['inputs']['triangle_baseline_report'] == TRIANGLE_BASELINE_SHA
            and report['atlas_input_packet']['triangle_baseline_report_sha256'] == TRIANGLE_BASELINE_SHA
            and len(report['accepted258_input_bindings']) == 803
            and set(report['accepted258_input_bindings']) <= set(report['inputs']), 'Lost accepted258 baseline binding')
    changed = {k for k, v in report['accepted258_input_bindings'].items() if report['inputs'][k] != v}
    require(changed <= {'tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py'},
            'Accepted258 nonalgorithm input changed')
    rows = report['continuous_native']['closed_boxes']
    require(len(rows) == 40 and canonical_digest(rows) == refinement['original_rows_sha256'], 'Original coordinate/target rows changed')
    require(refinement['parent_seconds'] == REFINEMENT_PARENT, 'Wrong selected shape parent')
    parents = [r for r in rows if r['seconds'] == REFINEMENT_PARENT]
    require(len(parents) == 1 and canonical_digest(parents[0]) == refinement['parent_sha256'], 'Stale shape parent')
    expected = aggregate_refined_shape(parents[0], refinement['children'])
    require(len(expected['area_targets']) == 194 and len(expected['birth_targets']) == 148
            and all(refinement[k] == v for k, v in expected.items()), 'Shape aggregation/complete original target map differs')
    before, after = refinement['work_before'], report['work_used']
    successful = sum('reason' not in c for c in refinement['children'])
    require(before['attempts'] == 40 and before['refinement_splits'] == 0 and before['proposal_evaluations'] == 323
            and after['attempts'] == before['attempts']+2
            and after['refinement_splits'] == before['refinement_splits']+1
            and after['proposal_evaluations'] == before['proposal_evaluations']+3*successful
            and after['independent_track_evaluations'] == before['independent_track_evaluations']+3*successful
            and before['float32_weight_values'] <= after['float32_weight_values'] <= LIMITS['float32_weight_values_total']
            and after['attempts'] <= LIMITS['continuous_boxes'] and after['refinement_splits'] <= LIMITS['refinement_splits']
            and after['proposal_evaluations'] <= LIMITS['proposal_evaluations'], 'Reset/omitted shape refinement shared work')
    for key, value in before['scalar_composition'].items():
        if isinstance(value, int):
            require(after['scalar_composition'][key] >= value, 'Reset child scalar work')
    matrices = report['shape_proof']['shared_skin_certificates']
    for child in refinement['children']:
        if 'reason' in child:
            require('budget' not in child['reason'], 'Child budget exhaustion cannot be accepted')
            continue
        for hoof, area in child['triangle_area'].items():
            for index, proof in enumerate(area['certificates']):
                original = parents[0]['triangle_area'][hoof]['certificates'][index]
                sources = {matrices[k]['source_sha256'] for k in original['shared_transform_certificates']}
                require({matrices[k]['source_sha256'] for k in proof['shared_transform_certificates']} == sources,
                        'Child source/bind hash changed')
    require(after['correlated_triangles']['child_area_targets'] == 194*successful
            and after['correlated_triangles']['child_birth_orientation_targets'] == 148*successful
            and 7760+194*successful <= after['correlated_triangles']['area_target_bound']
            and 2797+148*successful <= after['correlated_triangles']['orientation_target_bound'], 'Omitted child shape work')
    work = after['scalar_composition']
    require(work['weight_interval_compositions'] <= work['finite_composition_bound']
            and work['sine_ranges'] <= work['finite_sine_range_bound']
            and work['basic_interval_operations'] <= work['finite_basic_interval_operation_bound']
            and after['quaternion_norm']['bone_span_records'] <= after['quaternion_norm']['finite_bone_span_bound']
            and after['quaternion_norm']['branches'] <= after['quaternion_norm']['finite_branch_bound'],
            'Child operation work budget exhausted')
    require(refinement['native_cross_refutations'] == [r for r in report['shape_proof']['native_cross_refutations']
            if r['box_seconds'] in [c['seconds'] for c in refinement['children']]], 'Missing child refutation work')

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
        if isinstance(rotation, QuaternionSpan):
            budget.norm_records[lo, hi, bone['name']] = [
                {**b.certificate, 'basis_rounded_norm_squared': rounded_norm(b, 'basis')[0]}
                for b in rotation.branches]
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
    result = SkinSpan(result, [skin_context(transforms, surface, binds, lo, hi)])
    if hi == capture['length']:
        # Player fposmod owns the exact terminal as zero; direct queries also
        # expose the terminal key. Keep both, without assuming their equality.
        zero = surface_span_box(capture, surface, binds, 0., 0., functions, budget)
        result = SkinSpan(hull([result, zero]), result.skin_contexts+zero.skin_contexts)
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
            outside, refutation_points = [], []
            for time in [lo, (lo+hi)/2, hi]:
                independent_evaluations += 1
                points = sampled_points(capture, surface, binds, time)
                refutation_points.append((time, points))
                indices = np.argwhere(~box.contains(points))
                if len(indices):
                    outside.append({'seconds': time, 'vertex_components': indices[:16].tolist()})
            if outside:
                raise Unclosed('independent_interior_outside_enclosure', violations=outside,
                               next_input='Resolve concrete native-interpolation/mixer or search-branch counterexample before using this box.')
            closed.append({'seconds': [lo, hi], 'vertex_bounds': box, 'depth': depth, 'refutation_points': refutation_points})
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
    require(type(report['version']) is int and report['version'] in (1, 2, 3, 4, 5, 6, 7), 'Report version')
    if report['version'] in (2, 3, 4, 5, 6, 7):
        binding = report['input_binding']
        require(binding['kind'] == 'native-reacquired-v1' and type(binding['version']) is int
                and binding['version'] == 1, 'Input binding version')
        require(report['step_id'] == ('CAV-CONTACT-PHASE-SHAPE-REFINEMENT' if report['version'] == 7 else 'CAV-CONTACT-PHASE-TRIANGLE-BOUNDS' if report['version'] == 6 else 'CAV-CONTACT-PHASE-ACOS-CONSTANTS' if report['version'] == 5 else 'CAV-CONTACT-PHASE-QUATERNION-NORM' if report['version'] == 4 else ('CAV-CONTACT-PHASE-SLERP-BOUNDS' if report['version'] == 3 else 'CAV-CONTACT-PHASE-INPUT-BINDING'))
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
    if report['version'] in (3, 4, 5, 6, 7):
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
    if report['version'] in (4, 5, 6, 7):
        require(report['inputs']['norm_baseline_report'] == NORM_BASELINE_SHA
                and report['atlas_input_packet']['norm_baseline_report_sha256'] == NORM_BASELINE_SHA,
                'Norm proof/accepted255 binding differs')
        require(len(report['previous_operation_accounting']['coordinate_boxes']) == 19
                and len(report['previous_operation_accounting']['shape_cases']) == 3028
                and len(report['norm_target_replays']) == 8, 'Incomplete accepted255 accounting')
        certificates = report['continuous_native']['quaternion_norm_certificates']
        require(certificates, 'Missing quaternion norm certificates')
        for target in report['norm_target_replays']:
            if target['outcome'] == 'COORDINATE_CLOSED':
                require(any(r['seconds'] == target['original_seconds'] and r['bone'] == target['original_bone']
                            for r in certificates), 'Missing target quaternion certificate')
        for record in certificates:
            require(record['branches'], 'Missing norm proof branches')
            for branch in record['branches']:
                def lower(name):
                    v = branch[name][0]
                    return Q(*v) if isinstance(v, list) else rational(v)
                require(lower('mixer_rounded_norm_squared') > 0 and lower('basis_rounded_norm_squared') > 0
                        and len(branch['hamilton_roundoff']) == 2, 'Unproved norm denominator')
    if report['version'] in (5, 6, 7):
        require(report['inputs']['acos_baseline_report'] == ACOS_BASELINE_SHA
                and report['atlas_input_packet']['acos_baseline_report_sha256'] == ACOS_BASELINE_SHA,
                'Finite acos/accepted256 binding differs')
        require(len(report['accepted256_input_bindings']) == 801
                and set(report['accepted256_input_bindings']) <= set(report['inputs']), 'Lost accepted256 input names')
        require(len(report['previous_norm_accounting']['coordinate_boxes']) == 18
                and len(report['previous_norm_accounting']['shape_cases']) == 3677
                and len(report['acos_target_replays']) == 18, 'Incomplete accepted256 accounting')
        proofs = report['continuous_native']['finite_acos_constants']
        require(len(proofs) == 6 and {p['input_word'] for p in proofs} ==
                {w for words in ACOS_WORDS.values() for w in words}, 'Missing/duplicated finite acos state')
        for proof in proofs:
            identity = (proof['track'], proof['key_index'])
            require(proof['input_word'] in ACOS_WORDS.get(identity, ()), 'Finite acos proof transplanted to another key')
            require(canonical_digest(proof['source_keys']) == ACOS_KEY_SHA[proof['track']], 'Finite acos source keys changed')
            expected = finite_acos_constant(scalar.MAC_PROFILE['acosf'], proof['input_word'], report['arithmetic_proof'])
            # Frozen older proofs bind their own producer, not this replay file.
            expected['consumer_algorithm_sha256'] = report['inputs']['tools/units3d/cavalry_march_phase.py']
            expected['sha256'] = canonical_digest({k: v for k, v in expected.items() if k != 'sha256'})
            require({k: v for k, v in proof.items() if k not in ('track', 'key_index', 'source_keys')} == json_value(expected),
                    'Finite acos proof differs from rounded instruction replay')
        for domain in report['continuous_native']['scalar_domain_records']:
            for branch in domain['branches']:
                if (domain['track'], domain['key_index']) in ACOS_WORDS and branch['nonlinear']:
                    require(not branch['negative'] and 'constant_proof_sha256' in branch
                            and tuple(binary32_word(c) for c in domain['dot_states']) == ACOS_WORDS[domain['track'], domain['key_index']],
                            'Finite acos domain state/branch coverage differs')
                if 'constant_proof_sha256' in branch:
                    matched = [p for p in proofs if (p['track'], p['key_index']) == (domain['track'], domain['key_index'])]
                    require(len(matched) == 3 and branch['constant_proof_sha256'] == [p['sha256'] for p in matched],
                            'Finite acos branch proof coverage differs')
                    omega = float_box((min(Q(*p['omega_interval'][0]) for p in matched),
                                       max(Q(*p['omega_interval'][1]) for p in matched)))
                    require(branch['omega_interval'] == json_value(list(box_interval(omega))), 'Stale finite acos omega hull')
    if report['version'] in (6, 7):
        require(all(report['claims'][k] is False for k in ['success_dependency', 'verified_physical_candidate',
                'phase_runtime_unblocked', 'surface_unblocked', 'contact_certificate'])
                and report['claims']['policy_E'] is None and report['claims']['original_12_gates_preserved'] is True,
                'Diagnostic cannot grant physical acceptance or select E')
        require(report['inputs']['shape_baseline_report'] == SHAPE_BASELINE_SHA
                and report['atlas_input_packet']['shape_baseline_report_sha256'] == SHAPE_BASELINE_SHA
                and report['atlas_input_packet']['shape_method'] == SHAPE_METHOD
                and report['shape_proof']['method'] == SHAPE_METHOD, 'Shape proof/accepted257 binding differs')
        require(len(report['accepted257_input_bindings']) == 802
                and set(report['accepted257_input_bindings']) <= set(report['inputs'])
                and len(report['previous_shape_accounting']['shape_cases']) == 2797,
                'Incomplete accepted257 binding/case accounting')
        matrices = report['shape_proof']['shared_skin_certificates']
        seen, area_count, orientation_count = set(), 0, 0
        patches = report['shape_proof']['full_material_patches']
        require(sum(len(p['native_sole_triangles']) for p in patches.values()) == 194,
                'Incomplete original material faces')
        def check_time(part, seconds):
            actual = [matrices[k]['seconds'] for k in part['shared_transform_certificates']]
            require(actual[0] == seconds and (len(actual) == 1 or
                    (seconds[1] == report['atlas']['clip_seconds'] and actual[1] == [0., 0.])),
                    'Correlation certificate transplanted to another phase/birth reference')
        require(len({f for p in patches.values() for f in p['native_sole_triangles']}) == 194,
                'Duplicated/dropped original material face')
        child_rows = ([c for c in report['shape_refinement']['children'] if 'reason' not in c]
                      if report['version'] == 7 else [])
        for row in report['continuous_native']['closed_boxes']+child_rows:
            require(set(row['triangle_area']) == set(patches), 'Missing full-cycle material area patch')
            for hoof, area in row['triangle_area'].items():
                require(area['native_triangle_ids'] == patches[hoof]['native_sole_triangles']
                        and len(area['certificates']) == len(area['native_triangle_ids']), 'Dropped/changed source area face')
                unknown = []
                for index, proof in enumerate(area['certificates']):
                    require(proof['vertex_ids'] == patches[hoof]['native_triangles'][index], 'Material winding/face changed')
                    check_time(proof, row['seconds'])
                    identity = canonical_digest(proof)
                    if identity not in seen:
                        validate_shape_certificate(proof, matrices); seen.add(identity)
                    if proof['twice_area_interval'][0] <= 0:
                        unknown.append(index)
                    area_count += 1
                require(area['unclosed_area'] == unknown, 'Area nondegeneracy outcome changed')
            for hoof, shape in row['triangle_shape'].items():
                require(shape['native_triangle_ids'] == patches[hoof]['native_sole_triangles']
                        and len(shape['certificates']) == len(shape['native_triangle_ids']), 'Dropped birth-orientation face')
                unknown, opposite = [], []
                for index, proof in enumerate(shape['certificates']):
                    for reference in ('current', 'birth'):
                        part = proof[reference]
                        require(part['vertex_ids'] == patches[hoof]['native_triangles'][index], 'Birth/current winding changed')
                        birth = float(Q(*report['source_support_constraints'][hoof][0]))*report['atlas']['clip_seconds']
                        check_time(part, row['seconds'] if reference == 'current' else [birth, birth])
                        identity = canonical_digest(part)
                        if identity not in seen:
                            validate_shape_certificate(part, matrices); seen.add(identity)
                    dot = native.box_dot(native.Float32Box(*proof['current']['cross_interval']),
                                         native.Float32Box(*proof['birth']['cross_interval']), 3)
                    require(proof['orientation_interval'] == [float(dot.lo), float(dot.hi)], 'Original birth-normal criterion changed')
                    if proof['current']['twice_area_interval'][0] <= 0 or dot.lo <= 0:
                        unknown.append(index)
                    if dot.hi < 0:
                        opposite.append(index)
                    orientation_count += 1
                require(shape['unclosed_area_or_orientation'] == unknown and shape['opposite_orientation'] == opposite,
                        'Birth-orientation outcome changed')
        comparisons = report['shape_proof']['native_cross_refutations']
        require(comparisons and all(not row['violated_native_triangle_ids'] for row in comparisons)
                and {row['kind'] for row in comparisons} == {'adversarial_binary64_interior', 'frozen_native_ordered_vertices'}
                and sum(row['faces_checked'] for row in comparisons) ==
                    report['work_used']['correlated_triangles']['cross_refutation_faces'], 'Native cross refutation missing/failed')
        require(area_count == 194*(40+len(child_rows)) and orientation_count == 2797+148*len(child_rows)
                and report['work_used']['correlated_triangles']['area_targets'] == 7760
                and report['work_used']['correlated_triangles']['birth_orientation_targets'] == 2797,
                'Incomplete full-cycle area/original birth target coverage')
    if report['version'] == 7:
        validate_refined_shape(report)
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
                if isinstance(box, SkinSpan) and isinstance(birth_boxes[hoof], SkinSpan):
                    record['triangle_shape'][hoof] = correlated_shape(box[ids], birth_boxes[hoof], local_triangles)
                else:
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
            'scope': f'Every previous {len(coordinates)} coordinate and {len(shapes)} material shape case retained; uncertainty is not an inversion/impossibility witness.'}


def build(review_path, *, native_manifest=None, bundle_root=None,
          arithmetic_capture=None, arithmetic_receipt=None, baseline_report=None, norm_baseline_report=None,
          acos_baseline_report=None, triangle_baseline_report=None):
    proof_mode = arithmetic_capture is not None
    require((arithmetic_capture is None) == (arithmetic_receipt is None) == (baseline_report is None),
            'Arithmetic capture, receipt and baseline required together')
    require(not proof_mode or native_manifest is not None, 'Arithmetic mode requires explicit accepted native inputs')
    require(proof_mode == (norm_baseline_report is not None), 'Norm mode requires accepted255 baseline')
    require(proof_mode == (acos_baseline_report is not None), 'Finite acos mode requires accepted256 baseline')

    require(triangle_baseline_report is None or proof_mode, 'Shape refinement requires accepted arithmetic mode')
    triangle_baseline = None
    if triangle_baseline_report is not None:
        # The accepted file is hash-bound; its original rows are independently rebuilt below.
        triangle_baseline = native.read_bound(triangle_baseline_report, TRIANGLE_BASELINE_SHA)
        require(triangle_baseline['version'] == 6, 'Expected accepted258 baseline')
        parents = [r for r in triangle_baseline['continuous_native']['closed_boxes'] if r['seconds'] == REFINEMENT_PARENT]
        require(len(parents) == 1 and sum(len(a['certificates']) for a in parents[0]['triangle_area'].values()) == 194
                and sum(len(a['certificates']) for a in parents[0]['triangle_shape'].values()) == 148,
                'Accepted258 selected parent/face inventory differs')

    manifest, capture, surface, binds, patches, supports, functions, witness, context = load_inputs(
        review_path, native_manifest=native_manifest, bundle_root=bundle_root)
    arithmetic = baseline = norm_baseline = acos_baseline = shape_baseline = None
    if proof_mode:
        baseline = native.read_bound(baseline_report, BASELINE_SHA)
        validate_diagnostic(baseline)
        require(baseline['version'] == 2, 'Expected accepted252 baseline')
        norm_baseline = native.read_bound(norm_baseline_report, NORM_BASELINE_SHA)
        validate_diagnostic(norm_baseline)
        require(norm_baseline['version'] == 3, 'Expected accepted255 baseline')
        supplied = reacquired.read_json(acos_baseline_report)
        if supplied.get('version') == 5:
            shape_baseline = native.read_bound(acos_baseline_report, SHAPE_BASELINE_SHA)
            validate_diagnostic(shape_baseline)
            acos_baseline = native.read_bound(Path(shape_baseline['input_locations']['acos_baseline_report']), ACOS_BASELINE_SHA)
        else:
            acos_baseline = native.read_bound(acos_baseline_report, ACOS_BASELINE_SHA)
        validate_diagnostic(acos_baseline)
        require(acos_baseline['version'] == 4, 'Expected accepted256 baseline')
        arithmetic = ScalarAuthority(reacquired.read_json(arithmetic_capture), reacquired.read_json(arithmetic_receipt),
                                     capture, context['binding']['platform_math'])
        arithmetic.binding.update(capture_file_sha256=native.sha256(arithmetic_capture),
                                  receipt_file_sha256=native.sha256(arithmetic_receipt))
        context['locations'].update(arithmetic_capture=str(arithmetic_capture), arithmetic_receipt=str(arithmetic_receipt),
                                    baseline_report=str(baseline_report), norm_baseline_report=str(norm_baseline_report), acos_baseline_report=str(acos_baseline_report))
    require(triangle_baseline is None or shape_baseline is not None, 'Shape refinement requires accepted257 triangle inputs')
    if triangle_baseline is not None:
        context['locations']['triangle_baseline_report'] = str(triangle_baseline_report)
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
        input_packet.update(arithmetic_proof=arithmetic.binding, baseline_report_sha256=BASELINE_SHA,
                            norm_baseline_report_sha256=NORM_BASELINE_SHA, acos_baseline_report_sha256=ACOS_BASELINE_SHA)
    if shape_baseline is not None:
        input_packet.update(shape_baseline_report_sha256=SHAPE_BASELINE_SHA, shape_method=SHAPE_METHOD)
    if triangle_baseline is not None:
        input_packet['triangle_baseline_report_sha256'] = TRIANGLE_BASELINE_SHA
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
    norm_targets = []
    if arithmetic is not None:
        targets = [r for r in norm_baseline['continuous_native']['unclosed_boxes']
                   if r['reason'] == 'mixer_quaternion_norm_contains_zero']
        require(len(targets) == 8, 'Accepted255 norm target cardinality')
        for target in targets:
            lo, hi = target['seconds']
            try:
                replay = surface_span_box(capture, surface, binds, lo, hi, functions, budget)
                outside = []
                for time in [lo, (lo+hi)/2, hi]:
                    bad = np.argwhere(~replay.contains(sampled_points(capture, surface, binds, time)))
                    if len(bad):
                        outside.append({'seconds': time, 'vertex_components': bad[:16].tolist()})
                require(not outside, 'Norm target replay outside full raw geometry box')
                disposition = {'outcome': 'COORDINATE_CLOSED', 'vertices': len(replay.lo), 'refutation_rows': 3}
            except Unclosed as error:
                disposition = {'outcome': 'UNKNOWN', **error.detail}
            norm_targets.append({'original_seconds': target['seconds'], 'original_bone': target['bone'],
                                 'original_reason': target['reason'], **disposition})
    acos_targets = []
    acos_budget = Budget(arithmetic=arithmetic)
    if arithmetic is not None:
        original_work = dict(arithmetic.work)
        targets = acos_baseline['continuous_native']['unclosed_boxes']
        require(len(targets) == 18 and all(t['reason'] == 'acos_constant_authority_missing' for t in targets),
                'Accepted256 acos target identity')
        for target in targets:
            lo, hi = target['seconds']
            try:
                replay = surface_span_box(capture, surface, binds, lo, hi, functions, acos_budget)
                for time in [lo, (lo+hi)/2, hi]:
                    require(replay.contains(sampled_points(capture, surface, binds, time)).all(),
                            'Finite acos target outside full raw geometry box')
                disposition = {'outcome': 'COORDINATE_CLOSED', 'vertices': len(replay.lo), 'refutation_rows': 3}
            except Unclosed as error:
                disposition = {'outcome': 'UNKNOWN', **error.detail}
            acos_targets.append({'original_seconds': target['seconds'], 'original_track': target['track'],
                'original_key_index': target['key_index'], 'original_reason': target['reason'], **disposition})
    if arithmetic is not None:
        finite_work = {k: arithmetic.work[k]-v for k, v in original_work.items()}
        arithmetic.work = original_work
        finite_bound = 18*sum(len(t['keys'])-1 for t in capture['tracks'] if t['type'] == 2)*4
        require(finite_work['weight_interval_compositions'] <= finite_bound
                and finite_work['sine_ranges'] <= 3*finite_bound, 'Finite acos target work bound')
        require(len(acos_budget.norm_records) <= 18*len(capture['bones']), 'Finite acos target bone bound')
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
    shape_contexts, shape_comparisons = {}, []
    if shape_baseline is not None:
        require([r['seconds'] for r in records] == [r['seconds'] for r in shape_baseline['continuous_native']['closed_boxes']]
                and not unclosed, 'Accepted257 coordinate partition changed')
        for item, record in zip(closed, records):
            record['triangle_area'] = {}
            for hoof, patch in patches.items():
                proofs = [correlated_triangle(item['vertex_bounds'], surface, face) for face in patch['native_triangles']]
                record['triangle_area'][hoof] = {'native_triangle_ids': patch['native_sole_triangles'], 'certificates': proofs,
                    'unclosed_area': [i for i, proof in enumerate(proofs) if proof['twice_area_interval'][0] <= 0]}
        for item, record in zip(closed, records):
            lo, hi = item['seconds']
            points = [('adversarial_binary64_interior', t, p) for t, p in item['refutation_points']]
            points += [('frozen_native_ordered_vertices', sample_['time'], sample_['skinned_skeleton_local'][0])
                       for sample_ in samples if lo <= sample_['time'] <= hi]
            for kind, time, vertices in points:
                for hoof, patch in patches.items():
                    proofs = record['triangle_area'][hoof]['certificates']
                    bad = shape_refutation(proofs, vertices, patch['native_triangles'])
                    shape_comparisons.append({'kind': kind, 'seconds': time, 'box_seconds': [lo, hi], 'hoof': hoof,
                        'faces_checked': len(proofs), 'violated_native_triangle_ids': [patch['native_sole_triangles'][i] for i in bad]})
                    require(not bad, f'Native triangle normal refutation: {kind} {time} {hoof} {bad}')
        for box in [r['vertex_bounds'] for r in closed]+list(birth_boxes.values()):
            for c in box.skin_contexts:
                validate_skin_context(c)
                shape_contexts[c['sha256']] = c['identity']
        used['correlated_triangles'] = {'area_targets': sum(len(p['native_sole_triangles']) for p in patches.values())*len(closed),
            'area_target_bound': sum(len(p['native_sole_triangles']) for p in patches.values())*LIMITS['continuous_boxes'],
            'birth_orientation_targets': sum(len(s['native_triangle_ids']) for r in records for s in r['triangle_shape'].values()),
            'orientation_target_bound': sum(len(p['native_sole_triangles']) for p in patches.values())*LIMITS['continuous_boxes'],
            'per_cross_monomial_bound': 3*(3*4*4)**2,
            'cross_refutation_faces': sum(r['faces_checked'] for r in shape_comparisons),
            'cross_refutation_face_bound': (3*LIMITS['continuous_boxes']+2*LIMITS['dense_native_capture_rows'])*194,
            'scope': 'Two signed edges, at most twelve native slot identities/four homogeneous coordinates per face; three fixed wedge sums and at most two terminal contexts. No added subdivision or LIMITS.'}
    evaluations = len(phases)+used['independent_track_evaluations']+len(samples)+sum(r.get('refutation_rows', 0) for r in norm_targets)
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
                      arithmetic_verifier=ARITHMETIC_VERIFIER_SHA, norm_baseline_report=NORM_BASELINE_SHA, acos_baseline_report=ACOS_BASELINE_SHA)
        key_pairs = sum(len(t['keys'])-1 for t in capture['tracks'] if t['type'] == 2 and t['interpolation'] != 0)
        bound = LIMITS['continuous_boxes']*key_pairs*4
        require(arithmetic.work['weight_interval_compositions'] <= bound
                and arithmetic.work['sine_ranges'] <= 3*bound+2*key_pairs
                and arithmetic.work['basic_interval_operations'] <= 6*bound, 'Interval composition work bound')
        require(len(budget.norm_records) <= (LIMITS['continuous_boxes']+len(norm_targets)+1)*len(capture['bones']),
                'Quaternion proof branch-work bound')
        branch_bound = (LIMITS['continuous_boxes']+len(norm_targets)+1)*8*sum(
            len(t['keys']) for t in capture['tracks'] if t['type'] == 2)
        require(sum(len(v) for v in budget.norm_records.values()) <= branch_bound, 'Quaternion fixed-branch work bound')
        used['quaternion_norm'] = {'finite_branch_bound': branch_bound, 'bone_span_records': len(budget.norm_records), 'target_replays': len(norm_targets),
            'branches': sum(len(v) for v in budget.norm_records.values()),
            'finite_bone_span_bound': (LIMITS['continuous_boxes']+len(norm_targets)+1)*len(capture['bones']),
            'scope': 'Fixed search/key/scalar/mixer-sign branches only; original box/refinement/weight/proposal limits unchanged.'}
        used['scalar_composition'] = {**arithmetic.work, 'fixed_key_pairs': key_pairs,
            'dot_states_across_all_key_pairs': sum(len(r['dot_states']) for r in arithmetic.domains.values()),
            'finite_composition_bound': bound,
            'finite_sine_range_bound': 3*bound+2*key_pairs,
            'finite_basic_interval_operation_bound': 6*bound,
            'scope': 'Separate fixed-key/branch range work; original finite-weight counters and all LIMITS unchanged.'}
        used['finite_acos'] = {'constant_proofs': len(arithmetic.constant_records), 'constant_proof_bound': 6,
            'rounded_nodes': sum(len(p['nodes']) for p in arithmetic.constant_records.values()), 'rounded_node_bound': 54,
            'target_replays': len(acos_targets), 'target_replay_bound': 18, 'target_refutation_rows': sum(r.get('refutation_rows', 0) for r in acos_targets),
            'target_refutation_bound': 54, 'target_scalar_work': finite_work, 'target_composition_bound': finite_bound,
            'target_bone_span_records': len(acos_budget.norm_records), 'target_bone_span_bound': 18*len(capture['bones']),
            'scope': 'Additional finite six-state instruction proof and exact accepted256 18-box replays; original counters and LIMITS unchanged.'}
    for path in ['tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py',
                 'tools/units3d/check_cavalry_march_capture.py', 'tools/units3d/measure_unit_bodies.gd',
                 'docs/reviews/cluster-formations/cavalry-march-contact-prerequisite.md']:
        inputs[path if context else str(ROOT/path)] = native.sha256(ROOT/path)
    if arithmetic is not None:
        old_inputs = acos_baseline['inputs']
        require(len(old_inputs) == 801 and set(old_inputs) <= set(inputs), 'Lost accepted256 binding names')
        changed = {k for k, v in old_inputs.items() if inputs[k] != v}
        require(changed <= {'tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py'},
                'Accepted256 nonalgorithm input changed')
    if shape_baseline is not None:
        require(len(shape_baseline['inputs']) == 802 and set(shape_baseline['inputs']) <= set(inputs), 'Lost accepted257 input names')
        require({k for k, v in shape_baseline['inputs'].items() if inputs[k] != v} <=
                {'tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py'}, 'Accepted257 nonalgorithm input changed')
        inputs['shape_baseline_report'] = SHAPE_BASELINE_SHA
    refinement = None
    if triangle_baseline is not None:
        require(json_value(records) == triangle_baseline['continuous_native']['closed_boxes']
                and not unclosed, 'Accepted258 original coordinate/shape results changed')
        require(len(triangle_baseline['inputs']) == 803 and set(triangle_baseline['inputs']) <= set(inputs)
                and {k for k, v in triangle_baseline['inputs'].items() if inputs[k] != v} <=
                    {'tools/units3d/cavalry_march_phase.py', 'tools/units3d/test_cavalry_march_phase.py'},
                'Accepted258 input custody changed')
        used['proposal_evaluations'] = evaluations
        require(json_value(used) == triangle_baseline['work_used'], 'Accepted258 original work counters changed')
        parent = next(r for r in records if r['seconds'] == REFINEMENT_PARENT)
        refinement = refine_selected_shape(capture, surface, binds, functions, budget, used,
            parent, patches, birth_boxes, samples, shape_contexts)
        refinement['original_rows_sha256'] = canonical_digest(records)
        shape_comparisons.extend(refinement['native_cross_refutations'])
        evaluations = used['proposal_evaluations']
        inputs['triangle_baseline_report'] = TRIANGLE_BASELINE_SHA
    return json_value({
        **({'shape_refinement': refinement, 'accepted258_input_bindings': triangle_baseline['inputs']} if refinement else {}),
        **({'input_binding': context['binding'], 'input_locations': context['locations'],
            'atlas_input_packet': input_packet} if context else {}),
        'version': 7 if refinement else 6 if shape_baseline is not None else 5 if arithmetic else (2 if context else 1), 'step_id': 'CAV-CONTACT-PHASE-SHAPE-REFINEMENT' if refinement else 'CAV-CONTACT-PHASE-TRIANGLE-BOUNDS' if shape_baseline is not None else 'CAV-CONTACT-PHASE-ACOS-CONSTANTS' if arithmetic else ('CAV-CONTACT-PHASE-INPUT-BINDING' if context else 'CAV-CONTACT-PHASE'), 'status': 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY',
        **({'arithmetic_proof': arithmetic.binding, 'baseline_accounting': baseline_accounting(baseline, records, unclosed),
            'previous_operation_accounting': baseline_accounting(norm_baseline, records, unclosed),
            'norm_target_replays': norm_targets, 'acos_target_replays': acos_targets,
            'previous_norm_accounting': baseline_accounting(acos_baseline, records, unclosed),
            'accepted256_input_bindings': acos_baseline['inputs']} if arithmetic else {}),
        **({'previous_shape_accounting': baseline_accounting(shape_baseline, records, unclosed),
            'accepted257_input_bindings': shape_baseline['inputs'],
            'shape_proof': {'method': SHAPE_METHOD, 'full_material_patches': patches,
                'shared_skin_certificates': shape_contexts, 'native_cross_refutations': shape_comparisons,
                'birth_reference': 'Unchanged source support start, original native point-fit transform enclosure and winding. Dot uses independent current/birth times in the same skeleton metric.',
                'native_residual': 'Exact captured binary32 raw inputs and shared already-rounded skin matrices; three products/two sums plus origin, weight product and four ordered accumulations. Every rounding direction, optional FMA contraction and FTZ via accepted rnd; no reassociation identity is asserted for native code.'}} if shape_baseline is not None else {}),
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
                                  'finite_acos_constants': list(arithmetic.constant_records.values()),
                                  'acos_target_norm_certificates': [{'seconds': [lo, hi], 'bone': bone, 'branches': branches}
                                      for (lo, hi, bone), branches in acos_budget.norm_records.items()],
                                  'weight_domain_records': list(arithmetic.weight_domains.values()),
                                  'quaternion_norm_certificates': [{'seconds': [lo, hi], 'bone': bone, 'branches': branches}
                                      for (lo, hi, bone), branches in budget.norm_records.items()]} if arithmetic else {}),
                              'closed_boxes': records, 'unclosed_boxes': unclosed,
                              'closed_subset_diameter_upper_m': diameter, 'closed_subset_body_world_sphere_upper_m': body_world,
                              'method': ('Shared-weight exact fixed-key Gram quadratic plus explicit interpolation/Taylor, two-Hamilton/FMA/FTZ and normalization/Basis norm certificates; machine sign branches retained through Basis. Exact rational monotone Taylor sine/acos ranges plus recomputed accepted244 scalar errors, binary64 scale0/binary32 scale1 rounding and FTZ; fixed-dot states all enumerated, full weights enclosed through mixer/Basis/FK/true-bind/raw LBS. Six actual fixed positive acosf states use captured-instruction, all-rounding finite result proofs; every other out-of-domain state stays UNKNOWN.' if arithmetic else 'Outward binary32 track/search/mixer/Basis/FK/true-bind/unnormalized LBS boxes; every finite binary32 slerp weight is enumerated with pinned acosf/sinf/double sin. Exhausted domains stay UNKNOWN. No assumed libm ULP bound, sampled residual allowance, or fast-math reassociation.'),
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
        'reproduction': ({'build': 'python3 tools/units3d/cavalry_march_phase.py build --native-manifest MANIFEST_JSON --bundle-root BUNDLE_ROOT --review-record ACTUAL_RECEIPT_JSON --out REPORT_JSON'+(' --arithmetic-capture SCALAR_CAPTURE --arithmetic-receipt SCALAR_RECEIPT --baseline-report ACCEPTED252_REPORT --norm-baseline-report ACCEPTED255_REPORT --acos-baseline-report '+('ACCEPTED257_REPORT' if shape_baseline is not None else 'ACCEPTED256_REPORT')+(' --triangle-baseline-report ACCEPTED258_REPORT' if refinement else '') if arithmetic else ''),
                          'verify': 'python3 tools/units3d/cavalry_march_phase.py verify REPORT_JSON --native-manifest MANIFEST_JSON --bundle-root BUNDLE_ROOT --review-record ACTUAL_RECEIPT_JSON'+(' --arithmetic-capture SCALAR_CAPTURE --arithmetic-receipt SCALAR_RECEIPT --baseline-report ACCEPTED252_REPORT --norm-baseline-report ACCEPTED255_REPORT --acos-baseline-report '+('ACCEPTED257_REPORT' if shape_baseline is not None else 'ACCEPTED256_REPORT')+(' --triangle-baseline-report ACCEPTED258_REPORT' if refinement else '') if arithmetic else ''),
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
        p.add_argument('--norm-baseline-report', type=Path)
        p.add_argument('--acos-baseline-report', type=Path,
            help='Accepted256 v4 for v5 replay, or accepted257 v5 for correlated-triangle proof.')
        p.add_argument('--triangle-baseline-report', type=Path, help='Hash-bound accepted258 v6 for one selected-parent midpoint refinement.')
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
            require(existing['version'] in ((5, 6, 7) if proof_mode else ((2,) if fresh else (1,)))
                    and (existing['version'] == 7) == (args.triangle_baseline_report is not None), 'Report/input mode mismatch')
        report = build(args.review_record.resolve(),
                       native_manifest=args.native_manifest.resolve() if fresh else None,
                       bundle_root=args.bundle_root.resolve() if fresh else None,
                       arithmetic_capture=args.arithmetic_capture.resolve() if proof_mode else None,
                       arithmetic_receipt=args.arithmetic_receipt.resolve() if proof_mode else None,
                       baseline_report=args.baseline_report.resolve() if proof_mode else None,
                       norm_baseline_report=args.norm_baseline_report.resolve() if args.norm_baseline_report else None,
                       acos_baseline_report=args.acos_baseline_report.resolve() if args.acos_baseline_report else None,
                       triangle_baseline_report=args.triangle_baseline_report.resolve() if args.triangle_baseline_report else None)
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
