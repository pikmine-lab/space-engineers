#!/usr/bin/env bash
#
# Builds the Wine prefix at image build time.
#
# Split out of the Dockerfile because this is the step that fails, and failing
# one command at a time says which one. Every step is explicit for the same
# reason: `winetricks -q a b c` reports one exit code for three installs.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

export DISPLAY=:5

# Wine needs a display even for headless work, and its installers draw windows
# in silent mode. Started by hand rather than through xvfb-run: several commands
# have to share one server and one prefix state.
Xvfb :5 -screen 0 1024x768x16 &
XVFB_PID=$!
sleep 2
kill -0 "$XVFB_PID" 2>/dev/null || die "Xvfb did not start"

# mscoree=d for this one call, and it is not optional. Left alone, wineboot
# auto-installs Mono inside a prefix that is only half built; the install hangs
# for five minutes and leaves the prefix broken, which then surfaces as
# "could not load kernel32.dll, status c0000135" on every later command.
WINEDLLOVERRIDES="mscoree=d" wineboot --init /nogui || die "wineboot --init failed"
wineserver -w

# The real .NET Framework, not Mono: Torch is a WPF application and Mono cannot
# run WPF. This is the long step, around ten minutes.
winetricks -q --force dotnet48 || die "winetricks dotnet48 failed"
wineserver -w

winetricks -q --force vcrun2022 || die "winetricks vcrun2022 failed"
wineserver -w

winetricks -q corefonts || die "winetricks corefonts failed"
wineserver -w

kill "$XVFB_PID" 2>/dev/null || true
rm -rf ~/.cache/winetricks

echo "wine prefix ready"
