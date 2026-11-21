#!/usr/bin/env bash
# boot-to-ready.sh <label> <host> <start-epoch-seconds>
#
# Polls http://<host>/ until it answers, then prints how long it has
# been since <start-epoch-seconds>. The caller starts the clock at the
# moment it asks AWS for an instance, so the number includes everything:
# launch, boot, agent registration, configuration and service start.
set -euo pipefail
 
label=${1:?usage: boot-to-ready.sh <label> <host> <start-epoch>}
host=${2:?usage: boot-to-ready.sh <label> <host> <start-epoch>}
start=${3:?usage: boot-to-ready.sh <label> <host> <start-epoch>}
 
until curl -fsS -m 2 "http://${host}/" >/dev/null 2>&1; do
  sleep 2
done
 
echo "${label}: $(( $(date +%s) - start )) seconds"
