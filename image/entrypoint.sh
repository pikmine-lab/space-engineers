#!/usr/bin/env bash
#
# Brings the data volume up to date, then hands over to Torch.
#
# Everything here is idempotent and runs on every start: the volume holds the
# game and the world, the image holds the runtime. A container can be destroyed
# and recreated without losing anything, and a fresh volume ends up in the same
# state as an old one.
set -euo pipefail

SERVER=/data/server
INSTANCE="${SERVER}/instance"
STEAM_SDK=/data/steam-sdk-win

# 298740 is the dedicated server, free and downloadable anonymously. 1007 is
# Valve's Steamworks SDK Redist, which is where the up-to-date Steam libraries
# come from (see the DLL step below).
SE_APPID=298740
SDK_APPID=1007

log() { echo "[entrypoint] $*"; }

# --- 1. Game -----------------------------------------------------------------
# Not pinnable: Steam updates player clients automatically, so a server left on
# an older build stops accepting them. SE_SKIP_UPDATE only exists to make local
# restarts quick while debugging.
if [ "${SE_SKIP_UPDATE:-0}" = "1" ]; then
  log "SE_SKIP_UPDATE=1, skipping the game update"
else
  log "updating Space Engineers (appid ${SE_APPID})..."
  steamcmd \
    +@ShutdownOnFailedCommand 1 \
    +@NoPromptForPassword 1 \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER}" \
    +login anonymous \
    +app_update "${SE_APPID}" \
    +quit
fi

[ -d "${SERVER}/DedicatedServer64" ] || { log "FATAL: DedicatedServer64 missing, SteamCMD did not complete"; exit 10; }

# --- 2. Torch ----------------------------------------------------------------
# Copied out of the image, not downloaded, so a Jenkins outage cannot stop the
# server from starting. Only re-copied when the pinned build changes.
WANTED_BUILD="$(cat /opt/torch/.torch-build)"
CURRENT_BUILD="$(cat "${SERVER}/.torch-build" 2>/dev/null || echo none)"
if [ "${CURRENT_BUILD}" != "${WANTED_BUILD}" ]; then
  log "installing Torch build ${WANTED_BUILD} (was ${CURRENT_BUILD})"
  cp -a /opt/torch/. "${SERVER}/"
else
  log "Torch build ${CURRENT_BUILD} already installed"
fi

# --- 3. Steam libraries ------------------------------------------------------
# The dedicated server ships Steam DLLs from October 2023. Since July 2025 the
# Workshop stores its content as zstd chunks, which those DLLs cannot read, so
# mod downloads fail outright. Keen's hotfix did not settle it for everyone.
# Overwriting them with the ones from the SDK redist is the known fix, and it
# has to run after every game update since SteamCMD puts the old ones back.
log "fetching current Steam libraries (appid ${SDK_APPID})..."
steamcmd \
  +@ShutdownOnFailedCommand 1 \
  +@NoPromptForPassword 1 \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "${STEAM_SDK}" \
  +login anonymous \
  +app_update "${SDK_APPID}" validate \
  +quit

for dll in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
  src="$(find "${STEAM_SDK}" -name "${dll}" -type f 2>/dev/null | head -1)"
  if [ -z "${src}" ]; then
    log "WARNING: ${dll} not found in the SDK redist, keeping the shipped one"
    continue
  fi
  log "  ${dll}: $(stat -c '%s bytes, %y' "${src}" | cut -d. -f1)"
  cp -f "${src}" "${SERVER}/DedicatedServer64/${dll}"
  # Torch runs from the server root and loads its own copy from there.
  cp -f "${src}" "${SERVER}/${dll}"
done

# --- 4. Reference configuration ----------------------------------------------
# Only ever written when missing. Once a server is live, the volume holds the
# truth: overwriting it on every start would silently undo in-game admin
# changes. The repository describes how a *fresh* server starts out.
mkdir -p "${INSTANCE}"
if [ ! -f "${SERVER}/Torch.cfg" ]; then
  log "seeding Torch.cfg from the image"
  cp /opt/base/Torch.cfg "${SERVER}/Torch.cfg"
fi
if [ ! -f "${INSTANCE}/SpaceEngineers-Dedicated.cfg" ]; then
  log "seeding SpaceEngineers-Dedicated.cfg from the image"
  cp /opt/base/SpaceEngineers-Dedicated.cfg "${INSTANCE}/SpaceEngineers-Dedicated.cfg"
