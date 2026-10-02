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
: "${SECURITY_GROUP_ID:?SECURITY_GROUP_ID not set in vars.sh}"
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
# 4. Delete the security group (must happen after the instance is gone)
# ---------------------------------------------------------------------------
echo "Waiting 20s before attempting security group deletion..."
sleep 20

if ! aws ec2 describe-security-groups "${AWS_PROFILE_ARGS[@]}" --group-ids "$SECURITY_GROUP_ID" >/dev/null 2>&1; then
  echo "Security group $SECURITY_GROUP_ID not found — skipping deletion."
else
  echo "Deleting security group $SECURITY_GROUP_ID..."
  ATTEMPTS=0
  MAX_ATTEMPTS=6
  DELETE_ERR=""
  until DELETE_ERR="$(aws ec2 delete-security-group "${AWS_PROFILE_ARGS[@]}" --group-id "$SECURITY_GROUP_ID" 2>&1 >/dev/null)"; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]]; then
      echo "ERROR: failed to delete security group $SECURITY_GROUP_ID after $MAX_ATTEMPTS attempts" >&2
      echo "Last AWS error: $DELETE_ERR" >&2

      echo "Network interfaces still using this security group:" >&2
      aws ec2 describe-network-interfaces "${AWS_PROFILE_ARGS[@]}" \
        --filters "Name=group-id,Values=$SECURITY_GROUP_ID" \
        --query 'NetworkInterfaces[].{ENI:NetworkInterfaceId,Status:Status,Desc:Description,Attachment:Attachment.InstanceId}' \
        --output table >&2 || true

      echo "Other security groups referencing this one in their rules:" >&2
      aws ec2 describe-security-groups "${AWS_PROFILE_ARGS[@]}" \
        --filters "Name=ip-permission.group-id,Values=$SECURITY_GROUP_ID" \
        --query 'SecurityGroups[].GroupId' --output table >&2 || true
      aws ec2 describe-security-groups "${AWS_PROFILE_ARGS[@]}" \
        --filters "Name=egress.ip-permission.group-id,Values=$SECURITY_GROUP_ID" \
        --query 'SecurityGroups[].GroupId' --output table >&2 || true

      exit 1
    fi
    echo "Security group still in use, retrying in 10s... ($ATTEMPTS/$MAX_ATTEMPTS)"
    sleep 10
  done
  echo "Security group $SECURITY_GROUP_ID deleted."
fi

# ---------------------------------------------------------------------------
# 5. Delete the key pair uploaded to AWS
# ---------------------------------------------------------------------------
if ! aws ec2 describe-key-pairs "${AWS_PROFILE_ARGS[@]}" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair $KEY_NAME not found — skipping deletion."
else
  echo "Deleting key pair $KEY_NAME..."
  aws ec2 delete-key-pair "${AWS_PROFILE_ARGS[@]}" --key-name "$KEY_NAME" >/dev/null
  echo "Key pair $KEY_NAME deleted."
fi

echo "Cleanup complete."