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
# Only ever exists while recovering a stuck update, and is removed straight
# after. It holds a full second copy of the game, so around 8 GB.
SCRATCH=/data/scratch-install

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
#
# app_info_update is not optional. Left to itself, SteamCMD decides whether an
# update is needed from the product info it already holds, and it decides before
# the refresh lands: on 2026-08-08 it reported "already up to date" on build
# 24434105, eleven hours after the public branch had moved to 24555793, in a
# container created minutes earlier with an empty cache. The stale copy on disk
# is therefore not the cause and deleting it is not the cure; asking for the
# refresh explicitly is. Getting this wrong locks the server one build behind
# and no player can join, so the installed build is logged right after: a wrong
# answer has to be readable in `docker logs` rather than found days later.
#
# The rungs below are the recovery ladder, and each one is there because the one
# above it was measured failing on 2026-08-08, with the install stuck reporting
# "Access Denied" on the manifest it already had:
#
#   - a plain update is the normal path and costs nothing when it works;
#   - validate repairs an install whose files drifted, which is the common case;
#   - installing into an empty directory is the only thing that always works,
#     because a clean install never has to reconfigure from a manifest Steam has
#     since withdrawn. Its manifests are then handed to the real install, which
#     validate reconciles: that sequence is what recovered the server.
#
# The last rung starts the server anyway rather than exiting. Exiting only makes
# Docker restart the container, which repairs nothing and hides the reason in a
# loop of identical logs, and that is exactly how this incident presented.

# $1 install directory, $2 optional extra app_update argument.
update_game() {
  log "updating Space Engineers (appid ${SE_APPID}) in $1 ${2:-}"
  steamcmd \
    +@ShutdownOnFailedCommand 1 \
    +@NoPromptForPassword 1 \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "$1" \
    +login anonymous \
    +app_info_update 1 \
    +app_update "${SE_APPID}" ${2:-} \
    +quit
}

if [ "${SE_SKIP_UPDATE:-0}" = "1" ]; then
  log "SE_SKIP_UPDATE=1, skipping the game update"
elif update_game "${SERVER}"; then
  :
elif update_game "${SERVER}" validate; then
  log "the plain update failed, validate recovered it"
else
  log "WARNING: update still failing, reinstalling into ${SCRATCH} to get a clean manifest"
  rm -rf "${SCRATCH}"
  mkdir -p "${SERVER}/steamapps"
  rm -rf "${SERVER}/steamapps/downloading" "${SERVER}/steamapps/temp"
  if update_game "${SCRATCH}" \
    && cp -a "${SCRATCH}"/steamapps/appmanifest_*.acf "${SERVER}/steamapps/" \
    && update_game "${SERVER}" validate; then
    log "recovered from a clean manifest"
  else
    log "WARNING: the game could not be updated, starting on the installed build"
  fi
  rm -rf "${SCRATCH}"
fi

[ -d "${SERVER}/DedicatedServer64" ] || { log "FATAL: DedicatedServer64 missing, SteamCMD did not complete"; exit 10; }

# Read back rather than trusted: SteamCMD reports success in both cases, so the
# build number is the only thing that tells an update apart from a no-op.
MANIFEST="${SERVER}/steamapps/appmanifest_${SE_APPID}.acf"
BUILD="$(sed -n 's/.*"buildid"[^"]*"\([0-9]*\)".*/\1/p' "${MANIFEST}" 2>/dev/null | head -1 || true)"
log "game build ${BUILD:-unknown}"

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

# --- 5. World seed -----------------------------------------------------------
# The world is composed by hand on a play machine, not generated by the server:
# placing a planet needs the creative spawn menu, which is a gesture of play. It
# therefore travels in the image as a premade checkpoint, and the game copies it
# into a live world on first start exactly as it does with Keen's scenarios.
# PremadeCheckpointPath in the dedicated config is what points at it.
#
# Refreshed on every start rather than only when missing: this directory is a
# template the game reads and never writes, so keeping it aligned with the image
# is free. The useful consequence is that deleting instance/Saves is all it
# takes to go back to a pristine world after a test breaks something.
SEED="${SERVER}/premade-world"
if [ -d /opt/base-world ]; then
  log "refreshing the premade world from the image"
  rm -rf "${SEED}"
  mkdir -p "${SEED}"
  cp -a /opt/base-world/. "${SEED}/"
