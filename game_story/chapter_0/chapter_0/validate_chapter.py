#!/usr/bin/env python3
"""
validate_chapter.py — static checks + exhaustive path enumeration for a scripted chapter.

Usage:
    python validate_chapter.py chapter1_events.json chapter1_texts.csv [--schema chapter_events.schema.json] [--paths]

Static checks
  * JSON schema (if --schema given and jsonschema installed)
  * every text id referenced exists in the CSV (and unused CSV rows are listed)
  * every next / goto target is an event or ending
  * every flag read in a condition is set somewhere (or initial)
  * every var touched exists in initial_state.vars
  * every remove_modifier id is added somewhere
  * every event is reachable

Path enumeration
  Walks every option at every event, for every combination of trait branches and
  objective outcome (met / not met). Only EVENT effects are applied — the deterministic
  simulation (harvests, taxes, policy actions) is NOT run here, so the reported numbers
  are "event-only deltas": what the story itself gives or takes, which the player's
  economic play must make up.
"""
import argparse
import csv
import itertools
import json
import sys
from collections import defaultdict

PHASE_ORDER = {"start": 0, "end": 1}


# ---------------------------------------------------------------- helpers
def walk_conditions(cond, out):
    """Collect (kind, value) leaves from a condition tree."""
    if cond is None:
        return
    if "flag" in cond:
        out.append(("flag", cond["flag"]))
    elif "not" in cond:
        walk_conditions(cond["not"], out)
    elif "all" in cond or "any" in cond:
        for c in cond.get("all", cond.get("any")):
            walk_conditions(c, out)
    elif "var" in cond:
        out.append(("var", cond["var"]))
    elif "trait" in cond:
        out.append(("trait", (cond["trait"]["character"], cond["trait"]["trait"])))
    elif "objective" in cond:
        out.append(("objective", cond["objective"]))


def cmp(a, op, b):
    return {"==": a == b, "!=": a != b, ">": a > b, ">=": a >= b, "<": a < b, "<=": a <= b}[op]


class State:
    def __init__(self, data, traits, objective_met):
        self.vars = dict(data["initial_state"]["vars"])
        self.flags = set(data["initial_state"]["flags"])
        self.mods = {}
        self.objectives = set()
        self.traits = traits
        self.objective_met = objective_met
        self.trace = []
        self.granularity = "seasonal"
        self.snapshot = None

    def copy(self):
        s = State.__new__(State)
        s.vars = dict(self.vars)
        s.flags = set(self.flags)
        s.mods = dict(self.mods)
        s.objectives = set(self.objectives)
        s.traits = self.traits
        s.objective_met = self.objective_met
        s.trace = list(self.trace)
        s.granularity = self.granularity
        s.snapshot = self.snapshot
        return s

    def test(self, cond):
        if cond is None:
            return True
        if "flag" in cond:
            return cond["flag"] in self.flags
        if "not" in cond:
            return not self.test(cond["not"])
        if "all" in cond:
            return all(self.test(c) for c in cond["all"])
        if "any" in cond:
            return any(self.test(c) for c in cond["any"])
        if "var" in cond:
            return cmp(self.vars[cond["var"]], cond["cmp"], cond["value"])
        if "trait" in cond:
            t = cond["trait"]
            return self.traits.get(t["character"]) == t["trait"]
        if "objective" in cond:
            self.snapshot = dict(self.vars)  # values at the moment the objective is judged
            return self.objective_met  # scenario parameter; sim decides in-game
        raise ValueError(cond)

    def apply(self, effects):
        for e in effects:
            op = e["op"]
            if op == "add":
                self.vars[e["var"]] += e["value"]
            elif op == "set":
                self.vars[e["var"]] = e["value"]
            elif op == "set_flag":
                self.flags.add(e["flag"])
            elif op == "clear_flag":
                self.flags.discard(e["flag"])
            elif op == "add_modifier":
                self.mods[e["id"]] = (e["target"], e["value"], e["turns"])
            elif op == "remove_modifier":
                self.mods.pop(e["id"], None)
            elif op == "activate_objective":
                self.objectives.add(e["id"])
            elif op == "set_turn_granularity":
                self.granularity = e["value"]


