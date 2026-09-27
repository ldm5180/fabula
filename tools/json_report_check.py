"""The JSON report check for dropped scenarios.

Runs the RELEASE example binary (``example/bin/release/box_main``) with
``--report-json`` over ``tests/data/fixtures/scenario_dropped_after_entry.feature``
and requires valid JSON with the expected scenario and step structure:

- as written, an After hook ignores the first scenario once its steps
  ran.  The scenario was entered, so its element and its three steps
  stay in the report, closed out; the second scenario follows it.
- with ``-t "not @ignore_after"`` the tag filter drops the first
  scenario before entry, so no element is opened for it and only the
  second scenario is reported.

These are fabula's own expectations, NOT oracle output: the byte gate
never covers ``--report-json`` (see ``tools/byte_gate.py``).  The check
reads the report with Python's ``json`` module, so a missing or stray
comma or brace fails it.

Run from the repo root, after ``make example``::

    python3 tools/json_report_check.py
    python3 tools/json_report_check.py --selftest
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
EXAMPLE_BINARY = REPO_ROOT / "example" / "bin" / "release" / "box_main"
FIXTURE = "tests/data/fixtures/scenario_dropped_after_entry.feature"

FEATURE_NAME = "A scenario dropped after it entered"
DROPPED = "Ignored after all its steps ran"
NORMAL = "A normal scenario runs after it"
STEP_COUNT = 3

#  (label, extra arguments, the scenario names the report must hold).
CASES: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = (
    ("dropped after entry", (), (DROPPED, NORMAL)),
    ("dropped before entry", ("-t", "not @ignore_after"), (NORMAL,)),
)


def report_problems(text: str, want: tuple[str, ...]) -> list[str]:
    """What is wrong with one report, against the scenario names it must hold."""
    try:
        report = json.loads(text)
    except json.JSONDecodeError as error:
        return [f"not valid JSON: {error}"]
    if not isinstance(report, list) or len(report) != 1:
        return ["the report is not a list of exactly one feature"]
    feature = report[0]
    problems: list[str] = []
    if feature.get("name") != FEATURE_NAME:
        problems.append(f"feature name {feature.get('name')!r}")
    elements = feature.get("elements", [])
    names = tuple(element.get("name") for element in elements)
    if names != want:
        problems.append(f"scenarios {names!r}, expected {want!r}")
    for element in elements:
        steps = element.get("steps", [])
        statuses = [step.get("result", {}).get("status") for step in steps]
        if len(steps) != STEP_COUNT or statuses != ["passed"] * STEP_COUNT:
            problems.append(f"{element.get('name')!r}: steps {statuses!r}")
    return problems


def run_case(extra: tuple[str, ...]) -> tuple[int, str]:
    """The binary's exit code and stdout for the fixture with extra arguments."""
    result = subprocess.run(
        [str(EXAMPLE_BINARY), FIXTURE, *extra, "--report-json"],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )
    return result.returncode, result.stdout


def run_check() -> int:
    if not EXAMPLE_BINARY.exists():
        print(
            f"json_report_check: {EXAMPLE_BINARY} does not exist -- run `make example` first",
            file=sys.stderr,
        )
        return 1
    failed = False
    for label, extra, want in CASES:
        code, text = run_case(extra)
        problems = report_problems(text, want)
        if code != 0:
            problems.append(f"exit {code}, expected 0")
        for problem in problems:
            print(f"json_report_check: {label}: {problem}", file=sys.stderr)
        failed = failed or bool(problems)
    if failed:
        return 1
    print(
        f"json_report_check: {len(CASES)}/{len(CASES)} ok "
        "(fabula's own expectations, not oracle output)"
    )
    return 0


def _report(names: tuple[str, ...]) -> str:
    """A well-formed report holding the named scenarios, as a fixture."""
    step = {"result": {"status": "passed"}}
    elements = [{"name": name, "steps": [step] * STEP_COUNT} for name in names]
    return json.dumps([{"name": FEATURE_NAME, "elements": elements}])


def selftest() -> int:
    """Each failure mode must fire; a correct report must pass."""
    good = _report((DROPPED, NORMAL))
    cases = {
        "a correct report": (good, (DROPPED, NORMAL), False),
        "a missing comma": (good.replace("}, {", "} {"), (DROPPED, NORMAL), True),
        "a stray closing brace": (good + "}", (DROPPED, NORMAL), True),
        "a scenario dropped before entry reported": (good, (NORMAL,), True),
        "a scenario dropped after entry lost": (_report((NORMAL,)), (DROPPED, NORMAL), True),
    }
    failures = []
    for label, (text, want, should_fail) in cases.items():
        if bool(report_problems(text, want)) != should_fail:
            failures.append(label)
    if failures:
        print(f"json_report_check selftest: FAILED on {failures}", file=sys.stderr)
        return 1
    print("json_report_check selftest: ok (every failure mode fires; a correct report passes)")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true", help="run the self-test only")
    args = parser.parse_args()
    sys.exit(selftest() if args.selftest else run_check())
