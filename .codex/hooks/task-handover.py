#!/usr/bin/env python3
"""Native Codex hook: bounded task handover guidance and ready-marker guard."""
import json
import fcntl
import os
import subprocess
import sys
import tempfile
from pathlib import Path

RULES = Path(__file__).with_suffix(".md")


def registry_path(cwd):
    """All linked worktrees share a graph; no conversation history is read."""
    result = subprocess.run(['git', 'rev-parse', '--git-common-dir'], cwd=cwd,
                            capture_output=True, text=True, timeout=2)
    if result.returncode == 0:
        return (cwd / result.stdout.strip()).resolve() / 'codex-handoffs.json'
    return cwd / '.superpowers' / 'session-handover-graph.json'


def valid_session(value):
    return isinstance(value, str) and bool(value) and all(c.isalnum() or c == '-' for c in value)


def record_handoff(cwd, data):
    """Validate declarations under one shared lock; never infer tool calls or CI results."""
    path = registry_path(cwd)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        graph = json.loads(path.read_text()) if path.exists() else {'edges': {}, 'prs': {}}
        if data.get('kind') == 'dispatch':
            record_dispatch(graph, data)
        else:
            record_pr_handoff(graph, data)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
                temporary = Path(out.name)
                json.dump(graph, out, ensure_ascii=False, indent=2)
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def record_pr_handoff(graph, data):
    edges = graph['edges']
    source, target = data['source_session_id'], data.get('next_session_id')
    if not valid_session(target):
        raise ValueError('next_session_id must name exactly one fresh session')
    if 'tasks' in data:
        raise ValueError('dispatch and PR handoff records must be separate')
    for step in graph.get('steps', {}).values():
        if step['dispatcher_session_id'] in (source, target):
            raise ValueError('dispatcher cannot participate in PR handoff chains')
        owners = {step['implementation_session_id'], step['review_session_id']} - {None}
        if owners & {source, target} and not (
                data.get('step_id') == step['step_id'] and data.get('pr_url') and
                source == step['implementation_session_id'] and
                target == data.get('review_session_id')):
            raise ValueError('dispatched owners may only hand off their own PR')
    if source in edges and edges[source] != target:
        raise ValueError('一对多 handover 禁止：本 session 已有唯一后继')
    if target in edges and edges.get(source) != target:
        raise ValueError('目标 session 已交接过，不能作为全新后继')
    if any(s != source and t == target for s, t in edges.items()):
        raise ValueError('多对一 handover 禁止：目标 session 已有前驱')
    cursor, visited = target, {source}
    while True:
        if cursor in visited:
            raise ValueError('handover 必须是无环的一对一链，禁止返回旧 session')
        visited.add(cursor)
        if cursor not in edges:
            break
        cursor = edges[cursor]
    if data.get('pr_url'):
        pair = {k: data.get(k) for k in ['step_id', 'implementation_session_id', 'review_session_id']}
        owners = [pair['implementation_session_id'], pair['review_session_id']]
        if not all(isinstance(v, str) and v.strip() for v in pair.values()) or len(set(owners)) != 2:
            raise ValueError('每个 PR 必须指定一个 step、实施 session 和唯一 Review session')
        if source not in owners or (source == owners[0] and target != owners[1]):
            raise ValueError('禁止第三个 session 参与同一 PR；实施只能交给指定 Review')
        if data.get('kind') == 'pr_handoff' and (source != owners[0] or target != owners[1]):
            raise ValueError('PR handoff must go from implementation to its unique Review')
        step = graph.get('steps', {}).get(pair['step_id'])
        if step is not None:
            if (source != step['implementation_session_id'] or target != owners[1] or
                    owners[0] != step['implementation_session_id'] or
                    step['review_session_id'] not in (None, owners[1])):
                raise ValueError('PR owners must match the dispatched step')
            step['review_session_id'] = owners[1]
        for step_id, other in graph.get('steps', {}).items():
            if other['dispatcher_session_id'] in owners:
                raise ValueError('dispatcher cannot become a PR owner')
            if step_id != pair['step_id'] and set(owners) & {
                    other['implementation_session_id'], other['review_session_id']}:
                raise ValueError('session already owns another dispatched step')
        old = graph['prs'].get(data['pr_url'])
        if old is not None and old != pair:
            raise ValueError('同一 PR 的 step 和两个负责 session 不可被另一组替换')
        for url, existing in graph['prs'].items():
            if url != data['pr_url'] and (existing['step_id'] == pair['step_id'] or
                    set(owners) & {existing['implementation_session_id'], existing['review_session_id']}):
                raise ValueError('一个 step 只有一个 PR，一个 session 只负责一个 step／PR')
        graph['prs'][data['pr_url']] = pair
    edges[source] = target