# ---------------------------------------------------------------- static checks
def static_checks(data, texts):
    errors, warnings = [], []
    events = {e["id"]: e for e in data["events"]}
    endings = {e["id"]: e for e in data["endings"]}
    targets = set(events) | set(endings)
    init_vars = set(data["initial_state"]["vars"])
    objectives = {o["id"] for o in data["objectives"]}

    used_texts = set()
    flags_set = set(data["initial_state"]["flags"])
    flags_read = defaultdict(list)
    mods_added, mods_removed = set(), defaultdict(list)
    mod_targets = set()
    graph = defaultdict(set)

    def use_text(tid, where):
        used_texts.add(tid)
        if tid not in texts:
            errors.append(f"missing text id '{tid}' ({where})")

    def scan_effects(effs, where):
        for e in effs:
            if e["op"] in ("add", "set") and e["var"] not in init_vars:
                errors.append(f"{where}: var '{e['var']}' not in initial_state.vars")
            if e["op"] == "set_flag":
                flags_set.add(e["flag"])
            if e["op"] == "add_modifier":
                mods_added.add(e["id"])
                mod_targets.add(e["target"])
            if e["op"] == "remove_modifier":
                mods_removed[e["id"]].append(where)
            if e["op"] == "activate_objective" and e["id"] not in objectives:
                errors.append(f"{where}: unknown objective '{e['id']}'")

    def scan_cond(cond, where):
        leaves = []
        walk_conditions(cond, leaves)
        for kind, v in leaves:
            if kind == "flag":
                flags_read[v].append(where)
            elif kind == "var" and v not in init_vars:
                errors.append(f"{where}: condition var '{v}' not in initial_state.vars")
            elif kind == "trait" and v[0] not in data.get("characters", {}):
                errors.append(f"{where}: trait check on unknown character '{v[0]}'")
            elif kind == "objective" and v not in objectives:
                errors.append(f"{where}: unknown objective '{v}'")

    use_text(data["title_text"], "chapter")
    for cid, c in data.get("characters", {}).items():
        use_text(c["name_text"], f"character {cid}")
    for o in data["objectives"]:
        use_text(o["title_text"], o["id"])
        if "desc_text" in o:
            use_text(o["desc_text"], o["id"])
        for c in o["conditions"]:
            if c["var"] not in init_vars:
                errors.append(f"{o['id']}: var '{c['var']}' not in initial_state.vars")
            if "label_text" in c:
                use_text(c["label_text"], o["id"])

    for eid, ev in list(events.items()) + list(endings.items()):
        use_text(ev["title_text"], eid)
        if "body_text" in ev:
            use_text(ev["body_text"], eid)
        for r in ev.get("body_text_rules", []):
            use_text(r["text"], eid)
            scan_cond(r.get("if"), f"{eid}.body_text_rules")
        if ev.get("body_text_rules") and "if" in ev["body_text_rules"][-1]:
            warnings.append(f"{eid}: body_text_rules has no unconditional fallback")
        trig = ev.get("trigger")
        if trig:
            scan_cond(trig.get("condition"), f"{eid}.trigger")
        scan_effects(ev.get("on_fire", []), f"{eid}.on_fire")
        scan_effects(ev.get("effects", []), eid)
        for opt in ev.get("options", []):
            where = f"{eid}.{opt['id']}"
            use_text(opt["label_text"], where)
            scan_cond(opt.get("requires"), f"{where}.requires")
            scan_effects(opt["effects"], where)
            nxts = []
            if opt.get("next"):
                nxts.append(opt["next"])
            for r in opt.get("next_rules", []):
                scan_cond(r.get("if"), f"{where}.next_rules")
                nxts.append(r["goto"])
            if opt.get("next_rules") and "if" in opt["next_rules"][-1]:
                warnings.append(f"{where}: next_rules has no unconditional fallback")
            for n in nxts:
                if n not in targets:
                    errors.append(f"{where}: next target '{n}' does not exist")
                graph[eid].add(n)
        # every event must offer at least one option with no 'requires'
        if eid in events and all("requires" in o for o in ev["options"]):
            warnings.append(f"{eid}: every option has 'requires' — possible soft-lock")

    for f, wheres in flags_read.items():
        if f not in flags_set:
            errors.append(f"flag '{f}' is read ({wheres[0]}) but never set")
    for m, wheres in mods_removed.items():
        if m not in mods_added:
            errors.append(f"modifier '{m}' removed ({wheres[0]}) but never added")

    # reachability: scheduled events are roots
    roots = [eid for eid, ev in events.items() if ev.get("trigger")]
    seen, stack = set(roots), list(roots)
    while stack:
        for n in graph[stack.pop()]:
            if n not in seen:
                seen.add(n)
                stack.append(n)
    for t in targets - seen:
        errors.append(f"'{t}' is unreachable")

    unused = sorted(set(texts) - used_texts)
    if unused:
        warnings.append(f"{len(unused)} unused text ids: {', '.join(unused)}")

    return errors, warnings, sorted(mod_targets)


