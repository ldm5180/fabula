"""The subprogram-shape lint.

A tree gets hard to follow in a small number of measurable ways:
subprogram bodies that hold hundreds of statements, bodies declared
inside other bodies, block nesting several levels deep, signatures with
more outputs than a reader can hold, and literals that carry a scale
nothing on the page names.

This module measures those shapes and holds them to
``tools/shape-waivers``.  That file is not a way to hide a violation --
it is the only way to keep the gate ON while a known one exists.  It
fails on three things:

1. a violation that is not waived (new debt);
2. a waived violation whose value has GROWN (debt getting worse);
3. a waiver for a unit that no longer violates (a stale waiver -- the
   list cannot outlive what it excuses).

So a waiver can only ever shrink, and deleting one is how a refactor
cycle gets its RED.

The measurement is deliberately simple, because every committed source
is ``gnatformat``-ed and its indentation is therefore reliable.  A
subprogram BODY is a ``procedure``/``function``/``task body`` header
whose declaration ends in ``is`` rather than ``;`` -- so a spec, a
renaming, a generic instantiation, an expression function and a
``separate`` stub are all excluded.  Its own ``begin`` and ``end Name;``
sit at the header's indentation.

Run it from the repo root with no venv (stdlib only)::

    python3 tools/shape_check.py

    python3 tools/shape_check.py --selftest
    python3 tools/shape_check.py --write-waivers
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from dataclasses import dataclass, field

#  Every rule the lint measures, with its limit.  The key is what a
#  waiver line spells in its `metric` column, so renaming one
#  invalidates the waiver file: don't.
LIMITS: dict[str, int] = {
    "stmt": 40,  # R1  statement lines in a body
    "lines": 60,  # R2  total lines of a body, declarations included
    "depth": 3,  # R3  block nesting depth
    "nested": 0,  # R4  bodies declared inside another body
    "params": 5,  # R5  parameters
    "outs": 2,  # R6  out parameters (results; an `in out` is not one)
    "bools": 0,  # R7  adjacent Boolean parameters
    "file_lines": 1000,  # R8  lines in a body file
    "literals": 0,  # R9  bare numeric literals >= 100
    "alias": 0,  # R11 event alias that is not its literal minus E_
    "foreign": 0,  # R10 a comment pointing outside this repository
    "dated": 0,  # R10 a calendar date in a comment
}

RULE_OF: dict[str, str] = {
    "stmt": "R1",
    "lines": "R2",
    "depth": "R3",
    "nested": "R4",
    "params": "R5",
    "outs": "R6",
    "bools": "R7",
    "file_lines": "R8",
    "literals": "R9",
    "alias": "R11",
    "foreign": "R10",
    "dated": "R10",
}

#  Ada is case-insensitive and gnatformat keeps one declaration per
#  line, so a line-anchored match is enough to find a header.
_HEADER = re.compile(
    r"^(?P<indent>[ ]*)(?:overriding\s+)?"
    r"(?P<kind>procedure|function|task\s+body|package\s+body|protected\s+body)"
    r"\s+(?P<name>[A-Za-z][A-Za-z0-9_.]*|\"[^\"]+\")",
    re.I,
)
_END = re.compile(r"^(?P<indent>[ ]*)end\s+(?P<name>[A-Za-z][A-Za-z0-9_.]*|\"[^\"]+\")\s*;", re.I)
_BEGIN = re.compile(r"^(?P<indent>[ ]*)begin\s*$", re.I)

#  R3 counts BLOCKS, not indentation.  gnatformat wraps a long condition
#  onto deeper-indented continuation lines, and those are not nesting --
#  measuring the column would report a two-block loop as five deep.  So
#  the depth is a running count of block openers and closers instead.
_OPENS = re.compile(r"^(if|for|while|loop|case|declare)\b", re.I)
_CLOSES = re.compile(r"^end\s*(if|loop|case)?\s*;", re.I)

#  A body is a frame a reader must hold in their head; a package body is
#  not (it is a file's table of contents).  Only these two nest.
FRAME_KINDS = frozenset({"procedure", "function", "task body"})

#  R9: a literal is bare unless its line declares it, bounds a type, or
#  reads a bound off one.  Underscores are Ada's digit separator.
_LITERAL = re.compile(r"(?<![\w.#_])(\d[\d_]*)(?![\w_#])")
_LITERAL_EXEMPT = re.compile(r"\bconstant\b|\brange\b|'Last|'First|\bpragma\b|=>\s*<>", re.I)

#  R9 attributes a literal to the declaration above it, so a waiver
#  names something a reader can open rather than a line number that
#  moves.  Object declarations are deliberately NOT names here: a waiver
#  reading `X literals 1` would say nothing about where to look.
_DECL_NAME = re.compile(
    r"^[ ]*(?:overriding\s+)?"
    r"(?:procedure|function|type|subtype|task\s+body|package\s+body)"
    r"\s+([A-Za-z][A-Za-z0-9_.]*)",
    re.I,
)

#  R10 forbids a comment from citing anything outside this repository:
#  no tracker code, no file in another project, no section of a plan.
#  Each is a pointer that rots -- a reader who follows it finds a
#  renumbered issue, a deleted file, a rewritten plan -- where the
#  REASONING it stands for does not.  If the reasoning matters, state
#  it; if it is history, git log has it, and a commit body may cite
#  freely.
#  R10 forbids an incident date in a comment for the same reason: the
#  date is history, and git log has it, where the REASONING it stands
#  for is what the reader needs.  A date inside a quoted string is a
#  format or an example -- `"2026-01-15"` -- and is not counted.
_DATED = re.compile(r"\b20\d\d-\d\d-\d\d\b")
_QUOTED = re.compile(r'"[^"]*"')

_FOREIGN = re.compile(
    r"(?:\bPR\s*#\d+"        # PR #436
    r"|\bissue\s*#\d+"       # issue #2
    r"|§\s*\w+"         # section 8, of some other document
    r"|\b[\w/]+\.(?:go|cpp|hpp):\d+"    # some_file.cpp:41
    r"|\b[\w/]+\.(?:go|cpp|hpp)\b)",    # some_file.cpp
    re.I,
)

#  R11: the event wrapper constants an engine body declares so its
#  transition table can use the operator DSL.
_ALIAS = re.compile(
    r"^[ ]*([A-Za-z][A-Za-z0-9_]*)\s*:\s*constant\s+\w+\s*:=\s*\(\s*Kind\s*=>\s*E_([A-Za-z0-9_]+)\s*\)",
    re.I,
)


@dataclass(frozen=True)
class Finding:
    """One measured shape that exceeds its limit."""

    path: str
    unit: str
    metric: str
    value: int

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.path, self.unit.lower(), self.metric)

    def line(self) -> str:
        return f"{self.path:<58} {self.unit:<28} {self.metric:<10} {self.value}"


@dataclass
class Body:
    """One subprogram or task body, as the lint sees it."""

    name: str
    kind: str
    indent: int
    header: int  # 1-based line of the header
    begin: int | None = None
    end: int | None = None
    header_text: str = ""
    inner: list["Body"] = field(default_factory=list)


def strip_code(line: str) -> str:
    """The line without its comment, so a `--` note cannot be measured.

    A `--` inside a string literal starts no comment, and several
    messages contain one.  Cutting at the first `--` would drop the
    rest of such a line -- its closing parenthesis included -- and the
    paren depth this module tracks would never return to zero again,
    silently exempting every literal below it.  So the scan walks the
    line and only cuts outside a string, taking Ada's doubled `""` as
    an escaped quote rather than a close.
    """
    in_string = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '"':
            if in_string and line[i + 1 : i + 2] == '"':
                i += 2
                continue
            in_string = not in_string
        elif not in_string and ch == "-" and line[i + 1 : i + 2] == "-":
            return line[:i]
        i += 1
    return line


#  A numeral inside a message is text, not a magic number: R9 asks
#  whether a VALUE on the page is unexplained, and prose explains
#  itself.  A number that appears both as a literal and inside the
#  message about it is still caught -- the literal half is what fires.
_STRING = re.compile(r'"[^"]*"')


def without_strings(line: str) -> str:
    return _STRING.sub('""', line)


def is_blank_or_comment(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("--")


def _header_text(lines: list[str], start: int) -> tuple[str, int, bool]:
    """Join a (possibly wrapped) header and say whether a body follows.

    gnatformat wraps a long profile over several lines and puts a lone
    `is` on its own, so the header is read forward until the declaration
    resolves.  Only a `;` OUTSIDE the parentheses ends it: the ones
    between parameters are separators, not terminators, which is why
    depth is tracked character by character rather than per line.
    Returns (text, last line index, is_body).
    """
    depth = 0
    ended = False
    text_parts: list[str] = []
    i = start
    while i < len(lines) and i < start + 60:
        code = strip_code(lines[i])
        text_parts.append(code)
        for ch in code:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == ";" and depth <= 0:
                ended = True
        joined = " ".join(" ".join(text_parts).split())
        if depth <= 0:
            #  `is` opens a body only when nothing follows it on the
            #  declaration: `is new` instantiates, `is separate` stubs,
            #  `is (` is an expression function, `is abstract`/`is null`
            #  declare no body at all.
            if re.search(r"\bis\s+(new|separate|abstract|null)\b", joined, re.I):
                return joined, i, False
            if re.search(r"\bis\s*\(", joined, re.I):
                return joined, i, False
            if re.search(r"\brenames\b", joined, re.I):
                return joined, i, False
            if re.search(r"\bis\s*$", joined, re.I):
                return joined, i, True
            if ended:
                return joined, i, False
        i += 1
    return " ".join(" ".join(text_parts).split()), min(i, len(lines) - 1), False


def find_bodies(lines: list[str]) -> list[Body]:
    """Every subprogram, task and package body in one file, nested."""
    bodies: list[Body] = []
    stack: list[Body] = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        if is_blank_or_comment(raw):
            i += 1
            continue
        end = _END.match(raw)
        if end and stack:
            top = stack[-1]
            if len(end.group("indent")) == top.indent and end.group("name").lower() == top.name.lower():
                top.end = i + 1
                stack.pop()
                i += 1
                continue
        head = _HEADER.match(raw)
        if head:
            text, last, is_body = _header_text(lines, i)
            if is_body:
                kind = " ".join(head.group("kind").lower().split())
                body = Body(
                    name=head.group("name"),
                    kind=kind,
                    indent=len(head.group("indent")),
                    header=i + 1,
                    header_text=text,
                )
                if stack:
                    stack[-1].inner.append(body)
                else:
                    bodies.append(body)
                stack.append(body)
            i = last + 1
            continue
        begin = _BEGIN.match(raw)
        if begin and stack:
            top = stack[-1]
            if len(begin.group("indent")) == top.indent and top.begin is None:
                top.begin = i + 1
        i += 1
    return bodies


def walk(bodies: list[Body], frames: int = 0):
    """Every body, outermost first, with its count of enclosing FRAMES.

    A package body is a file's table of contents, not a frame a reader
    must hold in their head, so it does not raise the count: a
    subprogram declared directly in one is not nested (R4), and one
    declared inside another subprogram is.
    """
    for body in bodies:
        yield body, frames
        deeper = frames + (1 if body.kind in FRAME_KINDS else 0)
        for inner, level in walk(body.inner, deeper):
            yield inner, level


def _own_line_numbers(body: Body) -> list[int]:
    """The body's own lines, IN FILE ORDER: a nested body's lines are its.

    Ordered, and not the set it is built from, because R3 walks these
    lines counting block openers against closers -- a walk that means
    nothing except in the order the lines are written.  A set of small
    integers iterates in ascending order and stops doing so once the
    values outgrow its table, so R3 read some bodies from the middle and
    under-reported their nesting, and which bodies depended on nothing
    more than how far down a file they sat.
    """
    if body.end is None:
        return []
    span = set(range(body.header, body.end + 1))
    for inner in body.inner:
        if inner.end is not None:
            span -= set(range(inner.header, inner.end + 1))
    return sorted(span)


def measure_body(body: Body, lines: list[str]) -> dict[str, int]:
    """Every metric this body carries, whether or not it is over."""
    out: dict[str, int] = {}
    own = _own_line_numbers(body)
    out["lines"] = len(own)

    if body.begin is not None and body.end is not None:
        stmt = [
            n
            for n in own
            if body.begin < n < body.end and not is_blank_or_comment(lines[n - 1])
        ]
        out["stmt"] = len(stmt)
        depth = 0
        current = 0
        for n in stmt:
            code = strip_code(lines[n - 1]).strip()
            if _CLOSES.match(code):
                current = max(0, current - 1)
            elif _OPENS.match(code):
                current += 1
                depth = max(depth, current)
        out["depth"] = depth
    else:
        out["stmt"] = 0
        out["depth"] = 0

    params, outs, bools = parse_params(body.header_text)
    out["params"] = params
    out["outs"] = outs
    out["bools"] = bools
    return out


def parse_params(header: str) -> tuple[int, int, int]:
    """(parameter count, out-parameter count, adjacent-Boolean pairs).

    Read from the profile's outermost parentheses, so an access-to-
    subprogram parameter's own profile does not split a declaration.
    """
    start = header.find("(")
    if start < 0:
        return (0, 0, 0)
    depth = 0
    end = -1
    for i in range(start, len(header)):
        if header[i] == "(":
            depth += 1
        elif header[i] == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end < 0:
        return (0, 0, 0)

    chunks: list[str] = []
    depth = 0
    current: list[str] = []
    for ch in header[start + 1 : end]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == ";" and depth == 0:
            chunks.append("".join(current))
            current = []
        else:
            current.append(ch)
    chunks.append("".join(current))

    total = 0
    outs = 0
    #  One entry per DECLARATION, so `A, B : Boolean` is one run of two
    #  and `A : Boolean; B : Boolean` is two runs of one -- both adjacent.
    runs: list[tuple[int, bool]] = []
    for chunk in chunks:
        if ":" not in chunk:
            continue
        names, _, rest = chunk.partition(":")
        count = len([n for n in names.split(",") if n.strip()])
        if not count:
            continue
        total += count
        #  RESULTS only.  An `in out` is the subject the caller already
        #  holds, not an answer it must unpack, and R6's remedy --
        #  return a record -- applies to answers alone.  R5 still bounds
        #  the whole profile, so a signature threading five things is
        #  caught there.
        if re.match(r"\s*out\b", rest, re.I):
            outs += count
        type_text = re.sub(r"\s*(in\s+out|in|out)\b", "", rest, count=1, flags=re.I)
        type_text = type_text.split(":=")[0].strip()
        runs.append((count, type_text.lower() in ("boolean", "standard.boolean")))

    bools = 0
    run_len = 0
    for count, is_bool in runs:
        if is_bool:
            run_len += count
        else:
            bools += max(0, run_len - 1)
            run_len = 0
    bools += max(0, run_len - 1)
    return (total, outs, bools)


def count_literals(lines: list[str]) -> dict[str, int]:
    """Bare numeric literals >= 100, attributed to the declaration above.

    The exemption covers a whole declaration, not one line of it: a
    named constant table wraps over many lines and every literal in it
    is already spoken for by the name at the top.  So once a line
    declares a constant, bounds a type or reads a bound off one, the
    rest of that declaration is exempt until its terminating `;`
    outside parentheses.
    """
    found: dict[str, int] = {}
    current = "<file>"
    exempt = False
    depth = 0
    for raw in lines:
        decl = _DECL_NAME.match(raw)
        if decl:
            current = decl.group(1)
        code = without_strings(strip_code(raw))
        if code.strip() and _LITERAL_EXEMPT.search(code):
            exempt = True
        counted = not exempt
        for ch in code:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == ";" and depth <= 0:
                exempt = False
        if not counted or not code.strip():
            continue
        hits = [m for m in _LITERAL.findall(code) if int(m.replace("_", "")) >= 100]
        if hits:
            found[current] = found.get(current, 0) + len(hits)
    return found


def check_aliases(lines: list[str]) -> list[tuple[str, str]]:
    """Event aliases that do not spell their literal minus `E_`."""
    bad: list[tuple[str, str]] = []
    for raw in lines:
        match = _ALIAS.match(raw)
        if match and match.group(1).lower() != match.group(2).lower():
            bad.append((match.group(1), match.group(2)))
    return bad


def check_foreign(lines: list[str]) -> list[str]:
    """Pointers out of this repository, in a comment.  R10 forbids them."""
    found: list[str] = []
    for raw in lines:
        cut = raw.find("--")
        if cut < 0:
            continue
        #  A waiver line is whitespace-separated columns, so the name
        #  this reports has to be one token: "PR #436", not "PR" then
        #  "#436".
        found.extend(
            re.sub(r"\s+", "", m.group(0)) for m in _FOREIGN.finditer(raw[cut:])
        )
    return found


def check_dated(lines: list[str]) -> dict[str, int]:
    """Calendar dates in comments, each with how many lines carry it.

    R10 forbids them.  One finding per date and file, counted, so a
    waiver names something a reader can grep for.
    """
    found: dict[str, int] = {}
    for raw in lines:
        cut = raw.find("--")
        if cut < 0:
            continue
        for date in set(_DATED.findall(_QUOTED.sub("", raw[cut:]))):
            found[date] = found.get(date, 0) + 1
    return found


def find_declarations(lines: list[str]) -> list[tuple[str, str]]:
    """Every subprogram DECLARATION that is not a body, with its header.

    R5, R6 and R7 are properties of a profile, and a profile is what a
    caller reads -- so a spec, a forward declaration and an expression
    function are all measurable, and only bodies were being measured.
    Renamings and instantiations declare no profile of their own and are
    skipped, as they are for the body rules.
    """
    found: list[tuple[str, str]] = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        if is_blank_or_comment(raw):
            i += 1
            continue
        head = _HEADER.match(raw)
        if head and head.group("kind").lower() in ("procedure", "function"):
            text, last, is_body = _header_text(lines, i)
            lowered = text.lower()
            if not is_body and " renames " not in lowered and " is new " not in lowered:
                found.append((head.group("name"), text))
            i = last + 1
            continue
        i += 1
    return found


def spec_declares(path: pathlib.Path) -> set[str]:
    """The subprogram names a body file's own spec already declares.

    A profile appears twice for such a subprogram -- once in the spec and
    once on the body -- and it is ONE property.  It is reported against
    the spec, which is where a caller meets it, so the body's copy is
    skipped here rather than waived twice.
    """
    if path.suffix.lower() != ".adb":
        return set()
    spec = path.with_suffix(".ads")
    if not spec.is_file():
        return set()
    lines = spec.read_text(encoding="utf-8", errors="replace").split("\n")
    return {name.lower() for name, _ in find_declarations(lines)}


PROFILE_METRICS = ("params", "outs", "bools")


def analyze_file(path: pathlib.Path, rel: str) -> list[Finding]:
    """Every finding in one source file."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    findings: list[Finding] = []

    if rel.endswith(".adb") and len(lines) > LIMITS["file_lines"]:
        findings.append(Finding(rel, "<file>", "file_lines", len(lines)))

    in_spec = spec_declares(path)

    for body, frames in walk(find_bodies(lines)):
        if body.kind not in FRAME_KINDS:
            continue
        metrics = measure_body(body, lines)
        for metric in ("stmt", "lines", "depth", "params", "outs", "bools"):
            if metric in PROFILE_METRICS and body.name.lower() in in_spec:
                continue
            if metrics[metric] > LIMITS[metric]:
                findings.append(Finding(rel, body.name, metric, metrics[metric]))
        if frames > 0:
            findings.append(Finding(rel, body.name, "nested", 1))

    for name, header in find_declarations(lines):
        if name.lower() in in_spec:
            continue
        params, outs, bools = parse_params(header)
        for metric, value in zip(PROFILE_METRICS, (params, outs, bools)):
            if value > LIMITS[metric]:
                findings.append(Finding(rel, name, metric, value))

    for unit, count in count_literals(lines).items():
        findings.append(Finding(rel, unit, "literals", count))

    if rel.endswith(".adb"):
        for alias, literal in check_aliases(lines):
            findings.append(Finding(rel, alias, "alias", 1))

    for foreign in check_foreign(lines):
        findings.append(Finding(rel, foreign, "foreign", 1))

    for date, count in check_dated(lines).items():
        findings.append(Finding(rel, date, "dated", count))

    return findings