def record_dispatch(graph, data):
    tasks = data.get('tasks')
    if not isinstance(tasks, list) or not tasks:
        raise ValueError('dispatch requires complete tasks, not session lists')
    if any(key in data for key in ('next_session_id', 'next_session_ids', 'pr_url')):
        raise ValueError('dispatch and PR handoff records must be separate')
    source = data['source_session_id']
    steps = graph.setdefault('steps', {})
    seen = set()
    for task in tasks:
        if not isinstance(task, dict):
            raise ValueError('dispatch task must be an object')
        for key in ('step_id', 'dispatcher_session_id', 'acceptance', 'worktree', 'branch',
                    'implementation_session_id'):
            if not isinstance(task.get(key), str) or not task[key].strip():
                raise ValueError('dispatch requires ' + key)
        step_id = task['step_id']
        if step_id in seen:
            raise ValueError('duplicate dispatch step')
        seen.add(step_id)
        if task['dispatcher_session_id'] != source:
            raise ValueError('step must have exactly one dispatch authority')
        owner = task['implementation_session_id']
        review = task['review_session_id']
        if not valid_session(owner) or (review is not None and not valid_session(review)):
            raise ValueError('invalid implementation or Review session')
        if owner == source or review in (source, owner):
            raise ValueError('dispatcher must be separate from the implementation/Review pair')
        if not Path(task['worktree']).is_absolute() or not task['branch'].startswith('codex/'):
            raise ValueError('dispatch requires an absolute worktree and codex/ branch')
        dependencies = task['dependencies']
        if (not isinstance(dependencies, list) or
                any(not isinstance(dep, str) or not dep for dep in dependencies) or
                len(set(dependencies)) != len(dependencies)):
            raise ValueError('dependencies must be unique step ids')
        files = task.get('owned_files')
        if not isinstance(files, list) or not files:
            raise ValueError('owned_files must list repository-relative paths')
        for name in files:
            if (not isinstance(name, str) or not name or Path(name).is_absolute() or
                    any(part in ('', '.', '..') for part in name.split('/')) or
                    any(char in name for char in '*?[]\\')):
                raise ValueError('owned_files must be literal repository-relative paths')
        creation = task['creation_result']
        if (not isinstance(creation, dict) or creation.get('status') != 'created' or
                creation.get('session_id') != owner):
            raise ValueError('reconcile unknown creation results before registering or retrying')
        if task.get('status') not in ('active', 'merged'):
            raise ValueError('step status must be active or merged')
        old = steps.get(step_id)
        if old is not None:
            for key in ('dispatcher_session_id', 'dependencies', 'acceptance',
                        'worktree', 'branch', 'implementation_session_id', 'creation_result'):
                if task[key] != old[key]:
                    raise ValueError('duplicate dispatch or immutable step ownership changed')
            if old['review_session_id'] is not None and review != old['review_session_id']:
                raise ValueError('Review owner cannot be replaced')
            if old['status'] == 'merged' and task['status'] != 'merged':
                raise ValueError('completed step cannot be restarted')
        additions = task.get('scope_additions', [])
        previous = old.get('scope_additions', []) if old else []
        if not isinstance(additions, list) or additions[:len(previous)] != previous:
            raise ValueError('scope addition history must be preserved')
        original = old.get('original_owned_files', old['owned_files']) if old else files
        if task.get('original_owned_files', original) != original:
            raise ValueError('original file declaration cannot be replaced')
        expected_files = list(original)
        for addition in additions:
            if (not isinstance(addition, dict) or set(addition) != {'added_files', 'reason'} or
                    not isinstance(addition['reason'], str) or not addition['reason'].strip() or
                    not isinstance(addition['added_files'], list) or not addition['added_files']):
                raise ValueError('scope additions require added_files and a reason')
            for name in addition['added_files']:
                if not isinstance(name, str) or name not in files or name in expected_files:
                    raise ValueError('scope additions must append new literal owned files')
                expected_files.append(name)
        if files != expected_files:
            raise ValueError('owned files may only change through audited additions')
        if additions != previous and (old is None or old['status'] != 'active' or
                                      task['status'] != 'active' or review != old['review_session_id']):
            raise ValueError('only an existing active step may add owned files')
        steps[step_id] = dict(task)
        if additions:
            steps[step_id]['original_owned_files'] = list(original)
    # Walk the full declared graph, including converging prerequisites.
    def visit(step_id, visiting, visited):
        if step_id in visiting:
            raise ValueError('dispatch dependency cycle')
        if step_id in visited:
            return
        if step_id not in steps:
            raise ValueError('missing declared dependency')
        for dep in steps[step_id]['dependencies']:
            visit(dep, visiting | {step_id}, visited)
        visited.add(step_id)
    visited = set()
    for step_id in steps:
        visit(step_id, set(), visited)
    for step_id, task in steps.items():
        for dep in task['dependencies']:
            if steps[dep]['status'] != 'merged' or steps[dep].get('accepted') is not True:
                raise ValueError('declared dependency must be merged and accepted')
        owners = {task['implementation_session_id'], task['review_session_id']} - {None}
        if task['dispatcher_session_id'] in (set(graph['edges']) | set(graph['edges'].values())) or any(
                task['dispatcher_session_id'] in (pair['implementation_session_id'], pair['review_session_id'])
                for pair in graph['prs'].values()):
            raise ValueError('PR owner cannot also dispatch steps')
        for other_id, other in steps.items():
            if other_id == step_id:
                continue
            if owners & {other['implementation_session_id'], other['review_session_id'],
                         other['dispatcher_session_id']} or task['dispatcher_session_id'] in {
                             other['implementation_session_id'], other['review_session_id']}:
                raise ValueError('session already owns another step or dispatch role')
            if (Path(task['worktree']).resolve() == Path(other['worktree']).resolve() or
                    task['branch'] == other['branch']):
                raise ValueError('steps require separate worktrees and branches')
            if task['status'] == 'active' and other['status'] == 'active' and any(
                    a == b or a.startswith(b+'/') or b.startswith(a+'/')
                    for a in task['owned_files'] for b in other['owned_files']):
                raise ValueError('active file ownership overlaps')
        expected = (task['implementation_session_id'], task['review_session_id'])
        for source, target in graph['edges'].items():
            if owners & {source, target} and (source, target) != expected:
                raise ValueError('cannot return to a historical session owner')
        for pair in graph['prs'].values():
            if (step_id == pair['step_id'] or owners & {pair['implementation_session_id'], pair['review_session_id']}) and (
                    step_id != pair['step_id'] or expected != (
                        pair['implementation_session_id'], pair['review_session_id'])):
                raise ValueError('session already owns another PR')

