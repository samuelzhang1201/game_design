"""Read-only archer CERT audit. A counterexample is a failure, never a certificate.

Native capture uses an isolated, byte-identical scene subset and the project Godot
lock. No rendering, actor seating, weight normalization or source edits occur.
"""
import argparse
import base64
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/reviews/cluster-formations/evidence/locomotion/archers'
WORK = ROOT / '.superpowers/loco-cert-archers'
MODEL = 'scenes/models/units/archers.tscn'
BODY = 'assets/3D/units/archers/archers.glb'
LOCK = '/Users/samuelzhang/game_design-wt/godot_lock.sh'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')


def shortest(a, b):
    delta = (b - a + 180_000_000) % 360_000_000 - 180_000_000
    return 180_000_000 if delta == -180_000_000 else delta


def skin(vertices, joints, weights, matrices):
    if (not np.isfinite(weights).all() or (weights < 0).any()
            or not np.isfinite(vertices).all() or not np.isfinite(matrices).all()
            or joints.shape != weights.shape or len(vertices) != len(weights)
            or (joints < 0).any() or (joints >= len(matrices)).any()):
        raise ValueError('invalid native skin arrays')
    out = np.zeros_like(vertices, dtype=float)
    for slot in range(joints.shape[1]):
        m = matrices[joints[:, slot]]
        out += (np.einsum('nij,nj->ni', m[:, :3, :3], vertices)
                + m[:, :3, 3]) * weights[:, slot, None]
    return out


# Generated inside the ignored capture project; no fifth tracked helper path.
NATIVE = r'''extends SceneTree
var data: Dictionary = {}

func matrix(t: Transform3D) -> Array:
    return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],
        [t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],
        [t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0.0,0.0,0.0,1.0]]

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var model: Node3D = load("res://scenes/models/units/archers.tscn").instantiate()
    root.add_child(model)
    await process_frame
    var sk: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
    var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
    player.stop(true)
    sk.reset_bone_poses()
    sk.force_update_all_bone_transforms()
    data = {"pid":OS.get_process_id(),"godot":Engine.get_version_info(),
        "body_sha256":FileAccess.get_sha256("res://assets/3D/units/archers/archers.glb"),
        "scene_sha256":FileAccess.get_sha256("res://scenes/models/units/archers.tscn"),
        "skeleton_to_model":matrix(model.global_transform.affine_inverse()*sk.global_transform),
        "bones":[],"meshes":[],"clips":{},"samples":[]}
    for bone: int in sk.get_bone_count():
        data.bones.append({"name":sk.get_bone_name(bone),"parent":sk.get_bone_parent(bone),
            "rest":matrix(sk.get_bone_rest(bone)),"global_rest":matrix(sk.get_bone_global_rest(bone))})
    for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
        assert(mesh.skin != null and mesh.get_node(mesh.skeleton)==sk)
        var row: Dictionary = {"name":mesh.name,"path":str(model.get_path_to(mesh)),
            "mesh_to_model":matrix(model.global_transform.affine_inverse()*mesh.global_transform),
            "skin":[],"surfaces":[]}
        for bind: int in mesh.skin.get_bind_count():
            var bone: int = mesh.skin.get_bind_bone(bind)
            if bone < 0: bone=sk.find_bone(mesh.skin.get_bind_name(bind))
            assert(bone>=0)
            row.skin.append({"bone":bone,"name":sk.get_bone_name(bone),"pose":matrix(mesh.skin.get_bind_pose(bind))})
        for surface: int in mesh.mesh.get_surface_count():
            var a: Array=mesh.mesh.surface_get_arrays(surface)
            var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
            var n: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
            var b: PackedInt32Array=a[Mesh.ARRAY_BONES]
            var w: PackedFloat32Array=a[Mesh.ARRAY_WEIGHTS]
            var ix: PackedInt32Array=a[Mesh.ARRAY_INDEX]
            row.surfaces.append({"vertices_f32":Marshalls.raw_to_base64(v.to_byte_array()),
                "normals_f32":Marshalls.raw_to_base64(n.to_byte_array()),
                "bones_i32":Marshalls.raw_to_base64(b.to_byte_array()),
                "weights_f32":Marshalls.raw_to_base64(w.to_byte_array()),
                "indices_i32":Marshalls.raw_to_base64(ix.to_byte_array()),"vertices":v.size()})
        data.meshes.append(row)
    for clip: String in ["MARCH","PIVOT_LEFT","PIVOT_RIGHT"]:
        var name: String=""
        for candidate: String in player.get_animation_list():
            if candidate.get_file()==clip: name=candidate
        assert(not name.is_empty())
        var anim: Animation=player.get_animation(name)
        var times: Array[float]=[0.0,anim.length]
        for track: int in anim.get_track_count():
            for key: int in anim.track_get_key_count(track):
                var t: float=anim.track_get_key_time(track,key)
                if t>=0.0 and t<=anim.length and not t in times: times.append(t)
        times.sort()
        var keys: Array=times.duplicate()
        for i: int in range(1,keys.size()):
            for f: float in [0.25,0.5,0.75]: times.append(lerpf(keys[i-1],keys[i],f))
        for i: int in range(257): times.append(anim.length*float(i)/256.0)
        times.sort()
        data.clips[clip]={"length_s":anim.length,"tracks":anim.get_track_count(),
            "key_times":keys,"step":anim.step,"loop_mode":anim.loop_mode}
        var previous: float=-1.0
        for t: float in times:
            if t==previous: continue
            previous=t
            player.stop(true)
            sk.reset_bone_poses()
            player.play(name,0.0)
            player.seek(t,true)
            sk.force_update_all_bone_transforms()
            var row: Dictionary={"clip":clip,"time_s":t,"phase":t/anim.length,"globals":[],"locals":[]}
            for bone: int in sk.get_bone_count():
                row.globals.append(matrix(sk.get_bone_global_pose(bone)))
                row.locals.append(matrix(sk.get_bone_pose(bone)))
            data.samples.append(row)
    var file: FileAccess=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    file.store_string(JSON.stringify(data,"",true,true))
    file.close()
    print("ARCHER_CERT_NATIVE_CAPTURE ",data.samples.size()," samples PID ",OS.get_process_id())
    quit(0)
'''


