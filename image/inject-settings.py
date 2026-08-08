#!/usr/bin/env python3
"""Reapply declared settings to the worlds and to Modular Encounters Systems.

Two kinds of setting are code in this repository rather than state in the
volume, and neither survives on its own. World session settings live in the
world files, which the game rewrites on every save, and a world reset brings
back whatever the seed held. MES settings live in the world's Storage, which no
part of the repository touched until now, so a reset silently restored MES
defaults: no global NPC ceiling, no creature override.

Reapplying them at every start is what makes the declaration authoritative,
exactly as the modpack and the admin list already are. The cost is the mirror
image: a value changed in game, or through a /MES.Settings chat command, is
undone at the next restart. That is the intended trade, not an accident.

An absent setting is never created. The .NET serialiser reads these elements in
sequence, so inserting one in the wrong place corrupts the file in a way nothing
reports until much later. A declaration that matches nothing is reported and
skipped.
"""

import re
import sys
from pathlib import Path

# MES keeps its admin configuration in the world's Storage, under the folder
# Space Engineers derives from its Workshop id.
MES_STORAGE = "Storage/1521905890.sbm_ModularEncountersSystems"


def parse(path: Path) -> list[tuple[str, str, str]]:
    """Read the declaration into (target, setting, value) triples."""
    out = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if "=" not in line:
            print(f"ERROR: {path}:{n}: expected '<target>.<setting> = <value>'", file=sys.stderr)
            return []
        left, value = (p.strip() for p in line.split("=", 1))
        target, _, setting = left.rpartition(".")
        if not target or not setting:
            print(f"ERROR: {path}:{n}: '{left}' is missing a target", file=sys.stderr)
            return []
        out.append((target, setting, value))
    return out


def files_for(target: str, world: Path) -> list[Path]:
    """Resolve a declaration target to the files that carry it."""
    if target == "world":
        return [world / "Sandbox.sbc", world / "Sandbox_config.sbc"]
    if target.startswith("mes."):
        return [world / MES_STORAGE / f"Config-{target[4:]}.xml"]
    return []


def apply(path: Path, setting: str, value: str) -> bool | None:
    """Rewrite one element in place. None when the file has no such element."""
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return None

    # Keep whatever the file already has. The world files are UTF-8 with a BOM,
    # while the MES ones are UTF-8 without one despite declaring utf-16 in their
    # XML header. That declaration is a lie MES itself writes and reads back, so
    # it is left alone.
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")

    pattern = re.compile(rf"<{re.escape(setting)}>.*?</{re.escape(setting)}>", re.DOTALL)
    patched, count = pattern.subn(f"<{setting}>{value}</{setting}>", text, count=1)
    if count == 0:
        return None
    if patched == text:
        return False

    path.write_bytes((b"\xef\xbb\xbf" if bom else b"") + patched.encode("utf-8"))
    return True


def main() -> int:
    declaration = Path(sys.argv[1])
    worlds = [Path(w) for w in sys.argv[2:]]

    if not declaration.is_file():
        print(f"settings: no declaration at {declaration}, nothing to apply")
        return 0

    wanted = parse(declaration)
    if not wanted:
        return 0 if declaration.read_text(encoding="utf-8").strip() == "" else 1

    changed = already = missing = 0
    for world in worlds:
        for target, setting, value in wanted:
            paths = files_for(target, world)
            if not paths:
                print(f"ERROR: unknown target '{target}'", file=sys.stderr)
                return 1
            # Absent files are the normal case, not a failure: the seed carries
            # no Storage, so a world only gets its MES settings on the start
            # after the one that created it.
            results = [apply(p, setting, value) for p in paths if p.exists()]
            if not results:
                continue
            if all(r is None for r in results):
                missing += 1
                print(f"  {world.name}: {target}.{setting} not found, skipped")
            elif any(results):
                changed += 1
                print(f"  {world.name}: {target}.{setting} = {value}")
            else:
                already += 1

    print(
        f"settings: {changed} applied, {already} already set, {missing} not found"
        f" across {len(worlds)} world(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
