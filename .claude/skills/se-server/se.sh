#!/usr/bin/env bash
#
# Runs a command inside the live Space Engineers container on pikmine.
#
#   se.sh ls /data/server/Logs           in the container
#   se.sh --host docker logs --tail 50 "$SE"   on the host, $SE is the container
#
# Two things this exists for. The container name carries a Dokploy hash that
# changes on every redeploy, so it is resolved from the compose service label
# rather than written down anywhere. And the command travels on stdin instead of
# through the argument list: ssh, docker exec and a shell nested inside each
# other quote badly, which is how an hour gets lost to "Unterminated quoted
# string".
set -euo pipefail

HOST="${SE_HOST:-pikmine}"
LABEL=com.docker.compose.service=space-engineers

ON_HOST=0
if [ "${1:-}" = "--host" ]; then
  ON_HOST=1
  shift
fi

[ $# -gt 0 ] || { echo "usage: se.sh [--host] <command...>" >&2; exit 2; }

RESOLVE="SE=\$(docker ps -q -f label=${LABEL} | head -1)
[ -n \"\$SE\" ] || { echo 'no running space-engineers container' >&2; exit 1; }
export SE"

if [ "${ON_HOST}" = 1 ]; then
  ssh "${HOST}" "${RESOLVE}
exec bash -s" <<EOF
$*
EOF
else
  ssh "${HOST}" "${RESOLVE}
exec docker exec -i \"\$SE\" bash -s" <<EOF
$*
EOF
fi