def capture(godot):
    project = WORK / 'native-project'
    project.mkdir(parents=True, exist_ok=True)
    files = [MODEL, 'tools/units3d/archer_arp/pivot_import.gd']
    files += [str(p.relative_to(ROOT)) for p in (ROOT / BODY).parent.iterdir() if p.is_file()]
    hashes = {}
    for name in sorted(files):
        source, dest = ROOT / name, project / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        hashes[name] = sha(source)
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Archer CERT numeric only"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (project / 'capture.gd').write_text(NATIVE)
    commands = [[LOCK, str(ROOT / 'tools/run_with_timeout.py'), '180', godot,
                 '--headless', '--path', str(project), '--editor', '--import'],
                [LOCK, str(ROOT / 'tools/run_with_timeout.py'), '180', godot,
                 '--headless', '--path', str(project), '--script', str(project / 'capture.gd'),
                 '--', str(WORK / 'native.json')]]
    record = {'input_sha256': hashes, 'commands': commands, 'jobs': [],
              'extractor_sha256': hashlib.sha256(NATIVE.encode()).hexdigest()}
    write(WORK / 'execution.json', record)
    for index, command in enumerate(commands):
        # The shared lock encloses the existing bounded runner, including import.
        command[1:2] = [sys.executable, command[1]]
        log = WORK / f'native-{index}.log'
        with log.open('w') as stream:
            proc = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
            record['jobs'].append({'pid': proc.pid, 'log': str(log.relative_to(ROOT)), 'status': 'running'})
            write(WORK / 'execution.json', record)
            code = proc.wait()
        record['jobs'][-1].update(exit=code, status='completed', log_sha256=sha(log))
        write(WORK / 'execution.json', record)
        if code or re.search(r'SCRIPT ERROR|Parse Error|^ERROR:', log.read_text(), re.M):
            raise RuntimeError(f'native stage failed: {log}')
    if any(sha(ROOT / name) != digest or sha(project / name) != digest for name, digest in hashes.items()):
        raise ValueError('capture inputs changed')
    record['native_sha256'] = sha(WORK / 'native.json')
    write(WORK / 'execution.json', record)


