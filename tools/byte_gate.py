"""The automated byte gate (state.md entry 30, P10 review item 9).

Every entry in ``tests/data/golden/manifest.txt`` pairs a ``.feature``
file with a golden console capture from the pinned oracle (``cwt-
cucumber``, the SHA `docs/` and `state.md` name). This script runs the
RELEASE example binary (``example/bin/release/box_main``) over every
source file in the manifest and ``cmp``s its plain console stdout
against the matching golden byte for byte -- the same check the P10
review round ran by hand to find the CRITICAL a wider probe caught
(state.md entry 30, item 1: a 64-item box silently truncating
`6_tables.feature`'s 100-item row).

Console mode only. ``--report-json`` is never gated here: `match.
location` has no oracle counterpart at all (a C++ source position
fabula cannot reproduce, ledgered where it is computed), so a JSON
capture could never be byte-identical by construction, gate or no gate.

Feature 7 ships CRLF line endings; the oracle's own scanner double-
counts each CRLF inside a doc string (a ledgered oracle bug), so its
line numbers over the ORIGINAL file would never match fabula's correct
ones.  The manifest points feature 7's entry at an LF-normalized copy
of the source, `tests/data/golden/7_doc_strings_lf.feature`, generated
once from the pinned corpus original (`tr -d '\\r'`) -- the corpus
original itself stays untouched and byte-identical to the oracle's own
copy.

Run from the repo root, after `make example` (or `make gate`, which
depends on it)::

    python3 tools/byte_gate.py
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "tests" / "data" / "golden" / "manifest.txt"
EXAMPLE_BINARY = REPO_ROOT / "example" / "bin" / "release" / "box_main"


def read_manifest(path: pathlib.Path) -> list[tuple[str, str]]:
    """Parses non-comment, non-blank lines as ``<source> <golden>``."""
    entries: list[tuple[str, str]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        source, golden = line.split()
        entries.append((source, golden))
    return entries


def run_gate() -> int:
    if not EXAMPLE_BINARY.exists():
        print(
            f"byte_gate: {EXAMPLE_BINARY} does not exist -- run "
            "`make example` first",
            file=sys.stderr,
        )
        return 1

    entries = read_manifest(MANIFEST)
    failures: list[str] = []
    for source, golden in entries:
        source_path = REPO_ROOT / source
        golden_path = REPO_ROOT / golden
        result = subprocess.run(
            [str(EXAMPLE_BINARY), str(source_path)],
            capture_output=True,
            check=False,
        )
        actual = result.stdout + result.stderr
        expected = golden_path.read_bytes()
        if actual == expected:
            print(f"OK   {source}")
        else:
            print(f"FAIL {source} (vs {golden})")
            failures.append(source)

    print()
    if failures:
        print(f"byte_gate: {len(failures)}/{len(entries)} FAILED")
        for name in failures:
            print(f"  - {name}")
        return 1
    print(f"byte_gate: {len(entries)}/{len(entries)} ok")
    return 0


if __name__ == "__main__":
    sys.exit(run_gate())
