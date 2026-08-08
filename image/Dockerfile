# Space Engineers dedicated server, running under Wine and managed by Torch.
#
# There is no native Linux build of the Space Engineers dedicated server, so the
# Windows binaries run under Wine. Two consequences shape this file:
#
#   - The Wine prefix, with .NET Framework 4.8, is baked into the image rather
#     than built on first start. It takes around ten minutes and must be
#     identical on every rebuild, not a side effect of whenever a container
#     happened to start.
#
#   - The game itself is deliberately NOT in the image. Steam clients update
#     themselves, and a server pinned to an older build becomes unjoinable the
#     day Keen ships an update. SteamCMD refreshes it in the data volume at
#     every start instead. This is the one place where the "never latest" rule
#     of the pikmine infrastructure cannot be applied.

FROM ubuntu:24.04

# Wine 10.0 rather than the newer 11.0, which is also available: the .NET 4.8
# install is the most fragile part of this image, and 10.0 has a year of
# reported use behind it. Both are pinned WineHQ stable releases, so trying 11
# is a one-line change followed by a rebuild.
ARG WINE_VERSION=10.0.0.0~noble-1

# Torch is distributed through its Jenkins, not GitHub releases: its only tag
# dates from 2023 while master is actively developed. The build number is the
# only pin available.
ARG TORCH_BUILD=347

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win64 \
    WINEPREFIX=/wineprefix \
    WINEDEBUG=-all \
    XDG_RUNTIME_DIR=/run/user/1000

# i386 is required even though the server is 64-bit: the .NET 4.8 installer
# lays down both architectures and fails without the 32-bit Wine runtime.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg2 unzip xz-utils cabextract \
      xvfb xauth winbind python3 lib32gcc-s1 \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
 && wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
 && apt-get update \
 && apt-get install -y --install-recommends \
      winehq-stable=${WINE_VERSION} \
      wine-stable=${WINE_VERSION} \
      wine-stable-amd64=${WINE_VERSION} \
      wine-stable-i386=${WINE_VERSION} \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Winetricks from upstream: the distribution package lags behind, and the verbs
# that fetch Microsoft installers break when their URLs move.
RUN wget -qO /usr/local/bin/winetricks \
      https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
 && chmod +x /usr/local/bin/winetricks

# Ubuntu 24.04 already ships a user at UID 1000. Reuse that slot rather than
# adding a second one, so files in the data volume keep a predictable owner.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd -m -u 1000 -s /bin/bash se

RUN mkdir -p /opt/steamcmd \
 && curl -sqL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    | tar xz -C /opt/steamcmd \
 && printf '#!/bin/sh\ncd /opt/steamcmd\nexec ./steamcmd.sh "$@"\n' > /usr/local/bin/steamcmd \
 && chmod +x /usr/local/bin/steamcmd \
 && chown -R se:se /opt/steamcmd

# /data is created here with the right owner on purpose: Docker copies the
# ownership of the mountpoint when it initialises an empty named volume, which
# is what lets the container run unprivileged.
#
# /run/user/1000 is what XDG_RUNTIME_DIR points at. Wine expects it to exist and
# to belong to the user running it.
RUN mkdir -p /wineprefix /data /opt/torch /run/user/1000 \
 && chown -R se:se /wineprefix /data /opt/torch /run/user/1000 \
 && chmod 700 /run/user/1000

COPY --chown=se:se image/build-wineprefix.sh /opt/bin/

USER se

# The heavy step, around ten minutes. See the script: the order matters and one
# of the calls needs a specific DLL override to avoid corrupting the prefix.
RUN bash /opt/bin/build-wineprefix.sh

# Torch is fetched at build time so the image is self-contained and a running
# server never depends on the Jenkins being up. The build number travels with
# it: the entrypoint compares it to decide whether to copy again.
RUN wget -q -O /tmp/torch.zip \
      "https://build.torchapi.com/job/Torch/job/master/${TORCH_BUILD}/artifact/bin/torch-server.zip" \
 && unzip -q -o /tmp/torch.zip -d /opt/torch \
 && rm /tmp/torch.zip \
 && echo "${TORCH_BUILD}" > /opt/torch/.torch-build

# Prefer the real .NET Framework over Wine Mono, and keep the embedded browser
# out of the way. Set after the install so winetricks does its own thing first.
ENV WINEDLLOVERRIDES="mscoree=n,b;mshtml=n,b"

# Reference configuration, copied into the volume only when it has none. The
# repository stays the source of truth for a fresh world; once a server runs,
# its live configuration is the one in the volume.
COPY --chown=se:se server/config/ /opt/base/

# The world itself. It is composed by hand on a play machine rather than
# generated by the server, so it travels as a premade checkpoint that the game
# copies into a live world on first start, the same way it does with Keen's own
# scenarios. Around 3 MB, mostly the sector file.
COPY --chown=se:se server/world-seed/ /opt/base-world/
COPY --chown=se:se image/entrypoint.sh image/inject-mods.py image/inject-admins.py \
     image/inject-settings.py /opt/bin/

WORKDIR /data
# Invoked through bash rather than relying on the executable bit, which does
# not survive a checkout on every platform.
ENTRYPOINT ["/bin/bash", "/opt/bin/entrypoint.sh"]
