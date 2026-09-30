#!/usr/bin/env python3
"""Check the Markdown documentation against the repository.

For every Markdown file in the repository (tracked or not ignored), except
the history under doc/log/ and doc/work/ and the vendored shared/ tree:

- every relative Markdown link resolves to an existing file or directory;
- every backticked src/, doc/, data/ or tools/ path exists;
- every backticked bare .odin file name exists under src/ or shared/, and
  every bare .sjson file name under data/;
- every backticked identifier with an underscore (snake_case, Ada_Case or
  SCREAMING_CASE, optionally dotted like settings.touch_overlay) appears as a
  whole word in src/**/*.odin, data/**/*.sjson or tools/*, or is on the allow
  list below.

Prints one line per finding as "file: token" and a summary. Exits 1 on
findings. Run from anywhere: python3 tools/check_docs.py
"""

import pathlib
import re
import subprocess
import sys

# Names from outside the repository (SDL, raylib and Odin runtime sources,
# glibc and NDK functions, Android permissions) that no source file or
# comment in the repository names, and the naming convention words.
ALLOWED_EXTERNAL_NAMES = {
    "snake_case",
    "Ada_Case",
    "SCREAMING_CASE",
    "_cleanup_runtime",
    "SDL_HINT_JOYSTICK_HIDAPI_STEAM",
    "KEY_BACKSPACE",
    "KEY_ENTER",
    "AKEYCODE_DEL",
    "AKEYCODE_ENTER",
    "ANativeActivity_onCreate",
    "__errno_location",
    "__system_property_get",
    "memfd_create",
    "__wrap_fopen",
    "__real_fopen",
    "WRITE_EXTERNAL_STORAGE",
}

# Paths the build writes, so a checkout without a build lacks them.
GENERATED_PATHS = {
    "data/.build_stamp",
}

PATH_PREFIXES = ("src/", "doc/", "data/", "tools/")
PLACEHOLDER_MARKERS = ("<", "*", "NNNN", "YYYY", "…", "...")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
DOTTED_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\(\))?")
FILE_NAME = re.compile(r"[\w.-]+\.(odin|sjson|c|h|cpp|md|py|sh|png|wav|vox|ttf|txt|vs|fs|so|a|rules)")
# A backslash escape in a string literal (\n, \t) would glue its letter to
# the next word.
BACKSLASH_ESCAPE = re.compile(r"\\[a-z0-9]")
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def repository_root():
    return pathlib.Path(__file__).resolve().parent.parent


def markdown_files(root):
    listing = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.md"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.split("\n")
    # History, the vendored tree, and the user's inbox.
    skipped = ("doc/log/", "doc/work/", "shared/", "TODO.md")
    return sorted(
        root / name for name in listing
        if name and not name.startswith(skipped) and (root / name).is_file()
    )


def known_words(root):
    sources = list((root / "src").rglob("*.odin"))
    sources += list((root / "data").rglob("*.sjson"))
    this_script = pathlib.Path(__file__).resolve()
    sources += [
        path for path in (root / "tools").rglob("*")
        if path.is_file() and path.resolve() != this_script and "__pycache__" not in path.parts
    ]
    words = set()
    for path in sources:
        words.update(IDENTIFIER.findall(BACKSLASH_ESCAPE.sub(" ", path.read_text(errors="replace"))))
    return words


def prose_lines(text):
    """Yield the lines outside fenced code blocks."""
    in_fence = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield line


def is_placeholder(token):
    return any(marker in token for marker in PLACEHOLDER_MARKERS) or token.endswith("/…")


def path_findings(root, token):
    first_word = token.split()[0]
    if not first_word.startswith(PATH_PREFIXES) or is_placeholder(first_word) or first_word in GENERATED_PATHS:
        return []
    return [] if (root / first_word.rstrip("/")).exists() else [first_word]


def is_file_name(token):
    return FILE_NAME.fullmatch(token) is not None


# Where a bare file name of each extension must exist.
BARE_FILE_DIRECTORIES = {
    ".odin": ("src", "shared"),
    ".sjson": ("data",),
}
# SJSON files the game reads or writes outside data/: the configuration,
# a save's world file, the texture editor's edits.
FILES_OUTSIDE_DATA = {
    "config.sjson",
    "world.sjson",
    "texture_edits.sjson",
}


def bare_file_findings(root, token):
    directories = BARE_FILE_DIRECTORIES.get(pathlib.PurePath(token).suffix)
    if "/" in token or directories is None or token in FILES_OUTSIDE_DATA or is_placeholder(token) or not is_file_name(token):
        return []
    found = any(next((root / directory).rglob(token), None) for directory in directories)
    return [] if found else [token]


def identifier_findings(token, words):
    if is_file_name(token) or not DOTTED_IDENTIFIER.fullmatch(token):
        return []
    names = token.removesuffix("()").split(".")
    return [
        name for name in names
        if "_" in name.strip("_") and name not in words and name not in ALLOWED_EXTERNAL_NAMES
    ]


def link_findings(markdown_path, target):
    if re.match(r"[a-z]+:", target) or target.startswith("#"):
        return []
    relative = target.split("#")[0]
    return [] if (markdown_path.parent / relative).exists() else [target]


def file_findings(root, markdown_path, words):
    findings = []
    for line in prose_lines(markdown_path.read_text()):
        for target in LINK.findall(line):
            findings += link_findings(markdown_path, target)
        for _, token in INLINE_CODE.findall(line):
            token = token.strip()
            if not token:
                continue
            findings += path_findings(root, token)
            findings += bare_file_findings(root, token)
            findings += identifier_findings(token, words)
    return findings


def main():
    root = repository_root()
    words = known_words(root)
    total = 0
    files_with_findings = 0
    for markdown_path in markdown_files(root):
        findings = file_findings(root, markdown_path, words)
        relative = markdown_path.relative_to(root)
        for token in findings:
            print(f"{relative}: {token}")
        total += len(findings)
        files_with_findings += bool(findings)
    print(f"{total} findings in {files_with_findings} files")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
