"""Fresh cavalry component custody and portable replay; never a contact certificate."""
import argparse
import copy
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath

import check_cavalry_march_capture as audit

STEP = 'CAV-CONTACT-NATIVE-REACQUIRE'
ROOT = Path(__file__).resolve().parents[2]
PRIMARY = Path('/Users/samuelzhang/game_design')
EVIDENCE = PRIMARY / '.superpowers/cluster-formations-evidence-cache' / STEP
NAMESPACE = PRIMARY / 'assets/3D/units/cavalry/model_wip/contact-native-reacquired'
PROPOSAL_SHA = '18cc29e80ef90a9498a70c039740a731a4bc572e144d47ab35708ee6b31b22c8'
HISTORY = 'docs/reviews/cluster-formations/evidence/locomotion/cavalry'
SHARED_LOCK = '/Users/samuelzhang/game_design-wt/godot_lock.sh'
AUDIT_SHA = '2eeff65cc1ff6e4dc29882917ff776c98c0d8c119776aa9163a790ef58030adc'
LEGACY_NATIVE_SHA = '37266c5097ee2f5b80dbdc35e41c4d4a612bc06f6715bfd26b31601143792843'
LEGACY_PHASE_SHA = '534c62d6270d34ecd11394a2070572da95a35f5fed9bd55543c7bdd79d26f996'
require = audit.require
sha256 = audit.sha256


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def check_index(root, index, expected_digest):
    root = Path(root).resolve(strict=True)
    require(isinstance(index, list) and index and digest(index) == expected_digest, 'Bundle index digest mismatch')
    paths, roles = set(), {}
    for row in index:
        path, role = row['path'], row['role']
        require(isinstance(path, str) and path and '\\' not in path, 'Unsafe bundle path')
        relative = PurePosixPath(path)
        require(not relative.is_absolute() and str(relative) == path and
                all(part not in ('', '.', '..') for part in path.split('/')), 'Unsafe bundle path')
        require(path not in paths and isinstance(role, str) and role and role not in roles, 'Duplicate path/role')
        target = root / path
        require(not any(p.is_symlink() for p in [target, *target.parents] if p != root.parent), 'Symlink in bundle path')
        require(target.is_file() and target.resolve().is_relative_to(root), 'Missing/escaping bundle file')
        require(re.fullmatch('[0-9a-f]{64}', row['sha256']) is not None and sha256(target) == row['sha256'],
                'Bundle input hash mismatch')
        paths.add(path)
        roles[role] = target
    actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() or p.is_symlink()}
    require(actual == paths, 'Bundle is not closed')
    return roles


def publish_bundle(source, namespace, index):
    source, namespace = Path(source), Path(namespace)
    key = digest(index)
    check_index(source, index, key)
    destination = namespace / key
    namespace.mkdir(parents=True, exist_ok=True)
    require(not destination.exists(), 'Refusing to overwrite immutable bundle')
    shutil.copytree(source, destination)
    check_index(destination, index, key)
    return destination


def relocate_metadata(native, source, views, stage):
    """Rebind provenance on disposable copies; scientific arrays stay byte-for-byte values."""
    native, source, views = copy.deepcopy((native, source, views))
    native['project_root'] = str(stage / 'probe')
    native['engine_executable'] = str(stage / 'runtime/Godot')
    source['source_file'] = str(stage / 'source/body-response-c.blend')
    if views is not None:
        views['native_sha256'] = hashlib.sha256(canonical(native)).hexdigest()
    return native, source, views


def read_json(path):
    return json.loads(Path(path).read_text(), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))


