"""The subprogram-shape lint.

A tree gets hard to follow in a small number of measurable ways:
subprogram bodies that hold hundreds of statements, bodies declared
inside other bodies, block nesting several levels deep, signatures with
more outputs than a reader can hold, bodies that do several things in a
row, and literals that nothing on the page names.  One more rule reads
text, not shape: C++ wording carried over from the reference
interpreter (R12).

The rules (LIMITS below holds each limit):

  R1  stmt        statement lines in a body
  R2  lines       lines of a body, declarations included
  R3  depth       block nesting depth
  R4  nested      a body declared inside another body
  R5  params      parameters of a profile
  R6  outs        out parameters of a profile
  R7  bools       adjacent Boolean parameters
  R8  file_lines  lines in a body file
  R9  (retired: R13 reads every numeral it read)
  R10 foreign     a comment that points outside this repository
  R10 dated       a calendar date in a comment
  R11 alias       an event alias that is not its literal minus E_
  R12 carryover   C++ wording in fabula's own text
  R13 lit_num     numerals in logic, or in a computed constant
  R14 lit_char    character literals in logic
  R15 lit_str     string literals in logic
  R16 blocks      blocks at the top level of one body (limit 1)

R13-R15, the literal rules.  A literal is named when a declaration
gives it a name: a constant whose initializer is that one literal, an
element or choice of an aggregate that a constant declares (a named
table), a type or subtype declaration, or a pragma.  A constant whose
initializer computes (`Start + 3`, `Pad (X, 12)`) or whose subtype
holds a bound (`String (1 .. 12)`) does not name the numerals in it:
that is a COMPUTED constant, and R13 reads it as logic.  Everything else
is logic, and every literal in logic fires, except:

  - 0 and 1 in four idioms: a step (`X + 1`, `X - 1`); a range or slice
    origin (`1 ..`); an emptiness test (`= 0`, `/= 0` or `> 0` on a
    count name); a counter reset (the statement `Name := 0;` on a count
    name).  A count name is Length, Len, Count or Used, alone or after
    an underscore (Text'Length, Item_Count, Doc.Rules_Used; not
    Excused).  A default (`X : T := 0`) is no reset, and fires;
  - the numeral that selects an array dimension ('First (2), 'Last (2));
  - the blank in `[others => ' ']`, a fill;
  - the empty string "".

tests/src/ is exempt from R13-R15: a test's expected values are its
fixture data.  Every other rule, R16 included, still reads tests/src/.

A function that is only a case over its parameter, every choice a name
(`A`, `A | B`, `others`, never a literal), a literal per arm, IS a named
table (the enumeration value names each literal); its waiver carries
the reason "enum-indexed table" and stays.

Known limits, each by design or out of reach of a token reader:
  - a length is told from a handle only by its name;
  - a case over any discrete type with named choices counts as a case
    over an enumeration;
  - literals inside a constant's aggregate count as named, even
    positional ones with no component name;
  - a character or string literal inside a constant counts as named,
    even in a computed constant (`"Value " & X`);
  - R3 may count one extra level for a for or while loop whose
    condition wraps onto its own `loop` line;
  - the line-based rules (R1-R3 and the header reader) read the `"`
    in the character literal '"' as a string quote, so on that line a
    trailing comment is read as code; no source line pairs the two.

R16, the block rule.  An if, a case, a loop (for, while or bare), a
declare block and an extended return each open one block; R16 counts
those at the top level of a body's statements, and a body may hold one.
Two exemptions: one leading early-exit guard -- an if whose only
statement is `return` or `return X`, before any other statement -- does
not count; and a case counts once, whatever its arms hold, so a body
that is one case over an enumeration (a dispatch) holds one block.

This module measures those shapes and holds them to
``tools/shape-waivers``.  That file is not a way to hide a violation --
it is the only way to keep the gate ON while a known one exists.  Each
waiver must EQUAL what the tree carries, so it fails on four things:

1. a violation that is not waived (new debt);
2. a waived violation whose value has GROWN (debt getting worse);
3. a waived violation whose value has SHRUNK (slack a later change
   could grow back into unseen -- lower the waiver to the new count);
4. a waiver for a unit that no longer violates (a stale waiver -- the
   list cannot outlive what it excuses).

So a waiver moves only down, in the same change as the code that moves
it, and deleting one is how a refactor cycle gets its RED.

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
import bisect
import pathlib
import re
import subprocess
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
    #                      R9  retired: R13 reads every numeral it read
    "alias": 0,  # R11 event alias that is not its literal minus E_
    "foreign": 0,  # R10 a comment pointing outside this repository
    "dated": 0,  # R10 a calendar date in a comment
    "carryover": 0,  # R12 C++ wording in fabula's own text
    "lit_num": 0,  # R13 bare numerals in logic or in a computed constant
    "lit_char": 0,  # R14 bare character literals in logic
    "lit_str": 0,  # R15 bare string literals in logic
    "blocks": 1,  # R16 blocks at the top level of a body
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
    "alias": "R11",
    "foreign": "R10",
    "dated": "R10",
    "carryover": "R12",
    "lit_num": "R13",
    "lit_char": "R14",
    "lit_str": "R15",
    "blocks": "R16",
}

#  Metrics that COUNT occurrences rather than measure one shape.  Two
#  bodies with one name in one file add up, so a second overload cannot
#  grow under the first one's waiver.
COUNT_METRICS: frozenset[str] = frozenset({"lit_num", "lit_char", "lit_str", "blocks"})

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
    r"|\bsection\s+\d+"      # spec section 2, of some other document
    r"|\b[\w/]+\.(?:go|cpp|hpp):\d+"    # some_file.cpp:41
    r"|\b[\w/]+\.(?:go|cpp|hpp)\b)",    # some_file.cpp
    re.I,
)

#  R12 forbids C++ wording carried over from the reference interpreter
#  into fabula's own sources, examples, tests and docs.  fabula teaches
#  Ada: a message, example or comment that names a C++ call, container
#  or macro points the reader at an API fabula does not have.  The rule
#  reads every file under these paths, not only Ada comments, because
#  feature files and Markdown teach as much as the code.  tests/data/
#  is exempt: it holds the oracle's own inputs, byte-identical, and the
#  oracle's own captures of them.
CARRYOVER_TOKENS: tuple[str, ...] = ("cuke::", "std::", "context<", "CUKE_", "cucumber-cpp")
CARRYOVER_DIRS: tuple[str, ...] = ("src/", "example/", "tests/src/", "docs/")
CARRYOVER_FILES: tuple[str, ...] = ("README.md",)
CARRYOVER_EXEMPT: tuple[str, ...] = ("tests/data/",)

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


#  ---------------------------------------------------------------------
#  R13-R16 read tokens, not lines.  A pattern over one line cannot tell
#  the character literal '"' from the start of a string, the tick in
#  X'First or T'(...) from a character literal, or a numeral in a
#  message from one in the code.  A tokenizer reads the file once, left
#  to right, as the compiler does, and can.
#  ---------------------------------------------------------------------

RESERVED: frozenset[str] = frozenset(
    "abort abs abstract accept access aliased all and array at begin body"
    " case constant declare delay delta digits do else elsif end entry"
    " exception exit for function generic goto if in interface is limited"
    " loop mod new not null of or others out overriding package pragma"
    " private procedure protected raise range record rem renames requeue"
    " return reverse select separate some subtype synchronized tagged task"
    " terminate then type until use when while with xor".split()
)

_NUMERAL = re.compile(r"\d[\d_]*(?:#[0-9A-Fa-f_.]+#)?(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?")
_WORD = re.compile(r"[A-Za-z][A-Za-z0-9_]*")
_COMPOUND_OPS: tuple[str, ...] = ("..", ":=", "/=", ">=", "<=", "=>", "**", "<>", "<<", ">>")


@dataclass(frozen=True)
class Token:
    """One lexical element, with the line it starts on.

    kind is "num", "chr" or "str" for a literal (a string's text is its
    contents, a doubled quote undone), "kw" for a reserved word, "id"
    for a name (a reserved word used as an attribute, X'Range, is a
    name), and "op" for a delimiter, the tick included.
    """

    kind: str
    text: str
    line: int

    def is_op(self, *texts: str) -> bool:
        return self.kind == "op" and self.text in texts

    def is_kw(self, *words: str) -> bool:
        return self.kind == "kw" and self.text.lower() in words


def tokenize(text: str) -> list[Token]:
    """The file's tokens in order, with comments dropped.

    A tick opens a character literal unless it follows a name or a
    closing parenthesis: then it is an attribute (X'First) or a
    qualification (T'(...)).  A reserved word is not a name, so the tick
    in `when '(' =>` opens a literal.  A string runs to its closing
    quote, a doubled quote inside it standing for one, so a `--` or a
    numeral inside it is text.
    """
    tokens: list[Token] = []
    line = 1
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if ch in " \t\r\f\v":
            i += 1
            continue
        if text.startswith("--", i):
            stop = text.find("\n", i)
            i = n if stop < 0 else stop
            continue
        if ch == '"':
            j = i + 1
            parts: list[str] = []
            while j < n and text[j] != "\n":
                if text[j] == '"':
                    if text[j + 1 : j + 2] == '"':
                        parts.append('"')
                        j += 2
                        continue
                    break
                parts.append(text[j])
                j += 1
            tokens.append(Token("str", "".join(parts), line))
            i = j + 1
            continue
        if ch == "'":
            prev = tokens[-1] if tokens else None
            after_name = prev is not None and (prev.kind in ("id", "str") or prev.is_op(")"))
            if not after_name and i + 2 < n and text[i + 2] == "'" and text[i + 1] != "\n":
                tokens.append(Token("chr", text[i + 1], line))
                i += 3
                continue
            tokens.append(Token("op", "'", line))
            i += 1
            continue
        if ch.isdigit():
            numeral = _NUMERAL.match(text, i)
            assert numeral is not None
            tokens.append(Token("num", numeral.group(0), line))
            i = numeral.end()
            continue
        if ch.isalpha():
            word = _WORD.match(text, i)
            assert word is not None
            after_tick = bool(tokens) and tokens[-1].is_op("'")
            reserved = word.group(0).lower() in RESERVED and not after_tick
            tokens.append(Token("kw" if reserved else "id", word.group(0), line))
            i = word.end()
            continue
        for op in _COMPOUND_OPS:
            if text.startswith(op, i):
                tokens.append(Token("op", op, line))
                i += len(op)
                break
        else:
            tokens.append(Token("op", ch, line))
            i += 1
    return tokens


def _matching_close(tokens: list[Token], start: int) -> int:
    """The index of the bracket that closes the one at start."""
    depth = 0
    for idx in range(start, len(tokens)):
        if tokens[idx].is_op("(", "["):
            depth += 1
        elif tokens[idx].is_op(")", "]"):
            depth -= 1
            if depth == 0:
                return idx
    return len(tokens)


def _bracket_kinds(tokens: list[Token]) -> dict[int, str]:
    """Each opening bracket's kind: "aggregate", "call" or "group".

    A `[` always opens an aggregate.  A `(` right after a name or a `)`
    opens a call, an index, a conversion or a constraint: "call".  Any
    other `(` opens an aggregate when a `,`, `=>` or `with` sits at its
    own depth, and a grouping or an if, case, quantified or declare
    expression otherwise: "group".
    """
    kinds: dict[int, str] = {}
    for idx, tok in enumerate(tokens):
        if tok.is_op("["):
            kinds[idx] = "aggregate"
            continue
        if not tok.is_op("("):
            continue
        prev = tokens[idx - 1] if idx else None
        if prev is not None and (prev.kind in ("id", "str") or prev.is_op(")")):
            kinds[idx] = "call"
            continue
        first = tokens[idx + 1] if idx + 1 < len(tokens) else None
        if first is None or first.is_kw("if", "case", "for", "declare"):
            kinds[idx] = "group"
            continue
        kinds[idx] = "group"
        depth = 0
        for inner in tokens[idx + 1 : _matching_close(tokens, idx)]:
            if inner.is_op("(", "["):
                depth += 1
            elif inner.is_op(")", "]"):
                depth -= 1
            elif depth == 0 and (inner.is_op(",", "=>") or inner.is_kw("with")):
                kinds[idx] = "aggregate"
                break
    return kinds


LITERAL_METRICS: tuple[str, ...] = ("lit_num", "lit_char", "lit_str")
_METRIC_OF_KIND = {"num": "lit_num", "chr": "lit_char", "str": "lit_str"}

#  An emptiness test compares a length or a count with 0, and a counter
#  reset sets one to 0.  The lint cannot see types, so it reads the
#  name: the operand's last name must BE one of these words, or end in
#  one after an underscore (X'Length, Captures.Count, Doc.Rules_Used,
#  Line.Len, Item_Count; not Excused or Discount).  Anything else with
#  a 0 -- a handle, a status, a position, a depth -- fires, and names
#  its "none" value instead.
_COUNT_NAME = re.compile(r"(?:^|_)(?:length|len|count|used)$", re.I)

#  Where a statement starts, reading backward from its `:=`.
_STATEMENT_START: tuple[str, ...] = ("begin", "then", "else", "loop", "is", "do", "declare")

#  'First (2) and 'Last (2) select an array dimension; the argument is
#  which one, not a value, so it stays a literal.
_DIMENSION_ATTRIBUTES: tuple[str, ...] = ("first", "last", "length", "range")

#  What may sit on either side of an aggregate's element or choice.
_ELEMENT_BEFORE: tuple[str, ...] = ("(", "[", ",", "=>", "|", "..")
_ELEMENT_AFTER: tuple[str, ...] = (")", "]", ",", "=>", "|", "..")


def literal_metrics_for(rel: str) -> tuple[str, ...]:
    """The literal rules that read one repo-relative path.

    A test's expected values are its fixture data: naming each expected
    number, character or string would make the test harder to read, so
    no literal rule reads tests/src/.  Every other rule still does.
    """
    if rel.startswith("tests/src/"):
        return ()
    return LITERAL_METRICS


def _is_assignment_statement(tokens: list[Token], assign: int) -> bool:
    """Whether the `:=` at assign is a statement, not a default.

    A declaration or a parameter has a `:` between its start and its
    `:=`; an assignment statement has none.  The walk goes back to the
    statement's start: a `;`, an unmatched `(`, a `=>`, or a word that
    opens a statement sequence.
    """
    depth = 0
    for j in range(assign - 1, -1, -1):
        tok = tokens[j]
        if tok.is_op(")", "]"):
            depth += 1
        elif tok.is_op("(", "["):
            if depth == 0:
                return False
            depth -= 1
        elif depth == 0 and tok.is_op(":"):
            return False
        elif depth == 0 and (tok.is_op(";", "=>") or tok.is_kw(*_STATEMENT_START)):
            return True
    return True


def _ends_operand(tok: Token) -> bool:
    """Whether tok can end the left operand of a binary operator."""
    return tok.kind in ("num", "chr", "str", "id") or tok.is_op(")", "]")


def _allowed_numeral(tokens: list[Token], idx: int) -> bool:
    """A 0 or 1 in one of the four idioms, or a dimension selector.

    The idioms, as tokens:
      step        `+ 1` or `- 1` after an operand;
      origin      `1 ..`;
      emptiness   `= 0`, `/= 0` or `> 0` after a length or count name;
      reset       `Name := 0;` as a statement, Name a length or count
                  name.  A default (`X : T := 0`) is no reset.
    """
    value = tokens[idx].text.replace("_", "")
    prev = tokens[idx - 1] if idx >= 1 else None
    before = tokens[idx - 2] if idx >= 2 else None
    nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
    if value == "1" and prev is not None and before is not None:
        if prev.is_op("+", "-") and _ends_operand(before):
            return True
    if value == "1" and nxt is not None and nxt.is_op(".."):
        return True
    if value == "0" and prev is not None and before is not None:
        if prev.is_op("=", "/=", ">") and before.kind == "id" and _COUNT_NAME.search(before.text):
            return True
    if value == "0" and prev is not None and before is not None and nxt is not None:
        if (
            prev.is_op(":=")
            and nxt.is_op(";")
            and before.kind == "id"
            and _COUNT_NAME.search(before.text)
            and _is_assignment_statement(tokens, idx - 1)
        ):
            return True
    return (
        prev is not None
        and prev.is_op("(")
        and before is not None
        and before.kind == "id"
        and before.text.lower() in _DIMENSION_ATTRIBUTES
        and idx >= 3
        and tokens[idx - 3].is_op("'")
        and nxt is not None
        and nxt.is_op(")")
    )


def _is_fill(tokens: list[Token], idx: int) -> bool:
    """The blank in `[others => ' ']`: a fill, not a token of a grammar."""
    return (
        tokens[idx].text == " "
        and idx >= 2
        and tokens[idx - 1].is_op("=>")
        and tokens[idx - 2].is_kw("others")
        and idx + 1 < len(tokens)
        and tokens[idx + 1].is_op("]", ")")
    )


@dataclass
class _Decl:
    """A declaration the literal pass is inside, and where it ends.

    kind: "pragma" and "type" name every literal in them; "constant"
    names only some (see _named_by_constant); "record" and "object" are
    logic, kept only to name the unit a finding belongs to.
    """

    kind: str
    depth: int
    name: str
    assign: int | None = None


def _initializer_end(tokens: list[Token], start: int) -> int:
    """The index of the `;` (or the closing bracket) that ends an initializer."""
    depth = 0
    for idx in range(start, len(tokens)):
        tok = tokens[idx]
        if tok.is_op("(", "["):
            depth += 1
        elif tok.is_op(")", "]"):
            if depth == 0:
                return idx
            depth -= 1
        elif depth == 0 and tok.is_op(";"):
            return idx
    return len(tokens)


def _named_by_constant(
    tokens: list[Token], idx: int, decl: _Decl, frames: list[int], kinds: dict[int, str]
) -> bool:
    """Whether the constant being declared names the numeral at idx.

    It does when the numeral is the whole initializer (a sign allowed),
    or an element or a choice of an aggregate inside it: a named table.
    It does not when the numeral is an operand (`Start + 3`), a call's
    argument, or part of the subtype before the `:=`.  Those make the
    constant a COMPUTED one, and its name says what the result is, not
    what the numeral is.
    """
    if decl.assign is None or idx < decl.assign:
        return False
    start = decl.assign + 1
    if start < len(tokens) and tokens[start].is_op("+", "-"):
        start += 1
    if start == idx and _initializer_end(tokens, decl.assign + 1) == idx + 1:
        return True
    inside = [f for f in frames if f > decl.assign]
    if not inside or kinds.get(inside[-1]) != "aggregate":
        return False
    prev = tokens[idx - 1]
    if prev.is_op("+", "-") and not _ends_operand(tokens[idx - 2]):
        prev = tokens[idx - 2]
    nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
    return prev.is_op(*_ELEMENT_BEFORE) and nxt is not None and nxt.is_op(*_ELEMENT_AFTER)


def _first_name(tokens: list[Token], colon: int) -> str:
    """The first name of `A, B : ...`, given the index of its colon."""
    j = colon - 1
    while j >= 2 and tokens[j - 1].is_op(",") and tokens[j - 2].kind == "id":
        j -= 2
    return tokens[j].text


def _declared_name(tokens: list[Token], idx: int) -> str | None:
    """The name after `function`, `package body`, `task type` and the like."""
    j = idx + 1
    while j < len(tokens) and tokens[j].is_kw("body", "type"):
        j += 1
    if j >= len(tokens) or tokens[j].kind not in ("id", "str"):
        return None
    if tokens[j].kind == "str":
        return f'"{tokens[j].text}"'
    parts = [tokens[j].text]
    while j + 2 < len(tokens) and tokens[j + 1].is_op(".") and tokens[j + 2].kind == "id":
        parts.append(tokens[j + 2].text)
        j += 2
    return ".".join(parts)


def _is_operator_symbol(tokens: list[Token], idx: int) -> bool:
    """A string that names an operator (`function "="`, `Pkg."+"`)."""
    prev = tokens[idx - 1] if idx else None
    nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
    if prev is not None and (prev.is_kw("function", "renames") or prev.is_op(".")):
        return True
    return nxt is not None and nxt.is_op("(")


def count_literal_metrics(
    tokens: list[Token], unit_at_line: dict[int, str], metrics: tuple[str, ...]
) -> dict[tuple[str, str], int]:
    """R13-R15: bare literals per (unit, metric).

    A literal in a pragma or a type declaration is named by it.  A
    numeral in a constant is named unless the constant is computed (see
    _named_by_constant); a character or a string in a constant is always
    named.  Everywhere else a literal is logic, and fires unless it is a
    0/1 idiom, a dimension selector, the blank of a fill, or "".

    The unit is the innermost subprogram body around the literal; at
    library level, the constant, object, type or subprogram being
    declared.
    """
    kinds = _bracket_kinds(tokens)
    frames: list[int] = []
    decls: list[_Decl] = []
    header = "<file>"
    found: dict[tuple[str, str], int] = {}
    for idx, tok in enumerate(tokens):
        prev = tokens[idx - 1] if idx else None
        nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
        if tok.kind == "op":
            if tok.is_op("(", "["):
                frames.append(idx)
            elif tok.is_op(")", "]"):
                if frames:
                    frames.pop()
                while decls and decls[-1].kind != "record" and decls[-1].depth > len(frames):
                    decls.pop()
            elif tok.is_op(";"):
                while decls and decls[-1].kind != "record" and decls[-1].depth >= len(frames):
                    decls.pop()
            elif tok.is_op(":="):
                if decls and decls[-1].assign is None and decls[-1].depth == len(frames):
                    decls[-1].assign = idx
            elif tok.is_op(":") and prev is not None and prev.kind == "id":
                j = idx + 1
                while j < len(tokens) and tokens[j].is_kw("aliased"):
                    j += 1
                if j < len(tokens) and tokens[j].is_kw("constant"):
                    #  Only a declaration at library level names a unit;
                    #  one inside an expression belongs to that expression's
                    #  subprogram.
                    name = header if frames else _first_name(tokens, idx)
                    decls.append(_Decl("constant", len(frames), name))
                elif not frames and not (decls and decls[-1].kind in ("record", "pragma", "type")):
                    decls.append(_Decl("object", 0, _first_name(tokens, idx)))
            continue
        if tok.kind == "kw":
            if tok.is_kw("pragma"):
                decls.append(_Decl("pragma", len(frames), header))
            elif tok.is_kw("type", "subtype") and not (prev is not None and prev.is_kw("use")):
                if nxt is not None and nxt.kind == "id":
                    header = nxt.text
                decls.append(_Decl("type", len(frames), header))
            elif tok.is_kw("record"):
                if prev is not None and prev.is_kw("end"):
                    if decls and decls[-1].kind == "record":
                        decls.pop()
                elif not (prev is not None and prev.is_kw("null")):
                    if decls and decls[-1].kind == "type":
                        decls[-1] = _Decl("record", decls[-1].depth, decls[-1].name)
            elif tok.is_kw("function", "procedure", "entry", "package", "task", "protected"):
                header = _declared_name(tokens, idx) or header
            continue
        metric = _METRIC_OF_KIND.get(tok.kind)
        if metric is None or metric not in metrics:
            continue
        if tok.kind == "str" and _is_operator_symbol(tokens, idx):
            continue
        context = decls[-1] if decls else None
        if context is not None and context.kind in ("pragma", "type"):
            continue
        if context is not None and context.kind == "constant":
            if tok.kind != "num" or _named_by_constant(tokens, idx, context, frames, kinds):
                continue
        if tok.kind == "num" and _allowed_numeral(tokens, idx):
            continue
        if tok.kind == "chr" and _is_fill(tokens, idx):
            continue
        if tok.kind == "str" and tok.text == "":
            continue
        unit = unit_at_line.get(tok.line) or (context.name if context is not None else header)
        found[(unit, metric)] = found.get((unit, metric), 0) + 1
    return found


def statement_tokens(tokens: list[Token], token_lines: list[int], body: Body) -> list[Token]:
    """The tokens of a body's statements: after its begin, before its end."""
    if body.begin is None or body.end is None:
        return []
    lo = bisect.bisect_right(token_lines, body.begin)
    hi = bisect.bisect_left(token_lines, body.end)
    inner = [(b.header, b.end) for b in body.inner if b.end is not None]
    return [t for t in tokens[lo:hi] if not any(a <= t.line <= z for a, z in inner)]


def _leading_guard(region: list[Token]) -> bool:
    """The statements start with `if C then return [X]; end if;`.

    Nothing else may sit in that if: no second statement, no elsif and
    no else.  An `and then` or `or else` inside C or X is part of an
    expression, not a branch.
    """
    if not region or not region[0].is_kw("if"):
        return False
    paren = 0
    then_at = None
    for idx, tok in enumerate(region):
        if tok.is_op("(", "["):
            paren += 1
        elif tok.is_op(")", "]"):
            paren -= 1
        elif paren == 0 and tok.is_kw("then") and not region[idx - 1].is_kw("and"):
            then_at = idx
            break
    if then_at is None or then_at + 1 >= len(region) or not region[then_at + 1].is_kw("return"):
        return False
    paren = 0
    for idx in range(then_at + 1, len(region)):
        tok = region[idx]
        if tok.is_op("(", "["):
            paren += 1
        elif tok.is_op(")", "]"):
            paren -= 1
        elif paren == 0 and tok.is_kw("do"):
            return False
        elif paren == 0 and tok.is_op(";"):
            tail = region[idx + 1 : idx + 4]
            return (
                len(tail) == 3
                and tail[0].is_kw("end")
                and tail[1].is_kw("if")
                and tail[2].is_op(";")
            )
    return False


def count_blocks(region: list[Token]) -> int:
    """R16: the blocks at the top level of one statement sequence.

    An if, a case, a loop (for, while or bare), a declare block, a bare
    begin block and an extended return each open one.  A `for` or
    `while` and its `loop` are one block, as are a `declare` and its
    `begin`, and a case is one block whatever its arms hold.  Words
    inside parentheses belong to expressions (if, case, quantified and
    declare expressions), not to statements, and never count.  One
    leading early-exit guard (_leading_guard) does not count.
    """
    count = 0
    level = 0
    paren = 0
    loop_pending = False
    begin_pending = False
    closer_word = -1
    for idx, tok in enumerate(region):
        if tok.is_op("(", "["):
            paren += 1
            continue
        if tok.is_op(")", "]"):
            paren -= 1
            continue
        if paren or tok.kind != "kw" or idx == closer_word:
            continue
        if tok.is_kw("end"):
            #  `end if`, `end loop` and the like close one block; so do
            #  `end;` and `end Name;`, which have no word to skip.
            nxt = region[idx + 1] if idx + 1 < len(region) else None
            if nxt is not None and nxt.is_kw("if", "case", "loop", "return", "select", "record"):
                closer_word = idx + 1
            level = max(0, level - 1)
            continue
        opens = tok.is_kw("if", "case", "declare", "for", "while", "do", "select")
        if tok.is_kw("loop"):
            opens = not loop_pending
            loop_pending = False
        elif tok.is_kw("begin"):
            opens = not begin_pending
            begin_pending = False
        if tok.is_kw("for", "while"):
            loop_pending = True
        elif tok.is_kw("declare"):
            begin_pending = True
        if opens:
            if level == 0:
                count += 1
            level += 1
    if count and _leading_guard(region):
        count -= 1
    return count


#  The waiver reason that marks a named table.  A function that is only
#  a case over its parameter, each arm a table value, IS the naming the
#  literal rules ask for: the enumeration value names each literal.  Its
#  waiver stays for good, may only shrink, and is valid only on a unit
#  the lint itself recognizes as such a table.
TABLE_REASON = "enum-indexed table"


def _table_value(value: list[Token]) -> bool:
    """A literal, a plain name, or several of them joined by `&`."""
    expect_term = True
    i = 0
    while i < len(value):
        tok = value[i]
        if expect_term:
            if tok.kind in ("num", "chr", "str"):
                i += 1
            elif tok.kind == "id":
                i += 1
                while i + 1 < len(value) and value[i].is_op(".") and value[i + 1].kind == "id":
                    i += 2
            else:
                return False
            expect_term = False
        else:
            if not tok.is_op("&"):
                return False
            expect_term = True
            i += 1
    return bool(value) and not expect_term


def _split_at_depth_zero(tokens: list[Token], stops: tuple[str, ...]) -> list[list[Token]]:
    """tokens cut at every stop delimiter outside brackets."""
    parts: list[list[Token]] = [[]]
    depth = 0
    for tok in tokens:
        if tok.is_op("(", "["):
            depth += 1
        elif tok.is_op(")", "]"):
            depth -= 1
        if depth == 0 and tok.kind == "op" and tok.text in stops:
            parts.append([])
            continue
        parts[-1].append(tok)
    return parts


def _named_choices(choices: list[Token]) -> bool:
    """A case arm's choices are names only: `A`, `A | B`, `Pkg.A`, `others`.

    A literal choice (`when 1`, `when 'a'`) is a threshold or a
    character, not a value the enumeration names, so an arm with one
    makes its function no table.
    """
    if not choices:
        return False
    for choice in _split_at_depth_zero(choices, ("|",)):
        if len(choice) == 1 and choice[0].is_kw("others"):
            continue
        if not choice or choice[0].kind != "id" or len(choice) % 2 == 0:
            return False
        for k, tok in enumerate(choice):
            if k % 2 == 0 and tok.kind != "id":
                return False
            if k % 2 == 1 and not tok.is_op("."):
                return False
    return True


def _table_arms(arms: list[Token], statement: bool) -> bool:
    """Whether every `when` arm after a case's `is` yields a table value.

    statement: the arms are `when C => return V;` and end `end case;`.
    Otherwise they are the expression form, `when C => V, ...`.
    """
    if statement:
        if len(arms) < 3 or not (
            arms[-3].is_kw("end") and arms[-2].is_kw("case") and arms[-1].is_op(";")
        ):
            return False
        pieces = [p for p in _split_at_depth_zero(arms[:-3], (";",)) if p]
    else:
        pieces = _split_at_depth_zero(arms, (",",))
    if not pieces:
        return False
    for piece in pieces:
        if not piece[0].is_kw("when"):
            return False
        arrow = next((k for k, t in enumerate(piece) if t.is_op("=>")), None)
        if arrow is None or not _named_choices(piece[1:arrow]):
            return False
        value = piece[arrow + 1 :]
        if statement:
            if not value or not value[0].is_kw("return"):
                return False
            value = value[1:]
        if not _table_value(value):
            return False
    return True


def _case_arms(tokens: list[Token]) -> list[Token] | None:
    """The tokens after `case X is`, when tokens start with that case."""
    if not tokens or not tokens[0].is_kw("case"):
        return None
    for k, tok in enumerate(tokens):
        if tok.is_kw("is"):
            return tokens[k + 1 :]
    return None


def enum_tables(lines: list[str]) -> set[str]:
    """The functions in one file that are named tables, lowercased.

    A table is a function that is only a case over its parameter: a
    body with no declarations whose statements are one case statement,
    each arm `return V;`, or an expression function whose expression is
    one case expression.  Every choice is a name (_named_choices), and
    every arm's V is a literal, a name, or several joined by `&`.  The
    lint cannot see that the case selects on an enumeration; a case
    over any discrete value with named choices passes this test.
    """
    tokens = tokenize("\n".join(lines))
    token_lines = [t.line for t in tokens]
    tables: set[str] = set()
    for body, _ in walk(find_bodies(lines)):
        if body.kind != "function" or body.begin is None:
            continue
        header = [t for t in tokens if body.header <= t.line < body.begin]
        is_at = next((k for k, t in enumerate(header) if t.is_kw("is")), None)
        if is_at is None or is_at != len(header) - 1:
            continue
        arms = _case_arms(statement_tokens(tokens, token_lines, body))
        if arms is not None and _table_arms(arms, statement=True):
            tables.add(body.name.lower())
    for idx, tok in enumerate(tokens):
        if not tok.is_kw("function"):
            continue
        name = _declared_name(tokens, idx)
        depth = 0
        j = idx + 1
        while j < len(tokens):
            if tokens[j].is_op("(", "["):
                depth += 1
            elif tokens[j].is_op(")", "]"):
                depth -= 1
            elif depth == 0 and (tokens[j].is_kw("is") or tokens[j].is_op(";")):
                break
            j += 1
        if name is None or j + 1 >= len(tokens) or not tokens[j].is_kw("is"):
            continue
        if not tokens[j + 1].is_op("("):
            continue
        close = _matching_close(tokens, j + 1)
        arms = _case_arms(tokens[j + 2 : close])
        if arms is not None and _table_arms(arms, statement=False):
            tables.add(name.lower())
    return tables


def misused_table_waivers(
    waived: dict[tuple[str, str, str], tuple[int, str]], tables: dict[str, set[str]]
) -> list[tuple[str, str, str]]:
    """Waivers that give the table reason to something that is not one.

    The reason is valid only on a literal metric of a unit that
    enum_tables recognizes in that file.
    """
    bad: list[tuple[str, str, str]] = []
    for key, (_, reason) in waived.items():
        if not reason.lower().startswith(TABLE_REASON):
            continue
        path, unit, metric = key
        if metric not in LITERAL_METRICS or unit not in tables.get(path, set()):
            bad.append(key)
    return sorted(bad)


def check_waivers(
    findings: list[Finding],
    waived: dict[tuple[str, str, str], tuple[int, str]],
    tables: dict[str, set[str]],
    waiver_name: str,
) -> list[str]:
    """The gate's failure report, one printed line each; empty when it passes.

    A waiver must equal what the tree carries.  It fails when:
      - a finding has no waiver (new debt);
      - a finding is above its waiver (the debt has grown);
      - a finding is below its waiver (slack a later change could grow
        back into unseen: lower the waiver to the new count);
      - a waiver has no finding (stale: drop it);
      - a waiver gives the table reason to a unit that is not a table.
    """
    by_key = {f.key: f for f in findings}
    unwaived = sorted((f for f in findings if f.key not in waived), key=lambda f: (f.path, f.unit))
    grown = sorted(
        (f for f in findings if f.key in waived and f.value > waived[f.key][0]),
        key=lambda f: (f.path, f.unit),
    )
    loose = sorted(
        (f for f in findings if f.key in waived and f.value < waived[f.key][0]),
        key=lambda f: (f.path, f.unit),
    )
    stale = sorted(key for key in waived if key not in by_key)
    misused = misused_table_waivers(waived, tables)

    out: list[str] = []
    if unwaived:
        out += ["", "FAIL: shapes over a limit with no waiver.  Split them, or"]
        out.append(f"      record each in {waiver_name} with a reason:")
        for finding in unwaived:
            rule = RULE_OF[finding.metric]
            out.append(f"  {finding.line()}   ({rule}, limit {LIMITS[finding.metric]})")
    if grown:
        out += ["", "FAIL: waived shapes that have GROWN -- a waiver may only shrink:"]
        for finding in grown:
            out.append(f"  {finding.line()}  (waived at {waived[finding.key][0]})")
    if loose:
        out += ["", "FAIL: waived shapes that have SHRUNK -- a waiver must equal the tree:"]
        for finding in loose:
            out.append(
                f"  {finding.line()}  (waived at {waived[finding.key][0]};"
                f" lower the waiver to {finding.value})"
            )
    if stale:
        out += ["", "FAIL: waivers for shapes that no longer violate -- drop them:"]
        for path_, unit, metric in stale:
            out.append(f"  {path_:<58} {unit:<28} {metric}")
    if misused:
        out += ["", f'FAIL: "{TABLE_REASON}" on a unit that is not one (a function that is']
        out.append("      only a case over its parameter, a name per choice, a literal per arm):")
        for path_, unit, metric in misused:
            out.append(f"  {path_:<58} {unit:<28} {metric}")
    return out


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


def in_carryover_scope(rel: str) -> bool:
    """Whether R12 reads this repo-relative path."""
    if rel.startswith(CARRYOVER_EXEMPT):
        return False
    return rel in CARRYOVER_FILES or rel.startswith(CARRYOVER_DIRS)


def check_carryover(text: str) -> dict[str, int]:
    """Each carryover token in the text, with how often it appears."""
    found: dict[str, int] = {}
    for token in CARRYOVER_TOKENS:
        count = len(re.findall(re.escape(token), text, re.I))
        if count:
            found[token] = count
    return found


def carryover_findings(root: pathlib.Path, candidates: list[str]) -> list[Finding]:
    """R12 findings over those candidate paths that the rule covers.

    One finding per token and file, counted, so a waiver names the file
    and the token a reader can grep for.
    """
    findings: list[Finding] = []
    for rel in sorted(candidates):
        if not in_carryover_scope(rel):
            continue
        path = root / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for token, count in check_carryover(text).items():
            findings.append(Finding(rel, token, "carryover", count))
    return findings


def carryover_candidates(root: pathlib.Path) -> list[str]:
    """Every tracked or new file under the covered paths.

    Git's own list, not a directory walk: build output and the local
    notes that .gitignore excludes are not part of the repository, and
    a walk would read them.
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            *CARRYOVER_DIRS,
            *CARRYOVER_FILES,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"shape-check: git ls-files failed: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


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
    tokens = tokenize(text)
    token_lines = [t.line for t in tokens]
    unit_at_line: dict[int, str] = {}

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
        blocks = count_blocks(statement_tokens(tokens, token_lines, body))
        if blocks > LIMITS["blocks"]:
            findings.append(Finding(rel, body.name, "blocks", blocks))
        #  Outer bodies come first, so an inner body's lines end up
        #  attributed to the inner body.
        if body.end is not None:
            for number in range(body.header, body.end + 1):
                unit_at_line[number] = body.name

    for name, header in find_declarations(lines):
        if name.lower() in in_spec:
            continue
        params, outs, bools = parse_params(header)
        for metric, value in zip(PROFILE_METRICS, (params, outs, bools)):
            if value > LIMITS[metric]:
                findings.append(Finding(rel, name, metric, value))

    literal_counts = count_literal_metrics(tokens, unit_at_line, literal_metrics_for(rel))
    for (unit, metric), count in literal_counts.items():
        findings.append(Finding(rel, unit, metric, count))

    if rel.endswith(".adb"):
        for alias, literal in check_aliases(lines):
            findings.append(Finding(rel, alias, "alias", 1))

    for foreign in check_foreign(lines):
        findings.append(Finding(rel, foreign, "foreign", 1))

    for date, count in check_dated(lines).items():
        findings.append(Finding(rel, date, "dated", count))

    return findings


def canonical(findings: list[Finding]) -> list[Finding]:
    """One finding per (file, unit, metric).

    A file may declare the same name twice -- an overload, or the same
    nested helper in two frames -- and a waiver names a unit, not a
    line.  Collapsing here keeps the waiver file one line per waivable
    thing, so a count in the report and a count in the file agree.  A
    shape keeps its worst value; a count (COUNT_METRICS) keeps the sum.
    """
    merged: dict[tuple[str, str, str], Finding] = {}
    for finding in findings:
        seen = merged.get(finding.key)
        if seen is None:
            merged[finding.key] = finding
        elif finding.metric in COUNT_METRICS:
            merged[finding.key] = Finding(
                seen.path, seen.unit, seen.metric, seen.value + finding.value
            )
        elif finding.value > seen.value:
            merged[finding.key] = finding
    return list(merged.values())


#  The directories this lint measures.  Adding a source tree (an example
#  binary, a shell layer) means adding its glob here.
SOURCE_DIRS: tuple[str, ...] = ("src", "tests/src", "proof/src", "example/src")


def sources(root: pathlib.Path) -> list[pathlib.Path]:
    found: list[pathlib.Path] = []
    for rel in SOURCE_DIRS:
        base = root / rel
        if base.is_dir():
            found.extend(p for p in base.rglob("*.ad[sb]") if p.is_file())
    return sorted(found)


def read_waivers(path: pathlib.Path) -> dict[tuple[str, str, str], tuple[int, str]]:
    """Known violations, each with the value it may reach and its reason."""
    out: dict[tuple[str, str, str], tuple[int, str]] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=4)
        if len(parts) < 4:
            continue
        path_, unit, metric, value = parts[0], parts[1], parts[2], parts[3]
        reason = parts[4] if len(parts) > 4 else ""
        out[(path_, unit.lower(), metric)] = (int(value), reason)
    return out


WAIVER_HEADER = """\
#  Shapes knowingly over a limit, and why each one is still here.
#
#  This file is the reason `make shape` can stay ON.  Each value must
#  EQUAL what the tree carries.  A violation that is not listed here
#  fails the build; a listed one whose value has GROWN fails; one whose
#  value has SHRUNK fails too, until its line is lowered to the new
#  count; and a line for a shape that no longer violates fails, so the
#  list cannot outlive what it excuses.  A value moves only down, in the
#  same change as the code, and deleting a line is how a refactor cycle
#  gets its RED.
#
#  The limits are this script's LIMITS table.
#
#  --write-waivers rewrote this file from the tree once, to seed the
#  baseline.  Do not run it again to "fix" a failure: regenerating
#  silently absorbs exactly the regressions the gate exists to catch.
#  Lower and delete lines by hand as the shapes they excuse shrink.
#
#  Two reasons are special.  "baseline when the rule landed" marks debt
#  that was already in the tree when its rule arrived; each such line is
#  to go when its unit is next refactored.  "enum-indexed table" marks a
#  function that is only a case over its parameter, every choice a name
#  and one literal per arm: that function IS the naming, so its line
#  stays, and is valid only on a unit the lint recognizes as such a
#  table.
#
#  file                                                       unit                         metric     value  reason
"""

BASELINE_REASON = "baseline when the rule landed"


def write_waivers(
    path: pathlib.Path,
    findings: list[Finding],
    kept: dict[tuple[str, str, str], tuple[int, str]],
    tables: dict[str, set[str]],
) -> None:
    """Rewrite the waiver file from the findings.

    A line that already had a reason keeps it.  A literal finding on a
    recognized table gets the table reason; any other new line gets the
    baseline reason.
    """
    lines = [WAIVER_HEADER]
    for finding in sorted(findings, key=lambda f: (f.path, f.unit.lower(), f.metric)):
        reason = kept.get(finding.key, (0, ""))[1]
        if not reason:
            table_units = tables.get(finding.path, set())
            is_table = finding.metric in LITERAL_METRICS and finding.unit.lower() in table_units
            reason = TABLE_REASON if is_table else BASELINE_REASON
        lines.append(f"{finding.line()}  {reason}\n")
    path.write_text("".join(lines), encoding="utf-8")


SELFTEST_FIXTURE = '''\
package body Shape_Fixture is

   --  R13 must not fire inside a named table, however it wraps: the
   --  table IS the naming, and every literal in it is spoken for.
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

   --  R13: a bare literal carrying a scale nothing names.  The numeral
   --  in the message below is prose and must NOT be counted by R13;
   --  the message itself is one R15 string.
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

   --  R13 again, AFTER the line above.  Reading the `--` as a comment
   --  drops that line's closing paren, so every later `;` looks like it
   --  is inside parentheses, the named-declaration exemption never ends,
   --  and this bare literal is silently excused.  It must fire, and so
   --  must X's default: a default is not a counter reset.
   procedure After_Dashes is
      Limit : constant Integer := 30;
      X     : Integer := 0;
   begin
      X := 900 + Limit;
   end After_Dashes;

   --  R3: four blocks deep, and R4: a body inside a body.  R13 fires
   --  twice: the loop's upper bound and Y's initial value.
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
   function Doubled (N : Integer) return Integer is (N + N);
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
   --  §8 and spec section 2, and ported from some_file.go:41 via
   --  other_file.cpp:12.
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

#  R12: each carryover token once, in code and in a comment, in a file
#  the rule covers.
SELFTEST_CARRYOVER = '''\
--  Ported from cucumber-cpp.
procedure Fixture_Carryover is
begin
   Put ("Example of 'cuke::fail_scenario()'");
   Put ("as std::vector");
   Put ("a context<box> slot");
   Put ("CUKE_DOC_STRING");
end Fixture_Carryover;
'''

#  The same tokens in paths the rule must leave alone: the upstream
#  corpus and the oracle's captures under tests/data/, and a tree the
#  rule does not cover at all.
SELFTEST_CARRYOVER_EXEMPT: tuple[str, ...] = (
    "tests/data/cwt/parser/1_first_scenario.feature",
    "tests/data/golden/11_manual_fails.console.txt",
    "tools/notes.txt",
)


#  The literal rules' fixture: each marked line fires exactly once, and
#  the unmarked ones never.  Grammar_Tokens also holds two top-level
#  blocks (the case and the if), so R16 fires on it with the value 2.
SELFTEST_LITERALS = '''\
package body Literal_Fixture is
   Fence_Length : constant := 3;                       --  no fire: names the literal
   Type_First   : constant Positive := Start + 3;      --  lit_num: computed constant
   procedure Grammar_Tokens (C : Character) is
   begin
      case C is
         when '@' => null;                               --  lit_char: after reserved word
         when others => null;
      end case;
      if Line (I + 2) = Line (I) then null; end if;      --  lit_num
      Put (B, "Value ");                                 --  lit_str: message fragment
      Put (B, ESC & "[32m");                             --  lit_str: ANSI code in logic
      Put (B, Character'('"'));                          --  lit_char once; the tick must not open a string
      X := X + 1;                                        --  no fire: step idiom
      Buf := [others => ' '];                            --  no fire: fill
      Ok := S = "";                                      --  no fire: empty text
      Log ("gave up after 503 retries -- live");         --  lit_str once; numeral and `--` stay inside
   end Grammar_Tokens;
end Literal_Fixture;
'''

#  What a constant names and what it does not, the idioms read as
#  tokens, and where a finding is attributed.  Each line says what it
#  must do.
SELFTEST_CONSTANTS = '''\
package body Constant_Fixture is
   Table  : constant array (Kind) of Natural := [A => 7, B => 8];  --  no fire: a named table
   Signed : constant := -4;                                        --  no fire: a signed literal
   Padded : constant String := Pad ("x", 12);                      --  lit_num: a call argument
   Sized  : constant String (1 .. 12) := Make;                     --  lit_num: a subtype bound
   Label  : constant String := "none";                             --  no fire: a string in a constant
   type Small is range 0 .. 99;                                    --  no fire: a type
   subtype Digit is Character range '0' .. '9';                    --  no fire: a subtype
   type Cell is record
      Width : Natural := 5;                                        --  lit_num: a component default
   end record;
   function "=" (L, R : Cell) return Boolean is (L.Width = R.Width);  --  no fire: an operator symbol
   function Probe (H : Handle; Items : List) return Boolean
   is (declare
         Next : constant Natural := H + 4;                         --  lit_num, on Probe: computed
       begin
         Items'Length = 0                                          --  no fire: a length is empty
         and then Items.Count > 0                                  --  no fire: a count is not
         and then H /= 0                                           --  lit_num: a handle, not a count
         and then Items'First (2) = Next                           --  no fire: a dimension
         and then Character'Val (9) = ASCII.HT);                   --  lit_num: a value
   procedure Reset (N : out Natural; M : out Natural) is
      pragma Warnings (Off, "unused");                             --  no fire: a pragma
      Start : Natural := 0;                                        --  lit_num: a default is no reset
      First : Positive := 1;                                       --  lit_num: 1 is no idiom here
   begin
      N := Start + First;
      Put ([1 .. N => ' ']);                                       --  lit_char: only others fills
   end Reset;
end Constant_Fixture;
'''

SELFTEST_CONSTANTS_EXPECTED: dict[tuple[str, str], int] = {
    ("padded", "lit_num"): 1,
    ("sized", "lit_num"): 1,
    ("cell", "lit_num"): 1,
    ("probe", "lit_num"): 3,
    ("reset", "lit_num"): 2,
    ("reset", "lit_char"): 1,
}

#  The 0/1 idioms at their edges.  A reset is a STATEMENT whose target's
#  last name is a count word (Count, Length, Len, Used, standing alone or
#  after an underscore); a default, a handle, a status and a name that
#  only ends in those letters all fire.  The emptiness test reads the
#  same word test.
SELFTEST_IDIOMS = '''\
package body Idiom_Fixture is
   procedure Resets is
   begin
      Item_Count := 0;                                  --  no fire: a counter reset
      Doc.Rules_Used := 0;                              --  no fire: through a selector
      Line.Len := 0;                                    --  no fire
      H := 0;                                           --  lit_num: a handle
      Status_Code := 0;                                 --  lit_num: a status
      Excused := 0;                                     --  lit_num: "used" is no word here
      Discount := 0;                                    --  lit_num: "count" is no word here
   end Resets;

   procedure Defaults (Retries : Integer := 0) is      --  lit_num: a parameter default
      Count : Tag_Count := 0;                           --  lit_num: an object default
   begin
      null;
   end Defaults;

   function Empties (Text : String) return Boolean
   is (Excused = 0                                      --  lit_num: not a count
       and then Item_Count = 0                          --  no fire
       and then Len = 0                                 --  no fire
       and then Text'Length = 0                         --  no fire
       and then Discount > 0);                          --  lit_num: not a count
end Idiom_Fixture;
'''

SELFTEST_IDIOMS_EXPECTED: dict[tuple[str, str], int] = {
    ("resets", "lit_num"): 4,
    ("defaults", "lit_num"): 2,
    ("empties", "lit_num"): 2,
}

#  The tokenizer's traps, each on one line: ticks that are attributes
#  or qualifications, a character literal after a reserved word, a
#  comment marker and a numeral inside a string, a numeral in a
#  comment, the quote and the tick as character literals, and a
#  reserved word read as an attribute name.
SELFTEST_TOKENS = """\
X := T'(A => 1) & C'First & C'Image (N);  --  42 in a comment
when '(' => Put ("a -- b 7");
Y := '"' & ''' & Q'Range;
"""

SELFTEST_TOKENS_EXPECTED: list[tuple[str, str]] = [
    ("id", "X"), ("op", ":="), ("id", "T"), ("op", "'"), ("op", "("),
    ("id", "A"), ("op", "=>"), ("num", "1"), ("op", ")"), ("op", "&"),
    ("id", "C"), ("op", "'"), ("id", "First"), ("op", "&"), ("id", "C"),
    ("op", "'"), ("id", "Image"), ("op", "("), ("id", "N"), ("op", ")"),
    ("op", ";"),
    ("kw", "when"), ("chr", "("), ("op", "=>"), ("id", "Put"), ("op", "("),
    ("str", "a -- b 7"), ("op", ")"), ("op", ";"),
    ("id", "Y"), ("op", ":="), ("chr", '"'), ("op", "&"), ("chr", "'"),
    ("op", "&"), ("id", "Q"), ("op", "'"), ("id", "Range"), ("op", ";"),
]

#  R16: each body marked 2 fires once with that value; every other
#  body holds one block or none and must not fire.  No literal here
#  fires, so the only findings are blocks.
SELFTEST_BLOCKS = '''\
package body Block_Fixture is

   --  Two blocks side by side: 2.
   procedure Two_Blocks (N : Integer) is
   begin
      if Ready then
         Put (N);
      end if;
      for I in 1 .. N loop
         Put (I);
      end loop;
   end Two_Blocks;

   --  A while whose condition wraps onto its own loop line is one
   --  block, and a declare with its begin is one more: 2.
   procedure Wrapped_Loop (N : Integer) is
   begin
      while Ready
        and then Steady
      loop
         Put (N);
      end loop;
      declare
         M : constant Integer := N;
      begin
         Put (M);
      end;
   end Wrapped_Loop;

   --  One leading early-exit guard is exempt: 1, no finding.
   function Guarded (N : Integer) return Integer is
   begin
      if Done then
         return N;
      end if;
      for I in 1 .. N loop
         Put (I);
      end loop;
      return N;
   end Guarded;

   --  `or else` in a guard's condition is not an else branch: 1.
   function Or_Else_Guard (N : Integer) return Integer is
   begin
      if Done or else Stale then
         return N;
      end if;
      loop
         exit when Ready;
      end loop;
      return N;
   end Or_Else_Guard;

   --  Only the first guard is exempt; the second is a block: 2.
   procedure Two_Guards (N : Integer) is
   begin
      if Done then
         return;
      end if;
      if Stale then
         return;
      end if;
      Outer : loop
         exit Outer when Ready;
      end loop Outer;
   end Two_Guards;

   --  A guard that does more than return is a block: 2.
   procedure Busy_Guard (N : Integer) is
   begin
      if Done then
         Put (N);
         return;
      end if;
      case Mode is
         when Fast =>
            Put (N);
         when others =>
            null;
      end case;
   end Busy_Guard;

   --  A named block ends `end Name;`; the if after it still counts: 2.
   procedure Named_Block (N : Integer) is
   begin
      Inner : declare
         M : constant Integer := N;
      begin
         Put (M);
      end Inner;
      if Ready then
         Put (N);
      end if;
   end Named_Block;

   --  A guard with an else branch is a block: 2.
   procedure Guard_With_Else (N : Integer) is
   begin
      if Done then
         return;
      else
         Put (N);
      end if;
      loop
         exit when Ready;
      end loop;
   end Guard_With_Else;

   --  A guard after another statement is not leading: 2.
   procedure Late_Guard (N : Integer) is
   begin
      Put (N);
      if Done then
         return;
      end if;
      while Ready loop
         Put (N);
      end loop;
   end Late_Guard;

   --  A dispatch: one case, blocks inside its arms.  A case counts
   --  once, whatever its arms hold: 1, no finding.
   procedure Dispatch (K : Kind) is
   begin
      case K is
         when First_Kind =>
            if Ready then
               Put (K);
            end if;
            for I in 1 .. Width loop
               Put (I);
            end loop;
         when others =>
            null;
      end case;
   end Dispatch;

   --  Expressions are not blocks: a quantified expression, an if
   --  expression, a case expression, and `and then` / `or else` in a
   --  condition.  One block, the if statement: no finding.
   function Expressions_Only (N : Integer) return Boolean is
   begin
      pragma Assert (for all I in 1 .. N => Valid (I));
      Put ((if Ready then N else Width));
      if (Ready and then Steady) or else Done then
         Put (N);
      end if;
      return (case Mode is when Fast => True, when others => False);
   end Expressions_Only;

end Block_Fixture;
'''

SELFTEST_BLOCKS_EXPECTED: dict[tuple[str, str], int] = {
    ("two_blocks", "blocks"): 2,
    ("wrapped_loop", "blocks"): 2,
    ("two_guards", "blocks"): 2,
    ("busy_guard", "blocks"): 2,
    ("named_block", "blocks"): 2,
    ("guard_with_else", "blocks"): 2,
    ("late_guard", "blocks"): 2,
}

#  Two bodies with one name: their counts add up, so a second overload
#  cannot grow under the first one's waiver.
SELFTEST_OVERLOADS = '''\
package body Overload_Fixture is
   procedure Put (N : Integer) is
   begin
      Log ("one");
      if Ready then Log (N); end if;
      if Steady then Log (N); end if;
   end Put;
   procedure Put (S : String) is
   begin
      Log ("two");
      if Ready then Log (S); end if;
      if Steady then Log (S); end if;
   end Put;
end Overload_Fixture;
'''

#  Named tables: Spelling (a case statement) and Code (a case
#  expression) are tables; Width computes in an arm, and Label declares
#  something before its case, so neither is one.
SELFTEST_TABLES = '''\
package body Table_Fixture is
   function Spelling (K : Kind) return String is
   begin
      case K is
         when A =>
            return "a";
         when B | C =>
            return "<" & Name & ">";
      end case;
   end Spelling;

   function Code (S : Style) return String
   is (case S is
         when Plain  => "",
         when Passed => ESC & "[32m");

   function Width (K : Kind) return Natural is
   begin
      case K is
         when A =>
            return Size (K) + 1;
         when others =>
            return 0;
      end case;
   end Width;

   function Label (K : Kind) return String is
      Prefix : constant String := "k";
   begin
      case K is
         when others =>
            return Prefix & "x";
      end case;
   end Label;

   --  A choice that is a literal is a threshold, not a name: no table.
   function Threshold_For (Score : Integer) return Integer is
   begin
      case Score is
         when 1 =>
            return 10;
         when 2 =>
            return 20;
         when others =>
            return 99;
      end case;
   end Threshold_For;

   function Glyph (C : Character) return String
   is (case C is
         when 'a' | 'b' => "letter",
         when others    => "other");
end Table_Fixture;
'''


def _exact(label: str, got: dict, want: dict, failures: list[str]) -> None:
    """Record every key whose count differs, both ways."""
    for key in sorted(set(got) | set(want)):
        if got.get(key) != want.get(key):
            failures.append(
                f"{label}: {key[0]} {key[1]}: expected {want.get(key)}, got {got.get(key)}"
            )


def _findings_of(tmp: str, rel: str, text: str) -> dict[tuple[str, str], int]:
    """Every finding one fixture produces, collapsed as the gate does."""
    path = pathlib.Path(tmp) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return {(f.unit.lower(), f.metric): f.value for f in canonical(analyze_file(path, rel))}


def selftest() -> int:
    """Prove each rule fires on a fixture written to violate it once."""
    import tempfile

    failures: list[str] = []

    with tempfile.TemporaryDirectory() as tmp:
        #  Exact: every rule's findings on this fixture, and nothing
        #  more, so a rule that starts firing here fails too.
        got = _findings_of(tmp, "shape_fixture.adb", SELFTEST_FIXTURE)
        _exact(
            "shape fixture",
            got,
            {
                ("over_profile", "params"): 6,
                ("over_profile", "outs"): 3,
                ("over_profile", "bools"): 1,
                ("bare_literal", "lit_num"): 1,
                ("bare_literal", "lit_str"): 1,
                ("dashes_in_a_message", "lit_str"): 1,
                ("after_dashes", "lit_num"): 2,
                ("declared_only", "params"): 6,
                ("declared_only", "outs"): 3,
                ("declared_only", "bools"): 1,
                ("both", "bools"): 1,
                ("deep", "depth"): 4,
                ("deep", "lit_num"): 2,
                ("inner", "nested"): 1,
            },
            failures,
        )

        literal_want = {
            ("type_first", "lit_num"): 1,
            ("grammar_tokens", "lit_num"): 1,
            ("grammar_tokens", "lit_char"): 2,
            ("grammar_tokens", "lit_str"): 3,
            ("grammar_tokens", "blocks"): 2,
        }
        got = _findings_of(tmp, "src/literal_fixture.adb", SELFTEST_LITERALS)
        _exact("literal fixture", got, literal_want, failures)
        totals = {
            metric: sum(v for (_, m), v in got.items() if m == metric)
            for metric in LITERAL_METRICS
        }
        if totals != {"lit_num": 2, "lit_char": 2, "lit_str": 3}:
            failures.append(f"literal fixture totals: got {totals}")

        #  A test's expected values are its fixture data: no literal rule
        #  reads tests/src/, and every other rule still does.
        got = _findings_of(tmp, "tests/src/literal_fixture.adb", SELFTEST_LITERALS)
        _exact(
            "literal fixture under tests/src",
            got,
            {("grammar_tokens", "blocks"): 2},
            failures,
        )

        got = _findings_of(tmp, "src/constant_fixture.adb", SELFTEST_CONSTANTS)
        _exact("constant fixture", got, SELFTEST_CONSTANTS_EXPECTED, failures)

        tokens = [(t.kind, t.text) for t in tokenize(SELFTEST_TOKENS)]
        if tokens != SELFTEST_TOKENS_EXPECTED:
            failures.append(f"tokenizer: got {tokens}")

        got = _findings_of(tmp, "src/block_fixture.adb", SELFTEST_BLOCKS)
        _exact("block fixture", got, SELFTEST_BLOCKS_EXPECTED, failures)

        got = _findings_of(tmp, "src/overload_fixture.adb", SELFTEST_OVERLOADS)
        _exact(
            "overload fixture",
            got,
            {("put", "lit_str"): 2, ("put", "blocks"): 4},
            failures,
        )

        tables = enum_tables(SELFTEST_TABLES.split("\n"))
        if tables != {"spelling", "code"}:
            failures.append(f"enum tables: expected {{spelling, code}}, got {tables}")
        misused = misused_table_waivers(
            {
                ("src/t.adb", "spelling", "lit_str"): (2, TABLE_REASON),
                ("src/t.adb", "width", "lit_num"): (2, TABLE_REASON),
                ("src/t.adb", "width", "blocks"): (2, TABLE_REASON),
                ("src/t.adb", "label", "lit_str"): (1, "seeded baseline"),
                ("src/t.adb", "threshold_for", "lit_num"): (5, TABLE_REASON),
            },
            {"src/t.adb": tables},
        )
        want_misused = [
            ("src/t.adb", "threshold_for", "lit_num"),
            ("src/t.adb", "width", "blocks"),
            ("src/t.adb", "width", "lit_num"),
        ]
        if misused != want_misused:
            failures.append(f"table waivers: expected {want_misused}, got {misused}")

        got = _findings_of(tmp, "src/idiom_fixture.adb", SELFTEST_IDIOMS)
        _exact("idiom fixture", got, SELFTEST_IDIOMS_EXPECTED, failures)

        #  The waiver file must equal the tree: a count above its waiver
        #  has grown, one below it leaves slack a later change could grow
        #  back into unseen, and a waiver with no finding is stale.
        waiver_failures = check_waivers(
            [
                Finding("src/w.adb", "Exact", "lit_num", 3),
                Finding("src/w.adb", "Loose", "lit_num", 2),
                Finding("src/w.adb", "Grown", "lit_num", 4),
                Finding("src/w.adb", "New", "blocks", 2),
            ],
            {
                ("src/w.adb", "exact", "lit_num"): (3, BASELINE_REASON),
                ("src/w.adb", "loose", "lit_num"): (5, BASELINE_REASON),
                ("src/w.adb", "grown", "lit_num"): (1, BASELINE_REASON),
                ("src/w.adb", "gone", "lit_str"): (1, BASELINE_REASON),
            },
            {},
            "shape-waivers",
        )
        text = "\n".join(waiver_failures)
        for needle in (
            Finding("src/w.adb", "New", "blocks", 2).line(),
            f"{Finding('src/w.adb', 'Grown', 'lit_num', 4).line()}  (waived at 1)",
            f"{Finding('src/w.adb', 'Loose', 'lit_num', 2).line()}"
            "  (waived at 5; lower the waiver to 2)",
            "gone",
        ):
            if needle not in text:
                failures.append(f"waiver check: no line says {needle!r}:\n{text}")
        if "exact" in text.lower():
            failures.append(f"waiver check: an exact waiver failed:\n{text}")

        #  R3 reads a body's lines in the order they are written; a
        #  rotation of the same lines is a different, wrong answer.
        for body, _ in walk(find_bodies(SELFTEST_FIXTURE.split("\n"))):
            own = _own_line_numbers(body)
            if own != sorted(own):
                failures.append(f"{body.name}: own lines are not in file order")

        foreign = check_foreign(SELFTEST_FOREIGN.split("\n"))
        if foreign != [
            "PR#436",
            "issue#2",
            "§8",
            "section2",
            "some_file.go:41",
            "other_file.cpp:12",
        ]:
            failures.append(f"foreign check: got {foreign}")

        dated = check_dated(SELFTEST_DATED.split("\n"))
        if dated != {"2026-07-21": 1, "2026-08-19": 2}:
            failures.append(f"dated check: got {dated}")

        engine = pathlib.Path(tmp) / "fixture-engine.adb"
        engine.write_text(SELFTEST_ENGINE, encoding="utf-8")
        aliases = check_aliases(SELFTEST_ENGINE.split("\n"))
        if [a for a, _ in aliases] != ["Conn_Fail"]:
            failures.append(f"alias check: expected [Conn_Fail], got {aliases}")

        covered = "src/fixture_carryover.adb"
        tree = pathlib.Path(tmp) / "carryover"
        for rel in (covered, *SELFTEST_CARRYOVER_EXEMPT):
            path = tree / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(SELFTEST_CARRYOVER, encoding="utf-8")
        carryover = carryover_findings(tree, [covered, *SELFTEST_CARRYOVER_EXEMPT])
        got_carryover = sorted((f.path, f.unit, f.value) for f in carryover)
        want_carryover = sorted((covered, token, 1) for token in CARRYOVER_TOKENS)
        if got_carryover != want_carryover:
            failures.append(
                f"carryover check: expected {want_carryover}, got {got_carryover}"
            )

    if failures:
        print("FAIL: shape_check selftest")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("shape_check selftest: ok (every rule fires its exact count on its fixtures)")
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
    tables: dict[str, set[str]] = {}
    for path in sources(root):
        rel = str(path.relative_to(root))
        findings.extend(analyze_file(path, rel))
        tables[rel] = enum_tables(path.read_text(encoding="utf-8", errors="replace").split("\n"))
    findings.extend(carryover_findings(root, carryover_candidates(root)))
    findings = canonical(findings)

    waiver_path = root / args.waivers
    waived = read_waivers(waiver_path)
    if args.write_waivers:
        write_waivers(waiver_path, findings, waived, tables)
        print(f"wrote {len(findings)} waivers to {args.waivers}")
        return 0

    if not args.quiet:
        print(f"shape-check: {len(findings)} shapes over a limit, {len(waived)} waived")

    failure_lines = check_waivers(findings, waived, tables, str(args.waivers))
    for line in failure_lines:
        print(line)
    if not failure_lines:
        print("shape-check: ok (every shape is within its limit or waived at its exact value)")
    return 1 if failure_lines else 0


if __name__ == "__main__":
    sys.exit(main())
