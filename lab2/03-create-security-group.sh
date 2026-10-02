#!/bin/bash
set -euo pipefail

# Disable the AWS CLI's pager (e.g. less) so command output never pauses
# the script waiting for a keypress.
export AWS_PAGER=""

# Resolve the directory this script lives in, so vars.sh is written alongside it
# regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/vars.sh"

# --- Load profile from vars.sh ---
if [ ! -f "$VARS_FILE" ]; then
  echo "ERROR: $VARS_FILE not found. Create it with PROFILE=\"your-profile\" first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$VARS_FILE"

if [ -z "${PROFILE:-}" ]; then
  echo "ERROR: PROFILE is not set in $VARS_FILE." >&2
  exit 1
fi

# --- Verify AWS access with this profile before doing anything else ---
echo "Verifying AWS access for profile '$PROFILE'..."
if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null; then
  echo "ERROR: Unable to authenticate with profile '$PROFILE'. Check your credentials." >&2
  exit 1
fi
echo "Access verified for profile '$PROFILE'."

# Export so every subsequent aws command picks it up automatically,
# without needing --profile on each call.
export AWS_PROFILE="$PROFILE"

# --- Config (edit as needed) ---
GROUP_NAME="SG1-SSH-and-HTTP"
DESCRIPTION="SSH from MyIP only; HTTP everywhere"
VPC_ID="$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)"

# --- Get current public IP ---
MY_IP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "Detected public IP: $MY_IP"

# --- Create security group (or reuse if one with this name already exists in this VPC) ---
EXISTING_GROUP_ID="$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)"

if [ -n "$EXISTING_GROUP_ID" ] && [ "$EXISTING_GROUP_ID" != "None" ]; then
  GROUP_ID="$EXISTING_GROUP_ID"
  echo "Security group '$GROUP_NAME' already exists in $VPC_ID — reusing $GROUP_ID"
else
  GROUP_ID="$(aws ec2 create-security-group \
    --group-name "$GROUP_NAME" \
    --description "$DESCRIPTION" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)"
  echo "Created security group: $GROUP_ID"
fi

# --- SSH rule (restricted to my IP) ---
if aws ec2 authorize-security-group-ingress \
  --group-id "$GROUP_ID" \
  --protocol tcp \
  --port 22 \
  --cidr "${MY_IP}/32" 2>/tmp/sg_err.log; then
  echo "Added SSH rule for ${MY_IP}/32"
elif grep -q "InvalidPermission.Duplicate" /tmp/sg_err.log; then
  echo "SSH rule for ${MY_IP}/32 already exists — skipping"
else
  cat /tmp/sg_err.log >&2
  exit 1
fi

# --- HTTP rule (open to anywhere) ---
if aws ec2 authorize-security-group-ingress \
  --group-id "$GROUP_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 2>/tmp/sg_err.log; then
  echo "Added HTTP rule for 0.0.0.0/0"
elif grep -q "InvalidPermission.Duplicate" /tmp/sg_err.log; then
  echo "HTTP rule for 0.0.0.0/0 already exists — skipping"
else
  cat /tmp/sg_err.log >&2
  exit 1
fi
rm -f /tmp/sg_err.log

# --- Save vars for reuse by other scripts
echo "VPC_ID=${VPC_ID}" >> "${VARS_FILE}"
echo "MY_IP=${MY_IP}" >> "${VARS_FILE}"
echo "SECURITY_GROUP_ID=${GROUP_ID}" >> "${VARS_FILE}"

echo "go to AWS console --> VPC --> Security Group -->  select ${GROUP_NAME} "
echo "take a screenshot  of the Inbound rules for the evidence folder "