else
  log "no premade world in the image; the server will fall back to its scenario"
fi

# --- 6. Administrators -------------------------------------------------------
# Applied on every start, unlike the rest of the configuration: the admin list
# is declared in the provisioner, so it is code rather than something edited in
# the live file. Empty means nobody, which is a valid state to start from.
python3 /opt/bin/inject-admins.py "${INSTANCE}/SpaceEngineers-Dedicated.cfg" "${SE_ADMINS:-}"

# --- 7. Modpack --------------------------------------------------------------
# Applied to the live worlds and to the seed alike. Patching the seed is what
# removes the old "a fresh world ignores its mods until the second start": the
# world is now born with the right <Mods> element rather than acquiring it on
# the following run.
mapfile -t WORLDS < <(find "${INSTANCE}/Saves" -maxdepth 2 -name Sandbox_config.sbc 2>/dev/null)
if [ -f "${SEED}/Sandbox_config.sbc" ]; then
  WORLDS+=("${SEED}/Sandbox_config.sbc")
fi

if [ ${#WORLDS[@]} -eq 0 ]; then
  log "no world and no seed; the modpack will be applied on the next start"
else
  for cfg in "${WORLDS[@]}"; do
    python3 /opt/bin/inject-mods.py "${SE_MODS:-}" "${cfg}" "$(dirname "${cfg}")/Sandbox.sbc"
  done
fi

# --- 8. Run ------------------------------------------------------------------
# Xvfb is started by hand rather than through xvfb-run, and that is not a matter
# of taste. As PID 1, the xvfb-run script blocks forever in sigsuspend: the
# kernel drops signals whose handler is the default one when they are sent to
# PID 1, so the wake-up it waits for never arrives. Xvfb comes up, the command
# it was supposed to run never does, and the container sits there looking
# healthy with nothing inside it.
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

KEEN_LOG_DIR="${SERVER}/Logs"

# Counted from the game's own log rather than trusted to a fixed delay. No awk
# or bc: neither is guaranteed present in a slim image.
saves_done() {
  local n
  n="$(cat "${KEEN_LOG_DIR}"/Keen-*.log 2>/dev/null | grep -ac 'Saving world - END' || true)"
  echo "${n:-0}"
}

# SIGINT to the game process is what gets it to save and shut down in order.
# Wine turns it into the Windows CTRL_C_EVENT, and the runtime unwinds from
# there: nothing in Torch handles it, there is no Ctrl+C handler anywhere in its
# source. Three other routes were tried first and all fail here:
#
#   - `wine taskkill` without /F reports success and does nothing. It posts a
#     close message to top-level windows; -nogui has none, and giving Torch its
#     WPF window back does not help either, which was measured.
#   - The VRage Remote API logs "Remote API started on port 8080" and the port
#     really listens, but no request is ever answered: it stands on
#     HttpListener, hence http.sys, which Wine does not meaningfully implement.
#   - Writing `save` on the console does nothing: in -nogui Torch installs no
#     command loop at all, its console only prints. That is in Initializer.cs.
shutdown() {
  local before pid
  before="$(saves_done)"
  pid="$(pgrep -f "${GAME_PATTERN}" | head -1)"
  log "stop requested, sending SIGINT to Torch (pid ${pid:-unknown})"
  [ -n "${pid}" ] && kill -INT "${pid}" 2>/dev/null || true

  # The save lands within seconds and is the part that matters, so it is waited
  # on explicitly instead of trusting a fixed delay.
  for _ in $(seq 1 60); do
    [ "$(saves_done)" != "${before}" ] && { log "world saved"; break; }
    sleep 1
  done
  [ "$(saves_done)" = "${before}" ] && log "WARNING: no save seen after 60s"

  # Winding the process down is far slower than saving: measured at around 80
  # seconds. Worth waiting for a clean exit, but the world is already safe by
  # this point, which is why stop_grace_period only has to cover the save.
  for _ in $(seq 1 120); do
    torch_running || { log "Torch exited cleanly"; return; }
    sleep 1
  done
  log "WARNING: Torch still running, leaving the rest to Docker"
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
