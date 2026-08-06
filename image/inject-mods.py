#!/usr/bin/env python3
"""Rewrite the <Mods> element of a world from the modpack declared in SE_MODS.

The world files are the source of truth for the running server, but the modpack
is the source of truth for which mods that world should carry. Rewriting the
element on every start is what makes the list in the repository authoritative:
adding a mod is a redeploy, not a file edited over SSH.

Order matters in Space Engineers. When two mods define the same thing, the one
further down the list wins, so the sequence in SE_MODS is preserved verbatim.

Text substitution rather than an XML parser: these files are written by the
game, and a round trip through ElementTree reorders attributes and rewrites
namespaces, producing a diff the game has never seen.
"""

import re
import sys

MODS_RE = re.compile(r"<Mods\s*/>|<Mods>.*?</Mods>", re.DOTALL)


def mods_element(ids: list[str]) -> str:
    if not ids:
        return "<Mods />"
    items = "".join(
        f"<ModItem>"
        f"<Name>{i}.sbm</Name>"
        f"<PublishedFileId>{i}</PublishedFileId>"
        f"<PublishedServiceName>Steam</PublishedServiceName>"
        f"</ModItem>"
        for i in ids
    )
    return f"<Mods>{items}</Mods>"


def main() -> int:
    raw = sys.argv[1]
    targets = sys.argv[2:]

    ids = [m.strip() for m in raw.replace("\n", ",").split(",") if m.strip()]
    for i in ids:
        if not i.isdigit():
            print(f"ERROR: '{i}' is not a Steam Workshop id", file=sys.stderr)
            return 1

    element = mods_element(ids)
    touched = 0

    for path in targets:
        try:
            raw_bytes = open(path, "rb").read()
        except FileNotFoundError:
            continue

        # The game writes these files with a BOM. Keep whatever the file already
        # has instead of imposing one: the encoding is not ours to change.
        bom = raw_bytes.startswith(b"\xef\xbb\xbf")
        content = raw_bytes.decode("utf-8-sig")

        patched, count = MODS_RE.subn(element, content, count=1)
        if count == 0:
            # No <Mods> element at all. Not inserting one: the .NET serialiser
            # reads these elements in sequence, so putting it in the wrong place
            # would corrupt the world in a way nothing reports until later.
            if ids:
                print(f"ERROR: {path} has no <Mods> element, cannot apply the modpack", file=sys.stderr)
                return 1
            continue

        if patched != content:
            with open(path, "wb") as f:
                f.write((b"\xef\xbb\xbf" if bom else b"") + patched.encode("utf-8"))
        touched += 1

    print(f"modpack: {len(ids)} mod(s) applied to {touched} world file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
