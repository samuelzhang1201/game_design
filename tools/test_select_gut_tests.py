import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

SPEC = importlib.util.spec_from_file_location('selector', Path(__file__).with_name('select_gut_tests.py'))
selector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selector)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.catalog = selector.catalog()

    def select(self, *paths, include=()):
        return selector.select(paths, self.catalog, include)

    def test_docs_and_harness_need_no_godot(self):
        self.assertEqual(self.select('README.md', '.codex/hooks/task-handover.py')['files'], [])

    def test_runtime_prose_and_data_are_functional(self):
        for path in ['RANDOM_EVENTS.md', 'game_story/opening.md', 'data/economy/balance.csv']:
            with self.subTest(path=path):
                result = self.select(path)
                self.assertIn('engine-core', result['categories'])
                self.assertNotIn('simulation', result['categories'])

    def test_map_art_and_ui_route_to_consumers(self):
        self.assertIn('map3d', self.select('assets/3D/units/knight/knight.glb')['categories'])
        self.assertIn('ui', self.select('scripts/ui/top_bar.gd')['categories'])
        self.assertIn('engine-military', self.select('scripts/engine/army_conduct.gd')['categories'])

    def test_unknown_runtime_and_shared_fixtures_are_conservative(self):
        for path in ['new_runtime/file.bin', 'scripts/new_mode.gd', 'project.godot']:
            self.assertEqual(set(self.select(path)['categories']), set(selector.functional_categories()))
        self.assertEqual(set(self.select('tests/fixtures/test_env')['categories']), {'engine-core', 'ui'})
        self.assertEqual(set(self.select('tests/fixtures/unknown_fixture')['categories']),
                         set(selector.functional_categories()))

    def test_expensive_files_require_explicit_opt_in_even_when_changed(self):
        for category in ['simulation', 'gameplay', 'balance']:
            paths = self.catalog[category]
            path = paths[0] if paths else 'tests/balance/test_new.gd'
            self.assertEqual(self.select(path)['files'], [])
            if paths:
                self.assertIn(category, self.select(path, include=[category])['categories'])
            else:
                groups = {**self.catalog, category: [path]}
                self.assertIn(path, selector.select([], groups, [category])['files'])
        self.assertNotIn('tests/engine/test_determinism.gd', self.select('scripts/engine/tick_engine.gd')['files'])

    def test_campaign_scenarios_are_classified_by_content_not_engine_folder(self):
        for name in ['army_clearance', 'raid', 'siege', 'invasion_end_to_end', 'sighting_invasion']:
            self.assertIn(f'tests/engine/test_{name}.gd', self.catalog['gameplay'])

    def test_year_long_garrison_campaign_requires_simulation_opt_in(self):
        path = 'tests/engine/test_supply_garrisons.gd'
        self.assertIn(path, self.catalog['simulation'])
        self.assertNotIn(path, self.select('scripts/engine/supply_system.gd')['files'])
        self.assertIn(path, self.select('README.md', include=['simulation'])['files'])

    def test_model_runtime_still_selects_engine_and_ui_consumers(self):
        self.assertEqual(set(self.select('scripts/llm/openai_client.gd')['categories']), {'engine-core', 'ui'})

    def test_conduct_unit_neighbors_survive_extraction(self):
        self.assertIn('tests/engine/test_army_conduct_day.gd', self.catalog['engine-military'])
        self.assertIn('tests/simulation/test_conduct_replay.gd', self.catalog['simulation'])
        unit = Path('tests/engine/test_army_conduct_day.gd').read_text()
        self.assertNotIn('func test_twenty_four_months_twice_identical', unit)
        self.assertEqual(unit.count('\nfunc test_'), 10)

    def test_deleted_test_still_selects_surviving_category(self):
        chosen = self.select('tests/engine/test_army_deleted.gd')
        self.assertIn('tests/engine/test_army_conduct_day.gd', chosen['files'])
        self.assertNotIn('tests/engine/test_army_deleted.gd', chosen['files'])

    def test_new_test_subsystem_fails_conservatively(self):
        self.assertEqual(set(self.select('tests/new_mode/test_unknown.gd')['categories']), set(selector.functional_categories()))

    def test_git_diff_includes_deleted_and_both_sides_of_renames(self):
        with tempfile.TemporaryDirectory() as tmp:
            def git(*args):
                return subprocess.check_output(['git', '-C', tmp, *args])
            git('init', '-q')
            git('config', 'user.email', 'test@example.com')
            git('config', 'user.name', 'test')
            old = Path(tmp, 'scripts/engine/old.gd')
            old.parent.mkdir(parents=True)
            old.write_text('same content\n' * 20)
            Path(tmp, 'data.csv').write_text('x\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD').decode().strip()
            target = Path(tmp, 'scripts/ui/renamed.gd')
            target.parent.mkdir(parents=True)
            old.rename(target)
            Path(tmp, 'data.csv').unlink()
            git('add', '-A')
            git('commit', '-qm', 'rename and delete')
            self.assertEqual(set(selector.changed_paths(base, tmp)), {'scripts/engine/old.gd', 'scripts/ui/renamed.gd', 'data.csv'})

    def test_harness_changes_need_only_the_dedicated_self_checks(self):
        for path in ['run_tests.sh', 'tools/select_gut_tests.py', 'tests/categories.json', '.github/workflows/tests.yml']:
            self.assertEqual(self.select(path)['categories'], [])

    def test_deleted_tests_select_their_affected_categories_and_mixed_changes_union(self):
        self.assertEqual(set(self.select('tests/llm/test_openai_client.gd')['categories']), {'engine-core', 'ui'})
        self.assertEqual(set(self.select('tests/ui/test_deleted.gd')['categories']), {'ui'})
        self.assertEqual(set(self.select('tests/llm/test_deleted.gd', 'tests/engine/test_deleted.gd')['categories']),
                         {'engine-core', 'ui'})

    def test_comment_only_diff_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            def git(*args):
                return subprocess.check_output(['git', '-C', tmp, *args])
            git('init', '-q')
            git('config', 'user.email', 'test@example.com')
            git('config', 'user.name', 'test')
            source = Path(tmp, 'scripts/engine/comment.gd')
            source.parent.mkdir(parents=True)
            source.write_text('func run() -> void:\n\tpass\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            source.write_text('func run() -> void:\n\tpass\n\t# clarify behavior\n')
            self.assertTrue(selector.comment_only_diff('HEAD', tmp))
            self.assertEqual(selector.gut_relevant_paths('HEAD', tmp), [])
            source.write_text('func run() -> void:\n\tprint("changed")\n')
            self.assertFalse(selector.comment_only_diff('HEAD', tmp))
            self.assertEqual(selector.gut_relevant_paths('HEAD', tmp), ['scripts/engine/comment.gd'])

    def test_only_explicit_request_lines_opt_in(self):
        self.assertEqual(selector.requested_categories('Please discuss simulation and gameplay.'), [])
        self.assertEqual(selector.requested_categories('Reason\nGUT_INCLUDE: simulation, gameplay\n'), ['simulation', 'gameplay'])
        with self.assertRaises(ValueError):
            selector.requested_categories('GUT_INCLUDE: typo')
        chosen = self.select('README.md', include=selector.requested_categories('GUT_INCLUDE: simulation'))
        self.assertIn('simulation', chosen['categories'])

    def test_cli_rejects_unknown_categories_and_missing_tests(self):
        for args in [['--category', 'typo'], ['--test', 'tests/engine/test_deleted.gd']]:
            result = subprocess.run(['python3', 'tools/select_gut_tests.py', *args], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_cli_writes_ci_outputs_and_honors_explicit_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp, 'outputs')
            command = ['python3', 'tools/select_gut_tests.py', '--functional', '--github-output', str(output)]
            chosen = json.loads(subprocess.check_output(command))
            lines = output.read_text().splitlines()
            self.assertEqual(lines[0], 'run-gut=true')
            self.assertEqual(json.loads(lines[1].removeprefix('matrix=')), chosen['matrix'])
            self.assertNotIn('simulation', chosen['categories'])
            requested = json.loads(subprocess.check_output(command + ['--request-text', 'GUT_INCLUDE: simulation']))
            self.assertIn('simulation', requested['categories'])

    def test_ci_military_batches_cover_every_script_once_in_order(self):
        chosen = self.select('scripts/engine/army_system.gd')
        jobs = chosen['matrix']['include']
        military = [job for job in jobs if job['category'] == 'engine-military']
        self.assertEqual([job['batch'] for job in military], [1, 2, 3, 4])
        files = []
        for job in military:
            selected = json.loads(subprocess.check_output([
                'python3', 'tools/select_gut_tests.py', '--category', job['category'],
                '--batch', str(job['batch'])]))
            self.assertTrue(selected['files'])
            files.extend(selected['files'])
        self.assertEqual(files, self.catalog['engine-military'])
        self.assertEqual(len(files), len(set(files)))
        for job in jobs:
            if job['category'] != 'engine-military':
                self.assertEqual(job['batch'], 1)
        self.assertNotIn('simulation', [job['category'] for job in jobs])

    def test_real_runner_batch_count_offline_and_failure_propagation(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp, 'godot')
            fake.write_text("#!/usr/bin/env python3\nimport os, sys\nassert os.environ['CC_FORCE_OFFLINE'] == '1'\nif '--import' in sys.argv: sys.exit(0)\nfiles = next(arg for arg in sys.argv if arg.startswith('-gtest=')).split('=', 1)[1].split(',')\nassert files\nprint('Scripts', len(files))\nsys.exit(int(os.environ['FAKE_EXIT']))\n")
            fake.chmod(0o755)
            for batch, code in [(1, 0), (2, 0), (3, 0), (4, 0), (4, 3)]:
                result = subprocess.run(['./run_tests.sh', '--category', 'engine-military',
                                         '--batch', str(batch)], capture_output=True, text=True,
                    env={**os.environ, 'GODOT': str(fake), 'FAKE_EXIT': str(code)})
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)

    def test_workflow_aggregate_rejects_every_non_successful_matrix(self):
        workflow = Path('.github/workflows/tests.yml').read_text()
        self.assertIn('--batch "${{ matrix.batch }}"', workflow)
        self.assertIn('fail-fast: false', workflow)
        self.assertIn('TEST_TIMEOUT_SECONDS: 2100', workflow)
        aggregate = textwrap.dedent(workflow.split('  gut-tests:', 1)[1].split('        run: |', 1)[1])
        for run_gut, selected, expected in [('true', 'success', 0), ('false', 'skipped', 0),
                *[('true', state, 1) for state in ['failure', 'cancelled', 'skipped', '', 'timed_out']],
                ('false', 'success', 1)]:
            result = subprocess.run(['bash', '-e', '-c', aggregate], env={**os.environ,
                'HARNESS_RESULT': 'success', 'RUN_GUT': run_gut, 'SELECTED_RESULT': selected})
            self.assertEqual(result.returncode, expected)

    def test_batch_requires_one_category_and_valid_manifest_index(self):
        for args in [['--batch', '1'], ['--category', 'engine-military', '--batch', '0'],
                     ['--category', 'engine-military', '--batch', '5'],
                     ['--category', 'engine-core', '--batch', '2'],
                     ['--test', 'tests/engine/test_calendar.gd', '--batch', '1'],
                     ['--category', 'engine-military', '--category', 'ui', '--batch', '1']]:
            with self.subTest(args=args):
                result = subprocess.run(['python3', 'tools/select_gut_tests.py', *args], capture_output=True)
                self.assertNotEqual(result.returncode, 0)

    def test_every_test_is_classified_exactly_once(self):
        files = [p for group in self.catalog.values() for p in group]
        self.assertEqual(len(files), len(set(files)))
        self.assertEqual(set(files), {str(p) for p in Path('tests').rglob('test_*.gd')})


if __name__ == '__main__':
    unittest.main()
