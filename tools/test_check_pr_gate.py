import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('check_pr_gate', Path(__file__).with_name('check_pr_gate.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class PrGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    VALID_PR_BODY = 'Summary.\n\nprd_step: Step 5\nplayer_outcome: the petition appears at court\nwired: true\n'
    def pr_problems(self, body=VALID_PR_BODY, branch='codex/x', number=None, files=('scripts/a.gd',)):
        return gate.pr_body_problems(body, branch, number or gate.FIRST_CHECKED_PR[branch[:branch.find('/') + 1]], list(files))

    def test_pr_body_with_the_three_fields_passes(self):
        self.assertEqual(self.pr_problems(), [])
        listed = '- prd_step: CS-5.1\r\n- player_outcome: the petition appears\r\n- wired: false\r\n'
        self.assertEqual(self.pr_problems(listed), [])
    def test_pr_body_field_must_appear_exactly_once_on_its_own_line(self):
        for name in ('prd_step', 'player_outcome', 'wired'):
            without = '\n'.join(l for l in self.VALID_PR_BODY.split('\n') if not l.startswith(name))
            self.assertIn(name, ' '.join(self.pr_problems(without)))
            self.assertIn(name, ' '.join(self.pr_problems(self.VALID_PR_BODY + name + ': false\n')))
        self.assertEqual(len(self.pr_problems('')), 3)
        self.assertIn('prd_step', ' '.join(self.pr_problems('Mentions prd_step: Step 5 in prose.\n'
                                                           'player_outcome: x\nwired: false\n')))
    def test_pr_body_blank_field_does_not_read_the_next_line(self):
        body = 'prd_step: Step 5\nplayer_outcome:   \nwired: false\n'
        self.assertIn('player_outcome', ' '.join(self.pr_problems(body)))
    def test_pr_body_rejects_unknown_step_and_wired_value(self):
        self.assertIn('prd_step', ' '.join(self.pr_problems(self.VALID_PR_BODY.replace('Step 5', 'P4'))))
        self.assertIn('wired', ' '.join(self.pr_problems(self.VALID_PR_BODY.replace('wired: true', 'wired: yes'))))
    def test_pr_declared_harness_must_only_change_harness_files(self):
        body = 'prd_step: harness\nplayer_outcome: none: rule maintenance\nwired: false\n'
        self.assertEqual(self.pr_problems(body, files=['cicd_procedure.md', 'AGENTS.md', '.github/workflows/tests.yml']), [])
        self.assertEqual(self.pr_problems(body, branch='claude/x', files=['.claude/agents/architect.md', 'CLAUDE.md']), [])
        self.assertIn('scripts/a.gd', ' '.join(self.pr_problems(body, files=['cicd_procedure.md', 'scripts/a.gd'])))
        self.assertIn('wired', ' '.join(self.pr_problems(body.replace('wired: false', 'wired: true'),
                                                         files=['AGENTS.md'])))
    def test_pr_check_covers_new_codex_and_claude_branches(self):
        for prefix in ('codex/', 'claude/'):
            self.assertNotEqual(self.pr_problems('', branch=prefix + 'x'), [])
            self.assertEqual(self.pr_problems('', branch=prefix + 'x', number=gate.FIRST_CHECKED_PR[prefix] - 1), [])
            self.assertEqual(self.pr_problems(branch=prefix + 'x'), [])
        self.assertEqual(self.pr_problems('', branch='feat/x', number=10**6), [])
        self.assertEqual(self.pr_problems('', branch='claude/x', number=gate.FIRST_CHECKED_PR['codex/']), [])
    def test_a_claude_pr_spread_over_many_subsystems_needs_a_scope_reason(self):
        n, three = gate.FIRST_SCOPE_CHECKED_PR, ['scripts/engine/a.gd', 'scripts/ui/b.gd', 'scripts/map3d/c.gd', 'data/x.csv']
        self.assertEqual(gate.scope_problems('', 'claude/x', n, three[:2] + ['scripts/engine/d.gd', 'tests/e.gd']), [])
        self.assertIn('engine, map3d, ui', ' '.join(gate.scope_problems('', 'claude/x', n, three)))
        self.assertEqual(gate.scope_problems('x\nscope_reason: one rename across the bridge\n', 'claude/x', n, three), [])
        self.assertNotEqual(gate.scope_problems('scope_reason:   \n', 'claude/x', n, three), [])
        self.assertEqual(gate.scope_problems('', 'claude/x', n - 1, three), [])
        self.assertEqual(gate.scope_problems('', 'codex/x', n, three), [])
        self.assertEqual(gate.scope_problems('', 'claude/x', n, ['scripts/a.gd', 'scripts/b.gd', 'scripts/c.gd']), [])
    @staticmethod
    def declared(prd_step, wired, approval=''):
        return f'Summary.\n\nprd_step: {prd_step}\nplayer_outcome: x\nwired: {wired}\n' + (
            f'owner_approval: {approval}\n' if approval else '')
    def backlog(self, history, body=None, branch='claude/x', number=None):
        def read():
            if history is None:
                raise AssertionError('history read although the limit cannot bind')
            return history
        return gate.backlog_problems(read, body or self.declared('Step 5', 'false'), branch,
                                     number or gate.FIRST_CHECKED_PR['claude/'])
    def test_backlog_counts_unwired_pr_bodies_since_a_wired_or_approved_one(self):
        unwired = self.declared('Step 5', 'false')
        self.assertEqual(gate.unwired_since_gate([]), 0)
        self.assertEqual(gate.unwired_since_gate([unwired] * 3), 3)
        # newest first: the scan stops at the first wired PR, whatever is older
        self.assertEqual(gate.unwired_since_gate([unwired, self.declared('Step 5', 'true'), unwired, unwired]), 1)
        self.assertEqual(gate.unwired_since_gate([unwired, self.declared('Step 5', 'false', 'ok #12')] + [unwired] * 4), 1)
    def test_backlog_skips_harness_and_undeclared_pr_bodies(self):
        history = [self.declared('harness', 'false'), 'old PR, no fields', '', self.declared('Step 5', 'false')]
        self.assertEqual(gate.unwired_since_gate(history), 1)
    def test_the_sixth_unwired_claude_pr_waits_for_the_owner(self):
        unwired = self.declared('Step 5', 'false')
        self.assertEqual(self.backlog([unwired] * (gate.MAX_UNWIRED_BACKLOG - 1)), [])
        refused = self.backlog([unwired] * gate.MAX_UNWIRED_BACKLOG)
        self.assertEqual(len(refused), 1)
        self.assertIn('owner_approval', refused[0])
    def test_a_merged_wired_pr_restarts_the_count(self):
        unwired = self.declared('Step 5', 'false')
        self.assertEqual(self.backlog([unwired, unwired, self.declared('Step 5', 'true')] + [unwired] * 9), [])
    def test_owner_approval_must_name_this_pr_or_its_branch(self):
        full = [self.declared('Step 5', 'false')] * 9
        number = gate.FIRST_CHECKED_PR['claude/'] + 3
        named = self.declared('Step 5', 'false', f'owner said go on #{number}')
        self.assertEqual(self.backlog(full, named, number=number), [])
        self.assertEqual(self.backlog(full, self.declared('Step 5', 'false', 'owner said go on claude/x'), number=number), [])
        for words in ('all of them', f'#{number}0', f'#{number - 1}', 'claude/xy'):
            self.assertIn('must name', ' '.join(self.backlog(full, self.declared('Step 5', 'false', words), number=number)), words)
    def test_backlog_binds_only_unwired_nonharness_claude_prs_from_the_cutoff(self):
        for body, branch, number in (
                (self.declared('harness', 'false'), 'claude/x', None),
                (self.declared('Step 5', 'true'), 'claude/x', None),
                ('no fields at all', 'claude/x', None),
                (self.declared('Step 5', 'false'), 'codex/x', None),
                (self.declared('Step 5', 'false'), 'feat/x', None),
                (self.declared('Step 5', 'false'), 'claude/x', gate.FIRST_CHECKED_PR['claude/'] - 1)):
            self.assertEqual(self.backlog(None, body, branch, number), [], (body, branch, number))
    def test_merged_bodies_come_newest_first_and_treat_missing_bodies_as_empty(self):
        listing = json.dumps([{'body': 'old', 'mergedAt': '2026-11-01T00:00:00Z'},
                              {'body': None, 'mergedAt': '2026-11-03T00:00:00Z'},
                              {'body': 'new', 'mergedAt': '2026-11-02T00:00:00Z'}])
        with patch.object(gate.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, listing, '')) as run:
            self.assertEqual(gate.merged_bodies(), ['', 'new', 'old'])
        self.assertIn('merged', run.call_args.args[0])
    def test_check_pr_fails_closed_when_the_merged_prs_cannot_be_read(self):
        env = {'PR_BODY': self.declared('Step 5', 'false'), 'PR_BRANCH': 'claude/x',
               'PR_NUMBER': str(gate.FIRST_CHECKED_PR['claude/']), 'BASE_SHA': 'HEAD'}
        with patch.dict(os.environ, env), patch.object(gate, 'merged_bodies', side_effect=OSError('no gh')):
            self.assertEqual(gate.check_pr(), 1)
    def test_check_pr_command_reads_the_real_diff_and_fails_closed(self):
        git = ['git', '-C', str(self.root), '-c', 'user.name=Test', '-c', 'user.email=test@example.com']
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(git + ['commit', '--allow-empty', '-qm', 'base'], check=True)
        (self.root / 'game.gd').write_text('changed')
        subprocess.run(git + ['add', 'game.gd'], check=True)
        def run(body, base='HEAD'):
            return subprocess.run(['python3', gate.__file__, '--check-pr'], cwd=self.root, capture_output=True, text=True,
                                  timeout=10, env={**os.environ, 'PR_BODY': body, 'PR_BRANCH': 'codex/x',
                                                   'PR_NUMBER': str(gate.FIRST_CHECKED_PR['codex/']), 'BASE_SHA': base})
        self.assertEqual(run(self.VALID_PR_BODY).returncode, 0)
        refused = run(self.VALID_PR_BODY.replace('prd_step: Step 5', 'prd_step: harness').replace('wired: true', 'wired: false'))
        self.assertEqual(refused.returncode, 1)
        self.assertIn('game.gd', refused.stdout)
        self.assertEqual(run('').returncode, 1)
        self.assertNotEqual(run(self.VALID_PR_BODY, base='not-a-revision').returncode, 0)
    def test_ci_runs_the_pr_check_in_the_required_harness_job(self):
        workflow = Path(__file__).parents[1].joinpath('.github/workflows/tests.yml').read_text()
        harness_job = workflow.split('  gut-selected:')[0]
        self.assertIn('check_pr_gate.py', harness_job)

if __name__ == '__main__':
    unittest.main()
