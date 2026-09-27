"""Re-run the reference interpreter over every golden and compare.

Every golden console capture under ``tests/data/golden/`` claims to be
the pinned reference interpreter's own output (``cwt-cucumber``).  This
script turns that claim into a check any reviewer can run: it feeds the
oracle every source in both byte-gate manifests, exactly as
``tools/byte_gate.py`` feeds fabula (the manifest's repo-root-relative
path, ``cwd`` at the repo root, no flags, stdout then stderr joined),
and compares the result with the committed golden byte for byte.

Two oracle binaries take part:

* the pinned build, unmodified, writes every golden but two;
* the patched build writes the two ``11_manual_fails`` goldens.  Their
  bytes carry the text of the example's own fail hooks, and fabula's
  example words that text in Ada terms.  The patch
  (``tests/data/golden/oracle_examples.patch``) changes only the
  oracle's ``examples/`` step code, never its engine under ``src/``, so
  the engine behavior stays the oracle's.  ``--check`` refuses a patch
  that touches any other path.

Neither binary path lives in the repository.  Pass them as arguments or
set ``FABULA_ORACLE`` and ``FABULA_ORACLE_PATCHED``.  The pinned oracle
is cwt-cucumber at commit 662b4e482a9d53b17cce6b94092e1d0ca408bc27,
built Release with its target ``example``::

    cmake -S <oracle> -B <oracle>/build -DCMAKE_BUILD_TYPE=Release
    cmake --build <oracle>/build --target example

The patched oracle is the same commit with the patch applied under
``examples/`` and built the same way.

Run it from the repo root (stdlib only)::

    python3 tools/recapture_goldens.py --check
    python3 tools/recapture_goldens.py --write
    python3 tools/recapture_goldens.py --selftest

``--write`` rewrites every golden from the oracle.  It is the only way
a golden changes: a golden edited by hand is not independent evidence.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys
import tempfile
from collections.abc import Callable

from byte_gate import read_manifest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
GOLDEN_DIR = REPO_ROOT / "tests" / "data" / "golden"
MANIFESTS: tuple[pathlib.Path, ...] = (
    GOLDEN_DIR / "manifest.txt",
    GOLDEN_DIR / "example_manifest.txt",
)
PATCH = GOLDEN_DIR / "oracle_examples.patch"

PINNED = "pinned"
PATCHED = "patched"

#  The goldens whose bytes come from the patched oracle.  Both run the
#  @will_fail_before and @will_fail_after hooks, whose message text is
#  the only thing the patch changes.
PATCHED_GOLDENS: frozenset[str] = frozenset(
    {
        "tests/data/golden/11_manual_fails.console.txt",
        "tests/data/golden/example/11_manual_fails.console.txt",
    }
)

#  The one directory of the oracle the patch may touch.
PATCH_SCOPE = "examples/"

_PATCH_PATH = re.compile(r"^(?:diff --git a/(\S+) b/(\S+)|--- a/(\S+)|\+\+\+ b/(\S+))$")

Capture = Callable[[str, str], bytes]


def entries(manifests: tuple[pathlib.Path, ...]) -> list[tuple[str, str, str]]:
    """Every (source, golden, oracle) triple across the manifests."""
    found: list[tuple[str, str, str]] = []
    for manifest in manifests:
        for source, golden in read_manifest(manifest):
            oracle = PATCHED if golden in PATCHED_GOLDENS else PINNED
            found.append((source, golden, oracle))
    return found


def stale_patched(found: list[tuple[str, str, str]]) -> list[str]:
    """PATCHED_GOLDENS entries that no manifest lists any more."""
    listed = {golden for _, golden, _ in found}
    return sorted(PATCHED_GOLDENS - listed)


def patch_paths_outside_scope(patch_text: str) -> list[str]:
    """Every path the patch names that is not under ``examples/``."""
    outside: list[str] = []
    for line in patch_text.splitlines():
        match = _PATCH_PATH.match(line)
        if not match:
            continue
        for path in match.groups():
            if path and not path.startswith(PATCH_SCOPE) and path not in outside:
                outside.append(path)
    return outside


def oracle_capture(binaries: dict[str, pathlib.Path]) -> Capture:
    """A capture function that runs the named oracle binary."""

    def capture(oracle: str, source: str) -> bytes:
        #  The source goes in exactly as the manifest spells it, with
        #  cwd at the repo root: the output echoes that path string, so
        #  an absolute path would bake this machine into the capture.
        result = subprocess.run(
            [str(binaries[oracle]), source],
            capture_output=True,
            check=False,
            cwd=REPO_ROOT,
        )
        return result.stdout + result.stderr

    return capture


def check(
    found: list[tuple[str, str, str]], capture: Capture, golden_root: pathlib.Path
) -> int:
    """Compare every capture with its golden.  Returns the difference count."""
    differences = 0
    for source, golden, oracle in found:
        actual = capture(oracle, source)
        golden_path = golden_root / golden
        expected = golden_path.read_bytes() if golden_path.is_file() else None
        if actual == expected:
            print(f"OK   {golden}  ({oracle} oracle)")
        else:
            differences += 1
            reason = "missing" if expected is None else "differs"
            print(f"DIFF {golden}  ({oracle} oracle, golden {reason})")
    return differences


def write(
    found: list[tuple[str, str, str]], capture: Capture, golden_root: pathlib.Path
) -> None:
    for source, golden, oracle in found:
        golden_path = golden_root / golden
        actual = capture(oracle, source)
        old = golden_path.read_bytes() if golden_path.is_file() else None
        golden_path.write_bytes(actual)
        state = "unchanged" if old == actual else "rewritten"
        print(f"{state:<10} {golden}  ({oracle} oracle)")


def resolve_binaries(args: argparse.Namespace) -> dict[str, pathlib.Path] | str:
    """Both oracle paths, or a message naming the one that is missing."""
    given = {
        PINNED: (args.oracle or os.environ.get("FABULA_ORACLE"), "--oracle", "FABULA_ORACLE"),
        PATCHED: (
            args.oracle_patched or os.environ.get("FABULA_ORACLE_PATCHED"),
            "--oracle-patched",
            "FABULA_ORACLE_PATCHED",
        ),
    }
    binaries: dict[str, pathlib.Path] = {}
    for oracle, (value, flag, variable) in given.items():
        if not value:
            return f"no {oracle} oracle: pass {flag} or set {variable}"
        path = pathlib.Path(value).expanduser().resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            return f"the {oracle} oracle {path} is not an executable file"
        binaries[oracle] = path
    return binaries


def preflight(found: list[tuple[str, str, str]]) -> list[str]:
    """Problems that make a capture run meaningless, found before it."""
    problems: list[str] = []
    for golden in stale_patched(found):
        problems.append(f"{golden} is marked patched but no manifest lists it")
    if not PATCH.is_file():
        problems.append(f"{PATCH.relative_to(REPO_ROOT)} does not exist")
    else:
        for path in patch_paths_outside_scope(PATCH.read_text(encoding="utf-8")):
            problems.append(f"the oracle patch touches {path}, outside {PATCH_SCOPE}")
    return problems


def selftest() -> int:
    """Show that one changed byte in one golden fails the check."""
    failures: list[str] = []
    found = entries(MANIFESTS)
    if not found:
        failures.append("the manifests list no captures")
    if stale_patched(found):
        failures.append(f"stale patched goldens: {stale_patched(found)}")

    source, golden, oracle = found[0]
    original = (REPO_ROOT / golden).read_bytes()

    #  The committed golden stands in for the oracle, so the selftest
    #  needs no oracle binary: it exercises the comparison, not the
    #  capture.
    def stand_in(_oracle: str, _source: str) -> bytes:
        return original

    one = [(source, golden, oracle)]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        copy = root / golden
        copy.parent.mkdir(parents=True)
        copy.write_bytes(original)
        if check(one, stand_in, root) != 0:
            failures.append("an unchanged golden copy did not pass")

        changed = bytearray(original)
        changed[len(changed) // 2] ^= 0x01
        copy.write_bytes(bytes(changed))
        if check(one, stand_in, root) != 1:
            failures.append("a golden with one changed byte did not fail")

    inside = "diff --git a/examples/hooks.cpp b/examples/hooks.cpp\n"
    outside = "diff --git a/src/options.hpp b/src/options.hpp\n"
    if patch_paths_outside_scope(inside):
        failures.append("a patch under examples/ was refused")
    if patch_paths_outside_scope(outside) != ["src/options.hpp"]:
        failures.append("a patch under src/ was not refused")

    if failures:
        print("FAIL: recapture_goldens selftest")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("recapture_goldens selftest: ok (one changed byte fails the check)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="compare every golden")
    mode.add_argument("--write", action="store_true", help="rewrite every golden")
    mode.add_argument(
        "--selftest", action="store_true", help="show one changed byte fails"
    )
    parser.add_argument("--oracle", help="the pinned oracle binary")
    parser.add_argument("--oracle-patched", help="the patched oracle binary")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    found = entries(MANIFESTS)
    problems = preflight(found)
    binaries = resolve_binaries(args)
    if isinstance(binaries, str):
        problems.append(binaries)
    if problems:
        for problem in problems:
            print(f"recapture_goldens: {problem}", file=sys.stderr)
        return 2
    assert not isinstance(binaries, str)

    capture = oracle_capture(binaries)
    if args.write:
        write(found, capture, REPO_ROOT)
        return 0

    differences = check(found, capture, REPO_ROOT)
    print()
    if differences:
        print(f"recapture_goldens: {differences}/{len(found)} captures DIFFER")
        return 1
    print(f"recapture_goldens: {len(found)}/{len(found)} captures match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
