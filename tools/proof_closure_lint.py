"""The proof-closure lint.

`gnatprove` silently skips a unit nothing in the analyzed project graph
reaches -- a `with` on its own is not enough, since a withed generic
without a concrete proof instance is never analyzed.  `make prove`
exiting 0 cannot see that: gnatprove reports on what it looked at, not
on what it should have.

A `.spark` file alone proves nothing either: gnatprove writes one for
every unit in the project, including an uninstantiated generic
(`stop_reason` GENERIC_UNIT, no entities) and a `SPARK_Mode => Off`
unit (no entities).  So this lint reads the ENTITIES inside each
`.spark` file.  A unit counts as analyzed when at least one entity
whose `sloc` chain starts in that unit's source file has SPARK status
"all", and no such entity has any other status.  An entity analyzed
through a generic instance carries the generic's file in its `sloc`,
so an instantiated generic counts for the generic unit itself.

Every core unit (every ``*.ads`` under a ``CORE_DIRS`` directory) must
be analyzed or be named in ``tools/proof-waivers``.  Three failures:

1. UNWAIVED  -- a core unit gnatprove did not (fully) analyze, with no
   waiver.
2. STALE     -- a waiver names a unit gnatprove HAS since analyzed; the
   exemption is no longer needed.
3. UNKNOWN   -- a waiver names something that is not a core unit at
   all (a typo, or a unit since renamed); it excuses nothing and would
   silently keep excusing nothing forever.

So a waiver can only ever shrink, matching ``tools/shape-waivers``.
Waivers use the file-stem spelling (``fabula-args``, not
``Fabula.Args``); dots are normalized to hyphens on read.

Run it from the repo root with no venv (stdlib only), after `gnatprove`
has run::

    python3 tools/proof_closure_lint.py
    python3 tools/proof_closure_lint.py --selftest
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

#  Directories that hold core (proof-covered) units.  Later phases add
#  more (e.g. a scanner or parser package tree) by appending here.
CORE_DIRS: list[str] = ["src"]


def unit_of(path: pathlib.Path) -> str:
    """The unit id a source file names, lower-cased.

    A file name is the dotted unit with `-` for `.` -- Ada's default
    naming rule -- so the stem alone identifies the unit.
    """
    return path.stem.lower()


def collect_core_units(root: pathlib.Path, core_dirs: list[str]) -> set[str]:
    units: set[str] = set()
    for rel in core_dirs:
        base = root / rel
        if base.is_dir():
            units.update(unit_of(p) for p in base.glob("*.ads"))
    return units


def collect_analyzed_units(gnatprove_obj: pathlib.Path) -> set[str]:
    """Units with at least one fully-analyzed entity and none partial.

    Entities are attributed to the unit their first `sloc` names, so an
    instance's entities count for the generic they instantiate.
    """
    if not gnatprove_obj.is_dir():
        return set()
    full: set[str] = set()
    partial: set[str] = set()
    for spark_file in gnatprove_obj.rglob("*.spark"):
        try:
            data = json.loads(spark_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        entities = data.get("entities", {})
        statuses = data.get("spark", {})
        for key, entity in entities.items():
            sloc = entity.get("sloc") or []
            source = sloc[0].get("file") if sloc else None
            if not source:
                continue
            unit = unit_of(pathlib.Path(source))
            if statuses.get(key) == "all":
                full.add(unit)
            else:
                partial.add(unit)
    return full - partial


def read_waivers(path: pathlib.Path) -> dict[str, str]:
    """Waived unit -> reason.  Blank and `#`-comment lines are skipped."""
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        unit, _, reason = line.partition(" ")
        out[unit.strip().lower().replace(".", "-")] = reason.strip()
    return out


def check(core: set[str], analyzed: set[str], waived: dict[str, str]) -> list[str]:
    """Every failure line for this state, empty when the closure holds."""
    problems: list[str] = []
    unwaived = sorted(u for u in core - analyzed if u not in waived)
    for unit in unwaived:
        problems.append(f"UNWAIVED  {unit}: not fully analyzed by gnatprove, no waiver")
    stale = sorted(u for u in waived if u in analyzed)
    for unit in stale:
        problems.append(f"STALE     {unit}: waived, but gnatprove analyzed it")
    unknown = sorted(u for u in waived if u not in core)
    for unit in unknown:
        problems.append(f"UNKNOWN   {unit}: waived, but it names no core unit")
    return problems


def _spark_json(entries: list[tuple[str, str, str]], stop: str = "STOP_REASON_NONE") -> str:
    """A realistic `.spark` payload: (source file, entity name, status) rows."""
    entities = {}
    statuses = {}
    for index, (source, name, status) in enumerate(entries, start=1):
        key = f" {index}"
        entities[key] = {"name": name, "sloc": [{"file": source, "line": 1, "column": 1}]}
        statuses[key] = status
    return json.dumps(
        {"entities": entities, "spark": statuses, "stop_reason": stop}
    )


def selftest() -> int:
    """Prove the failure modes fire, on fixtures shaped like real output."""
    import tempfile

    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        src = root / "src"
        src.mkdir()
        gnatprove_obj = root / "proof" / "obj" / "gnatprove"
        gnatprove_obj.mkdir(parents=True)

        for stem in ("a", "b", "c", "d", "gen"):
            (src / f"{stem}.ads").write_text(f"package {stem} is end;\n")

        #  a: fully analyzed.
        (gnatprove_obj / "a.spark").write_text(_spark_json([("a.ads", "A", "all")]))
        #  b: uninstantiated generic -- no entities, generic stop reason.
        (gnatprove_obj / "b.spark").write_text(
            _spark_json([], stop="STOP_REASON_GENERIC_UNIT")
        )
        #  c: SPARK_Mode => Off -- no entities at all.
        (gnatprove_obj / "c.spark").write_text(_spark_json([]))
        #  d: a unit whose one entity is NOT in SPARK.
        (gnatprove_obj / "d.spark").write_text(_spark_json([("d.ads", "D", "no")]))
        #  gen: analyzed only THROUGH an instance in another unit's file.
        (gnatprove_obj / "inst.spark").write_text(
            _spark_json([("inst.ads", "Inst", "all"), ("gen.ads", "Inst.Gen.Op", "all")])
        )

        waivers = root / "proof-waivers"
        #  c is excused (Off), gen's waiver is stale (the instance
        #  analyzes it), ghost names nothing.
        waivers.write_text(
            "c off by design in this fixture\n"
            "gen the instance analyzes it -- stale on purpose\n"
            "ghost stale on purpose\n"
        )

        core = collect_core_units(root, CORE_DIRS)
        analyzed = collect_analyzed_units(gnatprove_obj)
        waived = read_waivers(waivers)
        problems = check(core, analyzed, waived)
        kinds = {p.split()[0] for p in problems}

        if "gen" not in analyzed:
            failures.append("gen must count as analyzed through its instance")
        if not any(p.startswith("UNWAIVED  b:") for p in problems):
            failures.append(f"expected UNWAIVED for the generic b, got: {problems}")
        if not any(p.startswith("UNWAIVED  d:") for p in problems):
            failures.append(f"expected UNWAIVED for the no-mode d, got: {problems}")
        if any(" c:" in p for p in problems):
            failures.append(f"c is waived (Off) and must not be reported: {problems}")
        if not any(p.startswith("STALE     gen:") for p in problems):
            failures.append(f"expected STALE for gen, got: {problems}")
        if "UNKNOWN" not in kinds or not any("ghost" in p for p in problems):
            failures.append(f"expected UNKNOWN for ghost, got: {problems}")
        if "a" not in analyzed:
            failures.append("a is fully analyzed and must count")

        #  Dotted waiver spelling normalizes to the file stem.
        waivers.write_text("Fabula.Args mixed unit\n")
        dotted = read_waivers(waivers)
        if "fabula-args" not in dotted:
            failures.append("dotted waiver spelling must normalize to hyphens")

    if failures:
        print("FAIL: proof_closure_lint selftest")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("proof_closure_lint selftest: ok (all failure modes fire on realistic fixtures)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", type=pathlib.Path)
    parser.add_argument(
        "--waivers", type=pathlib.Path, default=pathlib.Path("tools/proof-waivers")
    )
    parser.add_argument(
        "--gnatprove-obj",
        type=pathlib.Path,
        default=pathlib.Path("proof/obj/gnatprove"),
    )
    parser.add_argument(
        "--selftest", action="store_true", help="prove the failure modes fire"
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    root = args.root.resolve()
    core = collect_core_units(root, CORE_DIRS)
    analyzed = collect_analyzed_units(root / args.gnatprove_obj)
    waived = read_waivers(root / args.waivers)
    problems = check(core, analyzed, waived)

    if problems:
        print("FAIL: proof closure lint")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"proof-closure: ok ({len(core)} core units, all analyzed or waived)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
