#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Load vars.sh (same directory as this script)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.sh"

if [[ ! -f "$VARS_FILE" ]]; then
  echo "ERROR: $VARS_FILE not found" >&2
  exit 1
fi
source "$VARS_FILE"

: "${KEY_NAME:?KEY_NAME not set in vars.sh}"
: "${VM_SUDO_USER:?VM_SUDO_USER not set in vars.sh}"
: "${VM_PUBLIC_IP:?VM_PUBLIC_IP not set in vars.sh}"

# DEPLOY_SCRIPT, SERVICE_FILE, and SERVICE_NAME are hardcoded here by system
# requirement (fixed filenames/unit name this lab expects) rather than
# pulled from vars.sh — they are not meant to be configurable per-run.
# NOTE: deploy-web.sh is required to live inside a scripts/ subfolder
# alongside this script (i.e. ${SCRIPT_DIR}/scripts/deploy-web.sh).
DEPLOY_SCRIPT="${SCRIPT_DIR}/scripts/deploy-web.sh"
SERVICE_FILE="${SCRIPT_DIR}/acs730-web.service"
SERVICE_NAME="acs730-web"

for f in "$DEPLOY_SCRIPT" "$SERVICE_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file $f not found" >&2
    exit 1
  fi
done

# NOTE: KEY_NAME names the key pair imported to AWS (see 02); the private
# key file itself lives at ./keys/${KEY_NAME}. Per project convention,
# connections rely on ssh-agent already holding this key — no -i flag is
# passed here. If ssh-agent isn't running or the key isn't loaded, the
# commands below will fail fast with a clear SSH auth error.
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
ssh_run() { ssh "${SSH_OPTS[@]}" "${VM_SUDO_USER}@${VM_PUBLIC_IP}" "$@"; }
scp_to()  { scp "${SSH_OPTS[@]}" "$1" "${VM_SUDO_USER}@${VM_PUBLIC_IP}:$2"; }

# ---------------------------------------------------------------------------
# 1. Connect and confirm reachability
# ---------------------------------------------------------------------------
echo "Connecting as ${VM_SUDO_USER}@${VM_PUBLIC_IP} (key: ./keys/${KEY_NAME}) ..."
ssh_run 'echo "  Connected as $(whoami) on $(hostname)"'

# ---------------------------------------------------------------------------
# 2. Copy deploy-web.sh and the service unit to the VM
#    (vars.sh is NOT copied — deploy-web.sh derives the user via whoami,
#    since it always runs as VM_SUDO_USER over this same SSH connection)
# ---------------------------------------------------------------------------
echo "Copying deploy-web.sh and ${SERVICE_NAME}.service ..."
scp_to "$DEPLOY_SCRIPT" "~/deploy-web.sh"
scp_to "$SERVICE_FILE"  "~/${SERVICE_NAME}.service"
ssh_run "chmod +x ~/deploy-web.sh"

# ---------------------------------------------------------------------------
# 3. Run deploy-web.sh on the VM (installs httpd, writes index.html, starts it)
# ---------------------------------------------------------------------------
echo "Running deploy-web.sh on the VM ..."
ssh_run "~/deploy-web.sh"

echo "go to http://${VM_PUBLIC_IP} and take a screenshot for evidence before reboot"
read -r -p "Press Enter to continue with step 4 (install/enable/start the service and reboot) ..."

# ---------------------------------------------------------------------------
# 4. Install the systemd unit, reload, enable, and start it
# ---------------------------------------------------------------------------
echo "Installing ${SERVICE_NAME}.service ..."
ssh_run "sudo mv ~/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service && \
         sudo chown root:root /etc/systemd/system/${SERVICE_NAME}.service && \
         sudo chmod 644 /etc/systemd/system/${SERVICE_NAME}.service"

echo "Reloading systemd, enabling and starting ${SERVICE_NAME} ..."
ssh_run "sudo systemctl daemon-reload && \
         sudo systemctl enable --now ${SERVICE_NAME}"

# ---------------------------------------------------------------------------
# 5. Reboot the instance
# ---------------------------------------------------------------------------
echo "Rebooting the instance ..."
ssh_run "sudo reboot" || true

# ---------------------------------------------------------------------------
# 6. Wait for the instance to come back up
# ---------------------------------------------------------------------------
echo "Waiting for ${VM_PUBLIC_IP} to come back online ..."
sleep 10
MAX_ATTEMPTS=30
ATTEMPT=0
until ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
      "${VM_SUDO_USER}@${VM_PUBLIC_IP}" 'true' 2>/dev/null; do
  ATTEMPT=$((ATTEMPT + 1))
  if [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
    echo "ERROR: instance did not come back online after $((MAX_ATTEMPTS * 5))s" >&2
    exit 1
  fi
  echo "  Not up yet (attempt ${ATTEMPT}/${MAX_ATTEMPTS}), retrying in 5s ..."
  sleep 5
done
echo "Instance is back online."

# ---------------------------------------------------------------------------
# 7. Verify the service and httpd survived the reboot
# ---------------------------------------------------------------------------
echo
echo "=== Verifying ${SERVICE_NAME} and httpd after reboot ==="
FAILED=0

echo "[1/3] ${SERVICE_NAME} enabled:"
ENABLED="$(ssh_run "sudo systemctl is-enabled ${SERVICE_NAME}" || true)"
echo "      $ENABLED"
[[ "$ENABLED" == "enabled" ]] && echo "      PASS" || { echo "      FAIL"; FAILED=1; }

echo "[2/3] ${SERVICE_NAME} active:"
ACTIVE_SVC="$(ssh_run "sudo systemctl is-active ${SERVICE_NAME}" || true)"
echo "      $ACTIVE_SVC"
[[ "$ACTIVE_SVC" == "active" ]] && echo "      PASS" || { echo "      FAIL"; FAILED=1; }

echo "[3/3] httpd active:"
ACTIVE_HTTPD="$(ssh_run "sudo systemctl is-active httpd" || true)"
echo "      $ACTIVE_HTTPD"
[[ "$ACTIVE_HTTPD" == "active" ]] && echo "      PASS" || { echo "      FAIL"; FAILED=1; }

echo
echo "curl http://${VM_PUBLIC_IP} output:"
ssh_run "curl -s localhost | head -3" | sed 's/^/  /'

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "All checks passed. ${SERVICE_NAME} and httpd are running after reboot."
  echo "go to http://${VM_PUBLIC_IP} and take a screenshot for evidence after reboot"
else
  echo "One or more checks FAILED." >&2
  exit 1
fi