def write_new(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(canonical(value))


def observe_job(command, run, name, progress_directory, *, use_shared_lock=True, seconds=300):
    """Observe one job without conflating shared-lock wait with its existing execution deadline."""
    run = Path(run).resolve()
    require(re.fullmatch('[a-z0-9-]+', name) is not None and seconds > 0, 'Invalid observation job')
    request = {'command': command, 'run': str(run), 'name': name,
               'progress_directory': str(Path(progress_directory).resolve()), 'seconds': seconds}
    request_path = run / (name + '-request.json')
    require(not request_path.exists(), 'Refusing to repeat observation job')
    write_new(request_path, request)
    events = run / (name + '-events.jsonl')
    with events.open('xb') as stream:
        stream.write(canonical({'event': 'lock_wait_begin', 'monotonic': time.monotonic(), 'utc_unix': time.time(),
                                'command': command, 'use_shared_lock': use_shared_lock,
                                'stdout': str(run / (name + '-stdout.log')),
                                'stderr': str(run / (name + '-stderr.log'))}) + b'\n')
    launcher = [sys.executable, str(Path(__file__).resolve()), '_observe-child', str(request_path)]
    if use_shared_lock:
        launcher.insert(0, SHARED_LOCK)
    with (run / (name + '-launcher-stdout.log')).open('xb') as out, \
            (run / (name + '-launcher-stderr.log')).open('xb') as err:
        return subprocess.run(launcher, cwd=ROOT, stdout=out, stderr=err).returncode


def observe_child(request_path):
    request = read_json(request_path)
    run, name = Path(request['run']), request['name']
    with (run / (name + '-events.jsonl')).open('ab') as events:
        def event(kind, **fields):
            events.write(canonical({'event': kind, 'monotonic': time.monotonic(), 'utc_unix': time.time(),
                                    **fields}) + b'\n')
            events.flush()

        event('lock_acquired', observer_pid=os.getpid(),
              timing_note='Observed after observer startup; preceding interval includes that startup.')
        supervisor = [sys.executable, str(ROOT / 'tools/run_with_timeout.py'), str(request['seconds']),
                      *request['command']]
        with (run / (name + '-stdout.log')).open('xb') as out, (run / (name + '-stderr.log')).open('xb') as err:
            process = subprocess.Popen(supervisor, cwd=ROOT, stdout=out, stderr=err)
            event('supervisor_started', pid=process.pid, argv=supervisor, deadline_seconds=request['seconds'])
            children = set()
            try:
                children, last_progress, last_change, sampled = set(), None, time.monotonic(), False
                while process.poll() is None:
                    # Only inspect descendants of this observer's own supervisor, never a global process list.
                    found = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True, text=True, timeout=2)
                    current_children = {int(p) for p in found.stdout.split()} if found.returncode == 0 else set()
                    for pid in sorted(current_children - children):
                        event('child_start_observed', pid=pid, parent_pid=process.pid, argv=request['command'])
                    children |= current_children
                    files = sorted(Path(request['progress_directory']).glob('*.png'), key=lambda p: p.stat().st_mtime_ns)
                    progress = [(p.name, p.stat().st_mtime_ns, p.stat().st_size) for p in files]
                    if progress != last_progress:
                        event('progress', count=len(progress), files=progress)
                        last_progress, last_change = progress, time.monotonic()
                    if not sampled and current_children and time.monotonic() - last_change >= 15:
                        sampled = True
                        for pid in sorted(current_children):
                            stats = subprocess.run(['ps', '-p', str(pid), '-o', 'pid=,ppid=,etime=,stat=,%cpu='],
                                                   capture_output=True, text=True, timeout=2)
                            event('stalled_child_observed', pid=pid, seconds_without_file_change=time.monotonic()-last_change,
                                  process_stats=stats.stdout.strip(), last_completed=progress[-1][0] if progress else None)
                            sample = run / (name + '-pid-' + str(pid) + '-sample.txt')
                            with (run / (name + '-sample-output.log')).open('ab') as sample_log:
                                result = subprocess.run(['sample', str(pid), '1', '1', '-file', str(sample)],
                                                        stdout=sample_log, stderr=subprocess.STDOUT, timeout=10)
                            event('stack_sample', pid=pid, path=str(sample), exit_code=result.returncode)
                    time.sleep(.1)
                result = process.wait()
                return result
            except BaseException as error:
                event('observer_error', error=repr(error))
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                event('job_end', exit_code=process.returncode, supervisor_pid=process.pid,
                      observed_child_pids=sorted(children),
                      png_count=len(list(Path(request['progress_directory']).glob('*.png'))))


def component_result(report):
    # Paths belong to provenance, and are rebound explicitly rather than treated as scientific results.
    return {k: v for k, v in report.items() if k not in {
        'inputs', 'capture_directory', 'source_geometry', 'views_manifest', 'accounting_payload',
        'frozen_paths', 'reproduction'}}


def sample_grid(boundaries, length):
    """Check the frozen capture's complete time/scenario schema, including key-search sides."""
    times = sorted(set(boundaries))
    samples = set(times)
    for left, right in zip(times, times[1:]):
        samples.update(left + (right-left)*share for share in [.25, .5, .75])
    samples.update(phase*length for phase in [.137, .25, .26, .27, .31, .45, .57, .58, .76, .999999])
    for key in times:
        for offset in [-.0000100001, -.00001, -.0000099999, -.000001, .000001]:
            value = key + offset
            if 0 <= value <= length:
                samples.add(value)
    return sorted(samples)


