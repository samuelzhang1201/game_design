import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
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

    def test_every_test_is_classified_exactly_once(self):
        files = [p for group in self.catalog.values() for p in group]
        self.assertEqual(len(files), len(set(files)))
        self.assertEqual(set(files), {str(p) for p in Path('tests').rglob('test_*.gd')})


if __name__ == '__main__':
    unittest.main()
