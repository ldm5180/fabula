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
"all", and no such entity has any other status.

An entity analyzed through a generic PACKAGE instance carries the
generic's own file in its `sloc`, so an instantiated generic package
counts for the generic unit itself -- but a generic SUBPROGRAM
instance is a single entity whose `sloc` names only the instantiation
site, never the generic's own file, so a generic function or procedure
can never be marked analyzed this way.  A separate check covers it:
every generic subprogram a core spec declares must have at least one
`proof`-array entry, in any `.spark` file, whose `file` (or
`check_file`) names that generic's own `.adb` -- evidence its body was
analyzed through some instance, wherever that instance was written.

Every core unit (every ``*.ads`` under a ``CORE_DIRS`` directory) must
be analyzed or be named in ``tools/proof-waivers``.  Four failures:

1. UNWAIVED       -- a core unit gnatprove did not (fully) analyze,
   with no waiver.
2. STALE          -- a waiver names a unit gnatprove HAS since
   analyzed; the exemption is no longer needed.
3. UNKNOWN        -- a waiver names something that is not a core unit
   at all (a typo, or a unit since renamed); it excuses nothing and
   would silently keep excusing nothing forever.
4. UNINSTANTIATED -- a core spec declares a generic function or
   procedure with no proof-array evidence anywhere that its body was
   ever analyzed through an instance.

So a waiver can only ever shrink, matching ``tools/shape-waivers``.
Waivers use the file-stem spelling (``fabula-args``, not
``Fabula.Args``); dots are normalized to hyphens on read; the same
waiver dict excuses UNINSTANTIATED too.

Run it from the repo root with no venv (stdlib only), after `gnatprove`
has run::

    python3 tools/proof_closure_lint.py
    python3 tools/proof_closure_lint.py --selftest
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

#  Directories that hold core (proof-covered) units, each read without
#  recursion.  src/shell -- the shell, outside the proof by design --
#  sits under src and is therefore NOT core; the selftest pins that.
#  A later core tree is added by appending its directory here.
CORE_DIRS: list[str] = ["src"]

#  A generic block's own formal-subprogram parameters ("with function"
#  / "with procedure") start with "with", so they never match the bare
#  function/procedure pattern below; a "package" line means the block
#  is a generic PACKAGE, out of scope here (collect_analyzed_units
#  already covers it); the first bare function/procedure line is the
#  generic's own terminating declaration.
_GENERIC_LINE = re.compile(r"^\s*generic\b", re.I)
_GENERIC_PACKAGE = re.compile(r"^\s*package\b", re.I)
_TERMINATING_SUBPROGRAM = re.compile(
    r"^\s*(?:function|procedure)\s+([A-Za-z][A-Za-z0-9_]*)", re.I
)


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


def collect_generic_subprograms(
    root: pathlib.Path, core_dirs: list[str]
) -> list[tuple[str, str]]:
    """Every generic function/procedure a core spec declares, as (unit, name).

    A simple forward scan from each `generic` line: a `package` line
    means the generic is a package (out of scope here); the first bare
    function/procedure line is its terminating declaration.  Anything
    else -- a formal subprogram, a formal type, a blank or comment
    line -- is skipped.
    """
    found: list[tuple[str, str]] = []
    for rel in core_dirs:
        base = root / rel
        if not base.is_dir():
            continue
        for path in sorted(base.glob("*.ads")):
            lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
            unit = unit_of(path)
            i = 0
            while i < len(lines):
                if _GENERIC_LINE.match(lines[i]):
                    i += 1
                    while i < len(lines):
                        line = lines[i]
                        if _GENERIC_PACKAGE.match(line):
                            break
                        match = _TERMINATING_SUBPROGRAM.match(line)
                        if match:
                            found.append((unit, match.group(1)))
                            break
                        i += 1
                i += 1
    return found