def review_images(views_path, output):
    """Keep pixel-exact padded shell crops and labelled six-mode whole/crop comparison sheets."""
    from PIL import Image, ImageChops, ImageDraw
    views, output = read_json(views_path), Path(output)
    output.mkdir(exist_ok=False)
    (output / 'crops').mkdir()
    regions, groups, crops = {}, {}, []
    for row in views['rows']:
        group = (row['hoof'], row['phase'], row['view'])
        if row['mode'] == 'isolated_material':
            with Image.open(Path(views_path).parent / row['file']) as image:
                rgb = image.convert('RGB')
                bounds = ImageChops.difference(rgb, Image.new('RGB', rgb.size, rgb.getpixel((0, 0)))).getbbox()
                require(bounds is not None, 'Empty material shell view')
                regions[group] = [max(0, bounds[0]-32), max(0, bounds[1]-32),
                                  min(rgb.width, bounds[2]+32), min(rgb.height, bounds[3]+32)]
    for row in views['rows']:
        name = row['file']
        require(Path(name).name == name, 'Unsafe native view filename')
        with Image.open(Path(views_path).parent / name) as image:
            image.crop(regions[row['hoof'], row['phase'], row['view']]).save(output / 'crops' / name)
        crops.append({'source': 'views/'+name, 'source_sha256': row['sha256'], 'crop': 'review/crops/'+name,
                      'crop_sha256': sha256(output / 'crops' / name),
                      'box': regions[row['hoof'], row['phase'], row['view']]})
        groups.setdefault((row['hoof'], row['phase']), []).append(row)
    for (hoof, phase), rows in groups.items():
        for kind in ['whole', 'crop']:
            sheet = Image.new('RGB', (6*340, 5*272), (24, 24, 24))
            draw = ImageDraw.Draw(sheet)
            for i, row in enumerate(rows):
                image_path = Path(views_path).parent / row['file'] if kind == 'whole' else output / 'crops' / row['file']
                with Image.open(image_path) as image:
                    tile = image.convert('RGB')
                    tile.thumbnail((320, 240))
                    x, y = (i % 6)*340, (i // 6)*272
                    sheet.paste(tile, (x+10, y+28))
                    draw.text((x+10, y+6), row['view']+' / '+row['mode'], fill=(235, 225, 200))
            sheet.save(output / f'{hoof}-p{phase:.3f}-{kind}.png')
    write_new(output / 'crops.json', crops)


def validate_crops(bundle, views, crop_index):
    from PIL import Image
    require(len(crop_index) == len(views['rows']), 'Incomplete crop matrix')
    for row, crop in zip(views['rows'], crop_index):
        name = row['file']
        require(Path(name).name == name and crop['source'] == 'views/'+name and
                crop['crop'] == 'review/crops/'+name and crop['source_sha256'] == row['sha256'], 'Unbound crop view')
        box = crop['box']
        require(len(box) == 4 and all(type(n) is int for n in box) and
                0 <= box[0] < box[2] <= 2560 and 0 <= box[1] < box[3] <= 1600, 'Invalid faithful crop rectangle')
        require(sha256(bundle / crop['crop']) == crop['crop_sha256'], 'Changed crop bytes')
        with Image.open(bundle / crop['source']) as original, Image.open(bundle / crop['crop']) as cut:
            expected = original.crop(box)
            require(cut.size == expected.size and cut.mode == expected.mode and
                    cut.tobytes() == expected.tobytes(), 'Crop is not pixel-exact')


def validate_bundle_inputs(bundle, roles):
    expected = {'native': 'native/native.json', 'samples': 'native/samples.jsonl',
                'source_geometry': 'source-geometry.json', 'source_blend': 'source/body-response-c.blend',
                'engine': 'runtime/Godot', 'anatomy': 'anatomy-authored-v2.json',
                'frozen_native': 'frozen/native.json', 'frozen_geometry': 'frozen/geometry.json',
                'witness': 'frozen/witness.json', 'views': 'views/views.json'}
    require(all(roles.get(k) == bundle / path for k, path in expected.items()), 'Canonical replay role mismatch')
    require(sha256(audit.__file__) == AUDIT_SHA, 'Merged audit helper changed')
    legacy = audit.read_bound(bundle / 'history/march-native-contact.json', LEGACY_NATIVE_SHA)
    audit.read_bound(bundle / 'history/march-phase.json', LEGACY_PHASE_SHA)
    require(sha256(bundle / 'history/native-reacquire-proposal.md') == PROPOSAL_SHA, 'Frozen proposal changed')
    for path, expected_sha in legacy['inputs'].items():
        if '/game_design/' in path and '/model_wip/' not in path and '/.superpowers/' not in path:
            relative = path.split('/game_design/', 1)[1]
            require(sha256(bundle / 'resources' / relative) == expected_sha, 'Immutable physical input changed: '+relative)
    for role, key in [('source_blend', 'source'), ('frozen_native', 'native'),
                      ('frozen_geometry', 'geometry'), ('witness', 'witness')]:
        require(sha256(roles[role]) == audit.FROZEN[key], 'Frozen source/observation changed')
    require(sha256(roles['engine']) == legacy['inputs']['/Applications/Godot.app/Contents/MacOS/Godot'],
            'Frozen engine executable changed')
    require(read_json(roles['anatomy']) == legacy['anatomy_definition'], 'Provisional authored anatomy changed')
    native, views = read_json(roles['native']), read_json(roles['views'])
    require(roles.get('review_index') == bundle / 'review/crops.json', 'Missing faithful crop index')
    validate_crops(bundle, views, read_json(roles['review_index']))
    require(views['native_sha256'] == sha256(roles['native']) and
            views['accounting_sha256'] == sha256(roles['accounting']), 'Raw view/native/accounting binding changed')
    require(native['input_hashes'] == {path: sha256(bundle / 'resources' / path)
                                     for path in native['input_hashes']}, 'Raw capture resource bindings changed')
    document, binary = audit.read_glb(bundle / 'resources' / audit.GLB)
    boundaries = {0., native['length']}
    for track in native['tracks']:
        boundaries.update(key['time'] for key in track['keys'])
    for track in audit.raw_tracks(document, binary).values():
        boundaries.update(float(t) for t in track['times'])
    require(native['span_boundaries_seconds'] == sorted(boundaries) and
            native['sample_times_seconds'] == sample_grid(boundaries, native['length']), 'Incomplete original scenario grid')
    require(len(native['surfaces']) == 1 and len(native['surfaces'][0]['vertices']) == 21175 and
            len(native['surfaces'][0]['indices']) == 57141 and len(native['bones']) == len(native['skin']) == 53,
            'Incomplete full native schema')
    surface = dict(native['surfaces'][0])
    surface['joints'] = audit.np.asarray(surface['joints']).reshape(-1, 4)
    surface['weights'] = audit.np.asarray(surface['weights']).reshape(-1, 4)
    with roles['samples'].open() as stream:
        first = json.loads(next(stream))
    stages = audit.operation_enclosures(native, first, surface, [audit.matrix(b['pose']) for b in native['skin']],
                                       audit.system_math())
    require(all(row['outside_components'] == 0 for row in stages.values()), 'First-sample operation accounting fails')


def portable_replay(bundle, index, bundle_sha):
    bundle = Path(bundle).resolve(strict=True)
    roles = check_index(bundle, index, bundle_sha)
    required = {'native', 'samples', 'source_geometry', 'source_blend', 'engine', 'anatomy',
                'frozen_native', 'frozen_geometry', 'witness', 'accounting', 'views'}
    require(required <= roles.keys(), 'Incomplete portable replay roles')
    validate_bundle_inputs(bundle, roles)
    with tempfile.TemporaryDirectory(prefix='cavalry-replay-') as directory:
        stage = Path(directory).resolve()
        for folder in ['resources', 'native', 'engine-source', 'views', 'source', 'runtime', 'frozen']:
            source = bundle / folder
            require(source.is_dir(), f'Missing replay folder: {folder}')
            shutil.copytree(source, stage / ('probe' if folder == 'resources' else folder))
        shutil.copyfile(roles['anatomy'], stage / 'anatomy-authored-v2.json')
        shutil.copyfile(roles['accounting'], stage / roles['accounting'].name)
        native, source, views = relocate_metadata(read_json(roles['native']), read_json(roles['source_geometry']),
                                                  read_json(roles['views']), stage)
        (stage / 'native/native.json').write_bytes(canonical(native))
        write_new(stage / 'source-geometry.json', source)
        (stage / 'views/views.json').write_bytes(canonical(views))
        require(len(native['sample_times_seconds']) == 154 and len(native['tracks']) == 46 and
                len(native['import_trace']['all_animation_baked']) == 7 and
                sum(len(t['keys']) for tracks in native['import_trace']['all_animation_baked'].values()
                    for t in tracks) == 77276, 'Incomplete capture grid/import payload')
        original_root = audit.ROOT
        try:
            audit.ROOT = stage / 'probe'
            report = audit.audit(stage / 'native', stage / 'source-geometry.json', stage / 'frozen/native.json',
                                 stage / 'frozen/geometry.json', stage / 'frozen/witness.json', stage / 'views/views.json')
        finally:
            audit.ROOT = original_root
        require(sha256(report['accounting_payload']) == sha256(roles['accounting']), 'Recomputed operation accounting differs')
        require(report['numerical_accounting']['status'] == 'SAMPLED_OPERATIONS_ENCLOSED', 'Unexplained sampled arithmetic')
        require({hoof: p['sole_triangles'] for hoof, p in report['patch_counts'].items()} ==
                {'FrontHoof.L': 31, 'FrontHoof.R': 69, 'HindHoof.L': 46, 'HindHoof.R': 48}, 'Incomplete material partition')
        return component_result(report)


def fetch_github(endpoint):
    require(re.fullmatch(r'repos/samuelzhang1201/game_design/(issues/comments/[1-9][0-9]*|pulls/[1-9][0-9]*)', endpoint)
            is not None, 'Unrelated GitHub endpoint')
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True, timeout=30))


