#!/usr/bin/env python3
"""Rewrite the <Administrators> element of the dedicated config from SE_ADMINS.

Kept out of the repository on purpose: these are the Steam ids of real people,
and this repository is public. The provisioner reads them from a local file and
passes them in as an environment variable.

Applied on every start, like the modpack: the admin list is code, not something
edited in a live file. The tradeoff is that promoting someone from inside the
game does not survive a restart.

Text substitution rather than an XML parser, for the same reason as the modpack:
a round trip through ElementTree rewrites a file the game wrote.
"""

import re
import sys

ADMINS_RE = re.compile(r"<Administrators\s*/>|<Administrators>.*?</Administrators>", re.DOTALL)


def main() -> int:
    path, raw = sys.argv[1], sys.argv[2]

    ids = [i.strip() for i in raw.replace("\n", ",").split(",") if i.strip()]
    for i in ids:
        if not i.isdigit():
            print(f"ERROR: '{i}' is not a Steam64 id", file=sys.stderr)
            return 1

    if ids:
        inner = "".join(f"\n    <unsignedLong>{i}</unsignedLong>" for i in ids)
        element = f"<Administrators>{inner}\n  </Administrators>"
    else:
        element = "<Administrators />"

    raw_bytes = open(path, "rb").read()
    bom = raw_bytes.startswith(b"\xef\xbb\xbf")
    content = raw_bytes.decode("utf-8-sig")

    patched, count = ADMINS_RE.subn(element, content, count=1)
    if count == 0:
        print(f"ERROR: {path} has no <Administrators> element", file=sys.stderr)
        return 1

    if patched != content:
        with open(path, "wb") as f:
            f.write((b"\xef\xbb\xbf" if bom else b"") + patched.encode("utf-8"))

    print(f"admins: {len(ids)} administrator(s) applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
