import unittest
from ci_scope import needs_game_tests


class CiScopeTests(unittest.TestCase):
    def test_harness_and_guidance_need_only_harness_checks(self):
        self.assertFalse(needs_game_tests(['.codex/hooks/task-handover.py', 'AGENTS.md',
            '.github/workflows/tests.yml', 'docs/superpowers/plans/step.md']))

    def test_mixed_runtime_changes_still_need_game_checks(self):
        self.assertTrue(needs_game_tests(['.codex/harness.md', 'scripts/engine/battle.gd']))

    def test_runtime_markdown_and_csv_are_not_treated_as_docs(self):
        for path in ['RANDOM_EVENTS.md', 'game_story/chapter_0/opening.md', 'data/economy/balance.csv']:
            with self.subTest(path=path):
                self.assertTrue(needs_game_tests([path]))


if __name__ == '__main__':
    unittest.main()