def verify(manifest_path, bundle_root, review_record=None):
    manifest = read_json(manifest_path)
    require(manifest['version'] == 1 and manifest['step_id'] == STEP and
            manifest['status'] == 'CAPTURED_COMPONENT_INDEPENDENT_ACCEPTANCE_PENDING', 'Unknown new manifest schema')
    require(re.fullmatch('[0-9a-f]{40}', manifest['producer_head']) is not None, 'Invalid frozen producer HEAD')
    require(manifest['claims'] == {'source_import_anatomy_sampled': 'PENDING_INDEPENDENT_REVIEW',
            'continuous_arithmetic': False, 'physical_contact': False, 'phase_candidate': False,
            'CERT': False, 'policy_E': None, 'P4': False}, 'Overclaiming component scope')
    roles = check_index(bundle_root, manifest['bundle_index'], manifest['bundle_sha256'])
    require(manifest['producer_code_sha256'] == sha256(__file__) and
            sha256(roles['producer']) == manifest['producer_code_sha256'], 'Frozen producer code differs')
    repository_inputs = {role.split(':', 1)[1]: path for role, path in roles.items()
                         if role.startswith('resource:') and role != 'resource:project.godot'}
    repository_inputs.update({'tools/units3d/reacquire_cavalry_march_native.py': roles['producer'],
                              'tools/units3d/test_reacquire_cavalry_march_native.py': roles['producer_tests']})
    for path, file in repository_inputs.items():
        committed = subprocess.check_output(['git', 'show', manifest['producer_head']+':'+path], cwd=ROOT)
        require(hashlib.sha256(committed).hexdigest() == sha256(file), 'Input differs from frozen producer HEAD: '+path)
    result = portable_replay(bundle_root, manifest['bundle_index'], manifest['bundle_sha256'])
    require(result == manifest['component_result'], 'Actual replay differs from manifest')
    roles = check_index(bundle_root, manifest['bundle_index'], manifest['bundle_sha256'])
    native = read_json(roles['native'])
    require(manifest['sample_grid_sha256'] == digest(native['sample_times_seconds']) and
            manifest['physical_input_hashes'] == native['input_hashes'] and
            manifest['adverse_new_measurements'] == adverse_measurements(result), 'Manifest payload binding changed')
    require(manifest['proposal_sha256'] == PROPOSAL_SHA and manifest['history'] ==
            {'234': 'NOT_RESTORED_NEW_BYTES_NEW_REVIEW_REQUIRED', '242': 'DIAGNOSTIC_ONLY'}, 'Historical scope changed')
    if review_record is not None:
        record = read_json(review_record)
        common = subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=ROOT, text=True).strip()
        registry = read_json((ROOT / common).resolve() / 'codex-handoffs.json')
        number = record['binding']['pr_number']
        require(type(number) is int and number > 0, 'Invalid Review PR number')
        pr_url = f'https://github.com/samuelzhang1201/game_design/pull/{number}'
        pair = dict(registry['steps'][STEP], pr_url=pr_url)
        registered = registry['prs'][pr_url]
        require(all(registered[k] == pair[k] for k in
                    ['step_id', 'implementation_session_id', 'review_session_id']), 'Unregistered Review PR')
        published = fetch_github(f'repos/samuelzhang1201/game_design/issues/comments/{record["comment"]["id"]}')
        validate_receipt(record, manifest, sha256(manifest_path), pair, published)
        pr = fetch_github(f'repos/samuelzhang1201/game_design/pulls/{number}')
        require(pr['head']['ref'] == 'codex/cavalry-contact-native-reacquire' and
                pr['base']['ref'] == 'main', 'Unrelated reviewed PR')
    return result


