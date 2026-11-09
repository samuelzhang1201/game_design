import importlib.util
import json
import os
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
        # Most tests exercise one rule at a time; the receipt has its own tests below.
        self.preflight_receipts = patch.object(hook, 'require_preflight')
        self.preflight_receipts.start()
        self.addCleanup(self.preflight_receipts.stop)
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
        self.assertEqual(self.handoff()['decision'], 'block')
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
    def test_review_cannot_add_a_third_recipient(self):
        pair = dict(step_id='P5.2',pr_url='https://github.com/example/repo/pull/1',
                    implementation_session_id='old',review_session_id='new')
        self.assertEqual(self.handoff(**pair), {})
        self.assertEqual(self.handoff(source='new',target='next-step',**pair)['decision'], 'block')
    def test_fixed_pair_can_repeat_review_fix_rounds(self):
        pair = dict(kind='pr_handoff', step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='old', review_session_id='new')
        for _ in range(3):
            self.assertEqual(self.handoff(**pair), {})
            self.assertEqual(self.handoff('new', 'old', **pair), {})
        graph = json.loads(hook.registry_path(self.root).read_text())
        self.assertEqual(graph['edges'], {})
        self.assertEqual(len(graph['prs']), 1)
        self.assertEqual(self.handoff('old', 'old', **pair)['decision'], 'block')
        self.assertEqual(self.handoff('third', 'old', **pair)['decision'], 'block')

    def test_legacy_pair_can_upgrade_to_roundtrips_without_rewriting_edges(self):
        self.assertEqual(self.handoff(), {})
        pair = dict(kind='pr_handoff', step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='old', review_session_id='new')
        self.assertEqual(self.handoff(**pair), {})
        self.assertEqual(self.handoff('new', 'old', **pair), {})
        graph = json.loads(hook.registry_path(self.root).read_text())
        self.assertEqual(graph['edges'], {'old': 'new'})

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
        fields = {'status': 'active', 'prd_step': 'Step 5',
                  'player_outcome': 'the faction petition appears at court', 'wired': True, **fields}
        return dict(step_id=step, dispatcher_session_id='old', dependencies=dependencies or [],
                    owned_files=files or ['tools/a.py'], acceptance='targeted checks pass',
                    worktree=str(self.root / step), branch='codex/'+step,
                    implementation_session_id=owner, review_session_id=None,
                    creation_result={'status':'created', 'session_id':owner}, **fields)
    def dispatch(self, tasks):
        self.marker.update(kind='dispatch', tasks=tasks)
        self.save()
        return hook.respond(self.event)
    def unwired(self, step, dependencies=None, **fields):
        return self.task(step, 'worker-'+step, ['tools/'+step+'.py'], dependencies, wired=False, **fields)
    def done(self, step, dependencies=None, **fields):
        return self.unwired(step, dependencies, **{'status': 'merged', 'accepted': True, **fields})
    def task_merged(self, task):
        return {key: value for key, value in task.items() if key != 'status'} | {'status': 'merged', 'accepted': True}
    def legacy(self, *names):
        """A registry written before the gate: merged chain without product fields."""
        steps, previous = {}, []
        for name in names:
            step = self.done(name, previous)
            for key in ('prd_step', 'player_outcome', 'wired'):
                del step[key]
            steps[name], previous = step, [name]
        hook.registry_path(self.root).write_text(json.dumps({'edges': {}, 'prs': {}, 'steps': steps}))
        return steps
    def approval(self, statement):
        return {'statement': statement, 'reference': 'owner chat 2026-11-09'}
    def test_new_step_must_name_its_prd_step_and_player_outcome(self):
        bad = [{'prd_step': 'P4'}, {'prd_step': ''}, {'player_outcome': ' '}, {'wired': 'yes'}]
        for fields in bad:
            with self.subTest(fields=fields):
                self.assertEqual(self.dispatch([self.task(**fields)])['decision'], 'block')
        for key in ('prd_step', 'player_outcome', 'wired'):
            with self.subTest(missing=key):
                task = self.task()
                del task[key]
                self.assertEqual(self.dispatch([task])['decision'], 'block')
        self.assertFalse(hook.registry_path(self.root).exists())
        for name in ('Step 10', 'CS-5.1', 'AR-2', 'M6', 'L0'):
            with self.subTest(prd_step=name):
                self.assertIsNotNone(hook.PRD_STEP.fullmatch(name))
    def test_steps_registered_before_the_gate_keep_working(self):
        steps = self.legacy('old-a')
        steps['old-a'].update(status='active')
        del steps['old-a']['accepted']
        hook.registry_path(self.root).write_text(json.dumps({'edges': {}, 'prs': {}, 'steps': steps}))
        self.assertEqual(self.dispatch([steps['old-a']]), {})
        self.assertEqual(self.dispatch([dict(steps['old-a'], status='merged', accepted=True)]), {})
    def test_product_declaration_cannot_change_after_registration(self):
        task = self.unwired('a')
        self.assertEqual(self.dispatch([task]), {})
        for fields in ({'prd_step': 'Step 6'}, {'player_outcome': 'something else'}, {'wired': True},
                       {'owner_approval': self.approval('a approved')}):
            with self.subTest(fields=fields):
                self.assertEqual(self.dispatch([dict(task, **fields)])['decision'], 'block')
    def test_unwired_prerequisite_chain_stops_past_two_layers(self):
        # a <- b is two layers under c, allowed; a <- b <- c is three under d, refused.
        self.assertEqual(self.dispatch([self.done('a')]), {})
        self.assertEqual(self.dispatch([self.done('b', ['a'])]), {})
        self.assertEqual(self.dispatch([self.done('c', ['b'])]), {})
        before = self.graph()['steps']
        result = self.dispatch([self.unwired('d', ['c'])])
        self.assertEqual(result['decision'], 'block')
        self.assertIn('ask the owner', result['reason'])
        self.assertEqual(self.graph()['steps'], before)
    def test_step_the_player_can_reach_may_land_a_deep_chain(self):
        self.legacy('a', 'b', 'c', 'd')
        self.assertEqual(self.dispatch([self.task('landing', 'worker-l', ['tools/l.py'], ['d'])]), {})
    def test_steps_from_before_the_gate_count_as_unwired(self):
        self.legacy('a', 'b', 'c')
        self.assertEqual(self.dispatch([self.unwired('d', ['c'])])['decision'], 'block')
    def test_owner_approval_must_name_the_step(self):
        self.legacy('a', 'b', 'c')
        for approval in (self.approval('all recommendations approved'), {'statement': 'd approved'},
                         {'statement': ' ', 'reference': 'x'}, 'd approved'):
            with self.subTest(approval=approval):
                task = self.unwired('d', ['c'], owner_approval=approval)
                self.assertEqual(self.dispatch([task])['decision'], 'block')
        self.assertEqual(self.dispatch([self.unwired('d', ['c'], owner_approval=self.approval('Go ahead with d'))]), {})
    def test_owner_approval_restarts_the_chain_and_backlog(self):
        self.legacy('a', 'b', 'c')
        self.assertEqual(self.dispatch([self.done('d', ['c'], owner_approval=self.approval('d approved'))]), {})
        self.assertEqual(self.dispatch([self.done('e', ['d'])]), {})
        self.assertEqual(self.dispatch([self.done('f', ['e'])]), {})
        self.assertEqual(self.dispatch([self.done('g', ['f'])]), {})
        self.assertEqual(self.dispatch([self.unwired('h', ['g'])])['decision'], 'block')
    def test_backlog_of_unwired_steps_stops_at_the_limit(self):
        for step in 'abcde':
            self.assertEqual(self.dispatch([self.unwired(step)]), {})
        self.assertEqual(self.dispatch([self.unwired('f')])['decision'], 'block')
        self.assertEqual(self.dispatch([self.task('landing', 'worker-l', ['tools/l.py'])]), {})
    def test_merged_reachable_step_clears_the_backlog_but_an_open_one_does_not(self):
        for step in 'abcde':
            self.assertEqual(self.dispatch([self.done(step)]), {})
        landing = self.task('landing', 'worker-l', ['tools/l.py'])
        self.assertEqual(self.dispatch([landing]), {})
        self.assertEqual(self.dispatch([self.unwired('f')])['decision'], 'block')
        self.assertEqual(self.dispatch([self.task_merged(landing)]), {})
        self.assertEqual(self.dispatch([self.unwired('f')]), {})
    def test_harness_steps_do_not_count_and_cannot_touch_the_game(self):
        harness = dict(prd_step='harness', player_outcome='none: rule maintenance', wired=False)
        for step in 'vwxyz':
            self.assertEqual(self.dispatch([self.unwired(step)]), {})
        self.assertEqual(self.dispatch([self.task('h', 'worker-h', ['.codex/hooks/x.py'], **harness)]), {})
        self.assertEqual(self.dispatch([self.task('i', 'worker-i', ['scripts/engine/x.gd'], **harness)])['decision'], 'block')
        self.assertEqual(self.dispatch([self.task('j', 'worker-j', ['.codex/y.md'], **dict(harness, wired=True))])['decision'], 'block')
        self.assertEqual(self.dispatch([self.unwired('k')])['decision'], 'block')
    def test_retired_steps_do_not_fill_the_backlog(self):
        steps = self.legacy('a', 'b', 'c', 'd', 'e', 'f')
        for step in steps.values():
            step.update(status='superseded', dependencies=[])
        hook.registry_path(self.root).write_text(json.dumps({'edges': {}, 'prs': {}, 'steps': steps}))
        self.assertEqual(self.dispatch([self.unwired('g')]), {})
    def test_start_rules_state_the_product_gate(self):
        text = hook.respond({'hook_event_name': 'SessionStart'})['hookSpecificOutput']['additionalContext']
        self.assertIn('prd_step', text)
        self.assertIn('owner_approval', text)
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
    def test_necessary_existing_test_addition_is_audited_and_idempotent(self):
        task = self.task(files=['scripts/engine/pursuit.gd'])
        self.assertEqual(self.dispatch([task]), {})
        amendment = {'added_files': ['tests/engine/test_pursuit_merge_continuity.gd'],
                     'reason': 'Existing fixture must assert the pursuit route cap.'}
        changed = dict(task, owned_files=task['owned_files'] + amendment['added_files'],
                       scope_additions=[amendment])
        self.assertEqual(self.dispatch([changed]), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        self.assertEqual(self.dispatch([changed]), {})
        self.assertEqual(path.read_bytes(), before)
        saved = json.loads(before)['steps']['a']
        self.assertEqual(saved['original_owned_files'], task['owned_files'])
        self.assertEqual(saved['scope_additions'], [amendment])
        second = {'added_files':['tests/engine/another.gd'], 'reason':'Second related caller.'}
        self.assertEqual(self.dispatch([dict(changed,
            owned_files=changed['owned_files']+second['added_files'],
            scope_additions=[amendment, second])]), {})
        saved = json.loads(path.read_text())['steps']['a']
        self.assertEqual(saved['original_owned_files'], task['owned_files'])
        self.assertEqual(saved['scope_additions'], [amendment, second])

    def test_scope_additions_reject_invalid_changes_without_writing(self):
        task = self.task()
        self.assertEqual(self.dispatch([task, self.task('b', 'worker-b', ['tools/b.py'])]), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        addition = {'added_files': ['tests/existing.gd'], 'reason': 'Necessary fixture.'}
        changed = dict(task, owned_files=task['owned_files'] + addition['added_files'],
                       scope_additions=[addition])
        cases = [dict(changed, scope_additions=[]),
                 dict(changed, owned_files=['tests/existing.gd']),
                 dict(changed, scope_additions=[dict(addition, reason=' ')]),
                 dict(changed, scope_additions=[dict(addition, added_files=['tools/a.py'])]),
                 dict(changed, owned_files=['tools/a.py', '../escape'],
                      scope_additions=[dict(addition, added_files=['../escape'])]),
                 dict(changed, owned_files=['tools/a.py', 'tools/b.py'],
                      scope_additions=[dict(addition, added_files=['tools/b.py'])]),
                 dict(changed, acceptance='different goal'),
                 dict(changed, branch='codex/replacement'),
                 dict(changed, worktree=str(self.root/'replacement')),
                 dict(changed, review_session_id='review'),
                 dict(changed, implementation_session_id='replacement'),
                 dict(changed, creation_result={'status':'unknown'}),
                 dict(changed, original_owned_files=['replacement']),
                 dict(changed, status='merged')]
        for case in cases:
            with self.subTest(case=case):
                self.assertEqual(self.dispatch([case])['decision'], 'block')
                self.assertEqual(path.read_bytes(), before)
        self.assertEqual(self.dispatch([changed]), {})
        before = path.read_bytes()
        for case in [task, dict(changed, scope_additions=[dict(addition, reason='rewritten')])]:
            self.assertEqual(self.dispatch([case])['decision'], 'block')
            self.assertEqual(path.read_bytes(), before)
        merged = dict(changed, status='merged', accepted=True)
        self.assertEqual(self.dispatch([merged]), {})
        self.assertEqual(self.dispatch([merged]), {})
        extra = {'added_files':['tests/another.gd'], 'reason':'Another fixture.'}
        self.assertEqual(self.dispatch([dict(merged,
            owned_files=merged['owned_files']+extra['added_files'],
            scope_additions=[addition, extra])])['decision'], 'block')

    def test_scope_addition_atomic_replace_failure_preserves_registry(self):
        task = self.task()
        self.assertEqual(self.dispatch([task]), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        changed = dict(task, owned_files=['tools/a.py', 'tests/existing.gd'],
                       scope_additions=[{'added_files':['tests/existing.gd'], 'reason':'Fixture.'}])
        with patch.object(hook.os, 'replace', side_effect=OSError('disk failure')):
            self.assertEqual(self.dispatch([changed])['decision'], 'block')
        self.assertEqual(path.read_bytes(), before)

    def terminate(self, status='superseded', source='worker-a', **fields):
        return self.handoff(source, None, kind='step_terminal', step_id='a',
            terminal_status=status, unmerged=True, reason='Replaced by smaller steps.',
            human_authorization={'statement':'Human explicitly approved retiring step a.',
                                 'reference':'checkpoint/approval.json'}, **fields)

    def test_terminal_releases_files_preserves_snapshot_and_is_idempotent(self):
        for status in ('superseded', 'cancelled'):
            with self.subTest(status=status):
                path = hook.registry_path(self.root)
                path.unlink(missing_ok=True)
                task = self.task(accepted=False, failed_acceptance={'visual':'failed'})
                self.assertEqual(self.dispatch([task]), {})
                self.assertEqual(self.terminate(status), {})
                saved = json.loads(path.read_text())['steps']['a']
                self.assertEqual(saved['terminal']['previous_step'], task)
                self.assertEqual(saved['status'], status)
                self.assertFalse(saved['accepted'])
                self.assertEqual(saved['failed_acceptance'], task['failed_acceptance'])
                before = path.read_bytes()
                self.assertEqual(self.terminate(status), {})
                self.assertEqual(path.read_bytes(), before)
                self.assertEqual(self.dispatch([self.task('b','worker-b')]), {})
                before = path.read_bytes()
                for changed in [task, dict(saved, status='merged', accepted=True),
                                dict(saved, acceptance='rewritten'),
                                dict(saved, implementation_session_id='replacement')]:
                    self.assertEqual(self.dispatch([changed])['decision'], 'block')
                    self.assertEqual(path.read_bytes(), before)
                self.assertEqual(self.dispatch([self.task('c','worker-c',['c'],['a'])])['decision'], 'block')

    def test_terminal_is_not_an_accepted_dependency_even_with_prior_acceptance(self):
        task = self.task(accepted=True)
        self.assertEqual(self.dispatch([task]), {})
        self.assertEqual(self.terminate(), {})
        self.assertEqual(self.dispatch([self.task('b','worker-b',['b'],['a'])])['decision'], 'block')
        saved = json.loads(hook.registry_path(self.root).read_text())['steps']['a']
        self.assertEqual(self.dispatch([saved]), {})
        for changed in [dict(saved, review_session_id='replacement'),
                        dict(saved, status='active'), dict(saved, terminal={})]:
            self.assertEqual(self.dispatch([changed])['decision'], 'block')
        self.assertEqual(self.dispatch([dict(self.task('new','new-worker',['b']),
                                           status='cancelled')])['decision'], 'block')

    def test_terminal_rejects_missing_authority_wrong_owner_and_merged(self):
        task = self.task()
        self.assertEqual(self.dispatch([task]), {})
        self.assertEqual(self.terminate(source='stranger')['decision'], 'block')
        self.assertEqual(self.terminate(source='old')['decision'], 'block')
        self.terminate()
        marker_path = self.root/'.superpowers/session-handovers/worker-a.json'
        valid = json.loads(marker_path.read_text())
        # Start again with an active record, then exercise actual Stop marker validation.
        path = hook.registry_path(self.root)
        path.unlink()
        self.assertEqual(self.dispatch([task]), {})
        before = path.read_bytes()
        for fields in ({'human_authorization':None}, {'human_authorization':{}},
                       {'human_authorization':{'statement':'Approved', 'reference':''}},
                       {'human_authorization':{'statement':' ', 'reference':'approval'}},
                       {'unmerged':False}, {'reason':' '}, {'terminal_status':'merged'},
                       {'tasks':[]}, {'pr_url':'https://example.com/pull/1'},
                       {'next_session_id':'other'}):
            marker_path.write_text(json.dumps(dict(valid, **fields)))
            result = hook.respond(dict(self.event, session_id='worker-a'))
            self.assertEqual(result.get('decision'), 'block', fields)
            self.assertEqual(path.read_bytes(), before)
        self.assertEqual(self.dispatch([dict(task, status='merged', accepted=True)]), {})
        self.assertEqual(self.terminate()['decision'], 'block')

    def test_terminal_freezes_pr_pair_and_rejects_handoff_or_changed_retry(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        pair = dict(kind='pr_handoff', step_id='a', pr_url='https://example.com/pull/1',
                    implementation_session_id='worker-a', review_session_id='review-a')
        self.assertEqual(self.handoff('worker-a','review-a',**pair), {})
        self.assertEqual(self.terminate(source='review-a'), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        self.assertEqual(self.handoff('worker-a','review-a',**pair)['decision'], 'block')
        self.assertEqual(self.terminate('cancelled',source='review-a')['decision'], 'block')
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(json.loads(before)['prs'][pair['pr_url']]['review_session_id'], 'review-a')

    def test_terminal_runs_through_hook_process_and_shared_worktree_registry(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        subprocess.run(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.com',
                        'commit','--allow-empty','-qm','fixture'],check=True)
        linked = self.root/'linked'
        subprocess.run(['git','-C',str(self.root),'worktree','add','--detach','-q',str(linked)],check=True)
        self.assertEqual(self.dispatch([self.task()]), {})
        self.terminate()
        marker = json.loads((self.root/'.superpowers/session-handovers/worker-a.json').read_text())
        # Restore active fixture via a fresh test registry, not by editing a production registry.
        hook.registry_path(self.root).unlink()
        self.assertEqual(self.dispatch([self.task()]), {})
        (linked/'.superpowers/session-handovers').mkdir(parents=True)
        (linked/'HANDOVER.md').write_text('Human authorized retirement; original evidence retained.')
        marker['summary_path'] = 'HANDOVER.md'
        (linked/'.superpowers/session-handovers/worker-a.json').write_text(json.dumps(marker))
        event = dict(self.event, cwd=str(linked), session_id='worker-a')
        result = subprocess.run(['python3',hook.__file__], input=json.dumps(event),
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), {})
        saved = json.loads(hook.registry_path(self.root).read_text())['steps']['a']
        self.assertEqual(saved['terminal']['previous_step']['status'], 'active')
        self.assertEqual(self.dispatch([self.task('b','worker-b')]), {})

    def test_terminal_atomic_failure_keeps_active_registry(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        path = hook.registry_path(self.root)
        before = path.read_bytes()
        with patch.object(hook.os, 'replace', side_effect=OSError('disk failure')):
            self.assertEqual(self.terminate()['decision'], 'block')
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(self.dispatch([self.task('b','worker-b')])['decision'], 'block')

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
        for _ in range(3):
            self.assertEqual(self.handoff('worker-a','review-a',**pair), {})
            self.assertEqual(self.handoff('review-a','worker-a',**pair), {})
        self.assertEqual(self.dispatch([dict(self.task(), review_session_id='review-a')]), {})
        self.assertEqual(self.handoff('review-a','third',**pair)['decision'], 'block')
        changed = dict(self.task(), review_session_id='other-review')
        self.assertEqual(self.dispatch([changed])['decision'], 'block')
    def test_explicit_pr_handoff_requires_recipient_even_without_next_task(self):
        self.marker.update(kind='pr_handoff', pr_url='https://example.com/pull/1',
                           step_id='a', implementation_session_id='old',
                           review_session_id='review', next_task='')
        self.save()
        self.assertEqual(hook.respond(self.event).get('decision'), 'block')
    def test_dispatch_rejects_worktree_path_aliases(self):
        self.assertEqual(self.dispatch([self.task()]), {})
        alias = self.root / 'alias'
        (self.root / 'a').mkdir()
        alias.symlink_to(self.root / 'a', target_is_directory=True)
        for worktree in [str(self.root / 'a')+'/.', str(alias)]:
            task = dict(self.task('b', 'worker-b', ['tools/b.py']), worktree=worktree)
            self.assertEqual(self.dispatch([task]).get('decision'), 'block')
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
                "h.require_preflight=lambda *_:None; "
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
    def test_scope_addition_conflicts_across_real_worktrees(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        subprocess.run(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.com',
                        'commit','--allow-empty','-qm','fixture'],check=True)
        linked = self.root/'linked'
        subprocess.run(['git','-C',str(self.root),'worktree','add','--detach','-q',str(linked)],check=True)
        a, b = self.task(), self.task('b','worker-b',['tools/b.py'])
        self.assertEqual(self.dispatch([a, b]), {})
        before = hook.registry_path(self.root).read_bytes()
        changed = dict(a, owned_files=['tools/a.py','tools/b.py'],
            scope_additions=[{'added_files':['tools/b.py'], 'reason':'Related test.'}])
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            hook.record_handoff(linked, dict(self.marker, tasks=[changed]))
        self.assertEqual(hook.registry_path(self.root).read_bytes(), before)

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

    def plan(self, *tasks):
        session_fields = ('dispatcher_session_id', 'implementation_session_id', 'review_session_id',
                          'creation_result', 'status', 'accepted')
        return {'source_session_id': 'old',
                'tasks': [{k: v for k, v in task.items() if k not in session_fields} for task in tasks]}
    def run_check(self, plan):
        path = self.root / 'plan.json'
        path.write_text(json.dumps(plan))
        return subprocess.run(['python3', hook.__file__, '--check', str(path)], cwd=self.root,
                              capture_output=True, text=True, timeout=10)
    def check(self, *tasks):
        return self.run_check(self.plan(*tasks))
    def graph(self):
        return json.loads(hook.registry_path(self.root).read_text())
    def fill_unwired_backlog(self):
        for step in 'abcde':
            task = self.unwired(step)
            self.assertEqual(self.check(task).returncode, 0)
            self.assertEqual(self.dispatch([task]), {})

    def test_new_step_cannot_register_without_a_preflight_receipt(self):
        self.preflight_receipts.stop()
        result = self.dispatch([self.task()])
        self.assertEqual(result['decision'], 'block')
        self.assertIn('--check', result['reason'])
    def test_preflight_passes_then_the_same_declaration_registers(self):
        self.preflight_receipts.stop()
        task = self.task()
        checked = self.check(task)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertEqual(json.loads(checked.stdout), {'ok': True})
        self.assertNotIn('a', self.graph().get('steps', {}))
        self.assertEqual(self.dispatch([task]), {})
        graph = self.graph()
        self.assertEqual(graph['steps']['a']['implementation_session_id'], 'worker-a')
        self.assertEqual(graph['preflights'], {})
    def test_declaration_changed_after_preflight_is_refused(self):
        self.preflight_receipts.stop()
        task = self.task()
        self.assertEqual(self.check(task).returncode, 0)
        self.assertEqual(self.dispatch([dict(task, wired=False)])['decision'], 'block')
        self.assertEqual(self.dispatch([dict(task, owned_files=['tools/other.py'])])['decision'], 'block')
        self.assertNotIn('a', self.graph().get('steps', {}))
    def test_preflight_stops_the_product_gate_before_any_session_exists(self):
        self.preflight_receipts.stop()
        self.fill_unwired_backlog()
        checked = self.check(self.unwired('f'))
        self.assertEqual(checked.returncode, 1)
        self.assertIn('product gate', json.loads(checked.stdout)['reason'])
        self.assertNotIn('f', self.graph()['steps'])
    def test_preflight_rejects_overlap_unmet_dependency_and_duplicates(self):
        self.preflight_receipts.stop()
        registered = self.task()
        self.assertEqual(self.check(registered).returncode, 0)
        self.assertEqual(self.dispatch([registered]), {})
        overlap = self.check(self.task('b', 'worker-b', ['tools/a.py']))
        self.assertIn('overlaps', json.loads(overlap.stdout)['reason'])
        unmet = self.check(self.task('c', 'worker-c', ['tools/c.py'], ['a']))
        self.assertIn('merged and accepted', json.loads(unmet.stdout)['reason'])
        self.assertEqual(self.check(registered).returncode, 1)
    def test_preflight_rejects_a_malformed_plan(self):
        for plan in ({'tasks': []}, {'source_session_id': 'old'}, {'source_session_id': 'old', 'tasks': ['a']}, []):
            result = self.run_check(plan)
            self.assertEqual(result.returncode, 1, plan)
            self.assertFalse(json.loads(result.stdout)['ok'])

    def test_refused_step_cannot_be_relabelled_to_pass(self):
        self.preflight_receipts.stop()
        self.fill_unwired_backlog()
        refused = self.unwired('f')
        self.assertEqual(self.check(refused).returncode, 1)
        relabelled = self.check(dict(refused, wired=True))
        self.assertEqual(relabelled.returncode, 1)
        self.assertIn('owner_approval', json.loads(relabelled.stdout)['reason'])
        renamed = self.check(dict(refused, step_id='f2', wired=True))
        self.assertEqual(renamed.returncode, 1)
        self.assertIn('owner_approval', json.loads(renamed.stdout)['reason'])
    def test_owner_approval_releases_a_refused_step(self):
        self.preflight_receipts.stop()
        self.fill_unwired_backlog()
        refused = self.unwired('f')
        self.assertEqual(self.check(refused).returncode, 1)
        approved = dict(refused, owner_approval=self.approval('f approved'))
        self.assertEqual(self.check(approved).returncode, 0)
        self.assertEqual(self.dispatch([approved]), {})
    def test_refusal_at_stop_is_also_remembered(self):
        for step in 'abcde':
            self.assertEqual(self.dispatch([self.unwired(step)]), {})
        self.assertIn('product gate', self.dispatch([self.unwired('f')])['reason'])
        self.assertEqual(self.graph()['refused']['f']['wired'], False)
        self.assertIn('owner_approval', self.dispatch([dict(self.unwired('f'), wired=True)])['reason'])
        self.assertNotIn('f', self.graph()['steps'])

    def test_marker_fixed_after_a_block_is_recorded_on_the_continuation_stop(self):
        pending = dict(self.task(), creation_result={'status': 'pending'})
        self.assertEqual(self.dispatch([pending])['decision'], 'block')
        self.marker.update(tasks=[self.task()])
        self.save()
        self.assertEqual(hook.respond(dict(self.event, stop_hook_active=True)), {})
        self.assertIn('a', self.graph()['steps'])
    def test_continuation_stop_never_blocks_twice_and_records_nothing_invalid(self):
        self.marker.update(kind='dispatch', tasks=[dict(self.task(), creation_result={'status': 'pending'})])
        self.save()
        self.assertEqual(hook.respond(dict(self.event, stop_hook_active=True)), {})
        self.assertFalse(hook.registry_path(self.root).exists())
        (self.root / '.superpowers/session-handovers/old.json').write_text('{broken')
        self.assertEqual(hook.respond(dict(self.event, stop_hook_active=True)), {})

    VALID_PR_BODY = 'Summary.\n\nprd_step: Step 5\nplayer_outcome: the petition appears at court\nwired: true\n'
    def pr_problems(self, body=VALID_PR_BODY, branch='codex/x', number=None, files=('scripts/a.gd',)):
        return hook.pr_body_problems(body, branch, number or hook.FIRST_CHECKED_PR, list(files))

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
        self.assertEqual(self.pr_problems(body, files=['.codex/harness.md', 'AGENTS.md', '.github/workflows/tests.yml']), [])
        self.assertIn('scripts/a.gd', ' '.join(self.pr_problems(body, files=['.codex/harness.md', 'scripts/a.gd'])))
        self.assertIn('wired', ' '.join(self.pr_problems(body.replace('wired: false', 'wired: true'),
                                                         files=['AGENTS.md'])))
    def test_pr_check_covers_only_new_codex_branches(self):
        self.assertEqual(self.pr_problems('', branch='claude/x'), [])
        self.assertEqual(self.pr_problems('', number=hook.FIRST_CHECKED_PR - 1), [])
        self.assertNotEqual(self.pr_problems('', branch='codex/x'), [])
    def test_check_pr_command_reads_the_real_diff_and_fails_closed(self):
        git = ['git', '-C', str(self.root), '-c', 'user.name=Test', '-c', 'user.email=test@example.com']
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(git + ['commit', '--allow-empty', '-qm', 'base'], check=True)
        (self.root / 'game.gd').write_text('changed')
        subprocess.run(git + ['add', 'game.gd'], check=True)
        def run(body, base='HEAD'):
            return subprocess.run(['python3', hook.__file__, '--check-pr'], cwd=self.root, capture_output=True, text=True,
                                  timeout=10, env={**os.environ, 'PR_BODY': body, 'PR_BRANCH': 'codex/x',
                                                   'PR_NUMBER': str(hook.FIRST_CHECKED_PR), 'BASE_SHA': base})
        self.assertEqual(run(self.VALID_PR_BODY).returncode, 0)
        refused = run(self.VALID_PR_BODY.replace('prd_step: Step 5', 'prd_step: harness').replace('wired: true', 'wired: false'))
        self.assertEqual(refused.returncode, 1)
        self.assertIn('game.gd', refused.stdout)
        self.assertEqual(run('').returncode, 1)
        self.assertNotEqual(run(self.VALID_PR_BODY, base='not-a-revision').returncode, 0)
    def test_ci_runs_the_pr_check_in_the_required_harness_job(self):
        workflow = Path(__file__).parents[2].joinpath('.github/workflows/tests.yml').read_text()
        harness_job = workflow.split('  gut-selected:')[0]
        self.assertIn('task-handover.py --check-pr', harness_job)

if __name__ == '__main__':
    unittest.main()
