"""Official pass rate per snapshot, computed with programbench's own scoring code.
usage (from the programbench checkout): uv run python <this file> <out_dir> <instance_id>"""
import re, sys
from pathlib import Path
from programbench.eval.eval import EvaluationResult
from programbench.utils.load_data import get_active_branches, get_expected_tests, get_ignored_tests, load_all_instances
root, iid = Path(sys.argv[1]), sys.argv[2]
inst = {i["instance_id"]: i for i in load_all_instances(include_tests=True)}[iid]
active, expected, ignored = get_active_branches(inst), get_expected_tests(inst), get_ignored_tests(inst)
print(f"{'min':>4} {'snapshot':16} {'score%':>7} {'passed/total':>12}  note")
for snap in sorted(root.iterdir()):
    m = re.match(r"t(\d{3})", snap.name)
    if not m: continue
    f = snap / iid / f"{iid}.eval.json"
    if not f.exists():
        print(f"{int(m.group(1)):4d} {snap.name:16} {'-':>7} {'-':>8}  not graded yet"); continue
    r = EvaluationResult.model_validate_json(f.read_text())
    r = r.for_branches(active).only_expected(expected).without_ignored(ignored)
    note = r.error_code or ("; ".join(f"{b[:8]}:{[e.error_code for e in v]}" for b, v in r.test_branch_errors.items()) if r.test_branch_errors else "")
    print(f"{int(m.group(1)):4d} {snap.name:16} {100*r.score:7.2f} {r.n_resolved:5d}/{len(r):<5d}  {note}")
