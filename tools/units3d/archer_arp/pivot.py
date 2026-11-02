"""Author transient archer pivot poses from the unchanged ARP six-clip export.

Run in background Blender: --python pivot.py -- BODY_GLB WORK_DIRECTORY
[ACTUAL_NATIVE_MARCH_JSON IMPORTED_BODY_GLB CAPTURE_SHA256].
Read-only: --boundary-preflight SOURCE_GLB IMPORTED_BODY_GLB CAPTURE_JSON SHA256 PHASE...
Self-check: --boundary-self-check SOURCE_GLB IMPORTED_BODY_GLB CAPTURE_JSON SHA256
The output is input for the accepted Map3DArcherPivot, not a motion certificate.
Native bone space excludes the model root. Positive pack turn means RIGHT.
"""
import json
import hashlib
import math
from pathlib import Path
import struct
import sys

from mathutils import Matrix, Quaternion, Vector

PARTS = ('thigh_twist', 'thigh_stretch', 'leg_stretch', 'leg_twist', 'foot', 'toes_01')


def frame(direction, normal):
    y = direction.normalized()
    x = normal - y * normal.dot(y)
    if x.length < 1e-8:
        raise ValueError('undefined material frame')
    x.normalize()
    return Matrix((x, y, x.cross(y))).transposed()


def mix(a, b, share):
    if share == 0.0:
        return a.copy()
    if share == 1.0:
        return b.copy()
    def split(matrix):
        basis = matrix.to_3x3()
        x = basis.col[0].normalized()
        y = (basis.col[1] - x * basis.col[1].dot(x)).normalized()
        z = (basis.col[2] - x * basis.col[2].dot(x) - y * basis.col[2].dot(y)).normalized()
        rotation = Matrix((x, y, z)).transposed()
        return rotation, rotation.transposed() @ basis
    ar, aa = split(a)
    br, ba = split(b)
    # Matrix.lerp can shrink near-equal float32 rotations; keep native affine
    # residuals explicit and normalize the interpolated rotation quaternion.
    rotation = ar.to_quaternion().normalized().slerp(br.to_quaternion().normalized(), share).normalized().to_matrix()
    affine = Matrix([[aa[i][j] + (ba[i][j] - aa[i][j]) * share for j in range(3)] for i in range(3)])
    result = (rotation @ affine).to_4x4()
    result.translation = a.translation.lerp(b.translation, share)
    return result


def globals_of(local, parents):
    out, pending = {}, dict(local)
    while pending:
        count = len(pending)
        for name, matrix in list(pending.items()):
            parent = parents[name]
            if not parent or parent in out:
                out[name] = out[parent] @ matrix if parent else matrix.copy()
                del pending[name]
        if len(pending) == count:
            raise ValueError('cyclic native skeleton')
    return out


def locals_of(pose, parents):
    return {name: pose[parents[name]].inverted() @ matrix if parents[name] else matrix.copy()
            for name, matrix in pose.items()}