def load_accepted(manifest_path, bundle_root, review_record):
    require(review_record is not None, 'Actual new independent receipt required')
    result = verify(manifest_path, bundle_root, review_record)
    manifest = read_json(manifest_path)
    roles = check_index(bundle_root, manifest['bundle_index'], manifest['bundle_sha256'])
    return {'manifest': manifest, 'native': read_json(roles['native']), 'accounting': read_json(roles['accounting']),
            'component_result': result}


def validate_receipt(record, manifest, manifest_sha, pair, published):
    comment, binding = record['comment'], record['binding']
    matched = re.fullmatch(r'https://github.com/samuelzhang1201/game_design/pull/([1-9][0-9]*)', pair['pr_url'])
    require(matched is not None, 'Invalid registered PR')
    number = int(matched[1])
    require(comment == published and isinstance(comment['id'], int) and comment['id'] > 0,
            'Receipt differs from actual published GitHub record')
    require(comment['issue_url'] == f'https://api.github.com/repos/samuelzhang1201/game_design/issues/{number}'
            and comment['html_url'] == f'{pair["pr_url"]}#issuecomment-{comment["id"]}',
            'Unrelated GitHub receipt')
    require(comment['user']['id'] > 0 and comment['user']['login'] and comment['created_at'] and comment['updated_at'],
            'Missing GitHub receipt identity')
    require(hashlib.sha256(comment['body'].encode()).hexdigest() == record['body_sha256'], 'Published body digest mismatch')
    blocks = re.findall(r'```json\s*\n(.*?)\n```', comment['body'], re.DOTALL)
    require(len(blocks) == 1 and json.loads(blocks[0]) == binding, 'Verdict body/binding mismatch')
    require(pair['implementation_session_id'] == manifest['implementation_session_id'] and
            pair['review_session_id'] == manifest['review_session_id'] and
            pair['review_session_id'] != pair['implementation_session_id'], 'Registered owner pair mismatch')
    expected = {'step_id': STEP, 'verdict': 'ACCEPT_SOURCE_IMPORT_ANATOMY_SAMPLED_COMPONENT',
                'manifest_sha256': manifest_sha, 'bundle_sha256': manifest['bundle_sha256'],
                'producer_head': manifest['producer_head'], 'review_session_id': manifest['review_session_id'],
                'implementation_session_id': manifest['implementation_session_id'], 'pr_number': number,
                'continuous_contact_certified': False}
    require(all(binding.get(k) == v for k, v in expected.items()) and
            isinstance(binding.get('unresolved'), list) and binding['unresolved'], 'Unrelated or overclaiming Review verdict')
    return binding