def arrays(surface):
    count = surface['vertices']
    def read(key, dtype, width):
        return np.frombuffer(base64.b64decode(surface[key], validate=True), dtype=dtype).reshape(count, width)
    return (read('vertices_f32', '<f4', 3), read('bones_i32', '<i4', -1),
            read('weights_f32', '<f4', -1))


def material_patches(native, body):
    surface = body['surfaces'][0]
    v, j, w = arrays(surface)
    indices = np.frombuffer(base64.b64decode(surface['indices_i32']), dtype='<i4').reshape(-1, 3)
    rest = np.array([b['global_rest'] for b in native['bones']])
    sk = np.array(native['skeleton_to_model'])
    matrices = np.array([sk @ rest[b['bone']] @ np.array(b['pose']) for b in body['skin']])
    points = skin(v, j, w, matrices)
    triangles = points[indices]
    normal = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    # Godot uses clockwise front faces. Select downward-facing rest triangles
    # using stored outward normals, not a new lowest vertex at each animation time.
    normals = np.frombuffer(base64.b64decode(surface['normals_f32']), dtype='<f4').reshape(-1, 3)
    at = np.array(body['mesh_to_model'])
    normals = normals @ np.linalg.inv(at[:3, :3])
    out = {}
    for side in ('l', 'r'):
        binds = [i for i, b in enumerate(body['skin']) if b['name'] in ('foot.' + side, 'toes_01.' + side)]
        shoe = np.where(np.isin(j, binds), w, 0).sum(axis=1) > .8
        candidates = np.flatnonzero(shoe[indices].all(axis=1)
            & (normals[indices, 1].mean(axis=1) < 0)
            & (np.linalg.norm(normal, axis=1) > 0))
        if len(candidates) == 0:
            raise ValueError('missing material sole triangle')
        chosen = int(candidates[np.argmin(triangles[candidates, :, 1].max(axis=1))])
        ids = indices[chosen]
        out[side] = {'surface': 0, 'triangle': chosen, 'vertices': ids.tolist(),
                     'rest_model_positions_m': points[ids].tolist(),
                     'rest_area_m2': float(np.linalg.norm(normal[chosen]) / 2)}
    return out


def preserved_source():
    ref = '391f48adda4894ca453fa78a1e5c9bb2d63b560b'
    old = subprocess.check_output(['git', 'show', ref + ':' + BODY], cwd=ROOT)
    def read(data):
        if struct.unpack_from('<III', data) != (0x46546c67, 2, len(data)):
            raise ValueError('invalid GLB header')
        size = struct.unpack_from('<I', data, 12)[0]
        return json.loads(data[20:20 + size]), data[28 + size:]
    original, binary = read(old)
    current, appended = read((ROOT / BODY).read_bytes())
    for key, value in original.items():
        if key == 'buffers':
            continue
        actual = current[key]
        if key in ('animations', 'accessors', 'bufferViews'):
            actual = actual[:len(value)]
        if value != actual:
            raise ValueError('original source changed: ' + key)
    if appended[:len(binary)] != binary:
        raise ValueError('original source BIN changed')
    return {'git_ref': ref, 'sha256': hashlib.sha256(old).hexdigest(),
            'original_bin_bytes_preserved': len(binary),
            'original_clips_preserved': [a['name'] for a in original['animations']],
            'verification': 'Exact original JSON tables, old animation/accessor/view prefixes and all original BIN bytes compared independently.'}