def canonical(findings: list[Finding]) -> list[Finding]:
    """One finding per (file, unit, metric), carrying the worst value.

    A file may declare the same name twice -- an overload, or the same
    nested helper in two frames -- and a waiver names a unit, not a
    line.  Collapsing here keeps the waiver file one line per waivable
    thing, so a count in the report and a count in the file agree.
    """
    worst: dict[tuple[str, str, str], Finding] = {}
    for finding in findings:
        seen = worst.get(finding.key)
        if seen is None or finding.value > seen.value:
            worst[finding.key] = finding
    return list(worst.values())


#  The directories this lint measures.  Adding a source tree (an example
#  binary, a shell layer) means adding its glob here.
SOURCE_DIRS: tuple[str, ...] = ("src", "tests/src", "proof/src")


def sources(root: pathlib.Path) -> list[pathlib.Path]:
    found: list[pathlib.Path] = []
    for rel in SOURCE_DIRS:
        base = root / rel
        if base.is_dir():
            found.extend(p for p in base.rglob("*.ad[sb]") if p.is_file())
    return sorted(found)


def read_waivers(path: pathlib.Path) -> dict[tuple[str, str, str], int]:
    """Known violations, each with the value it is allowed to reach."""
    out: dict[tuple[str, str, str], int] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        path_, unit, metric, value = parts[0], parts[1], parts[2], parts[3]
        out[(path_, unit.lower(), metric)] = int(value)
    return out


