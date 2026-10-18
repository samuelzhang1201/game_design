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


def record_handoff(cwd, data):
    source, target = data['source_session_id'], data.get('next_session_id')
    if not isinstance(target, str) or not target or any(not (c.isalnum() or c == '-') for c in target):
        raise ValueError('next_session_id must name exactly one fresh session')
    path = registry_path(cwd)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        graph = json.loads(path.read_text()) if path.exists() else {'edges': {}, 'prs': {}}
        edges = graph['edges']
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
            old = graph['prs'].get(data['pr_url'])
            if old is not None and old != pair:
                raise ValueError('同一 PR 的 step 和两个负责 session 不可被另一组替换')
            for url, existing in graph['prs'].items():
                if url != data['pr_url'] and (existing['step_id'] == pair['step_id'] or
                        set(owners) & {existing['implementation_session_id'], existing['review_session_id']}):
                    raise ValueError('一个 step 只有一个 PR，一个 session 只负责一个 step／PR')
            graph['prs'][data['pr_url']] = pair
        edges[source] = target
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
                temporary = Path(out.name)
                json.dump(graph, out, ensure_ascii=False, indent=2)
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


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
