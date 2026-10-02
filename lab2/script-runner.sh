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

: "${INSTANCE_ID:?INSTANCE_ID not set in vars.sh}"
: "${KEY_NAME:?KEY_NAME not set in vars.sh}"

AWS_PROFILE_ARGS=()
if [[ -n "${PROFILE:-}" ]]; then
  AWS_PROFILE_ARGS=(--profile "$PROFILE")
fi

# ---------------------------------------------------------------------------
# 1. Confirm ssh-agent has an identity loaded (no key file ever referenced)
# ---------------------------------------------------------------------------
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  echo "ERROR: no SSH_AUTH_SOCK found — is ssh-agent running for this session?" >&2
  exit 1
fi
if ! ssh-add -l >/dev/null 2>&1; then
  echo "ERROR: ssh-agent is running but has no keys loaded (ssh-add -l failed)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Confirm AWS CLI can resolve credentials
# ---------------------------------------------------------------------------
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found in PATH" >&2; exit 1; }

if ! aws sts get-caller-identity "${AWS_PROFILE_ARGS[@]}" >/dev/null 2>&1; then
  echo "ERROR: AWS CLI cannot resolve credentials" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Terminate the EC2 instance
# ---------------------------------------------------------------------------
STATE="$(aws ec2 describe-instances "${AWS_PROFILE_ARGS[@]}" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "not-found")"

if [[ "$STATE" == "not-found" || "$STATE" == "None" ]]; then
  echo "Instance $INSTANCE_ID not found — skipping termination."
elif [[ "$STATE" == "terminated" ]]; then
  echo "Instance $INSTANCE_ID already terminated."
else
  echo "Terminating instance $INSTANCE_ID (current state: $STATE)..."
  aws ec2 terminate-instances "${AWS_PROFILE_ARGS[@]}" --instance-ids "$INSTANCE_ID" >/dev/null

  echo "Waiting for instance $INSTANCE_ID to reach 'terminated'..."
  aws ec2 wait instance-terminated "${AWS_PROFILE_ARGS[@]}" --instance-ids "$INSTANCE_ID"
  echo "Instance $INSTANCE_ID terminated."
fi

# ---------------------------------------------------------------------------
# 4. Delete the key pair uploaded to AWS
# ---------------------------------------------------------------------------
if ! aws ec2 describe-key-pairs "${AWS_PROFILE_ARGS[@]}" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair $KEY_NAME not found — skipping deletion."
else
  echo "Deleting key pair $KEY_NAME..."
  aws ec2 delete-key-pair "${AWS_PROFILE_ARGS[@]}" --key-name "$KEY_NAME" >/dev/null
  echo "Key pair $KEY_NAME deleted."
fi

echo "Cleanup complete."