def adverse_measurements(report):
    points = report['current_native_witness_positions']
    result = {}
    for stride in [5.9, 2.4]:
        delta = [points['0.25'][i] - points['0.137'][i] +
                 (stride * (.25 - .137) if i == 2 else 0) for i in range(3)]
        result[str(stride)] = {'vertex': 16496, 'phases': [.137, .25], 'stride_model_m': stride,
                              'displacement_model_m': delta, 'horizontal_slip_model_m': math.hypot(delta[0], delta[2]),
                              'status': 'ADVERSE_NEW_MEASUREMENT_NOT_CONTACT_CERTIFICATE'}
    return result


def existing_audit(run, views=None):
    custody = EVIDENCE / 'source-custody'
    report = audit.audit(run / 'native', run / 'source-geometry.json',
                         custody / audit.FROZEN['native'] / 'godot-imported-native-v3.json',
                         custody / audit.FROZEN['geometry'] / 'godot-imported-geometry-v3.json',
                         custody / audit.FROZEN['witness'] / 'march-contact-witness.json', views)
    require(report['numerical_accounting']['status'] == 'SAMPLED_OPERATIONS_ENCLOSED', 'Unexplained sampled arithmetic')
    return report


def freeze_acquisition(run, manifest_path, views_path=None, report_path=None):
    """Close all evidence, replay it, then preserve two complete copies before writing metadata."""
    run = Path(run).resolve(strict=True)
    require(not Path(manifest_path).exists(), 'Refusing to overwrite manifest')
    views_path = Path(views_path).resolve() if views_path else run / 'views/views.json'
    report = read_json(report_path) if report_path else existing_audit(run, views_path)
    require(report['capture_directory'] == str(run / 'native') and
            report['source_geometry'] == str(run / 'source-geometry.json') and
            report['views_manifest'] == str(views_path), 'Unrelated final-input audit')
    for path, expected_sha in report['inputs'].items():
        require(sha256(path) == expected_sha, 'Final-input audit evidence changed: '+path)
    raw = Path(tempfile.mkdtemp(prefix='bundle-building-', dir=EVIDENCE))
    roles = {}

    def keep(source, relative, role=None):
        destination = raw / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        require(sha256(source) == sha256(destination), 'Evidence copy changed bytes')
        roles[relative] = role or relative

    keep(run / 'native/native.json', 'native/native.json', 'native')
    keep(run / 'native/samples.jsonl', 'native/samples.jsonl', 'samples')
    keep(run / 'native/import-replay.res', 'native/import-replay.res', 'import_replay')
    keep(run / 'source-geometry.json', 'source-geometry.json', 'source_geometry')
    keep(run / 'anatomy-authored-v2.json', 'anatomy-authored-v2.json', 'anatomy')
    keep(report['accounting_payload'], Path(report['accounting_payload']).name, 'accounting')
    source = read_json(run / 'source-geometry.json')
    keep(source['source_file'], 'source/body-response-c.blend', 'source_blend')
    native = read_json(run / 'native/native.json')
    keep(native['engine_executable'], 'runtime/Godot', 'engine')
    keep(__file__, 'producer/reacquire_cavalry_march_native.py', 'producer')
    keep(ROOT / 'tools/units3d/test_reacquire_cavalry_march_native.py',
         'producer/test_reacquire_cavalry_march_native.py', 'producer_tests')
    for kind, filename in [('native', 'native.json'), ('geometry', 'geometry.json'), ('witness', 'witness.json')]:
        keep(report['frozen_paths'][kind], 'frozen/' + filename, 'frozen_' + kind if kind != 'witness' else 'witness')
    original = EVIDENCE / 'source-custody/254de0fd87286f654bcf50917a8db004e9f7413a4c416903c4e00c10961fc700/cavalry_rig_work.blend'
    keep(original, 'source/cavalry_rig_work.blend', 'original_source_blend')
    resources = {path: ROOT / path for path in native['input_hashes'] if path != 'project.godot'}
    resources['project.godot'] = run / 'probe/project.godot'
    for path in report['inputs']:
        candidate = Path(path)
        if candidate.is_relative_to(ROOT) and '/model_wip/' not in path:
            resources[str(candidate.relative_to(ROOT))] = candidate
    # Calibration and support domain stay bound to the complete accepted tables, not copied tuning values.
    for folder in ['data/army', 'data/battle', 'data/screens/map3d']:
        for file in (ROOT / folder).glob('*.csv'):
            resources[str(file.relative_to(ROOT))] = file
    for path, source_path in sorted(resources.items()):
        keep(source_path, 'resources/' + path, 'resource:' + path)
    for file in sorted((run / 'engine-source').rglob('*')):
        if file.is_file():
            relative = 'engine-source/' + str(file.relative_to(run / 'engine-source'))
            keep(file, relative)
    for file in sorted(views_path.parent.iterdir()):
        if file.is_file():
            keep(file, 'views/' + file.name, 'views' if file.name == 'views.json' else None)
    review = raw / 'review'
    review_images(views_path, review)
    for file in sorted(review.rglob('*')):
        if file.is_file():
            relative = str(file.relative_to(raw))
            roles[relative] = 'review_index' if file.name == 'crops.json' else relative
    for file in sorted(run.glob('*.log')):
        keep(file, 'logs/' + file.name)
    for file in sorted(run.glob('audit-*.json')):
        keep(file, 'logs/' + file.name)
    if report_path:
        keep(report_path, 'logs/audit-final.json')
    for name in ['required-views-failure.json', 'diagnosis-20261104-01.json',
                 'observation-20261104-02-result.json', 'diagnosis-engine-sources-index.json']:
        if (EVIDENCE / name).exists():
            keep(EVIDENCE / name, 'history/' + name)
    if views_path.parent.parent != run:
        for file in sorted(views_path.parent.parent.iterdir()):
            if file.is_file():
                keep(file, 'observation/' + file.name)
    for file in sorted((run / 'views').glob('*.png')):
        keep(file, 'history/partial-views/' + file.name)
    for filename in ['march-native-contact.json', 'march-phase.json']:
        keep(ROOT / HISTORY / filename, 'history/' + filename)
    keep(PRIMARY / '.superpowers/cluster-formations-dispatch/cavalry-archive-custody.json',
         'history/cavalry-archive-custody.json')
    proposal = PRIMARY / '.superpowers/cluster-formations-dispatch/frozen-inputs' / (PROPOSAL_SHA + '.md')
    require(sha256(proposal) == PROPOSAL_SHA, 'Frozen proposal changed')
    keep(proposal, 'history/native-reacquire-proposal.md')
    index = [{'path': path, 'role': role, 'sha256': sha256(raw / path)} for path, role in sorted(roles.items())]
    key = digest(index)
    replay = portable_replay(raw, index, key)
    require(replay == component_result(report), 'Portable replay changed component results')
    primary = publish_bundle(raw, NAMESPACE, index)
    archive = publish_bundle(raw, EVIDENCE / 'bundles', index)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    checkpoint = read_json(ROOT / '.superpowers/cavalry-contact-native-reacquire/setup-checkpoint.json')
    manifest = {'version': 1, 'step_id': STEP, 'capture_id': 'cavalry-native-' + key[:20],
                'status': 'CAPTURED_COMPONENT_INDEPENDENT_ACCEPTANCE_PENDING', 'producer_head': head,
                'producer_code_sha256': sha256(__file__),
                'capture_source_head': checkpoint['base'], 'implementation_session_id': checkpoint['implementation_session_id'],
                'review_session_id': checkpoint['review_session_id'],
                'proposal_sha256': PROPOSAL_SHA, 'bundle_sha256': key, 'bundle_index': index,
                'custody_annotations': [str(primary), str(archive)], 'component_result': replay,
                'adverse_new_measurements': adverse_measurements(report),
                'sample_grid_sha256': digest(native['sample_times_seconds']),
                'physical_input_hashes': native['input_hashes'],
                'history': {'234': 'NOT_RESTORED_NEW_BYTES_NEW_REVIEW_REQUIRED', '242': 'DIAGNOSTIC_ONLY'},
                'relocation': {'native': ['project_root', 'engine_executable'], 'source': ['source_file'],
                               'views': ['native_sha256'], 'scientific_arrays': 'UNCHANGED',
                               'method': 'Disposable copies only; existing merged audit assertions and operations are unchanged.'},
                'claims': {'source_import_anatomy_sampled': 'PENDING_INDEPENDENT_REVIEW',
                           'continuous_arithmetic': False, 'physical_contact': False, 'phase_candidate': False,
                           'CERT': False, 'policy_E': None, 'P4': False}}
    write_new(manifest_path, manifest)
    return manifest


