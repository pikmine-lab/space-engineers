#!/usr/bin/env python3
"""Collect what Steam knows about Space Engineers mods, and flag what is worth a look.

This gathers facts and raises signals. It does not decide: judging whether a mod
belongs in the pack means reading its comments, its changelog and sometimes its
source, which is the reviewer's job. What is automated here is everything that
can be checked mechanically and would be tedious to redo by hand for every mod.

Usage:
    python check-mod.py <url-or-id> [<url-or-id> ...] [--modpack path/to/modpack.txt]

Standard library only, on purpose: this has to run anywhere without an install.
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

SE_APPID = 244850  # Space Engineers 1. Space Engineers 2 is a different app.
SE_SERVER_APPID = 298740
UA = "Mozilla/5.0 (compatible; modpack-review)"
DETAILS_API = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
BUILD_API = f"https://api.steamcmd.net/v1/info/{SE_SERVER_APPID}"


def get(url: str, data: bytes | None = None, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def parse_id(token: str) -> str:
    """Accepts a raw id or any Steam URL carrying `?id=` / `/id/`."""
    m = re.search(r"[?&]id=(\d+)", token) or re.fullmatch(r"(\d+)", token.strip())
    if not m:
        raise SystemExit(f"cannot read a Workshop id from: {token}")
    return m.group(1)


def fetch_details(ids: list[str]) -> dict[str, dict]:
    body = [("itemcount", str(len(ids)))]
    body += [(f"publishedfileids[{i}]", v) for i, v in enumerate(ids)]
    raw = get(DETAILS_API, urllib.parse.urlencode(body).encode())
    files = json.loads(raw)["response"].get("publishedfiledetails", [])
    return {f["publishedfileid"]: f for f in files}


def fetch_required_items(mod_id: str) -> list[str]:
    """Dependencies as declared on the page.

    Frequently empty even when the mod genuinely needs others: plenty of authors
    only mention them in the description. Never treat an empty list as proof
    that a mod stands alone.
    """
    try:
        html = get(f"https://steamcommunity.com/sharedfiles/filedetails/?id={mod_id}").decode(
            "utf-8", "replace"
        )
    except urllib.error.URLError:
        return []
    block = re.search(r'id="RequiredItems"(.*?)(?:<div class="panel|</form>)', html, re.S)
    if not block:
        return []
    return list(dict.fromkeys(re.findall(r"filedetails/\?id=(\d+)", block.group(1))))


def server_updated_at() -> datetime | None:
    """Last publish date of the dedicated server, the reference for staleness."""
    try:
        data = json.loads(get(BUILD_API, timeout=20))["data"]
        branch = next(iter(data.values()))["depots"]["branches"]["public"]
        return datetime.fromtimestamp(int(branch["timeupdated"]), timezone.utc)
    except Exception:
        return None


def read_modpack(path: str) -> list[str]:
    ids = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                ids.append(line)
    return ids


def plain(bbcode: str) -> str:
    return re.sub(r"\[/?[^\]]+\]", "", bbcode)


def report(mod_id: str, f: dict, pack: list[str], ref: datetime | None) -> list[str]:
    """Prints the facts, returns the signals."""
    signals: list[str] = []

    if not f or f.get("result") != 1:
        print(f"\n{mod_id}: not found, or removed from the Workshop")
        return ["BLOCKING: item unavailable"]

    updated = datetime.fromtimestamp(f["time_updated"], timezone.utc)
    created = datetime.fromtimestamp(f["time_created"], timezone.utc)
    desc = plain(f.get("description", ""))
    tags = [t.get("tag") for t in f.get("tags", [])]

    print(f"\n{f['title']}  ({mod_id})")
    print(f"  app          {f.get('consumer_app_id')}")
    print(f"  created      {created:%Y-%m-%d}")
    print(f"  updated      {updated:%Y-%m-%d}")
    print(f"  subscribers   {f.get('subscriptions', 0):>8}   (lifetime {f.get('lifetime_subscriptions', 0)})")
    print(f"  tags         {', '.join(tags) or 'none'}")
    print(f"  size         {int(f.get('file_size', 0)) / 1048576:.1f} MB")

    declared = fetch_required_items(mod_id)
    cited = [i for i in dict.fromkeys(re.findall(r"id=(\d{6,})", f.get("description", ""))) if i != mod_id]
    repos = list(dict.fromkeys(re.findall(r"https?://(?:www\.)?(?:github|gitlab)\.com/[\w.-]+/[\w.-]+", f.get("description", ""))))

    print(f"  declared deps {declared or 'none'}")
    if cited:
        print(f"  ids cited in the description: {cited}")
    if repos:
        print(f"  source repo  {', '.join(repos)}")
    print(f"  description  {desc[:200].strip().replace(chr(10), ' ')}")

    if f.get("consumer_app_id") != SE_APPID:
        signals.append(f"BLOCKING: belongs to app {f.get('consumer_app_id')}, not Space Engineers 1 ({SE_APPID})")
    if f.get("banned"):
        signals.append(f"BLOCKING: banned ({f.get('ban_reason') or 'no reason given'})")
    if f.get("visibility") != 0:
        signals.append("BLOCKING: not public, the server will not be able to fetch it")

    # The Workshop holds several kinds of item under the same kind of URL, and
    # only actual mods belong in <Mods>. An in-game script is pasted into a
    # programmable block by a player; a blueprint is a grid; a world is a save.
    # Listing any of those as a mod fails silently: the server just never loads
    # what you expected.
    wrong_kind = {"ingameScript": "an in-game script, to paste into a programmable block",
                  "blueprint": "a blueprint, not a mod",
                  "world": "a world save, not a mod",
                  "scenario": "a scenario, not a mod"}
    for tag, what in wrong_kind.items():
        if tag in tags:
            signals.append(f"BLOCKING: this is {what}, it has no place in the modpack")
            break
    else:
        if "mod" not in tags:
            signals.append(f"BLOCKING: not tagged as a mod (tags: {', '.join(tags) or 'none'})")

    if ref and updated < ref:
        months = (ref - updated).days // 30
        if months >= 1:
            level = "CHECK" if months < 12 else "WARNING"
            signals.append(f"{level}: last updated {months} months before the current server build")

    for dep in declared:
        if dep not in pack:
            signals.append(f"CHECK: declared dependency {dep} is not in the modpack")
    for c in cited:
        if c not in pack and c not in declared:
            signals.append(f"CHECK: description points at {c}, which is neither declared nor in the pack")
    if not declared and re.search(r"\brequires?\b|\bneed(s|ed)?\b|\bdependenc", desc, re.I):
        signals.append("CHECK: the description mentions a requirement but nothing is declared, read it")
    # ExperimentalMode is on, so code is allowed. It still matters: a mod that
    # carries code breaks on game updates in a way a pure block mod does not.
    if "mod" in tags and "NoScripts" not in tags:
        signals.append("CHECK: no NoScripts tag, so it likely carries code and is more fragile across updates")
    if repos:
        signals.append(f"CHECK: source is public, look at its recent activity: {repos[0]}")

    return signals


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mods", nargs="+", help="Workshop URLs or ids")
    p.add_argument("--modpack", help="modpack.txt, to spot dependencies already present")
    args = p.parse_args()

    ids = [parse_id(m) for m in args.mods]
    pack = read_modpack(args.modpack) if args.modpack else []
    ref = server_updated_at()

    print(f"dedicated server last published: {ref:%Y-%m-%d}" if ref else "server build date unavailable")
    if pack:
        print(f"modpack currently holds {len(pack)} mod(s)")

    details = fetch_details(ids)

    verdicts = {}
    for mod_id in ids:
        signals = report(mod_id, details.get(mod_id, {}), pack, ref)
        if signals:
            print("  signals:")
            for s in signals:
                print(f"    - {s}")
        else:
            print("  signals: none, nothing mechanical to report")
        verdicts[mod_id] = signals

    blocking = {k: v for k, v in verdicts.items() if any(s.startswith("BLOCKING") for s in v)}
    print(f"\n{len(ids)} mod(s) examined, {len(blocking)} blocked outright.")
    print("Signals are leads, not a verdict: read the comments, the changelog and the source before deciding.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
