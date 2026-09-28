"""The console output snapshot check.

Runs the RELEASE example binary (``example/bin/release/box_main``) once
per line of ``tests/data/console_snapshots/MANIFEST.txt`` and compares
its stdout and its exit status with the snapshot the line names under
``tests/data/console_snapshots/expected/``: ``<name>.out``, byte for
byte. fabula writes all console output to stdout (``Console.Put`` and
``Console.Put_Line`` both write to ``Ada.Text_IO.Current_Output``, even
for an error-styled line), so a run whose stderr is not empty fails
the check outright, with no snapshot file to compare it against.

These are regression snapshots of fabula's own output, NOT oracle
output: the byte gate (``tools/byte_gate.py``) runs the same binary
with no flags at all. These snapshots cover the console reporter under
``-v``, ``-q``, ``-d``, ``-t``, ``-n`` and ``-c``, a file:line
selection, and the startup refusals: verbose and quiet text, dry-run,
a tag or name filter that drops a scenario, continue-on-failure, and
the unknown-flag, missing-value and bad-tag-expression refusals.

Run from the repo root, after ``make example``::

    python3 tools/console_snapshot_check.py
    python3 tools/console_snapshot_check.py --selftest
    python3 tools/console_snapshot_check.py --write

``--write`` rewrites every snapshot from the current binary.  Use it
only for an intended change of the console output, and read the diff
of every snapshot before committing it.  It exits 1, after writing
every snapshot, when any run's exit status no longer matches the
manifest's.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
EXAMPLE_BINARY = REPO_ROOT / "example" / "bin" / "release" / "box_main"
SNAPSHOTS = REPO_ROOT / "tests" / "data" / "console_snapshots"
MANIFEST = SNAPSHOTS / "MANIFEST.txt"
EXPECTED = SNAPSHOTS / "expected"

STDERR_NOT_EMPTY = "stderr is not empty: fabula writes all console output to stdout"


def read_manifest(path: pathlib.Path) -> list[tuple[str, int, list[str]]]:
    """(snapshot name, exit status, arguments) for every run the manifest lists."""
    runs = []
    seen_names: set[str] = set()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split("|")]
        if len(fields) < 2 or any(field == "" for field in fields):
            raise SystemExit(f"console_snapshot_check: {path}:{number}: bad line: {raw}")
        try:
            exit_status = int(fields[1])
        except ValueError:
            raise SystemExit(
                f"console_snapshot_check: {path}:{number}: bad exit status: {raw}"
            ) from None
        name = fields[0]
        if name in seen_names:
            raise SystemExit(
                f"console_snapshot_check: {path}:{number}: duplicate run name: {name}"
            )
        seen_names.add(name)
        runs.append((name, exit_status, fields[2:]))
    return runs


def run_of(binary: pathlib.Path, arguments: list[str]) -> tuple[bytes, bytes, int]:
    """One run's stdout, stderr and exit status."""
    done = subprocess.run(
        [str(binary), *arguments],
        capture_output=True,
        check=False,
        cwd=REPO_ROOT,
    )
    return done.stdout, done.stderr, done.returncode


def first_difference(got: bytes, want: bytes) -> str | None:
    """None when the two are equal; else where they first differ."""
    if got == want:
        return None
    for offset, (a, b) in enumerate(zip(got, want)):
        if a != b:
            return f"byte {offset}: got {bytes([a])!r}, snapshot has {bytes([b])!r}"
    return f"length {len(got)}, snapshot length {len(want)}"


def run_problems(
    stdout: bytes,
    stderr: bytes,
    status: int,
    want_stdout: bytes,
    want_status: int,
) -> list[str]:
    """Every way one run differs from its snapshot, empty when none."""
    problems = []
    out_problem = first_difference(stdout, want_stdout)
    if out_problem is not None:
        problems.append(f"stdout: {out_problem}")
    if stderr:
        problems.append(STDERR_NOT_EMPTY)
    if status != want_status:
        problems.append(f"exit status: got {status}, snapshot has {want_status}")
    return problems


