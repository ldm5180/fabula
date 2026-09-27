"""The JSON report snapshot check.

Runs the RELEASE example binary (``example/bin/release/box_main``) once
per line of ``tests/data/json_snapshots/MANIFEST.txt`` and compares the
JSON report it writes, byte for byte, with the snapshot the line names
under ``tests/data/json_snapshots/expected/``.

These are regression snapshots of fabula's own output, NOT oracle
output: the byte gate covers console output only (see
``tools/byte_gate.py``), and ``tools/json_report_check.py`` reads one
single-feature report for its structure.  The snapshots pin the rest of
the JSON writer: the comma between two features, a feature with no
scenario element, the ``[]`` of a report with no feature, scenarios
dropped before and after entry, and the trailing newline that standard
output gets and a report file does not.

Run from the repo root, after ``make example``::

    python3 tools/json_snapshot_check.py
    python3 tools/json_snapshot_check.py --selftest
    python3 tools/json_snapshot_check.py --write

``--write`` rewrites every snapshot from the current binary.  Use it
only for an intended change of the JSON output, and read the diff of
every snapshot before committing it.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
EXAMPLE_BINARY = REPO_ROOT / "example" / "bin" / "release" / "box_main"
SNAPSHOTS = REPO_ROOT / "tests" / "data" / "json_snapshots"
MANIFEST = SNAPSHOTS / "MANIFEST.txt"
EXPECTED = SNAPSHOTS / "expected"

TARGETS = ("stdout", "file")


def read_manifest(path: pathlib.Path) -> list[tuple[str, str, list[str]]]:
    """(snapshot name, target, arguments) for every run the manifest lists."""
    runs = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split("|")]
        if len(fields) < 3 or fields[1] not in TARGETS:
            raise SystemExit(f"json_snapshot_check: {path}:{number}: bad line: {raw}")
        runs.append((fields[0], fields[1], fields[2:]))
    return runs


def report_of(binary: pathlib.Path, target: str, arguments: list[str]) -> bytes:
    """The bytes of the JSON report one run writes to its target."""
    if target == "stdout":
        done = subprocess.run(
            [str(binary), *arguments, "--report-json"],
            capture_output=True,
            check=False,
            cwd=REPO_ROOT,
        )
        return done.stdout
    with tempfile.TemporaryDirectory() as scratch:
        report = pathlib.Path(scratch) / "report.json"
        subprocess.run(
            [str(binary), "--report-json=" + str(report), *arguments],
            capture_output=True,
            check=False,
            cwd=REPO_ROOT,
        )
        return report.read_bytes() if report.exists() else b""


def first_difference(got: bytes, want: bytes) -> str | None:
    """None when the two are equal; else where they first differ."""
    if got == want:
        return None
    for offset, (a, b) in enumerate(zip(got, want)):
        if a != b:
            return f"byte {offset}: got {bytes([a])!r}, snapshot has {bytes([b])!r}"
    return f"length {len(got)}, snapshot length {len(want)}"


def run_check(binary: pathlib.Path) -> int:
    if not binary.exists():
        print(
            f"json_snapshot_check: {binary} does not exist -- run `make example` first",
            file=sys.stderr,
        )
        return 1
    runs = read_manifest(MANIFEST)
    failed = 0
    for name, target, arguments in runs:
        snapshot = EXPECTED / name
        if not snapshot.exists():
            print(f"json_snapshot_check: {name}: no snapshot file", file=sys.stderr)
            failed += 1
            continue
        problem = first_difference(report_of(binary, target, arguments), snapshot.read_bytes())
        if problem is not None:
            print(f"json_snapshot_check: {name}: {problem}", file=sys.stderr)
            failed += 1
    if failed:
        print(f"json_snapshot_check: {failed} of {len(runs)} snapshots differ", file=sys.stderr)
        return 1
    print(
        f"json_snapshot_check: {len(runs)}/{len(runs)} identical "
        "(regression snapshots of fabula's own output, not oracle output)"
    )
    return 0


def write_snapshots(binary: pathlib.Path) -> int:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    runs = read_manifest(MANIFEST)
    for name, target, arguments in runs:
        (EXPECTED / name).write_bytes(report_of(binary, target, arguments))
    print(f"json_snapshot_check: wrote {len(runs)} snapshots; read every diff before committing")
    return 0


def selftest() -> int:
    """Each difference must be found; an equal report must pass."""
    report = b'[\n  {\n    "elements": [\n    ],\n    "uri": "a.feature"\n  }\n]'
    cases = {
        "an equal report": (report, report, False),
        "a trailing newline added": (report + b"\n", report, True),
        "a trailing newline lost": (report, report + b"\n", True),
        "a comma turned into a bracket": (
            report.replace(b"],", b"]["),
            report,
            True,
        ),
        "an empty report for a full one": (b"[]", report, True),
    }
    failures = [
        label
        for label, (got, want, should_differ) in cases.items()
        if (first_difference(got, want) is not None) != should_differ
    ]
    with tempfile.TemporaryDirectory() as scratch:
        manifest = pathlib.Path(scratch) / "MANIFEST.txt"
        manifest.write_text("# a comment\n\nx.json | stdout | a b | c\n", encoding="utf-8")
        if read_manifest(manifest) != [("x.json", "stdout", ["a b", "c"])]:
            failures.append("a manifest line with a spaced argument")
        manifest.write_text("x.json | pipe | a\n", encoding="utf-8")
        try:
            read_manifest(manifest)
            failures.append("a manifest line with an unknown target")
        except SystemExit:
            pass
    if failures:
        print(f"json_snapshot_check selftest: FAILED on {failures}", file=sys.stderr)
        return 1
    print("json_snapshot_check selftest: ok (every difference is found; an equal report passes)")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true", help="run the self-test only")
    parser.add_argument("--write", action="store_true", help="rewrite every snapshot")
    parser.add_argument(
        "--binary", type=pathlib.Path, default=EXAMPLE_BINARY, help="the binary to run"
    )
    args = parser.parse_args()
    if args.selftest:
        sys.exit(selftest())
    sys.exit(write_snapshots(args.binary) if args.write else run_check(args.binary))
