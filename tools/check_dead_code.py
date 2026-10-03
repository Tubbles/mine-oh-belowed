#!/usr/bin/env python3
"""Find top level definitions of the game's packages that nothing reaches.

Scans src/**/*.odin (the game package and the packages under src/, work
item 0145) for top level definitions (procedures, types, constants,
variables, anything written as `name ::`, `name: Type` or `name :=` at the
start of a line, or one tab deeper per enclosing file level `when` or
`foreign` block) and counts the references to each name as whole words in
the code of every .odin file under src/, with comments and string literals
stripped. The definition's own body and every definition line of the same
name (a platform variant in a sibling file) are no references.
Identifiers in build.sh, tools/ and the shaders under data/ count as
references too.

Reports two lists:

- definitions nothing references;
- definitions outside the test files that only *_test.odin files reference.

Names on the allow lists below are skipped, as are @(test), @(export),
@(init) and @(fini) procedures. Exits 1 when it finds anything, 0
otherwise. Run from anywhere: python3 tools/check_dead_code.py
"""

import pathlib
import re
import sys

REPOSITORY = pathlib.Path(__file__).resolve().parent.parent
SOURCE_DIRECTORY = REPOSITORY / "src"

# Names the linker, the runtime or a foreign side reaches without an Odin
# reference and without an attribute that says so.
ALLOWED_UNREFERENCED = {
    "main": "the program entry point",
}

# Test seams: definitions only the tests call, kept because the production
# code has no path that does the same deterministically.
ALLOWED_TEST_ONLY = {
    "load_chunk_now": "generates and inserts one chunk synchronously, where streaming uses workers",
    "reset_data_edits_reading": "resets the thread local overlay state a test set",
    "simulation_state_hash": "the determinism and save round trip tests compare worlds by it",
    "face_tile_orientation": "the Odin mirror of the chunk shader's tile orientation",
    "TILE_ORIENTATION_COUNT": "the number of orientations the chunk shader picks from",
    # The terrain field's entry points (0168), reached only through tests
    # until the field world is wired into the session (0167, Sequencing).
    "generate_field_chunk": "the terrain field's generation, wired in by M13",
    "world_position_to_sample": "the terrain field's position conversion, wired in by M13",
    "field_world_get_sample": "the terrain field's read, wired in by M13",
    "field_world_set_sample": "the terrain field's write, wired in by M13",
    "field_world_insert_chunk": "the terrain field's chunk insert, wired in by M13",
    "destroy_field_world": "the terrain field's teardown, wired in by M13",
    "encode_field_chunk_delta": "the terrain field's save codec, wired in by M13",
    "decode_field_chunk_delta": "the terrain field's load codec, wired in by M13",
    # The slice's content (0179), called by the session in 0179's wiring
    # round, after the switch to the field world.
    "register_planet_veins": "the veins on the sphere into the registry, wired in by 0179",
    "place_drill_on_frame": "the drill on a frame, wired in by 0179",
    "place_pod": "the pod in its crater at the home, wired in by 0179",
}

ENTRY_ATTRIBUTES = ("test", "export", "init", "fini")
EXTERNAL_REFERENCE_GLOBS = ("build.sh", "tools/**/*", "data/shaders/*")
EXCLUDED_EXTERNAL_FILES = {"tools/check_dead_code.py", "tools/code_graph.py"}

IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ATTRIBUTE_PREFIX = r"(?:@\([^)]*\)\s*)*"
CONSTANT_DEFINITION = re.compile(r"^" + ATTRIBUTE_PREFIX + r"([A-Za-z_][A-Za-z0-9_]*)\s*::")
VARIABLE_DEFINITION = re.compile(r"^" + ATTRIBUTE_PREFIX + r"([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)")
ATTRIBUTE_LINE = re.compile(r"^@\(([^)]*)\)\s*$")
KEYWORD_LINES = ("package ", "import ", "foreign ", "when ", "#")
# A `when` or `foreign` block of declarations: its members sit one tab
# deeper and it closes with a `}` at its own indentation.
DECLARATION_BLOCK_OPENER = re.compile(r"^(when |foreign (?!import))")


def strip_code_line(line, state):
    """Returns the line without comments and string literals.

    `state` carries an open block comment depth and an open raw string
    across lines, as a dictionary with the keys "comment" and "raw".
    """
    output = []
    index = 0
    while index < len(line):
        character = line[index]
        pair = line[index:index + 2]
        if state["comment"] > 0:
            if pair == "*/":
                state["comment"] -= 1
                index += 2
            elif pair == "/*":
                state["comment"] += 1
                index += 2
            else:
                index += 1
            continue
        if state["raw"]:
            if character == "`":
                state["raw"] = False
            index += 1
            continue
        if pair == "//":
            break
        if pair == "/*":
            state["comment"] += 1
            index += 2
            continue
        if character == "`":
            state["raw"] = True
            index += 1
            continue
        if character in "\"'":
            index = skip_quoted(line, index)
            output.append(" ")
            continue
        output.append(character)
        index += 1
    return "".join(output)


def skip_quoted(line, start):
    quote = line[start]
    index = start + 1
    while index < len(line):
        if line[index] == "\\":
            index += 2
            continue
        if line[index] == quote:
            return index + 1
        index += 1
    return index


def code_lines(path):
    """Returns the lines of an Odin file with comments and strings stripped."""
    state = {"comment": 0, "raw": False}
    text = path.read_text(encoding="utf-8")
    return [strip_code_line(line, state) for line in text.splitlines()]


def definition_name(line):
    if line.startswith(KEYWORD_LINES) or not line[:1].strip():
        return None
    match = CONSTANT_DEFINITION.match(line) or VARIABLE_DEFINITION.match(line)
    return match.group(1) if match else None


