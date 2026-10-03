"""A small reader of Bitsquid SJSON as the game reads data/ (work item
0207): core:encoding/json with Specification.SJSON. Standard library
only, so Blender's Python and the host's python3 both import it.

The forms: an implicit root object (a text starting with { is that
object), keys as bare identifiers or quoted strings, = or : between key
and value, commas optional between members and between array elements,
// line and /* */ block comments, and the values object, array, string
(JSON escapes), number (JSON's grammar: int without a fraction or an
exponent, else float), true, false and null. A duplicate key is an
error.
"""

import pathlib
import re

NUMBER_PATTERN = re.compile(r"-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ESCAPES = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}
LITERALS = {"true": True, "false": False, "null": None}


class SjsonError(ValueError):
    """The message names the line and the column."""


class Reader:
    def __init__(self, text):
        self.text = text
        self.position = 0

    def error(self, message):
        line = self.text.count("\n", 0, self.position) + 1
        column = self.position - (self.text.rfind("\n", 0, self.position) + 1) + 1
        return SjsonError(f"line {line}, column {column}: {message}")

    def peek(self):
        return self.text[self.position] if self.position < len(self.text) else ""

    def skip_space(self, commas=False):
        """Whitespace and comments, and commas where they separate."""
        while self.position < len(self.text):
            if self.text.startswith("//", self.position):
                end = self.text.find("\n", self.position)
                self.position = len(self.text) if end < 0 else end
            elif self.text.startswith("/*", self.position):
                end = self.text.find("*/", self.position + 2)
                if end < 0:
                    raise self.error("unclosed comment")
                self.position = end + 2
            elif self.peek().isspace() or (commas and self.peek() == ","):
                self.position += 1
            else:
                return


def read_string(reader):
    reader.position += 1
    parts = []
    while True:
        character = reader.peek()
        if character == "":
            raise reader.error("unclosed string")
        reader.position += 1
        if character == '"':
            return "".join(parts)
        if character == "\\":
            parts.append(read_escape(reader))
        else:
            parts.append(character)


def read_escape(reader):
    character = reader.peek()
    reader.position += 1
    if character in ESCAPES:
        return ESCAPES[character]
    digits = reader.text[reader.position:reader.position + 4]
    if character != "u" or not re.fullmatch(r"[0-9A-Fa-f]{4}", digits):
        reader.position -= 1
        raise reader.error("invalid escape")
    reader.position += 4
    return chr(int(digits, 16))


def read_number(reader):
    match = NUMBER_PATTERN.match(reader.text, reader.position)
    if match is None:
        raise reader.error("expected a value")
    reader.position = match.end()
    if match.group(1) is None and match.group(2) is None:
        return int(match.group(0))
    return float(match.group(0))


def read_key(reader):
    if reader.peek() == '"':
        return read_string(reader)
    match = IDENTIFIER_PATTERN.match(reader.text, reader.position)
    if match is None:
        raise reader.error("expected a key")
    reader.position = match.end()
    return match.group(0)


def read_members(reader, closing):
    """Members up to closing ("}" or "" for the implicit root)."""
    members = {}
    while True:
        reader.skip_space(commas=True)
        if reader.peek() == closing:
            reader.position += len(closing)
            return members
        if reader.peek() == "":
            raise reader.error("unclosed object")
        start = reader.position
        key = read_key(reader)
        if key in members:
            reader.position = start
            raise reader.error(f"duplicate key {key!r}")
        reader.skip_space()
        if reader.peek() not in ("=", ":"):
            raise reader.error("expected = or :")
        reader.position += 1
        members[key] = read_value(reader)


def read_array(reader):
    reader.position += 1
    elements = []
    while True:
        reader.skip_space(commas=True)
        if reader.peek() == "]":
            reader.position += 1
            return elements
        if reader.peek() == "":
            raise reader.error("unclosed array")
        elements.append(read_value(reader))


def read_value(reader):
    reader.skip_space()
    character = reader.peek()
    if character == "{":
        reader.position += 1
        return read_members(reader, "}")
    if character == "[":
        return read_array(reader)
    if character == '"':
        return read_string(reader)
    match = IDENTIFIER_PATTERN.match(reader.text, reader.position)
    if match is not None and match.group(0) in LITERALS:
        reader.position = match.end()
        return LITERALS[match.group(0)]
    return read_number(reader)


def loads(text):
    """The root object of an SJSON text."""
    reader = Reader(text)
    reader.skip_space()
    if reader.peek() == "{":
        reader.position += 1
        root = read_members(reader, "}")
        reader.skip_space()
        if reader.peek() != "":
            raise reader.error("text after the root object")
        return root
    return read_members(reader, "")


def load(path):
    """The root object of an SJSON file; an error names the path."""
    path = pathlib.Path(path)
    try:
        return loads(path.read_text())
    except SjsonError as error:
        raise SjsonError(f"{path}: {error}") from None
