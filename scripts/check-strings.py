#!/usr/bin/env python3
"""Checks the app's localizations. Standard library only; works with `python3 -I`.

    scripts/check-strings.py [--list-keys]

Checks:
  * every Resources/Localization/*.lproj/Localizable.strings is valid UTF-8 `.strings`
    syntax (`"key" = "value";`, comments allowed) without duplicate keys;
  * en.lproj maps every key to itself (English sentences are the keys, see
    Sources/TapTheTab/App/Localization.swift);
  * every language has exactly the keys of en.lproj;
  * format placeholders (%@, %d, %lld, positional %1$@ ...) are well formed and the same
    per key in every language (same positions and types; order may change only with
    positional placeholders);
  * every `L10n.tr("…")` in Sources/ uses a literal key without interpolation, the key
    exists in en.lproj, and the call passes one argument per placeholder;
  * no SwiftUI initializer or modifier is given a bare string literal
    (`Text("…")`, `Toggle("…", isOn:)`, `.help("…")`, ...): those are looked up as
    LocalizedStringKey in the wrong bundle. Use `L10n.tr` or `Text(verbatim:)`.

Exits 1 when any check fails. `--list-keys` prints the keys found in Sources/ and exits.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALIZATION_DIR = ROOT / "Resources" / "Localization"
SOURCES_DIR = ROOT / "Sources"
TABLE = "Localizable.strings"
DEVELOPMENT_LANGUAGE = "en"

errors = []


def error(where, message):
    errors.append(f"{where}: {message}")


# --- .strings parsing ----------------------------------------------------------------

class StringsSyntaxError(Exception):
    def __init__(self, line, message):
        super().__init__(message)
        self.line = line
        self.message = message


def parse_strings(text):
    """Returns [(key, value, line)] for a `.strings` file; raises StringsSyntaxError."""
    entries = []
    i = 0
    n = len(text)
    line = 1

    def skip_space_and_comments():
        nonlocal i, line
        while i < n:
            c = text[i]
            if c == "\n":
                line += 1
                i += 1
            elif c in " \t\r\ufeff":
                i += 1
            elif text.startswith("/*", i):
                end = text.find("*/", i + 2)
                if end < 0:
                    raise StringsSyntaxError(line, "unterminated /* comment")
                line += text.count("\n", i, end)
                i = end + 2
            elif text.startswith("//", i):
                end = text.find("\n", i)
                i = n if end < 0 else end
            else:
                return

    def read_quoted():
        nonlocal i, line
        if i >= n or text[i] != '"':
            raise StringsSyntaxError(line, 'expected "')
        i += 1
        out = []
        while True:
            if i >= n:
                raise StringsSyntaxError(line, "unterminated string")
            c = text[i]
            if c == '"':
                i += 1
                return "".join(out)
            if c == "\n":
                line += 1
            if c == "\\":
                if i + 1 >= n:
                    raise StringsSyntaxError(line, "dangling backslash")
                e = text[i + 1]
                simple = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "r": "\r", "'": "'"}
                if e in simple:
                    out.append(simple[e])
                    i += 2
                elif e == "U" or e == "u":
                    digits = text[i + 2:i + 6]
                    if not re.fullmatch(r"[0-9A-Fa-f]{4}", digits):
                        raise StringsSyntaxError(line, "bad \\U escape")
                    out.append(chr(int(digits, 16)))
                    i += 6
                else:
                    raise StringsSyntaxError(line, f"unknown escape \\{e}")
                continue
            out.append(c)
            i += 1

    while True:
        skip_space_and_comments()
        if i >= n:
            return entries
        start_line = line
        key = read_quoted()
        skip_space_and_comments()
        if i >= n or text[i] != "=":
            raise StringsSyntaxError(line, "expected = after key")
        i += 1
        skip_space_and_comments()
        value = read_quoted()
        skip_space_and_comments()
        if i >= n or text[i] != ";":
            raise StringsSyntaxError(line, "expected ; after value")
        i += 1
        entries.append((key, value, start_line))


# --- format placeholders -------------------------------------------------------------

PLACEHOLDER = re.compile(
    r"%(?:(?P<percent>%)|(?:(?P<pos>[1-9][0-9]*)\$)?[-+ #0']*[0-9]*(?:\.[0-9]+)?"
    r"(?P<conv>(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]))"
)


def placeholders(s):
    """Returns ({position: conversion}, problems) for a printf-style format string."""
    result = {}
    problems = []
    implicit = 0
    kinds = set()
    i = 0
    while True:
        i = s.find("%", i)
        if i < 0:
            break
        m = PLACEHOLDER.match(s, i)
        if not m:
            problems.append(f"malformed placeholder at {s[i:i + 6]!r}")
            i += 1
            continue
        i = m.end()
        if m.group("percent"):
            continue
        conv = m.group("conv")
        if m.group("pos"):
            kinds.add("positional")
            pos = int(m.group("pos"))
        else:
            kinds.add("sequential")
            implicit += 1
            pos = implicit
        if pos in result and result[pos] != conv:
            problems.append(f"argument {pos} used as both %{result[pos]} and %{conv}")
        result[pos] = conv
    if len(kinds) > 1:
        problems.append("mixes positional and sequential placeholders")
    if result and sorted(result) != list(range(1, max(result) + 1)):
        problems.append(f"placeholder positions {sorted(result)} have gaps")
    return result, problems


def describe(ph):
    return ", ".join(f"{pos}:%{conv}" for pos, conv in sorted(ph.items())) or "none"


# --- Swift scanning ------------------------------------------------------------------

def strip_comments(code):
    """Blanks out // and /* */ comments (keeping newlines) but leaves string literals."""
    out = []
    i = 0
    n = len(code)
    while i < n:
        if code.startswith('"""', i):
            end = code.find('"""', i + 3)
            end = n if end < 0 else end + 3
            out.append(code[i:end])
            i = end
        elif code[i] == '"':
            j = i + 1
            while j < n and code[j] not in '"\n':
                j += 2 if code[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(code[i:j])
            i = j
        elif code.startswith("//", i):
            end = code.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif code.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if code.startswith("/*", j):
                    depth += 1
                    j += 2
                elif code.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            out.append("".join(c if c == "\n" else " " for c in code[i:j]))
            i = j
        else:
            out.append(code[i])
            i += 1
    return "".join(out)


def read_swift_string(code, i):
    """Reads the "…" literal starting at code[i]. Returns (raw_body, end) or None."""
    if code.startswith('"""', i) or code[i] != '"':
        return None
    j = i + 1
    n = len(code)
    while j < n and code[j] not in '"\n':
        j += 2 if code[j] == "\\" else 1
    if j >= n or code[j] != '"':
        return None
    return code[i + 1:j], j + 1


def unescape_swift(raw):
    """Returns (value, problem) for the body of a Swift string literal."""
    if "\\(" in raw:
        return None, "uses string interpolation; pass values as format arguments"
    out = []
    i = 0
    while i < len(raw):
        c = raw[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        e = raw[i + 1:i + 2]
        simple = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "r": "\r", "0": "\0", "'": "'"}
        if e in simple:
            out.append(simple[e])
            i += 2
        elif e == "u":
            m = re.match(r"\\u\{([0-9A-Fa-f]{1,8})\}", raw[i:])
            if not m:
                return None, "bad \\u{} escape"
            out.append(chr(int(m.group(1), 16)))
            i += m.end()
        else:
            return None, f"unknown escape \\{e}"
    return "".join(out), None


def count_call_arguments(code, open_paren):
    """Number of top-level arguments of the call whose '(' is at code[open_paren]."""
    depth = 0
    count = 1
    i = open_paren
    n = len(code)
    while i < n:
        c = code[i]
        if c == '"':
            lit = read_swift_string(code, i)
            if lit is None:
                return None
            i = lit[1]
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return count
        elif c == "," and depth == 1:
            count += 1
        i += 1
    return None


L10N_CALL = re.compile(r"\bL10n\.tr\(")
LOCALIZED_KEY_LITERAL = re.compile(
    r"(?:\b(?:Text|Button|Toggle|Picker|Label|Menu|Link|TextField|SecureField|Section|"
    r"GroupBox|DisclosureGroup|Stepper|ProgressView|LabeledContent)"
    r"|\.(?:help|navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue))"
    r"\(\s*\""
)


def line_of(code, index):
    return code.count("\n", 0, index) + 1


def scan_sources():
    """Returns {key: [(where, argument_count)]} for every L10n.tr call in Sources/."""
    found = {}
    for path in sorted(SOURCES_DIR.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        code = strip_comments(path.read_text(encoding="utf-8"))
        for m in LOCALIZED_KEY_LITERAL.finditer(code):
            error(f"{rel}:{line_of(code, m.start())}",
                  "string literal passed as LocalizedStringKey; use L10n.tr(\"…\") or Text(verbatim:)")
        for m in L10N_CALL.finditer(code):
            where = f"{rel}:{line_of(code, m.start())}"
            j = m.end()
            while j < len(code) and code[j] in " \t\r\n":
                j += 1
            lit = read_swift_string(code, j) if j < len(code) else None
            if lit is None:
                error(where, "L10n.tr needs a single-line string literal as its key")
                continue
            key, problem = unescape_swift(lit[0])
            if problem:
                error(where, f"L10n.tr key {problem}")
                continue
            args = count_call_arguments(code, m.end() - 1)
            if args is None:
                error(where, "could not parse the L10n.tr call")
                continue
            found.setdefault(key, []).append((where, args - 1))
    return found


# --- main ----------------------------------------------------------------------------

def load_tables():
    tables = {}
    if not LOCALIZATION_DIR.is_dir():
        error(LOCALIZATION_DIR.relative_to(ROOT), "missing")
        return tables
    for lproj in sorted(LOCALIZATION_DIR.glob("*.lproj")):
        path = lproj / TABLE
        rel = path.relative_to(ROOT)
        language = lproj.name[:-len(".lproj")]
        if not path.is_file():
            error(rel, "missing")
            continue
        data = path.read_bytes()
        if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
            error(rel, "must be UTF-8, not UTF-16")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            error(rel, f"not valid UTF-8 ({exc})")
            continue
        try:
            entries = parse_strings(text)
        except StringsSyntaxError as exc:
            error(f"{rel}:{exc.line}", exc.message)
            continue
        table = {}
        for key, value, line in entries:
            if key in table:
                error(f"{rel}:{line}", f"duplicate key {key!r}")
            if not value.strip():
                error(f"{rel}:{line}", f"empty value for {key!r}")
            table[key] = (value, line)
        tables[language] = (rel, table)
    return tables


def main(argv):
    if "--list-keys" in argv:
        for key in sorted(scan_sources()):
            print(key)
        return 0

    tables = load_tables()
    used = scan_sources()

    if DEVELOPMENT_LANGUAGE not in tables:
        error(LOCALIZATION_DIR.relative_to(ROOT), f"no {DEVELOPMENT_LANGUAGE}.lproj/{TABLE}")
    else:
        en_rel, en = tables[DEVELOPMENT_LANGUAGE]
        en_placeholders = {}
        for key, (value, line) in en.items():
            if value != key:
                error(f"{en_rel}:{line}", f"English value must equal its key: {key!r} = {value!r}")
            ph, problems = placeholders(key)
            for problem in problems:
                error(f"{en_rel}:{line}", f"{key!r}: {problem}")
            en_placeholders[key] = ph

        for language, (rel, table) in tables.items():
            if language == DEVELOPMENT_LANGUAGE:
                continue
            for key in en:
                if key not in table:
                    error(rel, f"missing translation for {key!r}")
            for key, (value, line) in table.items():
                if key not in en:
                    error(f"{rel}:{line}", f"key not in {DEVELOPMENT_LANGUAGE}.lproj: {key!r}")
                    continue
                ph, problems = placeholders(value)
                for problem in problems:
                    error(f"{rel}:{line}", f"{key!r}: {problem}")
                if ph != en_placeholders[key]:
                    error(f"{rel}:{line}",
                          f"placeholders differ for {key!r}: "
                          f"en has {describe(en_placeholders[key])}, {language} has {describe(ph)}")

        for key, uses in sorted(used.items()):
            for where, arg_count in uses:
                if key not in en:
                    error(where, f"key missing from {en_rel}: {key!r}")
                    continue
                expected = len(en_placeholders[key])
                if arg_count != expected:
                    error(where, f"{key!r} has {expected} placeholder(s) but the call passes {arg_count} argument(s)")
        for key, (_, line) in sorted(en.items()):
            if key not in used:
                error(f"{en_rel}:{line}", f"key is not used in Sources/: {key!r}")

    if errors:
        for message in errors:
            print(f"error: {message}", file=sys.stderr)
        print(f"check-strings: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    count = len(tables.get(DEVELOPMENT_LANGUAGE, (None, {}))[1])
    print(f"check-strings: OK ({count} keys; languages: {', '.join(sorted(tables))})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
