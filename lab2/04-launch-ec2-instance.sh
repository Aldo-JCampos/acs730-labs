#!/bin/bash
# Creates the "Lab-workstation" EC2 instance using the key pair from vars.sh
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
: "${KEY_NAME:?KEY_NAME is not set in vars.sh}"
: "${VPC_ID:?VPC_ID is not set in vars.sh}"
: "${MY_IP:?MY_IP is not set in vars.sh}"
: "${SECURITY_GROUP_ID:?SECURITY_GROUP_ID is not set in vars.sh}"

export AWS_PROFILE="$PROFILE"

# Instance settings (taken from the console-generated command)
AMI_ID="ami-0fef201115eefe936"
INSTANCE_TYPE="t3.micro"
INSTANCE_NAME="Lab-workstation"

# ---------------------------------------------------------------------------
# 1. Pick a subnet in the VPC (prefer one that auto-assigns public IPs)
# ---------------------------------------------------------------------------
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[0].SubnetId' --output text)

if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)
fi

if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  echo "ERROR: No subnets found in VPC $VPC_ID" >&2
  exit 1
fi
echo "Using subnet: $SUBNET_ID"

# ---------------------------------------------------------------------------
# 2. Launch the instance with the key pair attached
# ---------------------------------------------------------------------------
echo "Launching $INSTANCE_NAME ($INSTANCE_TYPE) ..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --ebs-optimized \
  --network-interfaces "{\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"SubnetId\":\"$SUBNET_ID\",\"Groups\":[\"$SECURITY_GROUP_ID\"]}" \
  --credit-specification '{"CpuCredits":"unlimited"}' \
  --tag-specifications "{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"$INSTANCE_NAME\"}]}" \
  --metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' \
  --private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":true,"EnableResourceNameDnsAAAARecord":false}' \
  --count 1 \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for the instance to be running ..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# ---------------------------------------------------------------------------
# 3. Add the private key to the ssh-agent (so it can be forwarded if you
#    need to hop from this instance to another VM later)
# ---------------------------------------------------------------------------
PRIVATE_KEY_PATH="$SCRIPT_DIR/keys/$KEY_NAME"

if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  eval "$(ssh-agent -s)" >/dev/null
fi
ssh-add "$PRIVATE_KEY_PATH"

# ---------------------------------------------------------------------------
# 4. Output connection info
# ---------------------------------------------------------------------------
echo
echo "Done! $INSTANCE_NAME is running."
echo "  Instance ID: $INSTANCE_ID"
echo "  Subnet ID:   $SUBNET_ID"
echo "  Public IP:   $PUBLIC_IP"
echo
echo "Waiting 20s for the instance to finish booting before it's ready for SSH ..."
sleep 20

echo
echo "Connect with (-A forwards the agent so the key is available if you"
echo "SSH onward from this instance):"
echo "  ssh -A ec2-user@$PUBLIC_IP"

# ---------------------------------------------------------------------------
# 5. Record the vars created in vars.sh
# ---------------------------------------------------------------------------
echo "SUBNET_ID=${SUBNET_ID}" >> "${VARS_FILE}"
echo "INSTANCE_ID=${INSTANCE_ID}" >> "${VARS_FILE}"