def line_attributes(line):
    match = ATTRIBUTE_LINE.match(line.strip()) or re.match(r"^@\(([^)]*)\)", line)
    if not match:
        return set()
    return {part.split("=")[0].strip() for part in match.group(1).split(",")}


def indentation(line):
    return len(line) - len(line.lstrip("\t"))


def step_declaration_blocks(line, block_indents):
    """Updates the stack of open `when` and `foreign` block indentations.

    Returns True when the line opened or closed a block, so it is no
    definition.
    """
    depth = len(block_indents)
    if not line.strip():
        return False
    if depth > 0 and indentation(line) == depth - 1 and line[depth - 1:].startswith("}"):
        if not line.rstrip().endswith("{"):
            block_indents.pop()
        return True
    if indentation(line) != depth:
        return False
    body = line[depth:]
    if DECLARATION_BLOCK_OPENER.match(body) and body.rstrip().endswith("{"):
        block_indents.append(depth)
        return True
    return False


def parse_definitions(path, lines):
    """Returns the top level definitions of one file.

    Top level means at column 0, or one tab deeper per enclosing `when` or
    `foreign` block that itself sits at a declaration level. Each is a
    dictionary: name, path, line (1 based), end (the last line of its body,
    1 based) and attributes (the names inside @(...) on the definition line
    and the lines just above it).
    """
    definitions = []
    pending_attributes = set()
    block_indents = []
    for index, full_line in enumerate(lines):
        if step_declaration_blocks(full_line, block_indents):
            pending_attributes = set()
            continue
        depth = len(block_indents)
        line = full_line[depth:] if indentation(full_line) == depth else "\t"
        if ATTRIBUTE_LINE.match(line.strip()) and line.startswith("@"):
            pending_attributes |= line_attributes(line)
            continue
        name = definition_name(line)
        if name:
            definitions.append({
                "name": name,
                "path": path,
                "line": index + 1,
                "attributes": pending_attributes | line_attributes(line),
            })
        if line.strip():
            pending_attributes = set()
    for definition in definitions:
        definition["end"] = body_end(lines, definition["line"] - 1)
    return definitions


def body_end(lines, start):
    """Returns the 1 based last line of the definition starting at `start`.

    The body ends at the first line after which the brackets opened since
    the start are closed again.
    """
    depth = 0
    for index in range(start, len(lines)):
        for character in lines[index]:
            if character in "({[":
                depth += 1
            elif character in ")}]":
                depth -= 1
        if depth <= 0:
            return index + 1
    return len(lines)


def identifier_occurrences(path, lines):
    """Returns (name, line) for every identifier in the stripped lines."""
    return [
        (match.group(0), index + 1)
        for index, line in enumerate(lines)
        for match in IDENTIFIER.finditer(line)
    ]


def all_odin_files():
    return sorted(SOURCE_DIRECTORY.rglob("*.odin"))


def external_identifiers():
    names = set()
    for pattern in EXTERNAL_REFERENCE_GLOBS:
        for path in REPOSITORY.glob(pattern):
            relative = path.relative_to(REPOSITORY).as_posix()
            if not path.is_file() or relative in EXCLUDED_EXTERNAL_FILES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            names.update(IDENTIFIER.findall(text))
    return names


def is_test_file(path):
    return path.name.endswith("_test.odin")


def collect_references(files):
    """Returns name -> list of (path, line) over the given files."""
    references = {}
    for path in files:
        for name, line in identifier_occurrences(path, code_lines(path)):
            references.setdefault(name, []).append((path, line))
    return references


def outside_own_body(definition, reference):
    path, line = reference
    if path != definition["path"]:
        return True
    return not (definition["line"] <= line <= definition["end"])


def definition_sites(definitions):
    """Returns name -> {(path, line)} of every definition line of the name."""
    sites = {}
    for definition in definitions:
        sites.setdefault(definition["name"], set()).add((definition["path"], definition["line"]))
    return sites


def classify(definition, references, sites):
    """Returns "unreferenced", "test only" or None.

    Neither the definition's own body nor a definition line of the same
    name in another file (a platform variant) counts as a reference.
    """
    name_sites = sites[definition["name"]]
    others = [
        reference
        for reference in references.get(definition["name"], [])
        if outside_own_body(definition, reference) and reference not in name_sites
    ]
    if not others:
        return "unreferenced"
    if is_test_file(definition["path"]):
        return None
    if all(is_test_file(path) for path, _ in others):
        return "test only"
    return None


def is_allowed(definition, verdict, external):
    name = definition["name"]
    if definition["attributes"] & set(ENTRY_ATTRIBUTES):
        return True
    if name in external or name in ALLOWED_UNREFERENCED:
        return True
    return verdict == "test only" and name in ALLOWED_TEST_ONLY


def all_definitions():
    definitions = []
    for path in all_odin_files():
        definitions.extend(parse_definitions(path, code_lines(path)))
    return definitions


def findings():
    references = collect_references(all_odin_files())
    external = external_identifiers()
    definitions = all_definitions()
    sites = definition_sites(definitions)
    results = []
    for definition in definitions:
        verdict = classify(definition, references, sites)
        if verdict and not is_allowed(definition, verdict, external):
            results.append((verdict, definition))
    return results


def print_findings(results):
    for verdict in ("unreferenced", "test only"):
        group = [d for v, d in results if v == verdict]
        print(f"{verdict}: {len(group)}")
        for definition in group:
            relative = definition["path"].relative_to(REPOSITORY).as_posix()
            print(f"  {relative}:{definition['line']}: {definition['name']}")


def main():
    results = findings()
    print_findings(results)
    print(f"{len(results)} findings")
    return 1 if results else 0


if __name__ == "__main__":
    sys.exit(main())
