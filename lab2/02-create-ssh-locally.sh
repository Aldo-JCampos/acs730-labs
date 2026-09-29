#!/bin/bash
#
# create_ssh_key.sh
# Generates an ed25519 SSH key pair named "<profile>-key" (derived from
# PROFILE in vars.sh, lowercased) in the same directory this script is
# run from, imports it into AWS as a key pair, and records references
# to both in vars.sh.

set -euo pipefail

# Directory where this script is located (and where the key/vars files live)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.sh"

# ---------------------------------------------------------------------------
# 0. Load vars.sh and set the AWS profile to use
# ---------------------------------------------------------------------------
if [[ ! -f "${VARS_FILE}" ]]; then
    echo "Error: ${VARS_FILE} not found. Create it with a PROFILE variable set." >&2
    exit 1
fi

source "${VARS_FILE}"

if [[ -z "${PROFILE:-}" ]]; then
    echo "Error: PROFILE is not set in ${VARS_FILE}." >&2
    exit 1
fi

export AWS_PROFILE="${PROFILE}"
echo "Using AWS profile: ${AWS_PROFILE}"

# Key name is derived from the profile: lowercased, with a "-key" suffix.
KEY_NAME="$(echo "${PROFILE}" | tr '[:upper:]' '[:lower:]')-key"
KEYS_DIR="${SCRIPT_DIR}/keys"
KEY_PATH="${KEYS_DIR}/${KEY_NAME}"
mkdir -p "${KEYS_DIR}"
echo "Using key name: ${KEY_NAME}"

# Pass -f (or --force) to overwrite an existing local key pair without asking.
FORCE=0
if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
    FORCE=1
fi

# ---------------------------------------------------------------------------
# 1. Generate the local SSH key pair
# ---------------------------------------------------------------------------
if [[ -f "${KEY_PATH}" || -f "${KEY_PATH}.pub" ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
        echo "Existing key found. Removing (--force given)..."
        chmod u+w "${KEY_PATH}" "${KEY_PATH}.pub" 2>/dev/null || true
        rm -f "${KEY_PATH}" "${KEY_PATH}.pub"
    else
        echo "Key pair already exists at ${KEY_PATH}. Using the existing local key."
    fi
fi

if [[ ! -f "${KEY_PATH}" ]]; then
    # Generate the key (no passphrase, ed25519 type)
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -N "" -C "${KEY_NAME}"

    # Restrict permissions: private key readable/writable by owner only,
    # public key readable by everyone.
    chmod 600 "${KEY_PATH}"
    chmod 644 "${KEY_PATH}.pub"

    echo "SSH key pair created:"
    echo "  Private key: ${KEY_PATH} (permissions 600)"
    echo "  Public key:  ${KEY_PATH}.pub (permissions 644)"
fi

PUB_KEY_FILE="${KEY_PATH}.pub"

# ---------------------------------------------------------------------------
# 2. Verify AWS CLI connectivity
# ---------------------------------------------------------------------------
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found. Install it and configure your credentials." >&2
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: Unable to authenticate with AWS using profile '${AWS_PROFILE}'." >&2
    exit 1
fi
echo "AWS CLI connection verified."

# ---------------------------------------------------------------------------
# 3. Import the key into AWS as a key pair (skip if it already exists)
# ---------------------------------------------------------------------------
if aws ec2 describe-key-pairs --key-names "${KEY_NAME}" &> /dev/null; then
    echo "Key pair '${KEY_NAME}' already exists in AWS, reusing it."
else
    echo "Importing key pair '${KEY_NAME}' into AWS ..."
    aws ec2 import-key-pair \
        --key-name "${KEY_NAME}" \
        --public-key-material "fileb://${PUB_KEY_FILE}" &> /dev/null
fi

KEY_PAIR_ID=$(aws ec2 describe-key-pairs \
    --key-names "${KEY_NAME}" \
    --query 'KeyPairs[0].KeyPairId' \
    --output text)

echo "AWS Key Pair ID: ${KEY_PAIR_ID}"

# ---------------------------------------------------------------------------
# 4. Record the key name and AWS key-pair reference in vars.sh
# ---------------------------------------------------------------------------
echo "KEY_NAME=${KEY_NAME}" >> "${VARS_FILE}"
echo "AWS_KEY_PAIR_ID=${KEY_PAIR_ID}" >> "${VARS_FILE}"

echo "Updated ${VARS_FILE} with KEY_NAME=${KEY_NAME} and AWS_KEY_PAIR_ID=${KEY_PAIR_ID}"