def run_check(binary: pathlib.Path) -> int:
    if not binary.exists():
        print(
            f"console_snapshot_check: {binary} does not exist -- run `make example` first",
            file=sys.stderr,
        )
        return 1
    runs = read_manifest(MANIFEST)
    failed = 0
    for name, exit_status, arguments in runs:
        out_snapshot = EXPECTED / f"{name}.out"
        if not out_snapshot.exists():
            print(f"console_snapshot_check: {name}: no snapshot file", file=sys.stderr)
            failed += 1
            continue
        stdout, stderr, status = run_of(binary, arguments)
        problems = run_problems(
            stdout, stderr, status, out_snapshot.read_bytes(), exit_status
        )
        if problems:
            for problem in problems:
                print(f"console_snapshot_check: {name}: {problem}", file=sys.stderr)
            failed += 1
    if failed:
        print(f"console_snapshot_check: {failed} of {len(runs)} snapshots differ", file=sys.stderr)
        return 1
    print(
        f"console_snapshot_check: {len(runs)}/{len(runs)} identical "
        "(regression snapshots of fabula's own output, not oracle output)"
    )
    return 0


def write_snapshots(binary: pathlib.Path) -> int:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    runs = read_manifest(MANIFEST)
    warned = False
    for name, exit_status, arguments in runs:
        stdout, _stderr, status = run_of(binary, arguments)
        if status != exit_status:
            warned = True
            print(
                f"console_snapshot_check: {name}: exit status changed: "
                f"manifest has {exit_status}, the binary now returns {status}",
                file=sys.stderr,
            )
        (EXPECTED / f"{name}.out").write_bytes(stdout)
    print(f"console_snapshot_check: wrote {len(runs)} snapshots; read every diff before committing")
    return 1 if warned else 0


def selftest() -> int:
    """Each difference must be found; an equal run must pass."""
    stdout = b"Scenario: Apple  a.feature:1\n[   PASSED    ] Given an empty box\n"
    status = 1
    cases = {
        "an equal run": (stdout, b"", status, False),
        "a changed byte": (stdout.replace(b"PASSED", b"FAILED"), b"", status, True),
        "a lost trailing newline": (stdout[:-1], b"", status, True),
        "a changed exit status": (stdout, b"", 0, True),
        "a non-empty stderr": (stdout, b"stray text", status, True),
    }
    failures = [
        label
        for label, (got_out, got_err, got_status, should_differ) in cases.items()
        if bool(run_problems(got_out, got_err, got_status, stdout, status))
        != should_differ
    ]
    with tempfile.TemporaryDirectory() as scratch:
        manifest = pathlib.Path(scratch) / "MANIFEST.txt"
        manifest.write_text("# a comment\n\nx | 0 | a b | c\n", encoding="utf-8")
        if read_manifest(manifest) != [("x", 0, ["a b", "c"])]:
            failures.append("a manifest line with a spaced argument")
        manifest.write_text("x | not-a-number | a\n", encoding="utf-8")
        try:
            read_manifest(manifest)
            failures.append("a manifest line with a non-integer exit status")
        except SystemExit:
            pass
        manifest.write_text("x | 0 | a |\n", encoding="utf-8")
        try:
            read_manifest(manifest)
            failures.append("a manifest line with an empty field")
        except SystemExit:
            pass
        manifest.write_text("x | 0 | a\nx | 1 | b\n", encoding="utf-8")
        try:
            read_manifest(manifest)
            failures.append("a manifest with a duplicate run name")
        except SystemExit:
            pass
    if failures:
        print(f"console_snapshot_check selftest: FAILED on {failures}", file=sys.stderr)
        return 1
    print("console_snapshot_check selftest: ok (every difference is found; an equal run passes)")
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
