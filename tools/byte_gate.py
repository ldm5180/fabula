"""The automated byte gate.

Each manifest entry pairs a ``.feature`` file with a golden console
capture from the pinned oracle (``cwt-cucumber``). This script runs
the RELEASE example binary (``example/bin/release/box_main``) over
every source file in the manifest and ``cmp``s its plain console
stdout against the matching golden byte for byte -- the same check
that, run by hand at a narrower capacity, once let a 64-item box
silently truncate ``6_tables.feature``'s 100-item row until a wider
probe caught it. Two manifests ship: the corpus set
(``tests/data/golden/manifest.txt``, the default) and the example
suite (``tests/data/golden/example_manifest.txt``); ``make gate``
runs both.

Console mode only. ``--report-json`` is never gated here: `match.
location` has no oracle counterpart at all (a C++ source position
fabula cannot reproduce), so a JSON capture could never be
byte-identical by construction, gate or no gate.

Each manifest's own header says which inputs it leaves out and why,
and which goldens come from the patched oracle build
(``tools/recapture_goldens.py`` re-runs the oracle over both).

Every comparison runs the binary with the manifest's own repo-root-
relative path string and `cwd` set to the repo root, never an absolute
path: fabula's console output echoes back exactly the path string it
was given, so the golden captures stay byte-identical regardless of
where the repo is checked out.

Run from the repo root, after `make example` (or `make gate`, which
depends on it)::

    python3 tools/byte_gate.py
    python3 tools/byte_gate.py tests/data/golden/example_manifest.txt
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


def run_gate(manifest: pathlib.Path) -> int:
    if not EXAMPLE_BINARY.exists():
        print(
            f"byte_gate: {EXAMPLE_BINARY} does not exist -- run "
            "`make example` first",
            file=sys.stderr,
        )
        return 1

    entries = read_manifest(manifest)
    failures: list[str] = []
    for source, golden in entries:
        golden_path = REPO_ROOT / golden
        # `source` is passed to the binary exactly as the manifest spells
        # it (repo-root relative) with `cwd=REPO_ROOT`, never resolved to
        # an absolute path first: fabula's Location text echoes whatever
        # string it was given, so an absolute argument would bake this
        # machine's own path into the comparison and never match a
        # golden captured on a different host or CI runner.
        result = subprocess.run(
            [str(EXAMPLE_BINARY), source],
            capture_output=True,
            check=False,
            cwd=REPO_ROOT,
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
    # An optional manifest path lets `make gate` reuse this same
    # script against the second manifest without duplicating the
    # comparison logic. A relative argument resolves against the
    # repo root, like the entries inside it.
    manifest_arg = (
        REPO_ROOT / sys.argv[1] if len(sys.argv) > 1 else MANIFEST
    )
    sys.exit(run_gate(manifest_arg))
