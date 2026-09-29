#!/bin/bash
# Connects to the instance launched by 04-launch-ec2-instance.sh (same key,
# same vars.sh) and creates a sudo-enabled Linux user, named after PROFILE
# (lowercased, with a "User" suffix — e.g. profile "ACS730" -> "acs730User").
#
# No password is created. Password auth is not needed:
#   - The user logs in over SSH with a key only (password SSH login is off
#     by default on this AMI, and the account is created with a locked
#     password, so there's nothing to log in with anyway).
#   - sudo is granted through a dedicated /etc/sudoers.d drop-in scoped to
#     this one user, with NOPASSWD, instead of the "wheel" group default
#     (which would demand a password sudo would otherwise have to prompt
#     for, and that we never set).
set -euo pipefail

# ---------------------------------------------------------------------------
# Load configuration from vars.sh (same folder as this script)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/vars.sh"

if [[ ! -f "$VARS_FILE" ]]; then
  echo "ERROR: $VARS_FILE not found" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$VARS_FILE"

: "${PROFILE:?PROFILE is not set in vars.sh}"
: "${INSTANCE_ID:?INSTANCE_ID is not set in vars.sh (run 04-launch-ec2-instance.sh first)}"

export AWS_PROFILE="$PROFILE"

VM_SUDO_USER="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')User"
SSH_USER="ec2-user"

# ---------------------------------------------------------------------------
# 1. Look up the instance's public IP (04 prints it but doesn't save it)
# ---------------------------------------------------------------------------
read -r STATE VM_PUBLIC_IP < <(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress]' \
  --output text)

if [[ "$STATE" != "running" || -z "$VM_PUBLIC_IP" || "$VM_PUBLIC_IP" == "None" ]]; then
  echo "ERROR: $INSTANCE_ID is '$STATE' with public IP '$VM_PUBLIC_IP'" >&2
  exit 1
fi
echo "Instance $INSTANCE_ID is running at $VM_PUBLIC_IP"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
ssh_admin() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_PUBLIC_IP" "$@"; }
ssh_new()   { ssh "${SSH_OPTS[@]}" "$VM_SUDO_USER@$VM_PUBLIC_IP" "$@"; }

# ---------------------------------------------------------------------------
# 2. Connect with the key from script 04 (via ssh-agent)
# ---------------------------------------------------------------------------
echo "Connecting as $SSH_USER ..."
ssh_admin 'echo "  Connected as $(whoami) on $(hostname)"'

# ---------------------------------------------------------------------------
# 3. Create the user (no password), grant NOPASSWD sudo scoped to just this
#    user, and let it log in with the same key
#    (safe to re-run: skips creation if the user already exists)
# ---------------------------------------------------------------------------
echo "Creating user $VM_SUDO_USER ..."
ssh_admin "sudo bash -s -- '$VM_SUDO_USER' '$SSH_USER'" << 'REMOTE'
set -euo pipefail
VM_SUDO_USER="$1"
SSH_USER="$2"

if id "$VM_SUDO_USER" &>/dev/null; then
  echo "  User $VM_SUDO_USER already exists, skipping creation."
else
  # -p '!' leaves the password field locked ("!") instead of empty, so
  # password login/auth stays disabled for this account.
  useradd -m -s /bin/bash -p '!' "$VM_SUDO_USER"
  echo "  User $VM_SUDO_USER created (no password set, account locked)."
fi

# Grant sudo via a dedicated, minimal drop-in (least privilege: this file
# affects only $VM_SUDO_USER, not a shared group like wheel).
SUDOERS_FILE="/etc/sudoers.d/90-$VM_SUDO_USER"
echo "$VM_SUDO_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"
echo "  Wrote and validated $SUDOERS_FILE"

# Copy ec2-user's authorized key so $VM_SUDO_USER can SSH in with the same key
NEW_HOME="$(getent passwd "$VM_SUDO_USER" | cut -d: -f6)"
SRC_HOME="$(getent passwd "$SSH_USER" | cut -d: -f6)"
NEW_GROUP="$(id -gn "$VM_SUDO_USER")"
install -d -m 700 -o "$VM_SUDO_USER" -g "$NEW_GROUP" "$NEW_HOME/.ssh"
install -m 600 -o "$VM_SUDO_USER" -g "$NEW_GROUP" \
  "$SRC_HOME/.ssh/authorized_keys" "$NEW_HOME/.ssh/authorized_keys"
echo "  SSH key installed for $VM_SUDO_USER."
REMOTE

# ---------------------------------------------------------------------------
# 5. Verify that the new user has sudo power
# ---------------------------------------------------------------------------
echo
echo "=== Verifying sudo for $VM_SUDO_USER ==="
FAILED=0

# 5a. Account has no usable password (login is SSH-key only)
echo "[1/4] Account password status:"
PW_STATUS="$(ssh_admin "sudo passwd -S $VM_SUDO_USER")"
echo "      $PW_STATUS"
if awk '{print $2}' <<< "$PW_STATUS" | grep -qE '^(L|LK|NP)$'; then
  echo "      PASS: account has no usable password (locked / not set)"
else
  echo "      FAIL: account has a usable password"; FAILED=1
fi

# 5b. What sudo says this user is allowed to run
echo "[2/4] sudo rules for $VM_SUDO_USER:"
SUDO_RULES="$(ssh_admin "sudo -l -U $VM_SUDO_USER" || true)"
sed 's/^/      /' <<< "$SUDO_RULES"
if grep -Eq 'NOPASSWD:\s*ALL' <<< "$SUDO_RULES"; then
  echo "      PASS: $VM_SUDO_USER may run all commands via sudo"
else
  echo "      FAIL: no full NOPASSWD sudo rule found"; FAILED=1
fi

# 5c. Log in AS the new user (key only) and actually run a command as root
echo "[3/4] Running 'sudo whoami' as $VM_SUDO_USER over SSH:"
WHOAMI="$(ssh_new "sudo whoami" || true)"
echo "      Result: ${WHOAMI:-<nothing>}"
if [[ "$WHOAMI" == "root" ]]; then
  echo "      PASS: $VM_SUDO_USER can become root, without being prompted for a password"
else
  echo "      FAIL: sudo did not return root"; FAILED=1
fi

# 5d. Scope check: the drop-in only names this user, not a shared group
echo "[4/4] sudoers drop-in is scoped to $VM_SUDO_USER only:"
DROPIN="$(ssh_admin "sudo cat /etc/sudoers.d/90-$VM_SUDO_USER" || true)"
echo "      $DROPIN"
if grep -q "^$VM_SUDO_USER " <<< "$DROPIN" && ! grep -q '^%' <<< "$DROPIN"; then
  echo "      PASS: rule applies to $VM_SUDO_USER individually, not a group"
else
  echo "      FAIL: rule is missing or not scoped to this user"; FAILED=1
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "All checks passed. $VM_SUDO_USER has sudo power (key-based login, no password)."
  echo "Log in with (key already loaded in ssh-agent):  ssh $VM_SUDO_USER@$VM_PUBLIC_IP"
else
  echo "One or more checks FAILED." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Record the vars created in vars.sh
# ---------------------------------------------------------------------------
echo "VM_SUDO_USER=${VM_SUDO_USER}" >> "${VARS_FILE}"
echo "VM_PUBLIC_IP=${VM_PUBLIC_IP}" >> "${VARS_FILE}"