def encoded(value):
    if isinstance(value, Matrix):
        return {'$t' if len(value) == 4 else '$b': [list(row) for row in value]}
    if isinstance(value, dict):
        return {key: encoded(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [encoded(item) for item in value]
    return value


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def read_affine(value):
    rows = value.get('$t') if isinstance(value, dict) and set(value) == {'$t'} else None
    if not isinstance(rows, list) or len(rows) != 4 or any(not isinstance(r, list) or len(r) != 4 or not all(finite_number(x) for x in r) for r in rows) or rows[3] != [0, 0, 0, 1]:
        raise ValueError('invalid full affine matrix')
    matrix = Matrix(rows)
    if not math.isfinite(matrix.determinant()) or abs(matrix.determinant()) <= 1e-10 or not all(math.isfinite(x) for r in matrix.inverted() for x in r):
        raise ValueError('singular/overflowing full affine matrix')
    return matrix


def read_locals(value, parents):
    if not isinstance(value, dict) or set(value) != set(parents):
        raise ValueError('incomplete named native transforms')
    return {name: read_affine(item) for name, item in value.items()}


def matrix_error(a, b):
    values = [abs(a[i][j] - b[i][j]) for i in range(4) for j in range(4)]
    return max(values) if all(math.isfinite(v) for v in values) else math.inf


def change_space(local, parents, target_from_source):
    # Only roots change basis space; every parent-relative descendant stays intact.
    return {n: target_from_source @ m if not parents[n] else m.copy() for n, m in local.items()}


class NativeSource:
    def __init__(self, path):
        self.bytes = Path(path).read_bytes()
        length = struct.unpack_from('<I', self.bytes, 12)[0]
        self.doc = json.loads(self.bytes[20:20 + length])
        self.binary = self.bytes[28 + length:]
        self.cache = {}
        self.native_poses = {}
        self.joints = self.doc['skins'][0]['joints']
        nodes = self.doc['nodes']
        self.parents = {nodes[i]['name']: next((nodes[p]['name'] for p in self.joints
                       if i in nodes[p].get('children', [])), '') for i in self.joints}
        self.rest = self.pose(-1.0)
        self.reference = globals_of(self.rest, self.parents)
        root = next(n for n in nodes if n.get('name') == 'archers_rig')
        q = root['rotation']
        self.native_from_mesh = Quaternion((q[3], *q[:3])).normalized().to_matrix().inverted()
        attributes = self.doc['meshes'][0]['primitives'][0]['attributes']
        mesh_positions = self.accessor(attributes['POSITION'])
        positions = [self.native_from_mesh @ Vector(p) for p in mesh_positions]
        joints = self.accessor(attributes['JOINTS_0'])
        weights = self.accessor(attributes['WEIGHTS_0'])
        if 'JOINTS_1' in attributes:
            joints = [a + b for a, b in zip(joints, self.accessor(attributes['JOINTS_1']))]
            weights = [a + b for a, b in zip(weights, self.accessor(attributes['WEIGHTS_1']))]
        self.legs = {}
        self.sole_clouds = {}
        ibms = [Matrix([values[i:i + 4] for i in range(0, 16, 4)]).transposed() for values in self.accessor(self.doc['skins'][0]['inverseBindMatrices'])]
        for side in ('l', 'r'):
            palette = {self.joints.index(i) for i in self.joints
                       if nodes[i]['name'] in ('foot.' + side, 'toes_01.' + side)}
            ids = [i for i, (js, ws) in enumerate(zip(joints, weights))
                   if sum(w for j, w in zip(js, ws) if j in palette) > .8]
            foot_index = next(self.joints.index(i) for i in self.joints if nodes[i]['name'] == 'foot.' + side)
            toe_index = next(self.joints.index(i) for i in self.joints if nodes[i]['name'] == 'toes_01.' + side)
            cloud = []
            for i in ids:
                if sum(w for j, w in zip(joints[i], weights[i]) if j in palette) < .999999:
                    continue
                vertex = Vector((*mesh_positions[i], 1.0))
                foot_point, toe_point = Vector((0, 0, 0, 0)), Vector((0, 0, 0, 0))
                for j, w in zip(joints[i], weights[i]):
                    if j == foot_index:
                        foot_point += (ibms[j] @ vertex) * w
                    elif j == toe_index:
                        toe_point += (ibms[j] @ vertex) * w
                cloud.append((foot_point, toe_point))
            if not cloud:
                raise ValueError('missing actual rigid footwear surface')
            self.sole_clouds[side] = cloud
            low = min(positions[i].y for i in ids)
            ids = [i for i in ids if positions[i].y < low + .005]
            center = sum((positions[i] for i in ids), Vector()) / len(ids)
            self.legs[side] = {'knee_limits': {'$v2': [0.0, math.pi]},
                'rotation_limits': {part: math.pi for part in PARTS},
                'sole_in_foot': self.reference['foot.' + side].inverted() @ Matrix.Translation(center),
                # Joint frame retains the rigid toe origin under track interpolation;
                # actual toe shoe vertices are audited separately through skinning.
                'toe_in_toes': Matrix.Identity(4)}

    def use_native_march(self, dump_path, imported_body_path, capture_sha256=None):
        """Bind a trusted actual-playback capture; never infer its provenance from a label.

        The caller retains SHA256 from the GUT capture run separately from this file.
        This detects replacement/corruption, not a dishonest capture producer.
        Validate everything before changing this source; legacy unbound dumps reject.
        """
        payload = Path(dump_path).read_bytes()
        if not capture_sha256 or hashlib.sha256(payload).hexdigest() != capture_sha256:
            raise ValueError('native capture does not match independently retained SHA256')
        dump = json.loads(payload)
        imported = NativeSource(imported_body_path)
        for key, value in self.doc.items():
            if key == 'buffers':
                continue
            observed = imported.doc[key]
            if key in ('animations', 'accessors', 'bufferViews'):
                observed = observed[:len(value)]
            if observed != value:
                raise ValueError('native MARCH body differs from immutable source ' + key)
        if imported.binary[:len(self.binary)] != self.binary:
            raise ValueError('native MARCH body changed immutable source payload')
        if dump.get('schema') != 'archer-native-boundary-v1' or dump.get('kind') != 'raw_animation_player' or dump.get('clip') != 'MARCH':
            raise ValueError('expected raw AnimationPlayer MARCH capture, not calibrated input')
        project = Path(imported_body_path).resolve().parents[4]
        folder = project / 'assets/3D/units/archers'
        paths = {str(p.relative_to(project)) for p in folder.iterdir() if p.is_file()}
        paths.update(('scenes/models/units/archers.tscn', 'tools/units3d/archer_arp/pivot_import.gd'))
        digests = dump.get('resource_sha256', {})
        if set(digests) != paths or any(hashlib.sha256((project / p).read_bytes()).hexdigest() != digests[p] for p in paths):
            raise ValueError('native capture has stale body/import/scene/gear source digests')
        if digests['assets/3D/units/archers/archers.glb'] != hashlib.sha256(imported.bytes).hexdigest():
            raise ValueError('capture imported body path mismatch')
        if dump.get('capture_script_sha256') != hashlib.sha256((project / 'tests/map3d/test_archer_pivot.gd').read_bytes()).hexdigest():
            raise ValueError('stale native capture producer')
        if not isinstance(dump.get('godot'), dict) or not dump['godot'].get('hash') or not dump['godot'].get('string'):
            raise ValueError('native runtime identity missing')
        action = next(a for a in imported.doc['animations'] if a['name'] == 'MARCH')
        length = max(imported.accessor(s['input'])[-1][0] for s in action['samplers'])
        if not finite_number(dump.get('clip_length_s')) or abs(dump['clip_length_s'] - length) > 1e-6:
            raise ValueError('native MARCH length differs from source')
        rest = dump.get('rest', {})
        if rest.get('parents') != self.parents:
            raise ValueError('native skeleton names/parents differ from source')
        native_rest = read_locals(rest.get('locals'), self.parents)
        source_from_native = read_affine(dump.get('source_from_native'))
        native_from_source = read_affine(dump.get('native_from_source'))
        read_affine(dump.get('model_from_native'))
        if matrix_error(source_from_native @ native_from_source, Matrix.Identity(4)) > 1e-5 or matrix_error(native_from_source @ source_from_native, Matrix.Identity(4)) > 1e-5:
            raise ValueError('native/source affine transforms are not mutual inverses')
        converted_rest = change_space(native_rest, self.parents, source_from_native)
        if any(matrix_error(converted_rest[n], self.rest[n]) > 1e-5 for n in self.parents):
            raise ValueError('same-name native rest differs from bound source rest')
        # Validate the full captured named skins and ALL raw influences, never normalize.
        meshes = dump.get('meshes')
        if not isinstance(meshes, dict) or not meshes:
            raise ValueError('missing actual equipped mesh/skin data')
        for mesh in meshes.values():
            binds = mesh['binds']
            if not binds or len({b['bone'] for b in binds}) != len(binds):
                raise ValueError('missing or duplicate named Skin binds')
            for bind in binds:
                if bind['bone'] not in self.parents:
                    raise ValueError('unknown Skin bone')
                read_affine(bind['pose'])
            if not mesh['vertices']:
                raise ValueError('empty captured mesh')
            for vertex in mesh['vertices']:
                point = vertex['position']['$v3']
                if len(point) != 3 or not all(finite_number(v) for v in point):
                    raise ValueError('invalid captured material point')
                weights = vertex['influences']
                if not weights or any(type(w['bind']) is not int or not 0 <= w['bind'] < len(binds) or not finite_number(w['weight']) or w['weight'] < 0 for w in weights) or sum(w['weight'] for w in weights) <= 0:
                    raise ValueError('invalid raw skin weights/bind indices')
            if any(type(i) is not int or not 0 <= i < len(mesh['vertices']) for i in mesh['sole_indices']) or len(set(mesh['sole_indices'])) != len(mesh['sole_indices']):
                raise ValueError('invalid fixed material index')
        if not any(m['sole_indices'] for m in meshes.values()):
            raise ValueError('missing fixed sole material points')
        poses, raw_native = {}, {}
        for row in dump['samples']:
            phase = row.get('phase')
            if not finite_number(phase) or not 0 <= phase < 1 or phase in poses or row.get('kind') != 'raw_animation_player' or row.get('clip') != 'MARCH':
                raise ValueError('malformed/duplicate native MARCH phase or calibrated baseline')
            if not finite_number(row.get('time_s')) or abs(row['time_s'] - phase * length) > 1e-6:
                raise ValueError('native phase/time mismatch')
            local = read_locals(row['locals'], self.parents)
            global_pose = read_locals(row['globals'], self.parents)
            rebuilt = globals_of(local, self.parents)
            if any(matrix_error(rebuilt[n], global_pose[n]) > 1e-5 for n in self.parents):
                raise ValueError('native full local/global reconstruction mismatch')
            converted = change_space(local, self.parents, source_from_native)
            roundtrip = change_space(converted, self.parents, native_from_source)
            source_globals = globals_of(converted, self.parents)
            if any(matrix_error(roundtrip[n], local[n]) > 1e-5 or matrix_error(source_globals[n], source_from_native @ global_pose[n]) > 1e-5 for n in self.parents):
                raise ValueError('native/source full affine roundtrip failed')
            poses[phase], raw_native[phase] = converted, local
        if 0.0 not in poses:
            raise ValueError('actual native MARCH reference phase missing')
        self.native_poses = poses
        self.native_boundary = {'capture_sha256': capture_sha256, 'capture': dump,
                                'raw_native': raw_native, 'rest': native_rest,
                                'source_from_native': source_from_native, 'native_from_source': native_from_source}

    def boundary_preflight(self, phase):
        """Read-only finite input comparison; no solver/export/policy side effect."""
        if not finite_number(phase) or not self.native_poses or phase not in self.native_poses:
            raise ValueError('exact actual native MARCH phase missing; no nearest/interpolated fallback')
        raw_source = self.pose(phase)
        calibrated_source, _, _ = self.calibrated(phase)
        return {'physical_error_status': 'unknown', 'capture_sha256': self.native_boundary['capture_sha256'],
                'phase': phase, 'raw_native_locals': {n: m.copy() for n, m in self.native_boundary['raw_native'][phase].items()},
                'raw_source_locals': raw_source, 'calibrated_source_locals': calibrated_source,
                'native_rest': {n: m.copy() for n, m in self.native_boundary['rest'].items()}, 'source_rest': {n: m.copy() for n, m in self.rest.items()},
                'source_from_native': self.native_boundary['source_from_native'].copy(),
                'native_from_source': self.native_boundary['native_from_source'].copy(),
                'diagnostics': ['finite captured phase only; not a contact or full-domain certificate']}

    def accessor(self, index):
        if index not in self.cache:
            a = self.doc['accessors'][index]
            view = self.doc['bufferViews'][a['bufferView']]
            width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
            fmt = {5126: 'f', 5123: 'H', 5121: 'B', 5125: 'I'}[a['componentType']]
            size = struct.calcsize(fmt)
            start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
            stride = view.get('byteStride', width * size)
            self.cache[index] = [struct.unpack_from('<' + fmt * width, self.binary, start + i * stride)
                                 for i in range(a['count'])]
        return self.cache[index]

    def pose(self, phase):
        if self.native_poses and not finite_number(phase):
            raise ValueError('native phase must be finite numeric input')
        if phase >= 0 and self.native_poses:
            if phase not in self.native_poses:
                raise ValueError('actual native MARCH sample missing; no invented interpolation')
            return {name: matrix.copy() for name, matrix in self.native_poses[phase].items()}
        nodes = [dict(node) for node in self.doc['nodes']]
        if phase >= 0:
            action = next(a for a in self.doc['animations'] if a['name'] == 'MARCH')
            for channel in action['channels']:
                sampler = action['samplers'][channel['sampler']]
                if sampler.get('interpolation', 'LINEAR') not in ('LINEAR', 'STEP'):
                    raise ValueError('unsupported source interpolation')
                times, values = self.accessor(sampler['input']), self.accessor(sampler['output'])
                t, i = phase * times[-1][0], 0
                while i + 2 < len(times) and t > times[i + 1][0]:
                    i += 1
                w = (t - times[i][0]) / (times[i + 1][0] - times[i][0])
                if sampler.get('interpolation') == 'STEP':
                    w = 1.0 if t == times[i + 1][0] else 0.0
                a, b = values[i], values[i + 1]
                path = channel['target']['path']
                if path == 'rotation':
                    q = Quaternion((a[3], *a[:3])).normalized().slerp(Quaternion((b[3], *b[:3])).normalized(), w)
                    value = [q.x, q.y, q.z, q.w]
                else:
                    value = [x + (y - x) * w for x, y in zip(a, b)]
                nodes[channel['target']['node']][path] = value
        result = {}
        for i in self.joints:
            n = nodes[i]
            q = n.get('rotation', [0, 0, 0, 1])
            matrix = Quaternion((q[3], *q[:3])).normalized().to_matrix().to_4x4()
            matrix @= Matrix.Diagonal((*n.get('scale', [1, 1, 1]), 1))
            matrix.translation = Vector(n.get('translation', [0, 0, 0]))
            result[n['name']] = matrix
        return result

    def shoe_floor(self, foot, toe, side):
        foot_row, toe_row = foot.row[1], toe.row[1]
        lowest = min(foot_row.dot(a) + toe_row.dot(b) for a, b in self.sole_clouds[side])
        return lowest

    def floor_raise(self, foot, toe, side):
        return max(0.0, -self.shoe_floor(foot, toe, side))

    def calibrated(self, phase):
        original = self.pose(phase)
        raw = globals_of(original, self.parents)
        # Seat the received stance shoe; preserve the airborne foot and body.
        # Only transient leg goals change, never the source clip or actor origin.
        stance = min(('l', 'r'), key=lambda side: self.shoe_floor(raw['foot.' + side], raw['toes_01.' + side], side))
        for side in ('l', 'r'):
            lift = self.floor_raise(raw['foot.' + side], raw['toes_01.' + side], side)
            raw['foot.' + side].translation.y += lift
            raw['toes_01.' + side].translation.y += lift
        height = self.shoe_floor(raw['foot.' + stance], raw['toes_01.' + stance], stance)
        raw['foot.' + stance].translation.y -= height
        raw['toes_01.' + stance].translation.y -= height
        mapped = {n: m.copy() for n, m in raw.items()}
        hints = {}
        for side in ('l', 'r'):
            hip, knee, ankle = (raw[n + '.' + side].translation for n in ('thigh_twist', 'leg_stretch', 'foot'))
            axis = (ankle - hip).normalized()
            bend = knee - hip - axis * (knee - hip).dot(axis)
            if bend.length < 1e-8:
                raise ValueError('undefined raw knee radial')
            bend.normalize()
            upper = (self.reference['leg_stretch.' + side].translation - self.reference['thigh_twist.' + side].translation).length
            lower = (self.reference['foot.' + side].translation - self.reference['leg_stretch.' + side].translation).length
            distance = (ankle - hip).length
            along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
            height2 = upper * upper - along * along
            if height2 < -1e-10:
                raise ValueError('unreachable raw source')
            physical_knee = hip + axis * along + bend * math.sqrt(max(0, height2))
            normal = bend.cross(axis).normalized()
            rest_normal = (self.reference['leg_stretch.' + side].translation - self.reference['thigh_twist.' + side].translation).cross(
                self.reference['foot.' + side].translation - self.reference['leg_stretch.' + side].translation)
            body = raw['root.x'].to_3x3().normalized() @ self.reference['root.x'].to_3x3().normalized().transposed()
            old_normal = body @ rest_normal
            for parts, old, new in [(('thigh_twist', 'thigh_stretch'), knee - hip, physical_knee - hip),
                                     (('leg_stretch', 'leg_twist'), ankle - knee, ankle - physical_knee)]:
                correction = frame(new, normal) @ frame(old, old_normal).transposed()
                for part in parts:
                    name = part + '.' + side
                    basis = correction.transposed() @ raw[name].to_3x3()
                    mapped[name] = basis.to_4x4()
                    mapped[name].translation = raw[name].translation
            hints[side] = Matrix((bend, axis, bend.cross(axis))).transposed()
        corrected = {name: matrix.copy() for name, matrix in original.items()}
        for side in ('l', 'r'):
            for part in PARTS:
                name = part + '.' + side
                parent = self.parents[name]
                corrected[name] = mapped[parent].inverted() @ mapped[name] if parent else mapped[name].copy()
        hints['stance'] = stance
        return corrected, raw, hints

    def contact_plan(self, turn, entry, exit, steps=8):
        _, first, first_hints = self.calibrated(entry)
        _, last, last_hints = self.calibrated(exit)
        finish_yaw = Matrix.Rotation(-turn, 4, 'Y')
        # Keep the grounded source foot bearing weight through the first swing.
        stance = first_hints['stance']
        first_side = 'r' if stance == 'l' else 'l'
        exit_stance = last_hints['stance']
        release_at = 1.0 - 1.0 / (4 * steps)
        order = [first_side, 'r' if first_side == 'l' else 'l']
        contacts = {}
        for side in ('l', 'r'):
            leg = self.legs[side]
            initial = first['foot.' + side]
            final = finish_yaw @ last['foot.' + side]
            flat = self.reference['foot.' + side]
            contacts[side] = {'track': [], 'support': []}
            previous = initial.copy()
            previous_t = 0.0
            previous_toe = initial.inverted() @ first['toes_01.' + side]
            final_toe = last['foot.' + side].inverted() @ last['toes_01.' + side]
            flat_toe = flat.inverted() @ self.reference['toes_01.' + side]
            foot_knots = [(0.0, previous, previous_toe.copy())]
            own_steps = [i for i in range(steps) if order[i % 2] == side]
            for i in own_steps:
                a, b = i / steps, (i + 1) / steps
                if i == steps - 1 and side == exit_stance:
                    b = release_at
                strength = abs(math.sin(turn / 2))
                received_foot = mix(initial, last['foot.' + side], b)
                neutral = mix(received_foot, flat, strength)
                landing = final.copy() if i == own_steps[-1] else Matrix.Rotation(-turn * b, 4, 'Y') @ neutral
                if a > previous_t:
                    contacts[side]['support'].append((previous_t, a, previous.copy()))
                    foot_knots.append((a, previous.copy(), previous_toe.copy()))
                received_toe = mix(foot_knots[0][2], final_toe, b)
                landing_toe = final_toe.copy() if i == own_steps[-1] else mix(received_toe, flat_toe, strength)
                if i != own_steps[-1] or (i == steps - 2 and side != exit_stance):
                    landing.translation.y -= self.shoe_floor(landing, landing @ landing_toe, side)
                else:
                    landing.translation.y += self.floor_raise(landing, landing @ landing_toe, side)
                for substep in range(1, 9):
                    share = substep / 8
                    swing = mix(previous, landing, share)
                    relative = mix(previous_toe, landing_toe, share)
                    swing.translation.y += .035 * strength * math.sin(math.pi * share)
                    if substep < 8:
                        swing.translation.y += self.floor_raise(swing, swing @ relative, side)
                    foot_knots.append((a + (b - a) * share, swing, relative))
                previous, previous_t, previous_toe = landing, b, landing_toe
            # Receive the exit stance before releasing the other foot into MARCH.
            if side != exit_stance and own_steps[-1] == steps - 2:
                contacts[side]['support'].append((previous_t, release_at, previous.copy()))
                foot_knots.append((release_at, previous.copy(), previous_toe.copy()))
                for substep in range(1, 9):
                    share = substep / 8
                    foot_knots.append((release_at + (1.0 - release_at) * share,
                        mix(previous, final, share), mix(previous_toe, final_toe, share)))
                previous_t = 1.0
            if previous_t < 1.0:
                contacts[side]['support'].append((previous_t, 1.0, previous.copy()))
                foot_knots.append((1.0, previous.copy(), previous_toe.copy()))
            for t, foot, relative in foot_knots:
                local_hint = first_hints[side].to_quaternion().normalized().slerp(last_hints[side].to_quaternion().normalized(), t).normalized().to_matrix()
                kframe = Matrix.Rotation(-turn * t, 3, 'Y') @ local_hint
                contacts[side]['track'].append({'phase': float(t), 'sole': foot @ leg['sole_in_foot'],
                    'toe': foot @ relative, 'knee_frame': kframe})
            supports = []
            for a, b, foot in contacts[side]['support']:
                # A support keeps BOTH full frames fixed; select its exact knot.
                knot = next(k for k in contacts[side]['track'] if k['phase'] == a)
                supports.append({'start': float(a), 'end': float(b), 'sole': knot['sole'], 'toe': knot['toe']})
            contacts[side]['support'] = supports
        return contacts


    def case(self, turn, duration, phase, entry, exit, contacts=None):
        if not all(math.isfinite(v) for v in (turn, duration, phase, entry, exit)) or duration <= 0 or abs(turn) > math.pi or not 0 <= phase <= 1 or not 0 <= entry < 1 or not 0 <= exit < 1:
            raise ValueError('pivot parameter outside authored domain')
        if phase == 0:
            received = entry
        elif phase == 1:
            received = exit
        else:
            received = (entry + ((exit - entry) % 1) * phase) % 1
        pose, _, _ = self.calibrated(received)
        # Authored internal weight shift: endpoints match MARCH; model root/XZ,
        # committed yaw and operation duration remain entirely external.
        drop = .01 * abs(math.sin(turn / 2)) * math.sin(math.pi * phase) ** 2
        if phase not in (0.0, 1.0):
            for name, matrix in pose.items():
                if not self.parents[name]:
                    matrix.translation.y -= drop
        start, _, _ = self.calibrated(entry)
        finish, _, _ = self.calibrated(exit)
        return {'rest': {'locals': self.rest, 'parents': self.parents, 'legs': self.legs},
            'pose': pose, 'operation': {'yaw_rad': 0.0, 'turn_rad': turn, 'duration_s': duration,
                'phase': phase, 'march_entry_phase': entry, 'march_exit_phase': exit,
                'entry_pose': start, 'exit_pose': finish},
            'contacts': contacts if contacts is not None else self.contact_plan(turn, entry, exit)}


def boundary_self_check(source, args):
    """Small author-side checks, using only this branch and a pinned native capture."""
    import copy
    import tempfile
    source_path, imported_path, dump_path, capture_sha256 = args
    original = json.loads(Path(dump_path).read_text())
    frozen = encoded(source.native_poses)
    for phase in source.native_poses:
        result = source.boundary_preflight(phase)
        assert result['physical_error_status'] == 'unknown'
        assert matrix_error(result['source_from_native'] @ result['native_from_source'], Matrix.Identity(4)) < 1e-5
        # Mutating a returned record must not corrupt the bound raw baseline.
        result['raw_native_locals']['root.x'].translation.x += 1
    assert encoded(source.native_poses) == frozen
    for phase in (.123456789, .137 + 1e-13, math.nan, True):
        try:
            source.pose(phase)
        except ValueError:
            pass
        else:
            raise AssertionError('invented/malformed native phase')
    transform = Matrix(((2, .3, 0, 10), (0, 1, .2, 20), (0, 0, .5, 30), (0, 0, 0, 1)))
    local = {'a': Matrix.Translation((1, 2, 3)), 'b': Matrix.Translation((4, 5, 6))}
    parents = {'a': '', 'b': 'a'}
    converted = change_space(local, parents, transform)
    rebuilt = globals_of(converted, parents)
    assert matrix_error(converted['b'], local['b']) == 0
    assert matrix_error(rebuilt['b'], transform @ globals_of(local, parents)['b']) < 1e-5
    assert all(matrix_error(m, local[n]) < 1e-5 for n, m in change_space(converted, parents, transform.inverted()).items())
    for mutation in ('digest', 'import_digest', 'scene_digest', 'gear_digest', 'producer', 'rest', 'parent', 'cycle', 'phase', 'duplicate', 'nan', 'weight', 'bind', 'inverse', 'time', 'calibrated', 'substituted_raw'):
        dump = copy.deepcopy(original)
        if mutation == 'digest':
            dump['resource_sha256']['assets/3D/units/archers/archers.glb'] = '0' * 64
        elif mutation in ('import_digest', 'scene_digest', 'gear_digest'):
            path = {'import_digest': 'assets/3D/units/archers/archers.glb.import', 'scene_digest': 'scenes/models/units/archers.tscn', 'gear_digest': 'assets/3D/units/archers/archers_bow.res'}[mutation]
            dump['resource_sha256'][path] = '0' * 64
        elif mutation == 'producer':
            dump['capture_script_sha256'] = '0' * 64
        elif mutation == 'rest':
            dump['rest']['locals']['foot.l']['$t'][0][3] += .01
        elif mutation == 'parent':
            dump['rest']['parents']['foot.l'] = 'missing'
        elif mutation == 'cycle':
            dump['rest']['parents']['root.x'] = 'foot.l'
        elif mutation == 'phase':
            dump['samples'][0]['phase'] = 1.0
        elif mutation == 'duplicate':
            dump['samples'].append(dump['samples'][0])
        elif mutation == 'nan':
            dump['samples'][0]['locals']['foot.l']['$t'][0][0] = math.nan
        elif mutation == 'weight':
            next(iter(dump['meshes'].values()))['vertices'][0]['influences'][0]['weight'] = -.1
        elif mutation == 'bind':
            next(iter(dump['meshes'].values()))['binds'][0]['bone'] = 'missing'
        elif mutation == 'inverse':
            dump['native_from_source']['$t'][0][3] += .1
        elif mutation == 'time':
            dump['samples'][0]['time_s'] += .1
        elif mutation == 'calibrated':
            dump['samples'][0]['kind'] = 'calibrated'
        elif mutation == 'substituted_raw':
            dump['samples'][0]['locals'] = encoded(source.calibrated(0.0)[0])
        payload = json.dumps(dump).encode()
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'invalid.json'
            path.write_bytes(payload)
            try:
                # A relabelled replacement cannot match the independently retained hash.
                pin = capture_sha256 if mutation == 'substituted_raw' else hashlib.sha256(payload).hexdigest()
                source.use_native_march(path, imported_path, pin)
            except (ValueError, KeyError, TypeError):
                pass
            else:
                raise AssertionError('accepted malformed capture: ' + mutation)
        assert encoded(source.native_poses) == frozen, mutation + ' mutated bound input'
    # Legacy raw GLB author mode still evaluates arbitrary phases independently.
    fallback = NativeSource(source_path)
    assert fallback.pose(.123456789) and not fallback.native_poses
    print('BOUNDARY_SELF_CHECK_PASS', len(source.native_poses), 'exact phases; 17 atomic negative cases; E unknown')


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    if args and args[0] in ('--boundary-preflight', '--boundary-self-check'):
        source = NativeSource(args[1])
        source.use_native_march(args[3], args[2], args[4])
        if args[0] == '--boundary-self-check':
            boundary_self_check(source, args[1:5])
        else:
            if len(args) < 6:
                raise ValueError('explicit captured phases required')
            print(json.dumps(encoded([source.boundary_preflight(float(p)) for p in args[5:]]), allow_nan=False))
        return
    if len(args) not in (2, 5):
        raise ValueError('expected BODY_GLB WORK_DIRECTORY [NATIVE_MARCH_JSON IMPORTED_BODY_GLB CAPTURE_SHA256]')
    source_path, work = map(Path, args[:2])
    source = NativeSource(source_path)
    if len(args) == 5:
        source.use_native_march(args[2], args[3], args[4])
    work.mkdir(parents=True, exist_ok=True)
    cases = []
    for name, turn in [('PIVOT_LEFT', -math.pi), ('PIVOT_RIGHT', math.pi)]:
        contacts = source.contact_plan(turn, 0.0, 0.0)
        phases = sorted({i / 60 for i in range(61)} | {k['phase'] for side in contacts.values() for k in side['track']})
        for i, phase in enumerate(phases):
            case = source.case(turn, 2.0, phase, 0.0, 0.0, contacts)
            case['id'] = name + '/' + str(i)
            cases.append(case)
    metadata = {'body_glb_sha256': hashlib.sha256(source.bytes).hexdigest(),
        'helper_sha256': hashlib.sha256((Path(__file__).resolve().parents[3] / 'scripts/map3d/map3d_archer_pivot.gd').read_bytes()).hexdigest()}
    if len(args) == 5:
        metadata.update(native_march_sha256=hashlib.sha256(Path(args[2]).read_bytes()).hexdigest(),
            imported_body_sha256=hashlib.sha256(Path(args[3]).read_bytes()).hexdigest())
    (work / 'pivot-source-input.json').write_text(json.dumps(encoded({'source': metadata, 'cases': cases}), separators=(',', ':')) + '\n')
    print('PIVOT_AUTHOR_PREPARED', len(cases), 'unexecuted reference clip cases')


def append_pivots(path, inputs_path, results_path):
    """Append only two new sampled clips; preserve every existing GLB BIN byte."""
    import hashlib
    import copy
    inputs = json.loads(Path(inputs_path).read_text())
    results = json.loads(Path(results_path).read_text())
    if results['input_sha256'] != hashlib.sha256(Path(inputs_path).read_bytes()).hexdigest():
        raise ValueError('pivot result does not bind the author input')
    if results['helper_sha256'] != inputs['source']['helper_sha256']:
        raise ValueError('pivot result uses another helper')
    original = Path(path).read_bytes()
    if hashlib.sha256(original).hexdigest() != inputs['source']['body_glb_sha256']:
        raise ValueError('source body changed; re-author and validate pivots')
    n = struct.unpack_from('<I', original, 12)[0]
    doc = json.loads(original[20:20 + n])
    saved = copy.deepcopy(doc)
    binary = bytearray(original[28 + n:])
    original_binary = bytes(binary)
    lookup = {r['id']: r['result'] for r in results['cases']}
    native = NativeSource(path)
    names = [doc['nodes'][i]['name'] for i in native.joints]

    def accessor(rows, kind):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        for row in rows:
            binary.extend(struct.pack('<' + 'f' * len(row), *row))
        view = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(binary) - offset})
        index = len(doc['accessors'])
        item = {'bufferView': view, 'componentType': 5126, 'count': len(rows), 'type': kind}
        if kind == 'SCALAR':
            item.update(min=[rows[0][0]], max=[rows[-1][0]])
        doc['accessors'].append(item)
        return index

    for clip in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
        if any(a['name'] == clip for a in doc['animations']):
            raise ValueError('pivot already installed')
        cases = [c for c in inputs['cases'] if c['id'].startswith(clip + '/')]
        cases.sort(key=lambda c: int(c['id'].split('/')[1]))
        if len(cases) < 2 or [c['id'] for c in cases] != [clip + '/' + str(i) for i in range(len(cases))] or cases[0]['operation']['phase'] != 0.0 or cases[-1]['operation']['phase'] != 1.0:
            raise ValueError('incomplete reference pivot samples')
        duration = cases[0]['operation']['duration_s']
        if not math.isfinite(duration) or duration <= 0 or any(c['operation']['duration_s'] != duration for c in cases) or any(a['operation']['phase'] >= b['operation']['phase'] for a, b in zip(cases, cases[1:])):
            raise ValueError('noncanonical pivot sample times')
        times = [struct.unpack('<f', struct.pack('<f', duration * c['operation']['phase']))[0] for c in cases]
        if not all(math.isfinite(t) for t in times) or any(a >= b for a, b in zip(times, times[1:])):
            raise ValueError('pivot times must remain distinct finite float32 values')
        time = accessor([(t,) for t in times], 'SCALAR')
        animation = {'name': clip, 'channels': [], 'samplers': []}
        poses = []
        for case in cases:
            result = lookup[case['id']]
            if not result['ok'] or set(result['locals']) != set(names):
                raise ValueError('rejected or partial pivot pose')
            poses.append(result['locals'])
        for node in native.joints:
            name = doc['nodes'][node]['name']
            samples = {'translation': [], 'rotation': [], 'scale': []}
            previous = None
            for pose in poses:
                matrix = Matrix(pose[name]['$t'])
                if not all(math.isfinite(x) for row in matrix for x in row):
                    raise ValueError('nonfinite pivot transform')
                location, rotation, scale = matrix.decompose()
                rebuilt = Matrix.LocRotScale(location, rotation, scale)
                if max(abs(matrix[i][j] - rebuilt[i][j]) for i in range(4) for j in range(4)) > 1e-5:
                    raise ValueError('pivot affine cannot be represented by glTF TRS')
                if previous is not None and rotation.dot(previous) < 0:
                    rotation.negate()
                previous = rotation.copy()
                samples['translation'].append(tuple(location))
                samples['rotation'].append((rotation.x, rotation.y, rotation.z, rotation.w))
                samples['scale'].append(tuple(scale))
            for prop, values in samples.items():
                sampler = len(animation['samplers'])
                animation['samplers'].append({'input': time, 'output': accessor(values, 'VEC4' if prop == 'rotation' else 'VEC3'), 'interpolation': 'LINEAR'})
                animation['channels'].append({'sampler': sampler, 'target': {'node': node, 'path': prop}})
        doc['animations'].append(animation)
    doc['buffers'][0]['byteLength'] = len(binary)
    # Mesh, skin, binds, materials, source clip metadata and all old payload stay exact.
    for key in saved:
        if key not in ('buffers', 'bufferViews', 'accessors', 'animations'):
            assert doc[key] == saved[key], key
    assert doc['animations'][:len(saved['animations'])] == saved['animations']
    assert bytes(binary[:len(original_binary)]) == original_binary
    data = json.dumps(doc, separators=(',', ':')).encode()
    data += b' ' * (-len(data) % 4)
    binary += b'\0' * (-len(binary) % 4)
    output = struct.pack('<III', 0x46546c67, 2, 28 + len(data) + len(binary))
    output += struct.pack('<II', len(data), 0x4e4f534a) + data
    output += struct.pack('<II', len(binary), 0x004e4942) + binary
    Path(path).write_bytes(output)


if __name__ == '__main__':
    main()
