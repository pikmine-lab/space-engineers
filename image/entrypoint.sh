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
# -noupdate: Torch is pinned by the image, it must not fetch its own build.
# xvfb: Torch is a WPF application and needs a display even with -nogui.
cd "${SERVER}"
log "starting Torch"
exec xvfb-run -a wine Torch.Server.exe -noupdate -autostart -nogui -console