def capture(run, manifest_path, views_path=None, report_path=None):
    """Acquire through unchanged producers using the inherited finite 300s job budget."""
    run = Path(run).resolve()
    if views_path is not None:
        require(report_path is not None, 'Reusing completed views requires the final-input audit')
        return freeze_acquisition(run, manifest_path, views_path, report_path)
    require(not run.exists(), 'Refusing to overwrite acquisition')
    require(not Path(manifest_path).exists(), 'Refusing to overwrite manifest')
    run.mkdir(parents=True)
    custody = read_json(EVIDENCE / 'source-custody/custody-index.json')
    for row in custody['files']:
        require(sha256(row['custody']) == row['sha256'], 'Missing/changed durable source custody')
    proposal = read_json(ROOT / HISTORY / 'march-native-contact.json')
    write_new(run / 'anatomy-authored-v2.json', proposal['anatomy_definition'])
    audit.prepare(run / 'probe')

    def execute(name, command):
        result = observe_job(command, run, name, run / 'views', use_shared_lock=True)
        if result != 0:
            raise subprocess.CalledProcessError(result, command)

    godot = '/Applications/Godot.app/Contents/MacOS/Godot'
    godot_command = [godot, '--path', str(run / 'probe')]
    execute('import', godot_command + ['--headless', '--editor', '--import'])
    blend = EVIDENCE / 'source-custody' / audit.FROZEN['source'] / 'body-response-c.blend'
    execute('source', ['/Applications/Blender.app/Contents/MacOS/Blender', '--background', '--factory-startup',
                      '--disable-autoexec', str(blend), '--python', str(ROOT / 'tools/units3d/check_cavalry_march_capture.py'),
                      '--', 'source', str(run / 'source-geometry.json')])
    execute('native', godot_command + ['--headless', '--script', 'res://tools/units3d/cavalry_march_capture.gd',
                                     '--', '--out', str(run / 'native')])
    engine = run / 'engine-source'
    for name, reference in proposal['engine_source_references'].items():
        path = engine / name
        path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '20',
                        reference['url'], '--output', str(path)], check=True)
        require(sha256(path) == reference['sha256'], 'Pinned engine source mismatch')
    write_new(engine / 'sources-v5.json', proposal['engine_source_references'])
    report = existing_audit(run)
    write_new(run / 'audit-no-views.json', report)
    execute('views', godot_command + ['--script', 'res://tools/units3d/cavalry_march_capture.gd', '--',
                                    '--views', str(run / 'views'), '--native', str(run / 'native/native.json'),
                                    '--accounting', report['accounting_payload']])
    return freeze_acquisition(run, manifest_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    observer = commands.add_parser('_observe-child')
    observer.add_argument('request', type=Path)
    acquire = commands.add_parser('capture')
    acquire.add_argument('new_run', type=Path)
    acquire.add_argument('--out', type=Path, required=True)
    acquire.add_argument('--views', type=Path, help='Reuse this existing complete views.json without acquiring again')
    acquire.add_argument('--audit', type=Path, help='Existing final-input audit; replay is still recomputed from raw data')
    check = commands.add_parser('verify')
    check.add_argument('manifest', type=Path)
    check.add_argument('--bundle-root', type=Path, required=True)
    check.add_argument('--review-record', type=Path)
    args = parser.parse_args()
    if args.command == '_observe-child':
        return observe_child(args.request)
    elif args.command == 'capture':
        result = capture(args.new_run, args.out, args.views, args.audit)
        print('CAPTURED_COMPONENT_PENDING_REVIEW', result['bundle_sha256'])
    else:
        verify(args.manifest, args.bundle_root, args.review_record)
        print('ACCEPTED_COMPONENT_RECEIPT_VERIFIED' if args.review_record else 'REPLAYED_COMPONENT_PENDING_REVIEW')


if __name__ == '__main__':
    sys.exit(main())
