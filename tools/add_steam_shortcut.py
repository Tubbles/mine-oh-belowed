#!/usr/bin/env python3
"""Add or update the "Mine oh Belowed" non-Steam shortcut in a Steam user's shortcuts.vdf.

Steam must be closed while this runs, otherwise Steam overwrites the file on exit.
Usage: tools/add_steam_shortcut.py [--user-id 11963684] [--dry-run]

Only the standard library is used. The binary VDF format: 0x00 opens a nested
object, 0x01 a string, 0x02 a 32 bit integer, 0x08 closes an object. Keys and
strings are NUL terminated UTF-8.
"""

import argparse
import pathlib
import struct
import sys
import zlib

TYPE_OBJECT = 0x00
TYPE_STRING = 0x01
TYPE_INTEGER = 0x02
TYPE_END = 0x08

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_NAME = "Mine oh Belowed"
EXECUTABLE = REPOSITORY_ROOT / "bin" / "mine-oh-belowed"


def read_string(data: bytes, offset: int) -> tuple[str, int]:
    end = data.index(b"\x00", offset)
    return data[offset:end].decode("utf-8"), end + 1


def parse_object(data: bytes, offset: int) -> tuple[dict, int]:
    """Parse key value pairs until the closing byte. Insertion order is kept."""
    result: dict = {}
    while True:
        type_byte = data[offset]
        offset += 1
        if type_byte == TYPE_END:
            return result, offset
        key, offset = read_string(data, offset)
        if type_byte == TYPE_OBJECT:
            result[key], offset = parse_object(data, offset)
        elif type_byte == TYPE_STRING:
            result[key], offset = read_string(data, offset)
        elif type_byte == TYPE_INTEGER:
            result[key] = struct.unpack_from("<i", data, offset)[0]
            offset += 4
        else:
            raise ValueError(f"unknown VDF type byte {type_byte:#x} at offset {offset - 1}")


def serialize_object(values: dict) -> bytes:
    output = bytearray()
    for key, value in values.items():
        encoded_key = key.encode("utf-8") + b"\x00"
        if isinstance(value, dict):
            output += bytes([TYPE_OBJECT]) + encoded_key + serialize_object(value)
        elif isinstance(value, str):
            output += bytes([TYPE_STRING]) + encoded_key + value.encode("utf-8") + b"\x00"
        elif isinstance(value, int):
            output += bytes([TYPE_INTEGER]) + encoded_key + struct.pack("<i", value)
        else:
            raise TypeError(f"cannot serialize {type(value)} for key {key}")
    output += bytes([TYPE_END])
    return bytes(output)


def shortcut_app_id(executable: str, app_name: str) -> int:
    """The id Steam historically derives for non-Steam shortcuts, as a signed 32 bit value."""
    unsigned = (zlib.crc32((executable + app_name).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
    return struct.unpack("<i", struct.pack("<I", unsigned))[0]


def build_shortcut() -> dict:
    executable = f'"{EXECUTABLE}"'
    return {
        "appid": shortcut_app_id(executable, APP_NAME),
        "AppName": APP_NAME,
        "Exe": executable,
        "StartDir": f'"{REPOSITORY_ROOT}"',
        "icon": "",
        "ShortcutPath": "",
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "sortas": "",
        "tags": {},
    }


def upsert_shortcut(shortcuts: dict, shortcut: dict) -> str:
    for index, existing in shortcuts.items():
        if existing.get("AppName") == shortcut["AppName"]:
            shortcuts[index] = shortcut
            return f"updated entry {index}"
    next_index = str(max((int(index) for index in shortcuts), default=-1) + 1)
    shortcuts[next_index] = shortcut
    return f"added entry {next_index}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--user-id", default="11963684", help="Steam user id under userdata/")
    parser.add_argument("--dry-run", action="store_true", help="parse and report, write nothing")
    arguments = parser.parse_args()

    path = pathlib.Path.home() / ".steam" / "steam" / "userdata" / arguments.user_id / "config" / "shortcuts.vdf"
    original = path.read_bytes() if path.exists() else serialize_object({"shortcuts": {}})
    root, consumed = parse_object(original, 0)
    if consumed != len(original) or serialize_object(root) != original:
        print("error: the existing shortcuts.vdf does not round trip through this parser, refusing to write", file=sys.stderr)
        return 1

    outcome = upsert_shortcut(root.setdefault("shortcuts", {}), build_shortcut())
    print(outcome)
    for index, entry in root["shortcuts"].items():
        print(f"  {index}: {entry.get('AppName')}  appid={entry.get('appid')}  exe={entry.get('Exe')}")
    if arguments.dry_run:
        return 0
    path.write_bytes(serialize_object(root))
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
