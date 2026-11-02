"""Read-only cavalry native provenance audit; numerical observations are not certificates.

Requires the project's existing NumPy. No assets, import settings or policies are written.
"""
import argparse
import csv
import ctypes
import ctypes.util
import hashlib
import json
import math
import platform
import shutil
import struct
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GLB = "assets/3D/units/cavalry/cavalry.glb"
SCENE = "scenes/models/units/cavalry.tscn"
FROZEN = {
    'native': '30d69f07b6d76d155b7af33f40e62b7a32c774fd413fa76fcdfeb05d67d82308',
    'geometry': '4960509ddaae535d5deabdf687976dbba5a93f64ecc8674541efbac8d45a19bd',
    'witness': '00ea96475bf9887176479b7867bb6e2ac5a903a915c0d55bff50743b3b903583',
    'source': '01b7340791391919ea84f766db2f8d727e95e8b8e8f1c183ac7512193befd38d',
    'glb': 'bb82ae98905f336d9d36aadb09df54e97d0f5e52d0bb43152a998fdaadb803ed',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_bound(path, digest):
    require(sha256(path) == digest, f"Input hash mismatch: {path}")
    return json.loads(Path(path).read_text(), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))


def finite(values, width=None):
    result = np.asarray(values, dtype=np.float64)
    require(np.isfinite(result).all(), "Nonfinite numeric input")
    if width is not None:
        require(result.ndim == 2 and result.shape[1] == width, "Invalid array width")
    return result


def read_glb(path):
    data = Path(path).read_bytes()
    require(28 <= len(data) <= 64 * 1024 * 1024, "Invalid GLB size")
    magic, version, size, length, kind = struct.unpack_from('<5I', data)
    require((magic, version, size, kind) == (0x46546c67, 2, len(data), 0x4e4f534a), "Invalid GLB header")
    require(length % 4 == 0 and 20 + length + 8 <= size, "Invalid JSON chunk")
    document = json.loads(data[20:20 + length])
    n, kind = struct.unpack_from('<2I', data, 20 + length)
    require(kind == 0x004e4942 and n + length + 28 == size, "Invalid BIN chunk")
    require(len(document['buffers']) == 1 and 'uri' not in document['buffers'][0], "External GLB buffer")
    require(0 <= n - document['buffers'][0]['byteLength'] <= 3, "Invalid buffer length")
    return document, data[28 + length:]