fi

# --- 5. Administrators -------------------------------------------------------
# Applied on every start, unlike the rest of the configuration: the admin list
# is declared in the provisioner, so it is code rather than something edited in
# the live file. Empty means nobody, which is a valid state to start from.
python3 /opt/bin/inject-admins.py "${INSTANCE}/SpaceEngineers-Dedicated.cfg" "${SE_ADMINS:-}"

# --- 6. Modpack --------------------------------------------------------------
# The world does not exist yet on a first start: it is created from the premade
# checkpoint once the server is up, so the very first run of a modded server
# always needs a restart for the mods to land.
mapfile -t WORLDS < <(find "${INSTANCE}/Saves" -maxdepth 2 -name Sandbox_config.sbc 2>/dev/null)
if [ ${#WORLDS[@]} -eq 0 ]; then
  log "no world yet; the modpack will be applied on the next start"
else
  for cfg in "${WORLDS[@]}"; do
    python3 /opt/bin/inject-mods.py "${SE_MODS:-}" "${cfg}" "$(dirname "${cfg}")/Sandbox.sbc"
  done
fi

# --- 7. Run ------------------------------------------------------------------
# Xvfb is started by hand rather than through xvfb-run, and that is not a matter
# of taste. As PID 1, the xvfb-run script blocks forever in sigsuspend: the
# kernel drops signals whose handler is the default one when they are sent to
# PID 1, so the wake-up it waits for never arrives. Xvfb comes up, the command
# it was supposed to run never does, and the container sits there looking
# healthy with nothing inside it.
#
# Handing PID 1 to wine also means the game receives SIGTERM directly on
# `docker stop`, instead of it being swallowed by a shell wrapper.
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp &
export DISPLAY=:99

for _ in $(seq 1 30); do
  [ -e /tmp/.X11-unix/X99 ] && break
  sleep 1
done
[ -e /tmp/.X11-unix/X99 ] || { log "FATAL: Xvfb did not come up"; exit 11; }

# A shell deliberately stays above the game instead of exec'ing into it. Docker's
# SIGTERM means nothing to a Windows application: measured, the grace period just
# runs out and the process is killed with the world unsaved, losing everything
# since the last autosave. Something has to translate the signal.
#
# A shell at PID 1 does receive signals, as long as a handler is installed. The
# kernel only drops those whose handler is the default one, which is precisely
# what left xvfb-run stuck earlier.

# -noupdate: Torch is pinned by the image, it must not fetch its own build.
cd "${SERVER}"
log "starting Torch"
wine Torch.Server.exe -noupdate -autostart -nogui -console &

# `wine` hands over to start.exe, which spawns the real Torch.Server.exe as a
# separate process. Waiting on the pid above would prove nothing: the launcher
# outlives the game. Matching the full path is what tells them apart, since the
# launcher's own command line also mentions Torch.Server.exe.
GAME_PATTERN='server.Torch\.Server\.exe'
torch_running() { pgrep -f "${GAME_PATTERN}" >/dev/null 2>&1; }

shutdown() {
  log "stop requested, asking Torch to close and save"
  # No /F on purpose: this sends a close request, which Torch answers by saving
  # the world. Killing it outright is exactly what loses the session.
  wine taskkill /IM Torch.Server.exe >/dev/null 2>&1 || true
  for _ in $(seq 1 100); do
    torch_running || { log "Torch closed and the world was saved"; return; }
    sleep 1
  done
  log "WARNING: Torch still running after 100s, leaving it to Docker"
}
trap shutdown TERM INT

# Torch takes a while to come up, and never appearing is itself a failure worth
# reporting rather than waiting on forever.
for _ in $(seq 1 300); do
  torch_running && break
  sleep 1
done
torch_running || { log "FATAL: Torch never started"; exit 12; }
log "Torch is up"

# Sleep in the background and wait on it, so a signal is handled immediately
# instead of at the end of a blocking sleep. A crash also ends this loop, which
# stops the container and lets Docker restart it, rather than leaving a live
# container with nothing inside.
while torch_running; do
  sleep 2 &
  wait $! 2>/dev/null || true
done
log "Torch is gone, exiting"