def collect_analyzed_units(gnatprove_obj: pathlib.Path) -> set[str]:
    """Units with at least one fully-analyzed entity and none partial.

    Entities are attributed to the unit their first `sloc` names, which
    counts a generic PACKAGE instance for the generic it instantiates
    (its inner entities keep the generic's own file) -- a generic
    SUBPROGRAM instance does not work this way; see
    `collect_generic_evidence`.  A caller's own `.spark` file lists
    every entity it CALLS too, with no entry in `spark` at all -- that
    is a cross-reference, not an analysis outcome, and is skipped:
    otherwise calling a unit from a package that has its own
    subprogram body (so gnatprove records real cross-references, not
    just the bare Global contracts a body-less spec produces) would
    mark that unit permanently partial everywhere it is ever called
    from.
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
            if key not in statuses:
                continue
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


def collect_generic_evidence(gnatprove_obj: pathlib.Path) -> set[str]:
    """Units whose `.adb` a DIFFERENT unit's `proof`-array entry names.

    A generic subprogram's instance carries only the instantiation
    site in its entity `sloc` (see the module docstring), so this reads
    the `proof` array instead: each verification condition there also
    carries `file` and `check_file`.  A generic's OWN `.spark` file is
    already full of proof-array entries naming its own `.adb`, from its
    file's ordinary, non-generic subprograms -- that is true whether or
    not the generic itself was ever instantiated, so it proves nothing.
    Only an INSTANTIATING unit's `.spark` file gaining an entry that
    names the generic's `.adb` is real evidence: that shape appears
    only once gnatprove has analyzed the generic body through an
    instance, and disappears the moment the instantiation is dropped.
    """
    evidence: set[str] = set()
    if not gnatprove_obj.is_dir():
        return evidence
    for spark_file in gnatprove_obj.rglob("*.spark"):
        try:
            data = json.loads(spark_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        owner = unit_of(spark_file)
        for entry in data.get("proof", []):
            for key in ("file", "check_file"):
                source = entry.get(key)
                if not source or pathlib.Path(source).suffix.lower() != ".adb":
                    continue
                named_unit = unit_of(pathlib.Path(source))
                if named_unit != owner:
                    evidence.add(named_unit)
    return evidence


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


def check(
    core: set[str],
    analyzed: set[str],
    waived: dict[str, str],
    generics: list[tuple[str, str]],
    evidence: set[str],
) -> list[str]:
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
    uninstantiated = sorted(
        {(unit, name) for unit, name in generics if unit not in evidence and unit not in waived}
    )
    for unit, name in uninstantiated:
        problems.append(
            f"UNINSTANTIATED {unit}: generic {name} has no proof-array"
            " evidence its body was ever analyzed through an instance"
        )
    return problems


def _spark_json(
    entries: list[tuple[str, str, str]],
    stop: str = "STOP_REASON_NONE",
    proof: list[dict] | None = None,
) -> str:
    """A realistic `.spark` payload: (source file, entity name, status) rows."""
    entities = {}
    statuses = {}
    for index, (source, name, status) in enumerate(entries, start=1):
        key = f" {index}"
        entities[key] = {"name": name, "sloc": [{"file": source, "line": 1, "column": 1}]}
        statuses[key] = status
    return json.dumps(
        {
            "entities": entities,
            "spark": statuses,
            "stop_reason": stop,
            "proof": proof or [],
        }
    )


#  gsub: a realistic generic FUNCTION nested in an ordinary package,
#  the shape `collect_generic_subprograms` must find by a plain scan.
_GSUB_SOURCE = """\
package Gsub is

   generic
      with function Has_Tag (Name : String) return Boolean;
   function Eval (E : Integer) return Boolean;

end Gsub;
"""


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

        for stem in ("a", "b", "c", "d", "gen", "e"):
            (src / f"{stem}.ads").write_text(f"package {stem} is end;\n")
        (src / "gsub.ads").write_text(_GSUB_SOURCE)
        #  A shell unit: under src/shell, so never core.
        (src / "shell").mkdir()
        (src / "shell" / "shelly.ads").write_text("package shelly is end;\n")

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
        #  e: fully analyzed in its own file, and also NAMED (with no
        #  status at all) in a caller's file -- the shape gnatprove
        #  gives a cross-package call once the caller has a body of
        #  its own.  That reference must not demote e to partial.
        (gnatprove_obj / "e.spark").write_text(_spark_json([("e.ads", "E", "all")]))
        (gnatprove_obj / "caller.spark").write_text(
            json.dumps(
                {
                    "entities": {
                        " 1": {
                            "name": "E",
                            "sloc": [{"file": "e.ads", "line": 1, "column": 1}],
                        }
                    },
                    "spark": {},
                    "stop_reason": "STOP_REASON_NONE",
                }
            )
        )
        #  gsub: fully analyzed in its own right (so only the GENERIC
        #  check is under test here).  Its own `.spark` file's
        #  proof-array entries (from its ordinary code) must NOT count
        #  as evidence, so this one carries none; the evidence instead
        #  lives in gsub_caller.spark below, as it would for a real
        #  instantiating unit.
        (gnatprove_obj / "gsub.spark").write_text(
            _spark_json([("gsub.ads", "Gsub", "all")])
        )
        (gnatprove_obj / "gsub_caller.spark").write_text(
            _spark_json(
                [("gsub_caller.ads", "Gsub_Caller", "all")],
                proof=[{"file": "gsub.adb", "check_file": "gsub.adb"}],
            )
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
        generics = collect_generic_subprograms(root, CORE_DIRS)
        evidence = collect_generic_evidence(gnatprove_obj)
        problems = check(core, analyzed, waived, generics, evidence)
        kinds = {p.split()[0] for p in problems}

        if "shelly" in core:
            failures.append("a unit under src/shell must not count as core")
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
        if "e" not in analyzed:
            failures.append(
                "e is fully analyzed in its own file; a no-status reference"
                " to it from another file must not demote it to partial"
            )
        if ("gsub", "Eval") not in generics:
            failures.append(
                f"expected to detect generic function Eval in gsub, got: {generics}"
            )
        if any(p.startswith("UNINSTANTIATED gsub") for p in problems):
            failures.append(
                f"gsub has a matching proof-array entry and must not fire"
                f" UNINSTANTIATED: {problems}"
            )

        #  Drop gsub's evidence: its generic Eval must now fire
        #  UNINSTANTIATED, proving the counterexample the check exists
        #  for -- a generic subprogram instance gnatprove analyzed
        #  elsewhere leaves no trace `collect_analyzed_units` can see.
        (gnatprove_obj / "gsub_caller.spark").unlink()
        analyzed = collect_analyzed_units(gnatprove_obj)
        evidence = collect_generic_evidence(gnatprove_obj)
        problems = check(core, analyzed, waived, generics, evidence)
        if not any(p.startswith("UNINSTANTIATED gsub") for p in problems):
            failures.append(
                "expected UNINSTANTIATED for gsub once its evidence is"
                f" removed, got: {problems}"
            )

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
    generics = collect_generic_subprograms(root, CORE_DIRS)
    evidence = collect_generic_evidence(root / args.gnatprove_obj)
    problems = check(core, analyzed, waived, generics, evidence)

    if problems:
        print("FAIL: proof closure lint")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"proof-closure: ok ({len(core)} core units, all analyzed or waived)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