def accessor(document, binary, index):
    a = document['accessors'][index]
    require('sparse' not in a and not a.get('normalized', False), "Unsupported sparse/normalized accessor")
    view = document['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    dtype = np.dtype({5126: '<f4', 5123: '<u2', 5125: '<u4', 5121: 'u1'}[a['componentType']])
    count = a['count']
    stride = view.get('byteStride', width * dtype.itemsize)
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    end = offset + (count - 1) * stride + width * dtype.itemsize
    require(view.get('buffer', 0) == 0 and count > 0 and stride >= width * dtype.itemsize,
            "Invalid accessor count/stride")
    require(offset >= view.get('byteOffset', 0) and end <= view.get('byteOffset', 0) + view['byteLength'] <= len(binary),
            "Accessor outside buffer view")
    result = np.ndarray((count, width), dtype=dtype, buffer=binary, offset=offset,
                        strides=(stride, dtype.itemsize)).copy()
    require(np.isfinite(result).all(), "Nonfinite accessor")
    return result


def import_weights(weights):
    w = finite(weights, 4).astype(np.float32)
    require((w >= 0).all(), "Negative weight")
    total = np.zeros(len(w), dtype=np.float32)
    for i in range(4):
        total = total + w[:, i]
    require((total > 0).all(), "Empty skin weight")
    w = w / total[:, None]
    return (np.floor(w * np.float32(65535)) / np.float32(65535)).astype(np.float32)


def interpolate(times, values, time, *, rotation=False, step=False, native_length=None):
    t, v = finite(times), finite(values)
    require(t.ndim == 1 and len(t) == len(v) and len(t) > 0 and (np.diff(t) > 0).all(), "Invalid track keys")
    require(math.isfinite(time), "Nonfinite sample time")
    if rotation:
        require(v.ndim == 2 and v.shape[1] == 4 and np.all(np.abs(np.linalg.norm(v, axis=1) - 1) < 1e-5), "Invalid quaternion")
    i = max(0, min(len(t) - 1, int(np.searchsorted(t, time, side='right')) - 1))
    if native_length is not None:
        require(t[0] == 0 and (len(t) == 1 or t[-1] == native_length) and 0 <= time <= native_length,
                "Native clip needs explicit complete seam endpoints")
        # Pinned Animation::_find uses CMP_EPSILON, including before a key and the loop seam.
        low, high = 0, len(t) - 1
        while low <= high:
            middle = (low + high) // 2
            if abs(time - t[middle]) < max(1e-5, 1e-5 * abs(time)):
                i = middle
                break
            if time < t[middle]:
                high = middle - 1
            else:
                low = middle + 1
    if i == len(t) - 1 or time <= t[0] or step:
        return v[i].copy()
    f = (time - t[i]) / (t[i + 1] - t[i])
    if native_length is not None:
        f = float(np.float32(np.float32(time - t[i]) / np.float32(t[i + 1] - t[i])))
    a, b = v[i], v[i + 1]
    if not rotation:
        return a * (1 - f) + b * f
    dot = float(a @ b)
    if dot < 0:
        dot, b = -dot, -b
    if 1 - dot > 1e-5:
        angle = math.acos(min(1, dot))
        return (a * math.sin((1 - f) * angle) + b * math.sin(f * angle)) / math.sin(angle)
    return a * (1 - f) + b * f


def matrix(flat):
    a = np.eye(4)
    a[:3] = finite(flat).reshape(3, 4)
    return a


def trs(position, rotation, scale):
    x, y, z, w = finite(rotation)
    # Basis(Quaternion) divides by length_squared, also for the linear slerp branch.
    n = x*x + y*y + z*z + w*w
    require(n > 0, "Zero quaternion")
    s = 2 / n
    a = np.eye(4)
    a[:3, :3] = [[1-s*(y*y+z*z), s*(x*y-z*w), s*(x*z+y*w)],
                 [s*(x*y+z*w), 1-s*(x*x+z*z), s*(y*z-x*w)],
                 [s*(x*z-y*w), s*(y*z+x*w), 1-s*(x*x+y*y)]]
    a[:3, :3] *= finite(scale)[None, :]
    a[:3, 3] = finite(position)
    return a


def skin(surface, transforms):
    vertices, weights = finite(surface['vertices'], 3), finite(surface['weights'], 4)
    joints = finite(surface['joints'], 4)
    transforms = finite(transforms)
    require(len(vertices) == len(weights) == len(joints) and transforms.shape[1:] == (4, 4), "Skin dimensions")
    require((joints == np.floor(joints)).all() and (joints >= 0).all() and (joints < len(transforms)).all(), "Skin joint domain")
    require((weights >= 0).all(), "Negative skin weight")
    points = np.column_stack((vertices, np.ones(len(vertices))))
    deformed = np.einsum('nkij,nj->nki', transforms[joints.astype(int), :3], points)
    return np.einsum('nki,nk->ni', deformed, weights)


def topology(raw, native):
    """Full corner identity and oriented face multiset; never a position-only match."""
    def keys(s, weights):
        p, uv = finite(s['vertices'], 3), finite(s['uv'], 2)
        j = finite(s['joints'], 4)
        require(len(p) == len(uv) == len(j) == len(weights), "Attribute cardinality")
        require((j >= 0).all() and (j == np.floor(j)).all(), "Invalid bone index")
        return [tuple(row) for row in np.column_stack((p.astype(np.float32), uv.astype(np.float32), j, weights))]
    raw_keys, native_keys = keys(raw, import_weights(raw['weights'])), keys(native, finite(native['weights'], 4).astype(np.float32))
    require(Counter(raw_keys) == Counter(native_keys), "Raw/native corner attribute mismatch")
    def triangles(indices, count):
        a = finite(indices)
        require(a.ndim == 1 and len(a) % 3 == 0 and (a == np.floor(a)).all()
                and (a >= 0).all() and (a < count).all(), "Invalid triangle indices")
        return a.astype(int).reshape(-1, 3)
    rt = triangles(raw['indices'], len(raw_keys))
    nt = triangles(native['indices'], len(native_keys))[:, ::-1]
    def labels(a, b):
        ids = {key: i for i, key in enumerate(sorted(set(a) | set(b)))}
        return [ids[x] for x in a], [ids[x] for x in b]
    ra, na = labels(raw_keys, native_keys)
    for _ in range(len(ra)):
        def refine(lab, faces):
            incident = [[] for _ in lab]
            for a, b, c in faces:
                for x, y, z in [(a, b, c), (b, c, a), (c, a, b)]:
                    incident[x].append((lab[y], lab[z]))
            return [(v, tuple(sorted(incident[i]))) for i, v in enumerate(lab)]
        before = len(set(ra))
        ra, na = labels(refine(ra, rt), refine(na, nt))
        require(Counter(ra) == Counter(na), "Incident triangle topology mismatch")
        if len(set(ra)) == before or len(set(ra)) == len(ra):
            break
    groups = defaultdict(list)
    for i, key in enumerate(ra):
        groups[key].append(i)
    # Remaining true symmetries are resolved deterministically, then proved by the full face multiset.
    mapping = [groups[key].pop(0) for key in na]
    nt = np.array(mapping)[nt]
    def oriented(t):
        x = tuple(t)
        return min(x, x[1:] + x[:1], x[2:] + x[:2])
    require(Counter(map(oriented, rt)) == Counter(map(oriented, nt)), "Triangle coverage/orientation mismatch")
    return {'native_to_raw': mapping, 'triangles': len(rt), 'vertices': len(mapping),
            'position_duplicate_vertices': len(raw_keys) - len(set(tuple(x) for x in raw['vertices']))}


def source_parts(raw, source):
    require(np.array_equal(source['matrix_world'], np.eye(4)), "Unsupported source mesh transform")
    vertices = finite(source['vertices'], 3)[:, [0, 2, 1]]
    vertices[:, 2] *= -1  # Blender Z-up -> glTF Y-up, determinant +1.
    uv = finite(source['triangle_uv']).astype(np.float32)
    uv[:, :, 1] = np.float32(1) - uv[:, :, 1]
    triangles = finite(source['triangles'], 3)
    require((triangles == np.floor(triangles)).all(), "Fractional source index")
    triangles = triangles.astype(int)
    parts = source['parts']
    require(len(parts) == len(vertices) and triangles.shape == (len(uv), 3), "Source geometry dimensions")
    require((triangles >= 0).all() and (triangles < len(vertices)).all(), "Source triangle domain")
    lookup, faces = defaultdict(set), []
    def canonical(corners):
        corners = tuple(corners)
        return min(corners, corners[1:] + corners[:1], corners[2:] + corners[:2])
    for i, triangle in enumerate(triangles):
        corners = []
        for j, vertex in enumerate(triangle):
            key = tuple(vertices[vertex].astype(np.float32)) + tuple(uv[i, j])
            lookup[key].add(parts[vertex])
            corners.append(key)
        faces.append(canonical(corners))
    keys = [tuple(p) + tuple(u) for p, u in zip(finite(raw['vertices'], 3).astype(np.float32),
                                               finite(raw['uv'], 2).astype(np.float32))]
    require(all(len(lookup[k]) == 1 for k in keys), "Source anatomical corner identity missing or ambiguous")
    target_faces = [canonical([keys[i] for i in t]) for t in np.asarray(raw['indices']).reshape(-1, 3)]
    require(Counter(faces) == Counter(target_faces), "Source/raw triangle coverage/orientation mismatch")
    return [next(iter(lookup[k])) for k in keys]


def sole_patch(raw, parts, part):
    """Whole source-labeled hoof shell and every downward-facing rest-space facet.

    This is an explicit geometric underside candidate. Anatomical/ground contact
    acceptance still needs the native-window review; no height or passing-slip filter.
    """
    vertices = finite(raw['vertices'], 3)
    triangles = np.asarray(raw['indices']).reshape(-1, 3)
    labels = np.asarray(parts)[triangles]
    shell = np.flatnonzero((labels == part).all(axis=1))
    require(len(shell) and not ((labels == part).any(axis=1) & ~(labels == part).all(axis=1)).any(),
            "Missing hoof or mixed anatomical triangle")
    p = vertices[triangles]
    normals = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    require((np.linalg.norm(normals[shell], axis=1) > 0).all(), "Degenerate hoof triangle")
    sole = shell[normals[shell, 1] < 0]
    require(len(sole) > 0, "Empty sole surface")
    return {'source_part': int(part), 'shell_triangles': shell.tolist(),
            'shell_vertices': sorted(set(triangles[shell].ravel().tolist())),
            'sole_triangles': sole.tolist(), 'sole_vertices': sorted(set(triangles[sole].ravel().tolist()))}


def validate_patch(raw, parts, part, patch):
    require(patch == sole_patch(raw, parts, part), "Incomplete or forged anatomical patch")


def raw_surface(document, binary):
    require(len(document['meshes']) == 1 and len(document['meshes'][0]['primitives']) == 1, "Unexpected raw surfaces")
    primitive = document['meshes'][0]['primitives'][0]
    require(primitive.get('mode', 4) == 4, "Expected triangles")
    attributes = primitive['attributes']
    result = {name: accessor(document, binary, attributes[semantic]) for name, semantic in
              [('vertices', 'POSITION'), ('normals', 'NORMAL'), ('uv', 'TEXCOORD_0'),
               ('joints', 'JOINTS_0'), ('weights', 'WEIGHTS_0')]}
    result['indices'] = accessor(document, binary, primitive['indices']).ravel()
    return result


def raw_tracks(document, binary):
    animation = [a for a in document['animations'] if a['name'] == 'MARCH']
    require(len(animation) == 1, "Expected one raw MARCH")
    result = {}
    for channel in animation[0]['channels']:
        sampler = animation[0]['samplers'][channel['sampler']]
        key = (document['nodes'][channel['target']['node']]['name'], channel['target']['path'])
        require(key not in result and sampler.get('interpolation', 'LINEAR') in ('LINEAR', 'STEP'), "Unsupported or duplicate raw track")
        result[key] = {'times': accessor(document, binary, sampler['input']).ravel(),
                       'values': accessor(document, binary, sampler['output']),
                       'step': sampler.get('interpolation', 'LINEAR') == 'STEP'}
    return result


def native_tracks(native):
    result = {}
    for track in native['tracks']:
        key = (track['path'].split(':')[-1], {1: 'translation', 2: 'rotation', 3: 'scale'}[track['type']])
        require(key not in result and track['enabled'] and track['interpolation'] in (0, 1), "Unsupported native track")
        require(all(k['transition'] == 1 for k in track['keys']), "Nonlinear native key easing")
        result[key] = {'times': np.array([k['time'] for k in track['keys']]),
                       'values': np.array([k['value'] for k in track['keys']]), 'step': track['interpolation'] == 0}
    return result


def pose(bones, tracks, time, native_length=None):
    locals_, globals_ = [], []
    for i, bone in enumerate(bones):
        components = []
        for kind, default in [('translation', 'default_position'), ('rotation', 'default_rotation'), ('scale', 'default_scale')]:
            channel = tracks.get((bone['name'], kind))
            components.append(bone[default] if channel is None else interpolate(channel['times'], channel['values'], time,
                                                                               rotation=kind == 'rotation', step=channel['step'],
                                                                               native_length=native_length))
        local = trs(*components)
        parent = bone['parent']
        require(-1 <= parent < i, "Invalid or non-topological bone hierarchy")
        locals_.append(local)
        globals_.append(local if parent < 0 else globals_[parent] @ local)
    return np.array(locals_), np.array(globals_)


def forward_kinematics(bones, locals_):
    require(len(bones) == len(locals_), "Pose cardinality")
    result = []
    for i, local in enumerate(locals_):
        parent = bones[i]['parent']
        require(-1 <= parent < i, "Invalid parent")
        result.append(local if parent < 0 else result[parent] @ local)
    return np.array(result)


class Float32Box:
    """IEEE binary32 outward enclosure, not an empirically chosen error allowance.

    Endpoints include the exact real operation AND its rounded result. Thus each
    expression also encloses multiply-add contraction. Binary64 nextafter before
    binary32 directed conversion protects division/sqrt and endpoint evaluation.
    No overflow, division through zero, reassociation or transcendental assumption.
    """
    def __init__(self, lo, hi=None):
        self.lo = finite(lo).astype(np.float32).astype(float)
        self.hi = self.lo if hi is None else finite(hi).astype(np.float32).astype(float)
        require(np.isfinite(self.lo).all() and np.isfinite(self.hi).all()
                and (self.lo <= self.hi).all(), 'Invalid float32 enclosure')

    @classmethod
    def outward(cls, lo, hi):
        lo, hi = np.nextafter(lo, -np.inf), np.nextafter(hi, np.inf)
        lower, upper = np.asarray(lo, dtype=np.float32), np.asarray(hi, dtype=np.float32)
        lower = np.where(lower.astype(float) > lo, np.nextafter(lower, np.float32(-np.inf)), lower)
        upper = np.where(upper.astype(float) < hi, np.nextafter(upper, np.float32(np.inf)), upper)
        return cls(lower, upper)

    def __getitem__(self, key):
        return Float32Box(self.lo[key], self.hi[key])

    def __neg__(self):
        return Float32Box(-self.hi, -self.lo)

    def __add__(self, other):
        return self.outward(self.lo + other.lo, self.hi + other.hi)

    def __sub__(self, other):
        return self + -other

    def __mul__(self, other):
        products = np.broadcast_arrays(self.lo * other.lo, self.lo * other.hi,
                                       self.hi * other.lo, self.hi * other.hi)
        return self.outward(np.minimum.reduce(products), np.maximum.reduce(products))

    def __truediv__(self, other):
        require(((other.lo > 0) | (other.hi < 0)).all(), 'Division enclosure contains zero')
        quotients = np.broadcast_arrays(self.lo / other.lo, self.lo / other.hi,
                                        self.hi / other.lo, self.hi / other.hi)
        return self.outward(np.minimum.reduce(quotients), np.maximum.reduce(quotients))

    def sqrt(self):
        require((self.lo >= 0).all(), 'Negative sqrt enclosure')
        return self.outward(np.sqrt(self.lo), np.sqrt(self.hi))

    def contains(self, actual):
        actual = finite(actual)
        return (self.lo <= actual) & (actual <= self.hi)


def box_stack(values, axis=0):
    return Float32Box(np.stack([v.lo for v in values], axis), np.stack([v.hi for v in values], axis))


def box_dot(a, b, count):
    result = a[..., 0] * b[..., 0]
    for i in range(1, count):
        result = result + a[..., i] * b[..., i]
    return result


def system_math():
    """Use the captured platform's actual libm functions; assume no libm ULP budget."""
    library = ctypes.CDLL(ctypes.util.find_library('m'))
    functions = {}
    for name in ['acosf', 'sinf', 'sin']:
        function = getattr(library, name)
        number = ctypes.c_double if name == 'sin' else ctypes.c_float
        function.argtypes, function.restype = [number], number
        functions[name] = function
    return functions


def math_runtime_identity(functions):
    require(sys.platform == 'darwin' and platform.machine() == 'arm64', 'Captured native libm requires macOS arm64 replay')

    class ImageInfo(ctypes.Structure):
        _fields_ = [('path', ctypes.c_char_p), ('base', ctypes.c_void_p),
                    ('symbol', ctypes.c_char_p), ('address', ctypes.c_void_p)]

    lookup = ctypes.CDLL(None).dladdr
    lookup.argtypes, lookup.restype = [ctypes.c_void_p, ctypes.POINTER(ImageInfo)], ctypes.c_int
    images = {}
    for name, function in functions.items():
        info = ImageInfo()
        require(lookup(ctypes.cast(function, ctypes.c_void_p), ctypes.byref(info)) != 0, 'Unidentified libm image')
        header = ctypes.string_at(info.base, 32)
        magic, _, _, _, commands, size, _, _ = struct.unpack('<8I', header)
        require(magic == 0xfeedfacf and size < 1024*1024, 'Unexpected native libm image header')
        data, offset, uuid = ctypes.string_at(info.base+32, size), 0, None
        for _ in range(commands):
            command, length = struct.unpack_from('<II', data, offset)
            require(length >= 8 and offset+length <= size, 'Malformed libm load command')
            if command == 0x1b:
                uuid = data[offset+8:offset+24].hex()
            offset += length
        require(uuid is not None, 'Native libm has no build UUID')
        images[name] = {'image': info.path.decode(), 'mach_o_uuid': uuid}
    return {'platform': platform.platform(), 'functions': images,
            'scope': 'Actual platform function replay; no assumed transcendental ULP bound or continuous time enclosure.'}


def native_track_box(track, time, length, functions):
    """Replay every possible rounded dot in slerp, then enclose its multiply-adds.

    The finite enumeration is of floating-point intermediate values, not times.
    libm results are native-platform operation replay, NOT bounds on ideal sin/acos.
    """
    times = [key['time'] for key in track['keys']]
    values = [key['value'] for key in track['keys']]
    require(times[0] == 0 and (len(times) == 1 or times[-1] == length)
            and 0 <= time <= length, 'Unaccounted native track seam')
    if len(times) == 1:
        return Float32Box(values[0])
    low, high, index = 0, len(times)-1, 0
    while low <= high:
        middle = (low + high) // 2
        if abs(time-times[middle]) < max(1e-5, 1e-5*abs(time)):
            index = middle
            break
        if time < times[middle]:
            high = middle-1
        else:
            index, low = middle, middle+1
    a, b = Float32Box(values[index]), Float32Box(values[(index+1) % len(times)])
    if track['interpolation'] == 0:
        return a
    delta = np.float32(times[index+1]-times[index]) if index+1 < len(times) else np.float32(0)
    weight = np.float32(0) if abs(delta) < 1e-5 else np.float32(np.float32(time-times[index]) / delta)
    if track['type'] != 2:
        return a + (b-a) * Float32Box(weight)
    return slerp_box(a, b, weight, functions)


def slerp_box(a, b, weight, functions):
    dot = box_dot(a, b, 4)
    candidate, last = np.float32(dot.lo), np.float32(dot.hi)
    outputs = []
    # Near-unit adjacent keys yield a small finite set. A larger domain stays unknown.
    while candidate <= last:
        require(len(outputs) < 256, 'Slerp dot domain needs a larger explicit proof, not a tolerance')
        cosine, target = abs(candidate), -b if candidate < 0 else b
        if np.float32(1)-cosine > np.float32(1e-5):
            omega = functions['acosf'](float(cosine)) if cosine <= 1 else 0.
            denominator = functions['sinf'](omega)
            require(denominator != 0, 'Slerp denominator zero')
            # This is the source's DOUBLE overload for scale0 and FLOAT for scale1.
            scale0 = np.float32(functions['sin']((1.-float(weight))*omega) / denominator)
            scale1 = np.float32(functions['sinf'](float(np.float32(weight*np.float32(omega)))) / denominator)
        else:
            scale0, scale1 = np.float32(1)-weight, weight
        outputs.append(a*Float32Box(scale0) + target*Float32Box(scale1))
        candidate = np.nextafter(candidate, np.float32(np.inf))
    return Float32Box(np.minimum.reduce([v.lo for v in outputs]), np.maximum.reduce([v.hi for v in outputs]))


def normalize_box(q):
    return q * (Float32Box(1) / box_dot(q, q, 4).sqrt())


def imported_key_box(raw, time, rotation, functions):
    # GLTFDocument::_interpolate_track receives FLOAT time, and double key times.
    time = float(np.float32(time))
    times = raw['times']
    # GLTFAccessor::decode_as_quaternions normalizes even endpoint keys.
    values = [normalize_box(Float32Box(v)) if rotation else Float32Box(v) for v in raw['values']]
    index = int(np.searchsorted(times, time, side='right'))-1
    if index < 0 or index >= len(times)-1 or raw['step']:
        return values[max(0, index)]
    weight = np.float32((time-times[index])/(times[index+1]-times[index]))
    a, b = values[index], values[index+1]
    return normalize_box(slerp_box(a, b, weight, functions)) if rotation else a+(b-a)*Float32Box(weight)


def quaternion_product_box(a, b):
    x, y, z, w = [a[i] for i in range(4)]
    u, v, s, t = [b[i] for i in range(4)]
    return box_stack([w*u+x*t+y*s-z*v, w*v+y*t+z*u-x*s,
                      w*s+z*t+x*v-y*u, w*t-x*u-y*v-z*s])


def mixer_rotation_box(rest, target):
    rest, target = Float32Box(rest), Float32Box(target)
    relative = quaternion_product_box(rest * Float32Box([-1, -1, -1, 1]), target)
    # At weight=1 the two sin(omega) calls are identical: scales are exactly 0,1.
    # Include both short-arc branches if the outward box straddles w=0.
    if relative.hi[3] < 0:
        relative = -relative
    elif relative.lo[3] < 0:
        relative = Float32Box(np.minimum(relative.lo, -relative.hi), np.maximum(relative.hi, -relative.lo))
    mixed = quaternion_product_box(rest, relative)
    return normalize_box(mixed)


def basis_box(position, rotation, scale):
    q = Float32Box(rotation)
    x, y, z, w = [q[i] for i in range(4)]
    s = Float32Box(2) / box_dot(q, q, 4)
    xs, ys, zs = x*s, y*s, z*s
    wx, wy, wz, xx, xy, xz, yy, yz, zz = w*xs, w*ys, w*zs, x*xs, x*ys, x*zs, y*ys, y*zs, z*zs
    one = Float32Box(1)
    basis = box_stack([box_stack([one-(yy+zz), xy-wz, xz+wy]),
                       box_stack([xy+wz, one-(xx+zz), yz-wx]),
                       box_stack([xz-wy, yz+wx, one-(xx+yy)])])
    # Basis::set_quaternion_scale multiplies the rotation by a diagonal basis.
    diagonal = Float32Box(np.diag(scale))
    columns = [box_dot(basis, diagonal[:, i], 3) for i in range(3)]
    return box_stack(columns + [Float32Box(position)], axis=1)


def affine_box(a, b):
    columns = [box_dot(a[:, :3], b[:, i], 3) for i in range(4)]
    columns[3] = columns[3] + a[:, 3]
    return box_stack(columns, axis=1)


def operation_enclosures(native, sample, surface, binds, functions):
    """Validate each arithmetic boundary against its own captured input, no fitted epsilon."""
    stages = defaultdict(list)

    def check(name, enclosure, actual):
        actual = finite(actual).astype(np.float32).astype(float)
        stages[name].append({'outside_components': int(np.count_nonzero(~enclosure.contains(actual))),
                             'component_count': int(actual.size),
                             'max_interval_width': float(np.max(enclosure.hi - enclosure.lo))})

    for i, track in enumerate(native['tracks']):
        check('requested_track_platform_replay', native_track_box(track, sample['time'], native['length'], functions), sample['track_values'][i])
        value = sample['player_track_values'][i]
        check('player_track_platform_replay', native_track_box(track, sample['player_time'], native['length'], functions), value)
        bone_id = next(i for i, b in enumerate(native['bones']) if b['name'] == track['path'].split(':')[-1])
        bone, pose_components = native['bones'][bone_id], sample['pose_components'][bone_id]
        if track['type'] == 2:
            check('mixer_rotation', mixer_rotation_box(bone['rest_rotation'], value), pose_components['rotation'])
        elif track['type'] == 1:
            initial = Float32Box(matrix(bone['rest'])[:3, 3])
            check('mixer_position', initial + (Float32Box(value) - initial), pose_components['position'])
        else:
            raise ValueError('Unaccounted mixer track type')
    for i, (bone, pc) in enumerate(zip(native['bones'], sample['pose_components'])):
        check('basis', basis_box(pc['position'], pc['rotation'], pc['scale']), matrix(sample['locals'][i])[:3])
        local = Float32Box(matrix(sample['locals'][i])[:3])
        parent = bone['parent']
        global_box = local if parent < 0 else affine_box(Float32Box(matrix(sample['globals'][parent])[:3]), local)
        check('hierarchy', global_box, matrix(sample['globals'][i])[:3])
    transforms = box_stack([affine_box(Float32Box(matrix(g)[:3]), Float32Box(bind[:3]))
                            for g, bind in zip(sample['globals'], binds)])
    vertices, joints, weights = Float32Box(surface['vertices']), np.asarray(surface['joints'], dtype=int), Float32Box(surface['weights'])
    accumulated = Float32Box(np.zeros((len(joints), 3)))
    for i in range(4):
        transform = transforms[joints[:, i]]
        point = box_dot(transform[:, :, :3], vertices[:, None, :], 3) + transform[:, :, 3]
        accumulated = accumulated + point * weights[:, i, None]
    check('bind_and_cpu_lbs', accumulated, sample['skinned_skeleton_local'][0])
    return {name: {'outside_components': sum(v['outside_components'] for v in values),
                   'component_count': sum(v['component_count'] for v in values),
                   'max_interval_width': max(v['max_interval_width'] for v in values)}
            for name, values in stages.items()}


def import_operation_enclosures(document, raw_tracks_, target_tracks, native, functions):
    nodes = {node['name']: node for node in document['nodes'] if 'name' in node}
    keys, dropped, rests = [], [], []
    for (name, kind), track in raw_tracks_.items():
        if (name, kind) in target_tracks:
            target = target_tracks[name, kind]
            for time, value in zip(target['times'], target['values']):
                box = imported_key_box(track, time, kind == 'rotation', functions)
                keys.append({'bone': name, 'component': kind, 'time': float(time),
                             'outside_components': int(np.count_nonzero(~box.contains(np.float32(value))))})
        else:
            default = {'translation': [0, 0, 0], 'rotation': [0, 0, 0, 1], 'scale': [1, 1, 1]}[kind]
            base = Float32Box(nodes[name].get(kind, default))
            distance = 0.
            for value in track['values']:
                box = Float32Box(value)
                if kind == 'rotation':
                    box = normalize_box(normalize_box(box))
                difference = box-base
                distance = max(distance, float(np.max(np.maximum(abs(difference.lo), abs(difference.hi)))))
            # CMP_EPSILON is the pinned importer's comparison rule, never a contact allowance.
            dropped.append({'bone': name, 'component': kind, 'comparison_abs_difference_upper': distance,
                            'engine_immutable_comparison_proven': distance < float(np.float32(1e-5))})
    for bone in native['bones']:
        node = nodes[bone['name']]
        box = basis_box(node.get('translation', [0, 0, 0]), node.get('rotation', [0, 0, 0, 1]), node.get('scale', [1, 1, 1]))
        rests.append({'bone': bone['name'], 'outside_components': int(np.count_nonzero(
            ~box.contains(np.float32(matrix(bone['rest'])[:3]))))})
    return {'retained_keys': keys, 'removed_tracks': dropped, 'node_to_rest': rests,
            'covered': all(k['outside_components'] == 0 for k in keys+rests)
                       and all(d['engine_immutable_comparison_proven'] for d in dropped)}


def track_accounting(source, target, native):
    rows = []
    defaults = {b['name']: b for b in native['bones']}
    for (name, component), raw in source.items():
        imported = target.get((name, component))
        row = {'bone': name, 'component': component, 'source_keys': len(raw['times']),
               'source_interpolation': 'STEP' if raw['step'] else 'LINEAR'}
        if imported is None:
            default = defaults[name][{'translation': 'default_position', 'rotation': 'default_rotation', 'scale': 'default_scale'}[component]]
            delta = raw['values'] - default
            if component == 'rotation':
                delta = np.where((raw['values'] @ default < 0)[:, None], -raw['values'], raw['values']) - default
            row.update(operation='removed_immutable_track_uses_native_default', native_default=default,
                       max_source_default_component_difference=float(np.max(np.abs(delta))))
        else:
            removed = sorted(set(map(float, raw['times'])) - set(map(float, imported['times'])))
            key_residual, sign_flips = 0., 0
            for time, value in zip(imported['times'], imported['values']):
                expected = interpolate(raw['times'], raw['values'], time, rotation=component == 'rotation', step=raw['step'])
                if component == 'rotation' and expected @ value < 0:
                    expected, sign_flips = -expected, sign_flips + 1
                key_residual = max(key_residual, float(np.max(np.abs(value - expected))))
            branches = Counter()
            if component == 'rotation':
                for a, b in zip(imported['values'], imported['values'][1:]):
                    dot = float(a @ b)
                    branches[('sign_flip_' if dot < 0 else '') + ('slerp' if 1 - abs(dot) > 1e-5 else 'linear')] += 1
            row.update(operation='key_reduction' if removed else 'retained', native_keys=len(imported['times']),
                       value_operations=['GLTFAccessor normalized quaternion decode',
                                         'GLTFDocument slerp then normalization'] if component == 'rotation' else ['GLTFDocument linear interpolation'],
                       removed_seconds=removed, retained_key_max_component_residual=key_residual,
                       equivalent_quaternion_sign_flips=sign_flips, interpolation_branches=dict(branches),
                       seam_first_last_component_delta=(imported['values'][-1] - imported['values'][0]).tolist())
        rows.append(row)
    require(set(target) <= set(source), "Native track has no raw source")
    return rows


def frozen_witness(native_path, geometry_path, witness_path):
    old = read_bound(native_path, FROZEN['native'])
    geometry = read_bound(geometry_path, FROZEN['geometry'])['surfaces'][0]
    observation = read_bound(witness_path, FROZEN['witness'])
    surface = {'vertices': geometry['vertices'], 'joints': np.array(geometry['bones']).reshape(-1, 4),
               'weights': np.array(geometry['weights']).reshape(-1, 4)}
    points = []
    for phase in [.137, .25]:
        sample = next(s for s in old['samples'] if s['phase'] == phase)
        transforms = [matrix(sample['globals'][b['name']]) @ matrix(b['pose']) for b in old['skin']]
        points.append(skin(surface, transforms))
    delta = points[1] - points[0] + [0, 0, 5.9 * (.25 - .137)]
    index = observation['witness']['vertex']
    measured = float(np.linalg.norm(delta[index, [0, 2]]))
    # Compare independent arithmetic with the retained diagnostic, never a physical tolerance.
    require(math.isclose(measured, observation['witness']['horizontal_slip_model_m'], abs_tol=2e-15, rel_tol=0),
            "Frozen witness replay changed")
    require(np.allclose(delta[index], observation['witness']['displacement_model_m'], atol=2e-15, rtol=0),
            "Frozen witness vector changed")
    return {'vertex': index, 'phases': [.137, .25], 'stride_model_m': 5.9,
            'native_positions': [p[index].tolist() for p in points], 'displacement_model_m': delta[index].tolist(),
            'horizontal_slip_model_m': measured, 'status': 'ADVERSE_WITNESS_REPRODUCED_NOT_CERTIFICATE',
            'old79': {'count': 79, 'slip_range_model_m': observation['witness']['region_slip_min_max_model_m'],
                      'membership': 'Not supplied by frozen observations; not promoted to a complete patch.'}}


def audit(capture_dir, source_path, frozen_native, frozen_geometry, witness_path, views_path=None):
    native_path, samples_path = capture_dir / 'native.json', capture_dir / 'samples.jsonl'
    native = read_bound(native_path, sha256(native_path))
    source = read_bound(source_path, sha256(source_path))
    require(sha256(ROOT / GLB) == FROZEN['glb'] and source['source_sha256'] == FROZEN['source'], "Unexpected installed/source asset")
    require(sha256(source['source_file']) == FROZEN['source'], "Frozen Blender source changed")
    require(native['version'] == 2 and len(native['surfaces']) == 1 and len(native['bones']) == 53
            and len(native['skin']) == 53, "Incomplete native capture")
    functions = system_math()
    runtime = math_runtime_identity(functions)
    build = subprocess.check_output(['/usr/bin/sw_vers', '-buildVersion'], text=True).strip()
    require(native['runtime'] == {'os': 'macOS', 'build': build, 'arm64': True, 'double_precision': False},
            'Native capture/platform arithmetic mismatch')
    runtime['os_build'] = build
    require(not any(t['compressed'] for t in native['tracks']), 'Compressed tracks need separate operation accounting')
    for path, digest in native['input_hashes'].items():
        if path != 'project.godot':
            require(sha256(ROOT / path) == digest, f"Capture input changed: {path}")
    require(np.array_equal(matrix(native['mesh_to_skeleton']), np.eye(4)), "Nonidentity mesh conversion requires explicit accounting")
    require(native['loop_mode'] == 1 and all(t['loop_wrap'] for t in native['tracks']), "Unaccounted native loop policy")
    g, binary = read_glb(ROOT / GLB)
    raw, imported = raw_surface(g, binary), dict(native['surfaces'][0])
    imported['joints'] = np.array(imported['joints']).reshape(-1, 4)
    imported['weights'] = np.array(imported['weights']).reshape(-1, 4)
    require(len(imported['vertices']) == 21175 and len(imported['indices']) == 57141, "Incomplete native geometry")
    require(imported['primitive'] == 3 and finite(imported['normals'], 3).shape == (21175, 3)
            and finite(imported['tangents']).shape == (21175 * 4,), "Incomplete native surface attributes")
    mapping = topology(raw, imported)
    order = np.array(mapping['native_to_raw'])
    parts = source_parts(raw, source)
    patches = {}
    with (ROOT / 'tools/units3d/cavalry_tripo/tripo_parts.csv').open() as file:
        for row in csv.DictReader(file):
            label = row['role']
            if ' hoof' not in label:
                continue
            name = ('Front' if 'fore' in label else 'Hind') + 'Hoof.' + ('L' if 'near' in label else 'R')
            patch = sole_patch(raw, parts, int(row['part']))
            inverse = np.argsort(order)
            patch['native_shell_vertices'] = sorted(inverse[patch['shell_vertices']].tolist())
            patch['native_sole_vertices'] = sorted(inverse[patch['sole_vertices']].tolist())
            raw_faces = np.asarray(raw['indices']).reshape(-1, 3)
            selected = {tuple(sorted(x)) for x in raw_faces[patch['sole_triangles']]}
            patch['native_sole_triangles'] = [i for i, t in enumerate(order[np.asarray(imported['indices']).reshape(-1, 3)])
                                               if tuple(sorted(t)) in selected]
            patch['source_description'] = label
            patches[name] = patch
    require(set(patches) == {'HindHoof.L', 'HindHoof.R', 'FrontHoof.L', 'FrontHoof.R'}, "Incomplete four-hoof provenance")
    raw_names = [g['nodes'][j]['name'] for j in g['skins'][0]['joints']]
    require(raw_names == [b['name'] for b in native['bones']], "Raw/native named bone mapping changed")
    aliases = {'Head': 'head_h', 'R_Head': 'head'}
    require(set(aliases.get(name, name) for name in source['bone_names']) == set(raw_names), "Source bone alias coverage mismatch")
    parents = {child: i for i, n in enumerate(g['nodes']) for child in n.get('children', [])}
    joints = g['skins'][0]['joints']
    for i, node in enumerate(joints):
        expected_parent = joints.index(parents[node]) if parents[node] in joints else -1
        require(native['bones'][i]['parent'] == expected_parent, "Raw/native bone hierarchy mismatch")
    rig = next(n for n in g['nodes'] if n['name'] == 'cavalry_rig')
    root_transform = trs(rig.get('translation', [0, 0, 0]), rig.get('rotation', [0, 0, 0, 1]), rig.get('scale', [1, 1, 1]))
    require(np.array_equal(root_transform, matrix(native['skeleton_global']))
            and np.array_equal(root_transform, matrix(native['mesh_global'])), "Installed scene node transform mismatch")
    raw_bind = accessor(g, binary, g['skins'][0]['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    binds = np.array([matrix(b['pose']) for b in native['skin']])
    require(raw_names == [b['name'] for b in native['skin']] and np.array_equal(raw_bind, binds), "Inverse bind or alias disagreement")
    require([b['resolved_bone'] for b in native['skin']] == list(range(53)), "Named Skin resolution mismatch")
    source_tracks, target_tracks = raw_tracks(g, binary), native_tracks(native)
    accounting = track_accounting(source_tracks, target_tracks, native)
    import_enclosures = import_operation_enclosures(g, source_tracks, target_tracks, native, functions)
    default_tracks = {k: v for k, v in source_tracks.items() if k in target_tracks}
    raw_ordered = {k: v[order] for k, v in raw.items() if k != 'indices'}
    rows, new_witness = [], {}
    for line in samples_path.open():
        sample = json.loads(line)
        time = sample['time']
        _, raw_global = pose(native['bones'], source_tracks, time)
        _, dropped_global = pose(native['bones'], default_tracks, time)
        _, reduced_global = pose(native['bones'], target_tracks, time)
        reconstructed_local, reconstructed_global = pose(native['bones'], target_tracks, time, native['length'])
        require(sample['player_time'] == time % native['length'], 'Native player loop-time mismatch')
        _, player_global = pose(native['bones'], target_tracks, sample['player_time'], native['length'])
        actual_global = np.array([matrix(m) for m in sample['globals']])
        actual_local = np.array([matrix(m) for m in sample['locals']])
        evaluated_tracks = {key: {'times': [0.], 'values': [sample['player_track_values'][i]], 'step': False}
                            for i, key in enumerate(target_tracks)}
        _, track_global = pose(native['bones'], evaluated_tracks, 0.)
        component_locals = [trs(pc['position'], pc['rotation'], pc['scale']) for pc in sample['pose_components']]
        component_global = forward_kinematics(native['bones'], component_locals)
        local_global = forward_kinematics(native['bones'], actual_local)
        stages = [skin(raw_ordered, raw_global @ raw_bind), skin(raw_ordered, dropped_global @ raw_bind),
                  skin(raw_ordered, reduced_global @ binds), skin(raw_ordered, reconstructed_global @ binds),
                  skin(imported, reconstructed_global @ binds),
                  skin(imported, player_global @ binds),
                  skin(imported, track_global @ binds), skin(imported, component_global @ binds),
                  skin(imported, local_global @ binds),
                  skin(imported, actual_global @ binds), finite(sample['skinned_skeleton_local'][0], 3)]
        differences = [np.linalg.norm(b - a, axis=1) for a, b in zip(stages, stages[1:])]
        row = {'time': time, 'phase': sample['phase'],
               'max_vertex_delta_by_operation_m': {k: float(v.max()) for k, v in zip(
                   ['removed_tracks', 'import_key_normalization_and_reduction', 'native_key_search_and_float32_fraction', 'quantized_weights', 'player_loop_time',
                    'native_track_arithmetic_residual', 'native_mixer_arithmetic_residual', 'native_basis_arithmetic_residual',
                    'native_fk_arithmetic_residual', 'native_cpu_lbs_residual'], differences)},
               'native_pose_arithmetic_residual_m': float(np.linalg.norm(stages[5] - stages[9], axis=1).max()),
               'max_local_component_residual': float(np.max(np.abs(actual_local - reconstructed_local))),
               'raw_native_max_vertex_distance_m': float(np.linalg.norm(stages[0] - stages[9], axis=1).max()),
               'player_time': sample['player_time']}
        row['operation_enclosures'] = operation_enclosures(native, sample, imported, binds, functions)
        rows.append(row)
        if sample['phase'] in (.137, .25):
            new_witness[str(sample['phase'])] = stages[9][16496].tolist()
    require([r['time'] for r in rows] == native['sample_times_seconds'], "Missing or reordered native samples")
    for a, b in zip(native['span_boundaries_seconds'], native['span_boundaries_seconds'][1:]):
        require(any(a < r['time'] < b for r in rows), "Unobserved track span")
    frozen = frozen_witness(frozen_native, frozen_geometry, witness_path)
    require(set(new_witness) == {'0.137', '0.25'}, "Missing required current witness phases")
    for i, phase in enumerate(['0.137', '0.25']):
        require(np.allclose(new_witness[phase], frozen['native_positions'][i], rtol=0, atol=2e-15),
                "Current/frozen native witness disagreement; do not widen this arithmetic replay check")
    payload = {'topology': mapping, 'patches': patches, 'tracks': accounting, 'spans': rows,
               'import_operation_enclosures': import_enclosures}
    encoded = json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()
    digest = hashlib.sha256(encoded).hexdigest()
    detail = capture_dir.parent / f'accounting-{digest}.json'
    if detail.exists():
        require(detail.read_bytes() == encoded, "Immutable accounting payload collision")
    else:
        detail.write_bytes(encoded)
    inputs = {str(p.resolve()): sha256(p) for p in [native_path, samples_path, source_path, Path(source['source_file']), frozen_native,
                                                  frozen_geometry, witness_path, detail]}
    views = None
    if views_path is not None:
        views = read_bound(views_path, sha256(views_path))
        require(views['native_sha256'] == sha256(native_path), 'View/native provenance mismatch')
        visual_detail = capture_dir.parent / ('accounting-' + views['accounting_sha256'] + '.json')
        visual_payload = read_bound(visual_detail, views['accounting_sha256'])
        require(visual_payload['topology'] == mapping and visual_payload['patches'] == patches,
                'View anatomical topology or patch definition changed')
        inputs[str(visual_detail.resolve())] = views['accounting_sha256']
        require(views['display_server'] != 'headless' and views['renderer'] == 'forward_plus', 'Views are not native Forward+ window captures')
        expected = {(name, phase, view, mode) for name in patches for phase in [0., .137]
                    for view in ['underside', 'oblique'] for mode in ['native', 'source_parts', 'candidate_edges']}
        require(len(views['rows']) == len(expected) and
                {(r['hoof'], r['phase'], r['view'], r['mode']) for r in views['rows']} == expected, 'Incomplete anatomical views')
        inputs[str(views_path.resolve())] = sha256(views_path)
        for row in views['rows']:
            require(Path(row['file']).name == row['file'], 'Unsafe view filename')
            picture = views_path.parent / row['file']
            require(sha256(picture) == row['sha256'] and row['size'] == [2560, 1600], 'Changed or wrong-sized native view')
            inputs[str(picture.resolve())] = row['sha256']
    probe = Path(native['project_root'])
    for path, digest in native['input_hashes'].items():
        require(sha256(probe / path) == digest, f"Retained capture project input changed: {path}")
        inputs[str(probe / path)] = digest
    require(sha256(native['engine_executable']) == native['engine_executable_sha256'], "Captured engine executable changed")
    inputs[native['engine_executable']] = native['engine_executable_sha256']
    engine_sources = capture_dir.parent / 'engine-source/sources-v2.json'
    engine_refs = read_bound(engine_sources, sha256(engine_sources))
    inputs[str(engine_sources.resolve())] = sha256(engine_sources)
    for name, reference in engine_refs.items():
        path = engine_sources.parent / name
        require(sha256(path) == reference['sha256'] and native['engine']['hash'] in reference['url'], "Unbound engine source")
        inputs[str(path.resolve())] = reference['sha256']
    for path in [GLB, GLB + '.import', SCENE, 'tools/units3d/cavalry_rig/install.py',
                 'tools/units3d/cavalry_rig/actions.py', 'tools/units3d/cavalry_tripo/tripo_parts.csv',
                 'tools/units3d/archer_arp/pivot_import.gd', 'tools/units3d/cavalry_march_capture.gd',
                 'tools/units3d/cavalry_march_capture.gd.uid', 'tools/units3d/check_cavalry_march_capture.py',
                 'tools/units3d/test_cavalry_march_capture.py']:
        inputs[str(ROOT / path)] = sha256(ROOT / path)
    maxima = {key: max(r['max_vertex_delta_by_operation_m'][key] for r in rows)
              for key in rows[0]['max_vertex_delta_by_operation_m']}
    operation_summary = {name: {'outside_components': sum(r['operation_enclosures'][name]['outside_components'] for r in rows),
                               'component_count': sum(r['operation_enclosures'][name]['component_count'] for r in rows),
                               'max_sample_interval_width': max(r['operation_enclosures'][name]['max_interval_width'] for r in rows)}
                         for name in rows[0]['operation_enclosures']}
    numerical_covered = import_enclosures['covered'] and all(v['outside_components'] == 0 for v in operation_summary.values())
    return {'version': 1, 'step_id': 'CAV-CONTACT-NATIVE', 'status': 'BLOCKED_NOT_ACCEPTED',
            'engine': native['engine'], 'inputs': inputs, 'accounting_payload': str(detail.resolve()),
            'engine_source_references': engine_refs,
            'reproduction': {'prepare': 'python3 tools/units3d/check_cavalry_march_capture.py prepare NEW_PROBE',
                             'import': 'SHARED_GODOT_LOCK python3 tools/run_with_timeout.py 300 GODOT --headless --path NEW_PROBE --editor --import',
                             'capture': 'SHARED_GODOT_LOCK python3 tools/run_with_timeout.py 300 GODOT --headless --path NEW_PROBE --script res://tools/units3d/cavalry_march_capture.gd -- --out ABSOLUTE_NEW_CAPTURE',
                             'source': 'BLENDER --background --factory-startup --disable-autoexec FROZEN_BLEND --python tools/units3d/check_cavalry_march_capture.py -- source NEW_SOURCE_JSON',
                             'views': 'SHARED_GODOT_LOCK python3 tools/run_with_timeout.py 300 GODOT --path NEW_PROBE --script res://tools/units3d/cavalry_march_capture.gd -- --views ABSOLUTE_NEW_VIEWS --native NATIVE_JSON --accounting ACCOUNTING_JSON (normal window; never headless)',
                             'audit': 'python3 tools/units3d/check_cavalry_march_capture.py audit CAPTURE SOURCE_JSON --frozen-native FROZEN_NATIVE --frozen-geometry FROZEN_GEOMETRY --witness FROZEN_WITNESS --out MANIFEST',
                             'verify': 'python3 tools/units3d/check_cavalry_march_capture.py verify MANIFEST',
                             'exit_status': '2 means unresolved acceptance, including an identical replay of a blocked report. Never a PASS.'},
            'capture_directory': str(capture_dir.resolve()), 'source_geometry': str(source_path.resolve()),
            'views_manifest': str(views_path.resolve()) if views_path is not None else None,
            'native_view_evidence': {'images': len(views['rows']), 'legend': views['legend'], 'limits': views['limits'],
                                     'independent_review': 'PENDING_UNASSIGNED_SOLE_REVIEW'} if views else None,
            'frozen_paths': {'native': str(frozen_native.resolve()), 'geometry': str(frozen_geometry.resolve()),
                             'witness': str(witness_path.resolve())},
            'topology': {k: v for k, v in mapping.items() if k != 'native_to_raw'},
            'bones': len(raw_names), 'source_triangles': len(source['triangles']), 'sample_count': len(rows),
            'source_bone_aliases': aliases,
            'track_span_count': len(native['span_boundaries_seconds']) - 1,
            'loop_time_rule': 'AnimationPlayer::_process_playback_data applies fposmod; the exact length maps to zero. Direct track queries retain the terminal key. Both paths are captured and separately enclosed.',
            'track_operations': dict(Counter(r['operation'] for r in accounting)),
            'max_vertex_delta_by_operation_m': maxima,
            'numerical_accounting': {'status': 'SAMPLED_OPERATIONS_ENCLOSED' if numerical_covered else 'UNEXPLAINED_RESIDUAL',
                                     'platform_math': runtime, 'stages': operation_summary,
                                     'import_operations_covered': import_enclosures['covered'],
                                     'retained_key_count': len(import_enclosures['retained_keys']),
                                     'method': 'Outward binary32 endpoints include exact arithmetic and rounded/FMA results. Enumerate all binary32 dot intermediates, replay pinned-platform acosf/sinf/sin (including double scale0); enclose mixer/rest normalization, basis, affine FK, bind and four unnormalized influences.',
                                     'limits': 'Per-operation checks at captured times, not an interval over time or a physical error budget. No fast-math reassociation assumed. No libm ULP allowance assumed. Platform mismatch rejects replay.'},
            'native_pose_arithmetic_residual_m': max(r['native_pose_arithmetic_residual_m'] for r in rows),
            'patch_counts': {k: {name: len(v[name]) for name in ['shell_vertices', 'shell_triangles', 'sole_vertices', 'sole_triangles']}
                             for k, v in patches.items()},
            'patch_definition': 'Every source-labeled hoof shell triangle retained; candidate underside is every nondegenerate rest-space facet with outward normal Y<0. No low-height, weight, slip or success filter.',
            'frozen_witness': frozen, 'current_native_witness_positions': new_witness,
            'unresolved': ([] if numerical_covered else ['Native import/runtime operations fall outside independently derived arithmetic enclosures.']) +
                          ['Geometric underside candidates retain full source shells but are not independently accepted complete anatomical material patches.',
                           'Native anatomical images await the unique Review; no independent visual acceptance claimed.' if views else
                           'Native data capture is CPU only; normal-window anatomical views have not been supplied.'],
            'claims': {'continuous_uncertainty_bound': False, 'contact_certificate': False, 'phase_map': False,
                       'policy_E': None, 'activation': False, 'original_12_gates_preserved': True}}


def prepare(directory):
    """Copy the current scene's exact resource closure into an isolated import project."""
    directory = Path(directory)
    require(not directory.exists(), "Refusing to overwrite probe project")
    paths = [GLB, GLB + '.import', SCENE, 'tools/units3d/archer_arp/pivot_import.gd',
             'tools/units3d/cavalry_march_capture.gd', 'tools/units3d/cavalry_march_capture.gd.uid']
    for suffix in ['', '_mr', '_n']:
        image = f'assets/3D/units/cavalry/cavalry_cavalry_atlas{suffix}.jpg'
        paths.extend([image, image + '.import'])
    hashes = {name: sha256(ROOT / name) for name in paths}
    for name in paths:
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    (directory / 'project.godot').write_text('[application]\nconfig/name="Cavalry native provenance capture"\n[rendering]\nrenderer/rendering_method="forward_plus"\n')
    (directory / 'input-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    return hashes


def source_geometry(output):
    """Run inside a separate background Blender reading the frozen source, never save it."""
    import bpy
    require(not output.exists(), "Refusing to overwrite source capture")
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    require(len(meshes) == 1, "Expected one source mesh")
    obj = meshes[0]
    mesh = obj.data
    rigs = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    require(len(rigs) == 1, "Expected one source armature")
    part = mesh.attributes.get('tripo_part')
    require(part is not None and part.domain == 'POINT' and part.data_type == 'INT', "Missing anatomical source labels")
    mesh.calc_loop_triangles()
    payload = {'version': 1, 'source_file': str(Path(bpy.data.filepath).resolve()),
               'source_sha256': sha256(bpy.data.filepath), 'blender': bpy.app.version_string,
               'bone_names': [b.name for b in rigs[0].data.bones],
               'mesh': obj.name, 'matrix_world': [list(row) for row in obj.matrix_world],
               'vertices': [list(v.co) for v in mesh.vertices],
               'parts': [x.value for x in part.data],
               'triangles': [list(t.vertices) for t in mesh.loop_triangles],
               'triangle_uv': [[list(mesh.uv_layers.active.data[i].uv) for i in t.loops] for t in mesh.loop_triangles]}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, separators=(',', ':')) + '\n')
    print('SOURCE_CAPTURE', len(payload['vertices']), len(payload['triangles']), sha256(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    stage = sub.add_parser('prepare')
    stage.add_argument('directory', type=Path)
    source = sub.add_parser('source')
    source.add_argument('output', type=Path)
    check = sub.add_parser('audit')
    check.add_argument('capture', type=Path)
    check.add_argument('source', type=Path)
    check.add_argument('--frozen-native', type=Path, required=True)
    check.add_argument('--frozen-geometry', type=Path, required=True)
    check.add_argument('--witness', type=Path, required=True)
    check.add_argument('--out', type=Path, required=True)
    check.add_argument('--views', type=Path)
    verify = sub.add_parser('verify')
    verify.add_argument('manifest', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else None)
    if args.command == 'prepare':
        print(json.dumps(prepare(args.directory), indent=2))
    elif args.command == 'source':
        source_geometry(args.output)
    elif args.command == 'audit':
        report = audit(args.capture, args.source, args.frozen_native, args.frozen_geometry, args.witness, args.views)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({k: report[k] for k in ['status', 'topology', 'max_vertex_delta_by_operation_m', 'unresolved']}, indent=2))
        return 2 if report['status'] != 'PASS' else 0
    elif args.command == 'verify':
        manifest = json.loads(args.manifest.read_text())
        for path, digest in manifest['inputs'].items():
            require(sha256(path) == digest, f"Bound input changed: {path}")
        frozen = manifest['frozen_paths']
        replay = audit(Path(manifest['capture_directory']), Path(manifest['source_geometry']),
                       Path(frozen['native']), Path(frozen['geometry']), Path(frozen['witness']),
                       Path(manifest['views_manifest']) if manifest.get('views_manifest') else None)
        require(replay == manifest, "Manifest does not reproduce")
        print('REPLAY_IDENTICAL', manifest['status'])
        return 2 if manifest['status'] != 'PASS' else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