def respond(event):
    if not isinstance(event, dict):
        raise ValueError("hook input must be an object")
    name = event.get("hook_event_name", "")
    if name == "SessionStart":
        return {"hookSpecificOutput": {"hookEventName": name, "additionalContext": RULES.read_text(encoding="utf-8")}}
    if name != "Stop" or event.get("stop_hook_active", False):
        return {}
    cwd = Path(event.get("cwd", ".")).resolve()
    session_id = event.get("session_id", "")
    if not isinstance(session_id, str) or not session_id or any(not (c.isalnum() or c == "-") for c in session_id):
        return {}
    marker = cwd / ".superpowers" / "session-handovers" / (session_id + ".json")
    if not marker.is_file():
        return {}
    data = json.loads(marker.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("handover marker must be an object")
    if data.get("status") not in ["ready", "handed_off"] or data.get("source_session_id") != session_id:
        return {}
    summary = Path(data.get("summary_path", ""))
    if not summary.is_absolute():
        summary = cwd / summary
    summary = summary.resolve()
    if not summary.is_relative_to(cwd) or not summary.is_file() or not summary.read_text(encoding="utf-8").strip():
        return {"decision": "block", "reason": "任务交接尚未完成：先在当前工作树保存有效的精简 HANDOVER.md，再执行交接；不要重新读取全部历史。"}
    kind = data.get('kind')
    if kind not in (None, 'pr_handoff', 'dispatch'):
        return {'decision': 'block', 'reason': 'unknown handover kind'}
    if kind == 'dispatch':
        try:
            record_handoff(cwd, data)
        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
            return {'decision': 'block', 'reason': str(error)}
        return {}
    if kind == 'pr_handoff' and (not data.get('pr_url') or not valid_session(data.get('next_session_id'))):
        return {'decision': 'block', 'reason': 'pr_handoff requires pr_url, its owner pair and one recipient'}
    if any(k in data for k in ['next_session_ids', 'predecessor_session_ids']):
        return {"decision": "block", "reason": "handover 只允许一对一，禁止 session 列表"}
    if not data.get("next_task") and not data.get('next_session_id'):
        return {}
    if not isinstance(data.get('next_task'), str) or not data['next_task'].strip():
        return {"decision": "block", "reason": "next_task 必须是一个已授权的独立任务"}
    if data.get('next_session_id'):
        try:
            record_handoff(cwd, data)
        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
            return {"decision": "block", "reason": str(error)}
        return {}
    return {"decision": "block", "reason": "当前任务已到交接边界。读取精简检查点 " + str(summary) + "，为其中已授权的下一任务创建不继承历史的新 session（create_thread，禁止 fork/resume）；成功后将返回的 next_session_id 和 handed_off 状态写回 .superpowers/session-handovers/<source_session_id>.json，然后结束本 session。不要再实施下一任务，不要重读完整历史。若无新会话工具或用户已暂停，保留检查点并明确说明限制，不启动后台循环。"}

if __name__ == "__main__":
    try:
        event = json.load(sys.stdin)
        result = respond(event)
        # Runtime evidence only: no prompt or transcript is written.
        if isinstance(event, dict) and event.get("cwd"):
            try:
                audit = Path(event["cwd"]) / ".superpowers" / "hook-audit.jsonl"
                audit.parent.mkdir(parents=True, exist_ok=True)
                with audit.open("a", encoding="utf-8") as out:
                    out.write(json.dumps({"event": event.get("hook_event_name"),
                        "session_id": event.get("session_id"), "turn_id": event.get("turn_id"),
                        "source": event.get("source"), "decision": result.get("decision", "allow")}) + "\n")
            except OSError:
                pass
    except (OSError, ValueError, TypeError) as error:
        result = {"decision": "block", "reason": "Task handover hook could not read its checkpoint: " + str(error)}
    print(json.dumps(result, ensure_ascii=False))