WAIVER_HEADER = """\
#  Shapes knowingly over a limit, and why each one is still here.
#
#  This file is the reason `make shape` can stay ON.  A violation that is
#  not listed here fails the build; a listed one whose value has GROWN
#  fails; and a line for a shape that no longer violates fails too, so the
#  list cannot outlive what it excuses.  A waiver may only ever shrink,
#  and deleting one is how a refactor cycle gets its RED.
#
#  The limits are this script's LIMITS table.
#
#  --write-waivers rewrote this file from the tree once, to seed the
#  baseline.  Do not run it again to "fix" a failure: regenerating
#  silently absorbs exactly the regressions the gate exists to catch.
#  Delete lines by hand as the shapes they excuse go away.
#
#  file                                                       unit                         metric     value  reason
"""


def write_waivers(path: pathlib.Path, findings: list[Finding]) -> None:
    lines = [WAIVER_HEADER]
    for finding in sorted(findings, key=lambda f: (f.path, f.unit.lower(), f.metric)):
        lines.append(f"{finding.line()}  needs a reason\n")
    path.write_text("".join(lines), encoding="utf-8")


SELFTEST_FIXTURE = '''\
package body Shape_Fixture is

   --  R9 must not fire inside a named declaration, however it wraps:
   --  this table IS the naming, and every literal in it is spoken for.
   Width_Tiers : constant array (Positive range <>) of Width_Tier :=
     [(Bid_Above => 1_000_000, Max_Spread => 60_000),
      (Bid_Above => 500_000, Max_Spread => 45_000),
      (Bid_Above => 0, Max_Spread => 7_500)];

   --  R5/R6/R7: six parameters, three of them out, two adjacent Booleans.
   procedure Over_Profile
     (A : Integer; Closing : Boolean; Credit : Boolean; B : out Integer;
      C : out Integer; D : out Integer) is
   begin
      B := A;
      C := A;
      D := A;
   end Over_Profile;

   --  R9: a bare literal carrying a scale nothing names.  The numeral
   --  in the message below is prose and must NOT be counted.
   procedure Bare_Literal is
      X : Integer := 60_000;
   begin
      Log ("the 1800 s cap, in 1/10000 $");
      X := X + 1;
   end Bare_Literal;

   --  A message that contains Ada's own comment marker.  The `--` is
   --  inside a string, so the rest of the line is CODE: its closing
   --  paren must still count, or every literal after it in the file is
   --  silently exempted, and its own numeral must not be counted twice.
   procedure Dashes_In_A_Message is
   begin
      Log ("gave up after the 503 retries -- the order may be live");
   end Dashes_In_A_Message;

   --  R9 again, AFTER the line above.  Reading the `--` as a comment
   --  drops that line's closing paren, so every later `;` looks like it
   --  is inside parentheses, the named-declaration exemption never ends,
   --  and this bare literal is silently excused.  It must fire.
   procedure After_Dashes is
      Limit : constant Integer := 30;
      X     : Integer := 0;
   begin
      X := 900 + Limit;
   end After_Dashes;

   --  R3: four blocks deep, and R4: a body inside a body.
   procedure Deep is
      procedure Inner is
      begin
         null;
      end Inner;
   begin
      if True then
         for I in 1 .. 2 loop
            if True then
               declare
                  Y : Integer := 1;
               begin
                  Y := Y + 1;
               end;
            end if;
         end loop;
      end if;
      Inner;
   end Deep;

   --  R6 counts RESULTS, not subjects.  Two threaded in-out values plus
   --  two results is two: "return a record" fixes the results and is no
   --  fix at all for the state being threaded through.
   procedure Threaded_State
     (A : in out Integer; B : in out Integer; C : out Integer;
      D : out Integer);

   --  R5/R6/R7 hold of a DECLARATION, not of a body: this profile is
   --  what a caller reads, and there is no body here to read instead.
   procedure Declared_Only
     (A : Integer; Opening : Boolean; Closing : Boolean; B : out Integer;
      C : out Integer; D : out Integer);

   --  R7 on an expression function: still a profile, still two Booleans
   --  a caller cannot tell apart.
   function Both (Left : Boolean; Right : Boolean) return Boolean
   is (Left and then Right);

   --  Not bodies, and must not be measured as such: an expression
   --  function, a renaming, an instantiation and a stub.
   function Doubled (N : Integer) return Integer is (N * 2);
   procedure Alias (N : Integer) renames Over_Profile;
   procedure Sized is new Generic_Thing (Item => Integer);
   procedure Elsewhere is separate;

   --  Within every limit: this one must produce no finding at all.
   function Small (N : Integer) return Integer is
   begin
      return N + 1;
   end Small;

end Shape_Fixture;
'''