# ---------------------------------------------------------------- path enumeration
def enumerate_paths(data):
    events = {e["id"]: e for e in data["events"]}
    endings = {e["id"]: e for e in data["endings"]}
    schedule = sorted(
        (e for e in data["events"] if e.get("trigger")),
        key=lambda e: (e["trigger"]["turn"], PHASE_ORDER[e["trigger"]["phase"]]),
    )

    trait_axes = defaultdict(set)
    for ev in data["events"]:
        for opt in ev["options"]:
            for r in opt.get("next_rules", []):
                leaves = []
                walk_conditions(r.get("if"), leaves)
                for kind, v in leaves:
                    if kind == "trait":
                        trait_axes[v[0]].add(v[1])
    axis_names = sorted(trait_axes)
    axis_values = [sorted(trait_axes[a]) + ["<other>"] for a in axis_names]

    results = []

    def run_chain(state, eid, sched_idx):
        ev = events[eid]
        state.apply(ev.get("on_fire", []))
        available = [o for o in ev["options"] if state.test(o.get("requires"))]
        if not available:
            results.append(("SOFTLOCK", state, eid))
            return
        for opt in available:
            s = state.copy()
            s.trace.append(f"{eid}:{opt['id']}")
            s.apply(opt["effects"])
            nxt = opt.get("next")
            for r in opt.get("next_rules", []):
                if s.test(r.get("if")):
                    nxt = r["goto"]
                    break
            if nxt is None:
                run_schedule(s, sched_idx + 1)
            elif nxt in endings:
                s.apply(endings[nxt]["effects"])
                s.trace.append(nxt)
                results.append((nxt, s, None))
            else:
                run_chain(s, nxt, sched_idx)

    def run_schedule(state, idx):
        while idx < len(schedule):
            ev = schedule[idx]
            if state.test(ev["trigger"].get("condition")):
                run_chain(state, ev["id"], idx)
                return
            idx += 1
        results.append(("NO_ENDING", state, None))

    for combo in itertools.product(*axis_values):
        traits = dict(zip(axis_names, combo))
        for met in (True, False):
            run_schedule(State(data, traits, met), 0)
    return results


