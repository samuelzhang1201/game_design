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
        if 'kind' not in fields:
            data.pop('kind', None)
        if 'tasks' not in fields:
            data.pop('tasks', None)
        (self.root / '.superpowers/session-handovers' / (source+'.json')).write_text(json.dumps(data))
        return hook.respond(dict(self.event, session_id=source))
    def test_start_injects_only_compact_rule(self):
        result = hook.respond({'hook_event_name': 'SessionStart'})
        self.assertEqual(result['hookSpecificOutput']['hookEventName'], 'SessionStart')
        self.assertIn('不重新读取全部历史', result['hookSpecificOutput']['additionalContext'])
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
    def task(self, step='a', owner='worker-a', files=None, dependencies=None, **fields):
        return dict(step_id=step, dispatcher_session_id='old', dependencies=dependencies or [],
                    owned_files=files or ['tools/a.py'], acceptance='targeted checks pass',
                    worktree=str(self.root / step), branch='codex/'+step,
                    implementation_session_id=owner, review_session_id=None,
                    creation_result={'status':'created', 'session_id':owner},
                    status='active', **fields)
    def dispatch(self, tasks):
        self.marker.update(kind='dispatch', tasks=tasks)
        self.save()
        return hook.respond(self.event)
    def test_independent_dispatch_and_identical_retry(self):
        tasks = [self.task(), self.task('b','worker-b',['tools/b.py'])]
        self.assertEqual(self.dispatch(tasks), {})
        self.assertEqual(self.dispatch(tasks), {})
        graph = json.loads(hook.registry_path(self.root).read_text())
        self.assertEqual(set(graph['steps']), {'a','b'})
        self.assertEqual(graph['edges'], {})
    def test_dispatch_rejects_overlap_duplicate_and_owner_replacement_atomically(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        original = hook.registry_path(self.root).read_text()
        cases = [[self.task('b','worker-b')], [self.task(), self.task()],
                 [dict(self.task(), implementation_session_id='replacement')],
                 [dict(self.task(), dispatcher_session_id='other')],
                 [self.task('b','worker-a',['tools/b.py'])],
                 [self.task('b','worker-b',['tools'])]]
        for tasks in cases:
            with self.subTest(tasks=tasks):
                self.assertEqual(self.dispatch(tasks)['decision'], 'block')
                self.assertEqual(hook.registry_path(self.root).read_text(), original)
    def test_dependencies_require_merged_and_accepted_declaration(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        b = self.task('b','worker-b',['tools/b.py'],['a'])
        self.assertEqual(self.dispatch([b])['decision'], 'block')
        self.assertEqual(self.dispatch([dict(self.task(), status='merged', accepted=True)]), {})
        self.assertEqual(self.dispatch([b]), {})
    def test_dispatch_rejects_self_indirect_cycles_and_missing_dependencies(self):
        for tasks in [[self.task(dependencies=['a'])],
                      [self.task(dependencies=['b']), self.task('b','worker-b',['b'],['a'])],
                      [self.task(dependencies=['missing'])]]:
            self.assertEqual(self.dispatch(tasks)['decision'], 'block')
    def test_dispatch_requires_complete_records_and_known_creation_result(self):
        for field in ['owned_files','acceptance','worktree','branch','implementation_session_id',
                      'dispatcher_session_id','dependencies','review_session_id','creation_result']:
            task = self.task(); del task[field]
            with self.subTest(field=field):
                self.assertEqual(self.dispatch([task])['decision'], 'block')
        for files in [['../escape'], ['/absolute'], ['tools/../a'], []]:
            self.assertEqual(self.dispatch([dict(self.task(), owned_files=files)])['decision'], 'block')
        task = dict(self.task(), creation_result={'status':'unknown'})
        self.assertEqual(self.dispatch([task])['decision'], 'block')
    def test_dispatch_pr_pair_matches_registered_owners(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        pair = dict(kind='pr_handoff', step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='worker-a', review_session_id='review-a')
        self.assertEqual(self.handoff('worker-a','review-a',**pair), {})
        self.assertEqual(self.handoff('review-a','third',**pair)['decision'], 'block')
        changed = dict(self.task(), review_session_id='other-review')
        self.assertEqual(self.dispatch([changed])['decision'], 'block')
    def test_dispatch_cannot_reuse_historical_session(self):
        self.assertEqual(self.handoff('former','child'), {})
        self.assertEqual(self.dispatch([self.task(owner='former')])['decision'], 'block')
    def test_legacy_registry_preserved_when_dispatch_is_added(self):
        self.assertEqual(self.handoff('legacy','legacy-review'), {})
        self.assertEqual(self.dispatch([self.task()]), {})
        graph=json.loads(hook.registry_path(self.root).read_text())
        self.assertEqual(graph['edges'], {'legacy':'legacy-review'})
    def test_converging_dependencies_allow_reusing_completed_files(self):
        self.assertEqual(self.dispatch([dict(self.task(), status='merged', accepted=True),
            dict(self.task('b','worker-b',['tools/b.py']), status='merged', accepted=True)]), {})
        self.assertEqual(self.dispatch([self.task('c','worker-c',['tools/a.py'],['a','b'])]), {})
    def test_failed_atomic_replace_leaves_registry_unchanged(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        with patch.object(hook.os, 'replace', side_effect=OSError('disk failure')):
            self.assertEqual(self.dispatch([self.task('b','worker-b',['tools/b.py'])])['decision'], 'block')
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(sorted(p.name for p in path.parent.iterdir()),
                         sorted([path.name, path.with_suffix('.lock').name, 'session-handovers']))
    def test_concurrent_dispatch_serializes_conflicting_files(self):
        common = self.root/'common.json'
        processes = []
        for i in range(2):
            source = 'dispatcher-'+str(i)
            task = dict(self.task(str(i),'worker-'+str(i)), dispatcher_session_id=source)
            marker = dict(self.marker, kind='dispatch', source_session_id=source, tasks=[task])
            script = ("import importlib.util,json,pathlib; "
                "s=importlib.util.spec_from_file_location('h',"+repr(str(Path(hook.__file__)))+"); "
                "h=importlib.util.module_from_spec(s);s.loader.exec_module(h); "
                "h.registry_path=lambda cwd:pathlib.Path("+repr(str(common))+"); "
                "h.record_handoff(pathlib.Path('.'),json.loads("+repr(json.dumps(marker))+"))")
            processes.append(subprocess.Popen(['python3','-c',script], stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        results = [p.communicate(timeout=10) for p in processes]
        self.assertEqual(sorted(p.returncode for p in processes), [0,1], results)
        self.assertEqual(len(json.loads(common.read_text())['steps']), 1)
    def test_dispatch_conflicts_across_real_worktrees(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        subprocess.run(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.com',
                        'commit','--allow-empty','-qm','fixture'],check=True)
        linked = self.root/'linked'
        subprocess.run(['git','-C',str(self.root),'worktree','add','--detach','-q',str(linked)],check=True)
        self.assertEqual(self.dispatch([self.task()]), {})
        task = self.task('b','worker-b')
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            hook.record_handoff(linked, dict(self.marker, tasks=[task]))
    def test_dispatcher_cannot_become_a_pr_owner(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        pair = dict(kind='pr_handoff', step_id='other', pr_url='https://example.com/pull/2',
                    implementation_session_id='old', review_session_id='review')
        self.assertEqual(self.handoff('old','review',**pair)['decision'], 'block')
    def test_dispatch_cannot_duplicate_a_legacy_pr_step(self):
        pair = dict(step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='legacy', review_session_id='legacy-review')
        self.assertEqual(self.handoff('legacy','legacy-review',**pair), {})
        self.assertEqual(self.dispatch([self.task()])['decision'], 'block')
    def test_legacy_handoff_cannot_steal_a_dispatched_owner(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        self.assertEqual(self.handoff('stranger','worker-a')['decision'], 'block')
    def test_terminal_pr_owner_cannot_be_dispatcher(self):
        self.assertEqual(self.handoff('parent','old'), {})
        self.assertEqual(self.dispatch([self.task()])['decision'], 'block')
    def test_pr_handoff_rejects_dispatch_fields(self):
        pair = dict(kind='pr_handoff', step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='old', review_session_id='review', tasks=[self.task()])
        self.assertEqual(self.handoff('old','review',**pair)['decision'], 'block')
    def test_real_git_worktrees_resolve_the_same_registry(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        subprocess.run(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.com',
                        'commit','--allow-empty','-qm','fixture'],check=True)
        linked = self.root/'linked'
        subprocess.run(['git','-C',str(self.root),'worktree','add','--detach','-q',str(linked)],check=True)
        self.assertEqual(hook.registry_path(self.root),hook.registry_path(linked))

if __name__ == '__main__':
    unittest.main()
