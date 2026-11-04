"""Portable custody and actual published-review boundary controls."""
import copy
import hashlib
import json
import shutil
import tempfile
import sys
import subprocess
import time
import unittest
from unittest.mock import patch
from pathlib import Path

import reacquire_cavalry_march_native as fresh


class BundleTests(unittest.TestCase):
    def test_observer_failure_still_stops_its_own_supervisor(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            request = run / 'request.json'
            fresh.write_new(request, {'command': [sys.executable, '-c', 'import time;time.sleep(30)'],
                                     'run': str(run), 'name': 'broken', 'seconds': 5,
                                     'progress_directory': str(run / 'views')})
            real_popen = subprocess.Popen
            processes = []

            def start(*args, **kwargs):
                process = real_popen(*args, **kwargs)
                processes.append(process)
                return process

            def failed_observation(*args, **kwargs):
                time.sleep(.2)
                raise RuntimeError('diagnostic observer failed')

            with patch.object(fresh.subprocess, 'Popen', start), patch.object(fresh.subprocess, 'run', failed_observation):
                try:
                    with self.assertRaises(RuntimeError):
                        fresh.observe_child(request)
                    self.assertIsNotNone(processes[0].poll(), 'Observer must not release lock with its child still running')
                finally:
                    if processes[0].poll() is None:
                        processes[0].terminate()
                        processes[0].wait(timeout=5)

    def test_rehashed_rgba_crop_with_unchanged_alpha_cannot_hide_changed_rgb(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'views').mkdir()
            (root / 'review/crops').mkdir(parents=True)
            original = Image.new('RGBA', (4, 4), (100, 100, 100, 255))
            original.save(root / 'views/a.png')
            cropped = original.crop((1, 1, 3, 3))
            cropped.save(root / 'review/crops/a.png')
            row = {'file': 'a.png', 'sha256': fresh.sha256(root / 'views/a.png')}
            index = [{'source': 'views/a.png', 'crop': 'review/crops/a.png', 'box': [1, 1, 3, 3],
                      'source_sha256': row['sha256'], 'crop_sha256': fresh.sha256(root / 'review/crops/a.png')}]
            fresh.validate_crops(root, {'rows': [row]}, index)
            cropped.putpixel((0, 0), (1, 2, 3, 255))
            cropped.save(root / 'review/crops/a.png')
            index[0]['crop_sha256'] = fresh.sha256(root / 'review/crops/a.png')
            with self.assertRaisesRegex(ValueError, 'pixel-exact'):
                fresh.validate_crops(root, {'rows': [row]}, index)

    def test_grid_contains_quarters_support_phases_loop_and_search_sides(self):
        grid = fresh.sample_grid([0., 1.], 1.)
        self.assertEqual(grid, sorted(set(grid)))
        for value in [0., .25, .5, .75, 1., .137, .999999, .000001,
                      1.-.0000100001, 1.-.00001, 1.-.0000099999]:
            self.assertIn(value, grid)
        self.assertNotIn(-.000001, grid)

    def test_accepted_loader_rejects_absent_receipt_before_reading_data(self):
        with self.assertRaisesRegex(ValueError, 'receipt required'):
            fresh.load_accepted(Path('/absent/manifest'), Path('/absent/bundle'), None)

    def test_role_alias_cannot_redirect_audit_to_different_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            roles = {'native': root / 'other/native.json'}
            with self.assertRaisesRegex(ValueError, 'Canonical replay role'):
                fresh.validate_bundle_inputs(root, roles)

    def test_shared_lock_wait_does_not_spend_child_execution_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            lock = run / 'lock-fixture.sh'
            lock.write_text('#!/bin/sh\nsleep 1.2\nexec "$@"\n')
            lock.chmod(0o700)
            with patch.object(fresh, 'SHARED_LOCK', str(lock)):
                result = fresh.observe_job([sys.executable, '-c', 'import time;time.sleep(.1)'],
                                           run, 'queued', run / 'views', seconds=1)
            self.assertEqual(result, 0)
            events = [json.loads(s) for s in (run / 'queued-events.jsonl').read_text().splitlines()]
            self.assertGreaterEqual(events[1]['monotonic'] - events[0]['monotonic'], 1.2)
            self.assertLess(events[-1]['monotonic'] - events[1]['monotonic'], 1)

    def test_observed_job_preserves_nonzero_exit_and_regular_file_output(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            command = [sys.executable, '-c', 'import sys;print("out");print("err",file=sys.stderr);sys.exit(7)']
            result = fresh.observe_job(command, run, 'failure', run / 'views', use_shared_lock=False)
            self.assertEqual(result, 7)
            events = [json.loads(s) for s in (run / 'failure-events.jsonl').read_text().splitlines()]
            self.assertEqual([e['event'] for e in events[:2]], ['lock_wait_begin', 'lock_acquired'])
            self.assertEqual(events[-1]['event'], 'job_end')
            self.assertEqual(events[-1]['exit_code'], 7)
            self.assertGreaterEqual(events[-1]['monotonic'], events[1]['monotonic'])
            self.assertIn('out', (run / 'failure-stdout.log').read_text())
            self.assertIn('err', (run / 'failure-stderr.log').read_text())

    def test_observed_timeout_remains_failure_and_retains_partial_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            progress = run / 'views'
            command = [sys.executable, '-c',
                       'import pathlib,time; p=pathlib.Path(' + repr(str(progress)) + ');'
                       'p.mkdir();(p/"partial.png").write_bytes(b"partial");time.sleep(30)']
            self.assertEqual(fresh.observe_job(command, run, 'timeout', progress,
                                              use_shared_lock=False, seconds=1), 124)
            events = [json.loads(s) for s in (run / 'timeout-events.jsonl').read_text().splitlines()]
            self.assertTrue(any(e['event'] == 'progress' and e['count'] == 1 for e in events))
            self.assertEqual(events[-1]['exit_code'], 124)
            self.assertEqual((progress / 'partial.png').read_bytes(), b'partial')
            self.assertIn('timed out after 1s', (run / 'timeout-stderr.log').read_text())
            with self.assertRaises(ValueError):
                fresh.observe_job(command, run, 'timeout', progress, use_shared_lock=False, seconds=1)

    def test_relocation_changes_only_explicit_provenance_fields(self):
        native = {'project_root': '/old/probe', 'engine_executable': '/old/Godot',
                  'bones': [{'default_position': [1, 2, 3]}], 'tracks': [{'keys': [1]}]}
        source = {'source_file': '/old/C.blend', 'parts': [17], 'vertices': [[1, 2, 3]]}
        views = {'native_sha256': fresh.digest(native), 'rows': [{'file': 'view.png'}]}
        original = copy.deepcopy((native, source, views))
        n, s, v = fresh.relocate_metadata(native, source, views, Path('/new'))
        self.assertEqual((native, source, views), original)
        self.assertEqual(n, dict(native, project_root='/new/probe', engine_executable='/new/runtime/Godot'))
        self.assertEqual(s, dict(source, source_file='/new/source/body-response-c.blend'))
        self.assertEqual(v, dict(views, native_sha256=hashlib.sha256(fresh.canonical(n)).hexdigest()))

    def test_canonical_digest_is_order_independent_and_rejects_nonfinite(self):
        self.assertEqual(fresh.digest({'a': 1, 'b': [2]}), fresh.digest({'b': [2], 'a': 1}))
        with self.assertRaises(ValueError):
            fresh.digest({'x': float('nan')})

    def test_explicit_root_relocation_and_missing_tampered_or_escaping_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'native.json').write_text('{"weights":[0.75]}')
            entry = {'path': 'native.json', 'sha256': fresh.sha256(root / 'native.json'), 'role': 'native'}
            index = [entry]
            self.assertEqual(fresh.check_index(root, index, fresh.digest(index)), {'native': root.resolve() / 'native.json'})
            for path in ['../native.json', '/native.json', 'a/../native.json', './native.json', 'a\\native.json']:
                bad = [dict(entry, path=path)]
                with self.subTest(path=path), self.assertRaises(ValueError):
                    fresh.check_index(root, bad, fresh.digest(bad))
            (root / 'link').symlink_to(root / 'native.json')
            bad = [dict(entry, path='link')]
            with self.assertRaises(ValueError):
                fresh.check_index(root, bad, fresh.digest(bad))
            (root / 'link').unlink()
            (root / 'native.json').write_text('{"weights":[1]}')
            with self.assertRaises(ValueError):
                fresh.check_index(root, index, fresh.digest(index))
            (root / 'native.json').unlink()
            with self.assertRaises(ValueError):
                fresh.check_index(root, index, fresh.digest(index))

    def test_closed_index_rejects_unindexed_files_duplicate_paths_and_duplicate_roles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'a').write_text('a')
            entry = {'path': 'a', 'sha256': fresh.sha256(root / 'a'), 'role': 'native'}
            for index in [[entry, entry], [entry, dict(entry, role='source')]]:
                with self.assertRaises(ValueError):
                    fresh.check_index(root, index, fresh.digest(index))
            (root / 'b').write_text('b')
            with self.assertRaises(ValueError):
                fresh.check_index(root, [entry], fresh.digest([entry]))

    def test_publish_refuses_overwrite_and_rehashes_durable_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / 'source'
            source.mkdir()
            (source / 'a').write_text('a')
            index = [{'path': 'a', 'sha256': fresh.sha256(source / 'a'), 'role': 'source'}]
            bundle = fresh.publish_bundle(source, base / 'durable', index)
            self.assertEqual(bundle.name, fresh.digest(index))
            self.assertEqual((bundle / 'a').read_bytes(), b'a')
            with self.assertRaises(ValueError):
                fresh.publish_bundle(source, base / 'durable', index)

    def test_receipt_binds_actual_github_body_manifest_bundle_head_and_registered_pair(self):
        manifest = {'step_id': fresh.STEP, 'producer_head': 'a' * 40, 'bundle_sha256': 'b' * 64,
                    'implementation_session_id': 'implementation-1', 'review_session_id': 'review-1'}
        binding = {'step_id': fresh.STEP, 'verdict': 'ACCEPT_SOURCE_IMPORT_ANATOMY_SAMPLED_COMPONENT',
                   'manifest_sha256': 'c' * 64, 'bundle_sha256': 'b' * 64, 'producer_head': 'a' * 40,
                   'review_session_id': 'review-1', 'implementation_session_id': 'implementation-1',
                   'pr_number': 999, 'continuous_contact_certified': False,
                   'unresolved': ['continuous contact and phase remain unaccepted']}
        body = 'Independent verdict\n```json\n' + json.dumps(binding) + '\n```'
        published = {'id': 42, 'node_id': 'IC_42',
                     'html_url': 'https://github.com/samuelzhang1201/game_design/pull/999#issuecomment-42',
                     'issue_url': 'https://api.github.com/repos/samuelzhang1201/game_design/issues/999',
                     'body': body, 'user': {'id': 123, 'login': 'reviewer'}, 'created_at': '2026-11-04T00:00:00Z',
                     'updated_at': '2026-11-04T00:00:00Z', 'reactions': {'total_count': 0, '+1': 0}}
        record = {'comment': published, 'body_sha256': hashlib.sha256(body.encode()).hexdigest(), 'binding': binding}
        pair = {'implementation_session_id': 'implementation-1', 'review_session_id': 'review-1',
                'pr_url': 'https://github.com/samuelzhang1201/game_design/pull/999'}
        self.assertEqual(fresh.validate_receipt(record, manifest, 'c' * 64, pair, published), binding)
        live = copy.deepcopy(published)
        live['reactions'].update({'total_count': 1, '+1': 1})
        with self.subTest(metadata='reaction-only'):
            self.assertEqual(fresh.validate_receipt(record, manifest, 'c'*64, pair, live), binding)
        self.assertEqual(record['comment']['reactions'], {'total_count': 0, '+1': 0}, 'Preserve the full frozen snapshot')
        live['user']['avatar_url'] = 'https://example.invalid/new-avatar'
        live['updated_at'] = '2026-11-04T01:00:00Z'
        with self.subTest(metadata='unrelated-live-profile-and-update-time'):
            self.assertEqual(fresh.validate_receipt(record, manifest, 'c'*64, pair, live), binding)
        for key, value in [('id', 43), ('node_id', 'IC_43'),
                           ('html_url', 'https://github.com/samuelzhang1201/game_design/pull/234#issuecomment-42'),
                           ('issue_url', 'https://api.github.com/repos/samuelzhang1201/game_design/issues/234'),
                           ('created_at', '2026-11-03T00:00:00Z')]:
            live = copy.deepcopy(published)
            live[key] = value
            with self.subTest(changed_identity=key), self.assertRaises(ValueError):
                fresh.validate_receipt(record, manifest, 'c'*64, pair, live)
        live = copy.deepcopy(published)
        live['user']['id'] += 1
        with self.subTest(changed_identity='author-id'), self.assertRaises(ValueError):
            fresh.validate_receipt(record, manifest, 'c'*64, pair, live)
        fabricated = copy.deepcopy(record)
        fabricated['comment']['user']['id'] += 1
        with self.subTest(changed_identity='fabricated-preserved-author'), self.assertRaises(ValueError):
            fresh.validate_receipt(fabricated, manifest, 'c'*64, pair, published)
        for key, value in [('producer_head', 'd'*40), ('manifest_sha256', 'd'*64),
                           ('bundle_sha256', 'd'*64), ('review_session_id', 'implementation-1'),
                           ('pr_number', 234), ('continuous_contact_certified', True)]:
            bad = copy.deepcopy(record)
            bad['binding'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                fresh.validate_receipt(bad, manifest, 'c'*64, pair, published)
        unrelated = copy.deepcopy(published)
        unrelated['body'] += '\nchanged after preservation'
        with self.assertRaises(ValueError):
            fresh.validate_receipt(record, manifest, 'c'*64, pair, unrelated)


def dataset_controls(manifest_path, bundle_path):
    """Exercise the actual full dataset in an intact different directory, with no original-path reads."""
    manifest = fresh.read_json(manifest_path)
    controls = {}
    with tempfile.TemporaryDirectory(prefix='cavalry-independent-root-') as directory:
        relocated = Path(directory) / 'intact-bundle'
        shutil.copytree(bundle_path, relocated)
        original_sha = fresh.audit.sha256

        def forbid_original_inputs(path):
            text = str(path)
            if any(fragment in text for fragment in ['/acquisition-20261104-01/',
                    '/cluster-loco-clip-cavalry/', '/cavalry-contact-native/game_design/']):
                raise AssertionError('Portable verifier attempted original input: '+text)
            return original_sha(path)

        with patch.object(fresh.audit, 'sha256', forbid_original_inputs):
            fresh.verify(manifest_path, relocated)
        controls['intact_different_root_full_recomputed_replay'] = True
        native_path, views_path = relocated / 'native/native.json', relocated / 'views/views.json'
        anatomy_path = relocated / 'anatomy-authored-v2.json'
        originals = {p: p.read_bytes() for p in [native_path, views_path, anatomy_path]}
        for name in ['unanimated_default', 'import_setting', 'skin_weight', 'normalized_weights',
                     'material_partition', 'missing_grid_quarter']:
            for path, payload in originals.items():
                path.write_bytes(payload)
            native, views, anatomy = (fresh.read_json(p) for p in [native_path, views_path, anatomy_path])
            if name == 'unanimated_default':
                animated = {t['path'].split(':')[-1] for t in native['tracks'] if t['type'] == 1}
                bone = next(b for b in native['bones'] if b['name'] not in animated)
                bone['default_position'][0] += 1
            elif name == 'import_setting':
                native['import_trace']['settings']['remove_immutable_tracks'] = False
            elif name == 'skin_weight':
                weights = native['surfaces'][0]['weights']
                i = next(i for i, v in enumerate(weights) if v > 0)
                weights[i] += .125
            elif name == 'normalized_weights':
                weights = native['surfaces'][0]['weights']
                for i in range(0, len(weights), 4):
                    total = sum(weights[i:i+4])
                    weights[i:i+4] = [v/total for v in weights[i:i+4]]
            elif name == 'material_partition':
                hoof = anatomy['hooves']['FrontHoof.L']
                key = next(k for k, v in hoof.items() if isinstance(v, list) and v)
                hoof[key] = hoof[key][:-1]
            else:
                del native['sample_times_seconds'][1]
            native_path.write_bytes(fresh.canonical(native))
            views['native_sha256'] = fresh.sha256(native_path)
            views_path.write_bytes(fresh.canonical(views))
            anatomy_path.write_bytes(fresh.canonical(anatomy))
            index = copy.deepcopy(manifest['bundle_index'])
            for row in index:
                row['sha256'] = fresh.sha256(relocated / row['path'])
            try:
                fresh.portable_replay(relocated, index, fresh.digest(index))
            except ValueError as error:
                expected = {'unanimated_default': 'First-sample operation', 'import_setting': 'import settings changed',
                            'skin_weight': 'First-sample operation', 'normalized_weights': 'First-sample operation',
                            'material_partition': 'authored anatomy changed', 'missing_grid_quarter': 'scenario grid'}[name]
                if expected not in str(error):
                    raise AssertionError(name+' rejected for unintended reason: '+str(error)) from error
                controls[name] = str(error)
            else:
                raise AssertionError('Corrupt dataset accepted: '+name)
        for path, payload in originals.items():
            path.write_bytes(payload)
        missing = relocated / 'native/import-replay.res'
        held = missing.read_bytes()
        missing.unlink()
        with unittest.TestCase().assertRaises(ValueError):
            fresh.check_index(relocated, manifest['bundle_index'], manifest['bundle_sha256'])
        missing.write_bytes(held)
        controls['missing_replay_resource'] = 'rejected before data loading'
        index = copy.deepcopy(manifest['bundle_index'])
        index[0]['path'] = '../escape'
        with unittest.TestCase().assertRaises(ValueError):
            fresh.check_index(relocated, index, fresh.digest(index))
        controls['traversal'] = 'rejected before data loading'
    print(json.dumps(controls, indent=2))


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--dataset':
        dataset_controls(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        unittest.main()