SELFTEST_FOREIGN = '''\
package Fixture.Foreign is

   --  Fixed in PR #436, reported as issue #2, specified in the plan's
   --  §8, and ported from some_file.go:41 via other_file.cpp:12.
   procedure Nothing;

end Fixture.Foreign;
'''

SELFTEST_DATED = '''\
package Fixture.Dated is

   --  Measured live 2026-07-21: the band was 40 KB.  The wire spells a
   --  day "2026-01-15", which is a format, not a date.
   Format : constant String := "2026-01-15";

   --  The 2026-08-19 incident, and the fix that the
   --  2026-08-19 follow-up asked for.
   procedure Nothing;

end Fixture.Dated;
'''

SELFTEST_ENGINE = '''\
package body Fixture.Engine is

   Open      : constant Ev := (Kind => E_Open);
   Conn_Fail : constant Ev := (Kind => E_Conn_Failed);

end Fixture.Engine;
'''


def selftest() -> int:
    """Prove each rule fires on a fixture written to violate it once."""
    import tempfile

    failures: list[str] = []

    with tempfile.TemporaryDirectory() as tmp:
        body = pathlib.Path(tmp) / "shape_fixture.adb"
        body.write_text(SELFTEST_FIXTURE, encoding="utf-8")
        found = analyze_file(body, "shape_fixture.adb")
        got = {(f.unit.lower(), f.metric): f.value for f in found}

        expected: list[tuple[tuple[str, str], int | None]] = [
            (("over_profile", "params"), 6),
            (("over_profile", "outs"), 3),
            (("over_profile", "bools"), 1),
            (("bare_literal", "literals"), 1),
            (("after_dashes", "literals"), 1),
            (("declared_only", "params"), 6),
            (("declared_only", "outs"), 3),
            (("declared_only", "bools"), 1),
            (("both", "bools"), 1),
            (("deep", "depth"), 4),
            (("inner", "nested"), 1),
        ]
        for key, value in expected:
            if key not in got:
                failures.append(f"expected {key[1]} on {key[0]}, found none")
            elif value is not None and got[key] != value:
                failures.append(f"{key[0]} {key[1]}: expected {value}, got {got[key]}")

        #  R3 reads a body's lines in the order they are written; a
        #  rotation of the same lines is a different, wrong answer.
        for body, _ in walk(find_bodies(SELFTEST_FIXTURE.split("\n"))):
            own = _own_line_numbers(body)
            if own != sorted(own):
                failures.append(f"{body.name}: own lines are not in file order")

        for unit in (
            "doubled",
            "alias",
            "sized",
            "elsewhere",
            "small",
            "threaded_state",
        ):
            over = [m for (u, m) in got if u == unit]
            if over:
                failures.append(f"{unit} must produce no finding, produced {over}")

        foreign = check_foreign(SELFTEST_FOREIGN.split("\n"))
        if foreign != ["PR#436", "issue#2", "§8", "some_file.go:41", "other_file.cpp:12"]:
            failures.append(f"foreign check: got {foreign}")

        dated = check_dated(SELFTEST_DATED.split("\n"))
        if dated != {"2026-07-21": 1, "2026-08-19": 2}:
            failures.append(f"dated check: got {dated}")

        engine = pathlib.Path(tmp) / "fixture-engine.adb"
        engine.write_text(SELFTEST_ENGINE, encoding="utf-8")
        aliases = check_aliases(SELFTEST_ENGINE.split("\n"))
        if [a for a, _ in aliases] != ["Conn_Fail"]:
            failures.append(f"alias check: expected [Conn_Fail], got {aliases}")

    if failures:
        print("FAIL: shape_check selftest")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("shape_check selftest: ok (every rule fires once on the fixture)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", type=pathlib.Path)
    parser.add_argument(
        "--waivers", type=pathlib.Path, default=pathlib.Path("tools/shape-waivers")
    )
    parser.add_argument(
        "--selftest", action="store_true", help="prove each rule fires on a fixture"
    )
    parser.add_argument(
        "--write-waivers",
        action="store_true",
        help="rewrite the waiver file from what the tree carries today",
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    root = args.root.resolve()
    findings: list[Finding] = []
    for path in sources(root):
        findings.extend(analyze_file(path, str(path.relative_to(root))))
    findings = canonical(findings)

    waiver_path = root / args.waivers
    if args.write_waivers:
        write_waivers(waiver_path, findings)
        print(f"wrote {len(findings)} waivers to {args.waivers}")
        return 0

    waived = read_waivers(waiver_path)
    unwaived = [f for f in findings if f.key not in waived]
    grown = [f for f in findings if f.key in waived and f.value > waived[f.key]]
    live = {f.key for f in findings}
    stale = sorted(key for key in waived if key not in live)

    if not args.quiet:
        print(f"shape-check: {len(findings)} shapes over a limit, {len(waived)} waived")

    failed = False
    if unwaived:
        failed = True
        print()
        print("FAIL: shapes over a limit with no waiver.  Split them, or")
        print(f"      record each in {args.waivers} with a reason:")
        for finding in sorted(unwaived, key=lambda f: (f.path, f.unit)):
            rule = RULE_OF[finding.metric]
            print(f"  {finding.line()}   ({rule}, limit {LIMITS[finding.metric]})")
    if grown:
        failed = True
        print()
        print("FAIL: waived shapes that have GROWN -- a waiver may only shrink:")
        for finding in sorted(grown, key=lambda f: (f.path, f.unit)):
            print(f"  {finding.line()}  (waived at {waived[finding.key]})")
    if stale:
        failed = True
        print()
        print("FAIL: waivers for shapes that no longer violate -- drop them:")
        for path_, unit, metric in stale:
            print(f"  {path_:<58} {unit:<28} {metric}")

    if not failed:
        print("shape-check: ok (every shape is within its limit or waived)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