def audit(source_blend):
    if sha(source_blend) != '5e35e49060dd2515c6f167dd3e6928a311b58435cb7081faddcb28012e9801e8':
        raise ValueError('source blend is not the accepted six-clip source')
    execution = json.loads((WORK / 'execution.json').read_text())
    if execution.get('native_sha256') != sha(WORK / 'native.json'):
        raise ValueError('unbound native dump')
    for name, digest in execution['input_sha256'].items():
        if sha(ROOT / name) != digest:
            raise ValueError('changed native input ' + name)
    native = json.loads((WORK / 'native.json').read_text())
    if native['body_sha256'] != sha(ROOT / BODY) or native['scene_sha256'] != sha(ROOT / MODEL):
        raise ValueError('native scene/body mismatch')
    if {m['name'] for m in native['meshes']} != {'archers', 'archers_bow', 'archers_quiver', 'archers_arrow'}:
        raise ValueError('incomplete equipped scene')
    body = next(m for m in native['meshes'] if m['name'] == 'archers')
    patches = material_patches(native, body)
    sk = np.array(native['skeleton_to_model'])
    prepared = []
    for mesh in native['meshes']:
        for index, surface in enumerate(mesh['surfaces']):
            prepared.append((mesh, index, arrays(surface)))
    def points(sample, mesh, a):
        global_pose = np.array(sample['globals'])
        matrices = np.array([sk @ global_pose[b['bone']] @ np.array(b['pose']) for b in mesh['skin']])
        return skin(*a, matrices), matrices
    march = next(s for s in native['samples'] if s['clip'] == 'MARCH' and s['phase'] == 0)
    baseline = {m['name']: points(march, m, a)[0] for m, _, a in prepared}
    boundaries, observed, contact_extrema, first_stance = [], {}, {}, []
    pivot_zero = {}
    for sample in native['samples']:
        clip = sample['clip']
        for mesh, surface, a in prepared:
            p, matrices = points(sample, mesh, a)
            radial = np.linalg.norm(p[:, [0, 2]], axis=1)
            worst = int(np.argmax(radial))
            key = clip + '/' + mesh['name']
            if key not in observed or radial[worst] > observed[key]['radius_model_m']:
                observed[key] = {'radius_model_m': float(radial[worst]), 'phase': sample['phase'],
                    'time_s': sample['time_s'], 'surface': surface, 'vertex': worst,
                    'position_model_m': p[worst].tolist()}
            if mesh['name'] == 'archers':
                for side, patch in patches.items():
                    triangle = p[patch['vertices']]
                    key = clip + '/' + side
                    gap = float(np.abs(triangle[:, 1]).max())
                    if key not in contact_extrema or gap > contact_extrema[key]['max_absolute_gap_m']:
                        normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
                        normal /= np.linalg.norm(normal)
                        contact_extrema[key] = {'phase': sample['phase'], 'max_absolute_gap_m': gap,
                            'positions_model_m': triangle.tolist(), 'unsigned_normal': normal.tolist(),
                            'meaning': 'Includes swing; diagnostic only, not a stance failure.'}
                if clip != 'MARCH' and sample['phase'] <= .125:
                    triangle = p[patches['r']['vertices']]
                    yaw = (1 if clip == 'PIVOT_LEFT' else -1) * np.pi * sample['phase']
                    c, s = np.cos(yaw), np.sin(yaw)
                    triangle = triangle @ np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])
                    if sample['phase'] == 0:
                        pivot_zero[clip] = triangle.copy()
                    slip = np.linalg.norm((triangle - pivot_zero[clip])[:, [0, 2]], axis=1)
                    first_stance.append({'clip': clip, 'phase': sample['phase'],
                        'max_slip_m': float(slip.max()), 'min_separation_m': float(triangle[:, 1].min()),
                        'max_separation_m': float(triangle[:, 1].max()),
                        'max_penetration_m': float(max(0, -triangle[:, 1].min()))})
            if clip != 'MARCH' and sample['phase'] in (0, 1):
                raw = baseline[mesh['name']]
                delta = np.linalg.norm(p - raw, axis=1)
                vertex = int(np.argmax(delta))
                _, raw_matrices = points(march, mesh, a)
                v, j, w = a
                witness = {'clip': clip, 'pivot_phase': sample['phase'], 'native_march_phase': 0,
                    'mesh': mesh['name'], 'surface': surface, 'vertex': vertex,
                    'max_jump_model_m': float(delta[vertex]), 'march_position_m': raw[vertex].tolist(),
                    'pivot_position_m': p[vertex].tolist(), 'bind_vertex_m': v[vertex].tolist(),
                    'raw_weights': w[vertex].tolist(), 'bind_indices': j[vertex].tolist(),
                    'march_skin_matrices': raw_matrices[j[vertex]].tolist(),
                    'pivot_skin_matrices': matrices[j[vertex]].tolist()}
                if mesh['name'] == 'archers':
                    witness['fixed_sole_patches'] = {side: {
                        'march_positions_m': raw[patch['vertices']].tolist(),
                        'pivot_positions_m': p[patch['vertices']].tolist(),
                        'max_material_jump_m': float(np.linalg.norm(p[patch['vertices']] - raw[patch['vertices']], axis=1).max())}
                        for side, patch in patches.items()}
                boundaries.append(witness)
    scale = json.loads((ROOT / 'docs/reviews/cluster-formations/evidence/cf01/measurements.json').read_text())['models']['archers']['scale_inputs']
    with (ROOT / 'data/army/unit_footprints.csv').open() as stream:
        footprint = next(row for row in csv.DictReader(stream) if row['arm'] == 'archers')
    with (ROOT / 'data/army/balance.csv').open() as stream:
        policy = [row for row in csv.DictReader(stream) if any(str(v).startswith('body_locomotion_archers_') for v in row.values())]
    if policy:
        raise ValueError('installed policy needs a new audit; this counterexample binds the pre-policy inputs')
    for value in observed.values():
        value['radius_world_m'] = value['radius_model_m'] * scale['world_scale']
        value['radius_simulation_m'] = value['radius_model_m'] * scale['simulation_scale']
    # This is the existing solver's arithmetic allowance, NOT a contact policy.
    solver = (ROOT / 'scripts/map3d/map3d_archer_pivot.gd').read_text()
    arithmetic_eps = float(re.search(r'const EPS: float = ([0-9.]+)', solver)[1])
    if max(b['max_jump_model_m'] for b in boundaries) <= arithmetic_eps:
        raise RuntimeError('frozen seam failure no longer reproduces; full certification must be implemented, not auto-passed')
    source = {'schema': 1, 'arm': 'archers', 'status': 'REJECTED_NATIVE_MARCH_SEAM',
        'certificate': None, 'source_blend': {'path': str(source_blend), 'sha256': sha(source_blend)},
        'input_sha256': execution['input_sha256'], 'capture': {
            'sha256': execution['native_sha256'], 'execution_sha256': sha(WORK / 'execution.json'),
            'path': str((WORK / 'native.json').relative_to(ROOT)), 'godot': native['godot'],
            'pid': native['pid'], 'sample_count': len(native['samples']),
            'kind': 'fresh headless numeric resource extraction; not a render or realtime visual check'},
        'audit_sha256': sha(Path(__file__)), 'clips': native['clips'], 'scale': scale,
        'immutable_original_source': preserved_source(),
        'frame_rate': {'native_import_fps': 30, 'pivot_key_spacing': 'nonuniform source keys retained by pivot_import.gd'},
        'policy': {'rows': policy, 'contact_um': None, 'turn_q': None, 'installed': False},
        'mapping': {'positive': 'PIVOT_RIGHT', 'negative': 'PIVOT_LEFT', 'tie_udeg': 180_000_000,
            'world_yaw': 'yaw_start - turn * phase', 'canonical_clip_duration_s': 2.0},
        'geometry': [{'mesh': m['name'], 'skin_bones': [b['name'] for b in m['skin']],
            'surfaces': [s['vertices'] for s in m['surfaces']]} for m in native['meshes']]}
    for name in ['tools/units3d/archer_arp/export.py', 'tools/units3d/archer_arp/pivot.py',
                 'scripts/map3d/map3d_archer_pivot.gd', 'data/army/unit_footprints.csv',
                 'data/army/balance.csv', 'data/screens/map3d/army_art.csv',
                 'docs/reviews/cluster-formations/evidence/cf01/measurements.json']:
        source['input_sha256'][name] = sha(ROOT / name)
    payload = json.dumps(source, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    source['payload_sha256'] = hashlib.sha256(payload).hexdigest()
    source['digest_rule'] = 'SHA256 canonical JSON excluding payload_sha256 and digest_rule; no certificate digest is issued.'
    contacts = {'schema': 1, 'status': 'FAIL', 'source_payload_sha256': source['payload_sha256'],
        'reason': 'Installed native MARCH at phase 0 and either pivot endpoint have different material vertex positions. Mapped MARCH cannot replace raw MARCH as the boundary baseline.',
        'existing_solver_arithmetic_allowance_m': arithmetic_eps,
        'allowance_is_contact_policy': False,
        'ground': {'model_y_m': 0.0, 'root_translation_changed': False, 'weights_normalized': False},
        'fixed_material_patches': patches, 'boundary_counterexamples': boundaries,
        'first_right_stance': {'interval': [0, .125], 'samples': first_stance,
            'basis': 'Accepted eight-step contact_plan: native phase-0 right stance remains planted while left foot swings. Material triangle chosen once in native rest.',
            'limitation': 'Only first stance sampled; no full-domain contact or positive-area contact PASS.'},
        'whole_cycle_patch_diagnostics': contact_extrema,
        'continuous_argument': 'The native clips use continuous TRS interpolation. A nonzero difference at their common boundary prevents C0 continuity. One admitted half-turn at MARCH phase 0 disproves the universal conjunction; finite interior samples do not certify any remaining domain.',
        'domain': {'half_turn_right': 'counterexample', 'half_turn_left': 'diagnostic symmetric counterexample',
            'all_microdegrees_phases_durations_and_arbitrary_native_march_entry_exit': 'NOT CERTIFIED',
            'near_zero_wrap': 'integer mapping selfchecks only; not physical acceptance'},
        'required_prerequisite_proposal': {
            'scope': 'Register a separate archer native-MARCH transition/contact authoring step before resuming CERT.',
            'candidate_paths': ['tools/units3d/archer_arp/pivot.py', 'scripts/map3d/map3d_archer_pivot.gd',
                                'tests/map3d/test_archer_pivot.gd'],
            'acceptance': 'Receive and release exact actual native MARCH poses and fixed material sole patches over every admitted entry/exit phase; preserve old source clips, gear, root seat, scale, radius and committed yaw/duration; demonstrate conservative continuous bounds and independently dense native checks.',
            'registration': 'PROPOSAL ONLY. No additional file ownership or implementation authorized.'},
        'visual': 'NOT RUN: numeric certification failed; inherited actual OS focus/pause issue remains unresolved.'}
    envelope = {'schema': 1, 'status': 'NOT_CERTIFIED', 'source_payload_sha256': source['payload_sha256'],
        'radius_simulation_m': int(footprint['radius_m']), 'ordinary_scale': scale,
        'equipped_observations': observed,
        'coverage': 'All native extracted body/bow/quiver/arrow vertices at every native key, quarter/mid/three-quarter interval and 257 uniform samples of each of three clips. Full yaw preserves XZ radius exactly.',
        'continuous_bound': {'status': 'NOT ESTABLISHED', 'reason': 'Finite native clip samples do not enclose interpolated poses or arbitrary adaptive entry/exit/turn parameters. Numeric contact boundary already fails; no full CERT or radius PASS follows.'},
        'retained_obligations': 'All original 12 P4 gates, full native real-window matrix, independent unique Review, later policy/consumer/activation remain required.'}
    for name, value in [('source.json', source), ('pivot-contacts.json', contacts), ('pivot-envelope.json', envelope)]:
        write(OUT / name, value)
    print('CERT REJECTED: maximum native seam jump model metres', max(b['max_jump_model_m'] for b in boundaries))
    return 2

def self_check():
    # Hand calculation: two raw weights .25 and .5, translated by 2 and 4.
    # Vertex x=1 -> .25*3 + .5*5 = 3.25, NOT normalized 4.333...
    matrices = np.repeat(np.eye(4)[None], 2, axis=0)
    matrices[:, 0, 3] = [2, 4]
    actual = skin(np.array([[1., 0, 0]]), np.array([[0, 1]]),
                  np.array([[.25, .5]]), matrices)
    np.testing.assert_allclose(actual, [[3.25, 0, 0]], atol=0, rtol=0)
    for weights in (np.array([[float('nan'), .5]]), np.array([[-.1, .5]])):
        try:
            skin(np.array([[1., 0, 0]]), np.array([[0, 1]]), weights, matrices)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid raw weights accepted')
    assert shortest(0, 180_000_000) == 180_000_000
    assert shortest(359_000_000, 1_000_000) == 2_000_000
    assert shortest(1_000_000, 359_000_000) == -2_000_000
    assert shortest(0, 1) == 1 and shortest(1, 0) == -1
    print('SELF_CHECK PASS: raw weights, invalid inputs, tie/wrap/microdegree')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--source-blend', type=Path)
    args = parser.parse_args()
    self_check()
    if args.capture:
        capture(args.godot)
    if args.source_blend:
        sys.exit(audit(args.source_blend.resolve(strict=True)))
    if not args.self_check and not args.capture:
        parser.error('supply --self-check, --capture, or --source-blend for the audit')
