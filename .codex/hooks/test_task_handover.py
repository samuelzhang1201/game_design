import importlib.util
import json
import tempfile
import subprocess
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('handover', Path(__file__).with_name('task-handover.py'))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

class HandoverHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / '.superpowers/session-handovers').mkdir(parents=True)
        self.summary = self.root / 'HANDOVER.md'
        self.summary.write_text('Approved task; next: finish the named test.')
        self.event = {'hook_event_name': 'Stop', 'cwd': str(self.root), 'session_id': 'old'}
        self.marker = {'status': 'ready', 'source_session_id': 'old', 'summary_path': str(self.summary), 'next_task': 'finish test'}
    def save(self):
        (self.root / '.superpowers/session-handovers/old.json').write_text(json.dumps(self.marker))
    def handoff(self, source='old', target='new', **fields):
        data = dict(self.marker, source_session_id=source, next_session_id=target, **fields)
        (self.root / '.superpowers/session-handovers' / (source+'.json')).write_text(json.dumps(data))
        return hook.respond(dict(self.event, session_id=source))
    def test_start_injects_only_compact_rule(self):
        result = hook.respond({'hook_event_name': 'SessionStart'})
        self.assertEqual(result['hookSpecificOutput']['hookEventName'], 'SessionStart')
        self.assertIn('不要重新读取全部历史', result['hookSpecificOutput']['additionalContext'])
    def test_no_marker_does_not_interfere(self):
        self.assertEqual(hook.respond(self.event), {})
    def test_ready_requires_fresh_session(self):
        self.save()
        result = hook.respond(self.event)
        self.assertEqual(result['decision'], 'block')
        self.assertIn('create_thread', result['reason'])
        self.assertIn('禁止 fork/resume', result['reason'])
    def test_completed_handoff_does_not_duplicate(self):
        self.marker.update(status='handed_off', next_session_id='new')
        self.save()
        self.assertEqual(hook.respond(self.event), {})
    def test_other_session_and_repeated_stop_are_not_chained(self):
        self.save()
        self.assertEqual(hook.respond(dict(self.event, session_id='new')), {})
        self.assertEqual(hook.respond(dict(self.event, stop_hook_active=True)), {})
    def test_missing_or_outside_summary_is_refused(self):
        self.marker['summary_path'] = str(self.root / 'missing.md')
        self.save()
        self.assertEqual(hook.respond(self.event)['decision'], 'block')
        self.marker['summary_path'] = str(Path(__file__).resolve())
        self.save()
        self.assertEqual(hook.respond(self.event)['decision'], 'block')
    def test_no_remaining_task_ends_without_new_session(self):
        self.marker['next_task'] = ''
        self.save()
        self.assertEqual(hook.respond(self.event), {})
    def test_existing_cloud_hook_preserved(self):
        config = json.loads(Path(__file__).parents[1].joinpath('hooks.json').read_text())
        commands = [h['command'] for group in config['hooks']['SessionStart'] for h in group['hooks']]
        self.assertTrue(any('session-start.sh' in c for c in commands))
        self.assertTrue(any('task-handover.py' in c for c in commands))
        self.assertIn('Stop', config['hooks'])
    def test_start_explains_one_small_step_and_exactly_two_owners(self):
        text = hook.respond({'hook_event_name':'SessionStart'})['hookSpecificOutput']['additionalContext']
        self.assertIn('Review', text)
        self.assertIn('一对一', text)
        self.assertIn('第三', text)
    def test_fan_out_and_fan_in_are_rejected(self):
        self.assertEqual(self.handoff(), {})
        self.assertEqual(self.handoff(target='another')['decision'], 'block')
        self.assertEqual(self.handoff(source='another')['decision'], 'block')
    def test_cycles_and_self_handoff_are_rejected(self):
        self.assertEqual(self.handoff(), {})
        self.assertEqual(self.handoff(source='new',target='old')['decision'], 'block')
        self.assertEqual(self.handoff(source='same',target='same')['decision'], 'block')
    def test_plural_and_non_string_targets_are_rejected(self):
        self.assertEqual(self.handoff(target=['one','two'])['decision'], 'block')
        self.assertEqual(self.handoff(next_session_ids=['one','two'])['decision'], 'block')
    def test_retries_keep_the_same_single_successor(self):
        self.assertEqual(self.handoff(), {})
        self.assertEqual(self.handoff(source='new', target='next'), {})
        self.assertEqual(self.handoff(), {})
        graph = json.loads(hook.registry_path(self.root).read_text())
        self.assertEqual(graph['edges'], {'old': 'new', 'new': 'next'})
    def test_an_old_chain_head_is_not_a_fresh_successor(self):
        self.assertEqual(self.handoff(source='existing',target='child'), {})
        self.assertEqual(self.handoff(source='other',target='existing')['decision'], 'block')
    def test_a_session_cannot_own_two_different_prs(self):
        pair = dict(step_id='P5.2',pr_url='https://github.com/example/repo/pull/1',
                    implementation_session_id='old',review_session_id='new')
        self.assertEqual(self.handoff(**pair), {})
        pair.update(step_id='P5.3',pr_url='https://github.com/example/repo/pull/2')
        self.assertEqual(self.handoff(**pair)['decision'], 'block')
        self.assertEqual(self.handoff(), {})
    def test_feature_pair_cannot_gain_a_third_owner(self):
        pair = dict(step_id='P5.2',pr_url='https://github.com/example/repo/pull/1',
                    implementation_session_id='old',review_session_id='new')
        self.assertEqual(self.handoff(**pair), {})
        changed = dict(pair,review_session_id='third')
        self.assertEqual(self.handoff(source='new',target='third',**changed)['decision'], 'block')
    def test_implementation_hands_off_to_its_own_reviewer(self):
        pair = dict(step_id='P5.2',pr_url='https://github.com/example/repo/pull/1',
                    implementation_session_id='old',review_session_id='review')
        self.assertEqual(self.handoff(target='third',**pair)['decision'], 'block')
    def test_review_can_handoff_to_the_next_independent_step(self):
        pair = dict(step_id='P5.2',pr_url='https://github.com/example/repo/pull/1',
                    implementation_session_id='old',review_session_id='new')
        self.assertEqual(self.handoff(**pair), {})
        self.assertEqual(self.handoff(source='new',target='next-step',**pair), {})
    def test_shared_registry_prevents_conflicts_between_worktrees(self):
        with patch.object(hook, 'registry_path', return_value=self.root/'shared.json'):
            self.assertEqual(self.handoff(), {})
            other = self.root/'worktree'
            (other/'.superpowers/session-handovers').mkdir(parents=True)
            (other/'HANDOVER.md').write_text('A different step in a different checkout.')
            marker = dict(self.marker,source_session_id='other',next_session_id='new',summary_path='HANDOVER.md')
            (other/'.superpowers/session-handovers/other.json').write_text(json.dumps(marker))
            result = hook.respond(dict(self.event,cwd=str(other),session_id='other'))
            self.assertEqual(result['decision'],'block')
    def test_real_git_worktrees_resolve_the_same_registry(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        subprocess.run(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.com',
                        'commit','--allow-empty','-qm','fixture'],check=True)
        linked = self.root/'linked'
        subprocess.run(['git','-C',str(self.root),'worktree','add','--detach','-q',str(linked)],check=True)
        self.assertEqual(hook.registry_path(self.root),hook.registry_path(linked))

if __name__ == '__main__':
    unittest.main()