def report_paths(data, results):
    init = data["initial_state"]["vars"]
    obj = data["objectives"][0]
    obj_vars = [c["var"] for c in obj["conditions"]]
    by_end = defaultdict(list)
    problems = []
    for end, s, where in results:
        if end in ("SOFTLOCK", "NO_ENDING"):
            problems.append(f"{end} at {where}: {' > '.join(s.trace)}")
        by_end[end].append(s)

    # dedupe by trace
    uniq = {tuple(s.trace): s for _, s, _ in results}
    print(f"\n== Path enumeration: {len(results)} runs, {len(uniq)} distinct choice paths ==")
    for p in problems:
        print("  PROBLEM:", p)

    val = lambda s, v: (s.snapshot or s.vars)[v]
    print("\nEvent-only deltas at the objective deadline (sim/policy play not included):")
    hdr = f"  {'ending':<18}{'paths':>6}  " + "  ".join(f"{v.split('.')[-1]:>22}" for v in obj_vars)
    print(hdr)
    for end, states in sorted(by_end.items()):
        cells = []
        for v in obj_vars:
            ds = [val(s, v) - init[v] for s in states]
            cells.append(f"{min(ds):>+10} .. {max(ds):>+9}")
        print(f"  {end:<18}{len(states):>6}  " + "  ".join(f"{c:>22}" for c in cells))

    print("\nGap the economy must close (target - start - best/worst event delta):")
    for c in obj["conditions"]:
        v = c["var"]
        ds = [val(s, v) - init[v] for _, s, _ in results]
        lo, hi = min(ds), max(ds)
        if c["cmp"] in (">=", ">"):
            best, worst = c["value"] - init[v] - hi, c["value"] - init[v] - lo
            print(f"  {v:<38} need {c['cmp']}{c['value']:<7} start {init[v]:<6} "
                  f"sim must add: best path {best:+}, worst path {worst:+}")
        else:
            best, worst = init[v] + lo - c["value"], init[v] + hi - c["value"]
            print(f"  {v:<38} need {c['cmp']}{c['value']:<7} start {init[v]:<6} "
                  f"end value (event-only): {init[v] + lo} .. {init[v] + hi}")

    reach = defaultdict(int)
    for _, s, _ in results:
        for step in s.trace:
            reach[step.split(":")[0]] += 1
    never = [e["id"] for e in data["events"] if reach[e["id"]] == 0] + \
            [e["id"] for e in data["endings"] if reach[e["id"]] == 0]
    if never:
        print("\n  Never reached in enumeration:", ", ".join(never))
    return not problems and not never


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("events")
    ap.add_argument("texts")
    ap.add_argument("--schema")
    ap.add_argument("--paths", action="store_true", help="enumerate all choice paths")
    ap.add_argument("--illustrations", help="illustrations_manifest.csv to cross-check")
    a = ap.parse_args()

    data = json.load(open(a.events, encoding="utf-8"))
    with open(a.texts, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    texts = {}
    dup = []
    for r in rows:
        if r["text_id"] in texts:
            dup.append(r["text_id"])
        texts[r["text_id"]] = r

    ok = True
    if a.schema:
        try:
            import jsonschema
            jsonschema.validate(data, json.load(open(a.schema, encoding="utf-8")))
            print("schema: ok")
        except ImportError:
            print("schema: skipped (pip install jsonschema)")
        except Exception as ex:  # jsonschema.ValidationError
            print("schema: FAIL —", getattr(ex, "message", ex))
            ok = False

    errors, warnings, mod_targets = static_checks(data, texts)
    errors += [f"duplicate text id '{d}'" for d in dup]
    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"static: {len(errors)} errors, {len(warnings)} warnings")
    print("modifier targets the engine must implement:", ", ".join(mod_targets))
    ok = ok and not errors

    if a.illustrations:
        with open(a.illustrations, encoding="utf-8", newline="") as f:
            man = {r["illus_id"]: r for r in csv.DictReader(f)}
        used = {}
        for ev in data["events"] + data["endings"]:
            iid = ev.get("illustration")
            if iid is None:
                print("WARN  no illustration on", ev["id"])
            elif iid not in man:
                print("ERROR illustration", iid, "on", ev["id"], "missing from manifest"); ok = False
            else:
                used[iid] = ev["id"]
        for iid, r in man.items():
            if r["kind"] == "scene" and iid not in used:
                print("WARN  scene", iid, "not used by any event")
        print(f"illustrations: {len(used)} linked, {sum(r['kind'] == 'scene' for r in man.values())} scenes in manifest")

    if a.paths:
        ok = report_paths(data, enumerate_paths(data)) and ok

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
