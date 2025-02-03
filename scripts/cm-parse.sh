#!/usr/bin/env bash
#
# Script Name: upload-configmap-to-vault.sh
#
# Description:
#   1. Reads user inputs for:
#       - HashiCorp Vault URL
#       - ConfigMap file name (YAML)
#       - Target path in Vault (e.g. secret/my-configmap)
#   2. Parses the ConfigMap (.data) for key-value pairs.
#   3. Uploads those key-values into Vault.
#
# Prerequisites:
#   - 'vault' CLI installed
#   - 'yq' for YAML parsing
#   - Proper Vault authentication (e.g., 'vault login' or VAULT_TOKEN set)
#
# Usage:
#   ./upload-configmap-to-vault.sh
#   or pass arguments:
#       ./upload-configmap-to-vault.sh -u https://my-vault:8200 -c configmap.yaml -p secret/data/myapp
#   or set env vars:
#       VAULT_URL=https://my-vault:8200 CONFIGMAP_FILE=configmap.yaml VAULT_PATH=secret/myapp ./upload-configmap-to-vault.sh

set -euo pipefail

#######################################
# Show usage information.
#######################################
usage() {
  cat <<EOF
Usage: $0 [-u <vault-url>] [-c <configmap-file>] [-p <vault-path>]

Options:
  -u  HashiCorp Vault URL (e.g. https://my-vault:8200)
  -c  ConfigMap file name (YAML) (e.g. my-configmap.yaml)
  -p  Target path in Vault KV (e.g. secret/my-configmap)

Environment variables (alternative):
  VAULT_URL
  CONFIGMAP_FILE
  VAULT_PATH

Example:
  $0 -u https://my-vault:8200 -c my-configmap.yaml -p secret/my-configmap

EOF
  exit 1
}

#######################################
# Parse command-line arguments.
#######################################
while getopts "u:c:p:h" opt; do
  case ${opt} in
    u )
      VAULT_URL=$OPTARG
      ;;
    c )
      CONFIGMAP_FILE=$OPTARG
      ;;
    p )
      VAULT_PATH=$OPTARG
      ;;
    h )
      usage
      ;;
    * )
      usage
      ;;
  esac
done

#######################################
# Pull from environment variables if not set
#######################################
: "${VAULT_URL:=${VAULT_URL:-}}"
: "${CONFIGMAP_FILE:=${CONFIGMAP_FILE:-}}"
: "${VAULT_PATH:=${VAULT_PATH:-}}"

#######################################
# Prompt user if still not set
#######################################
if [ -z "${VAULT_URL}" ]; then
  read -r -p "Enter the Vault URL (e.g. https://my-vault:8200): " VAULT_URL
fi

if [ -z "${CONFIGMAP_FILE}" ]; then
  read -r -p "Enter the ConfigMap YAML file (e.g. my-configmap.yaml): " CONFIGMAP_FILE
fi

if [ -z "${VAULT_PATH}" ]; then
  read -r -p "Enter the Vault path (e.g. secret/my-configmap): " VAULT_PATH
fi

#######################################
# Validate inputs
#######################################
if [ -z "${VAULT_URL}" ] || [ -z "${CONFIGMAP_FILE}" ] || [ -z "${VAULT_PATH}" ]; then
  echo "Error: Missing required arguments."
  usage
fi

if [ ! -f "${CONFIGMAP_FILE}" ]; then
  echo "Error: ConfigMap file '${CONFIGMAP_FILE}' not found!"
  exit 1
fi

#######################################
# Show summary of inputs
#######################################
cat <<EOF
-------------------------------------------------------
HashiCorp Vault URL:  ${VAULT_URL}
ConfigMap file:       ${CONFIGMAP_FILE}
Vault KV path:        ${VAULT_PATH}
-------------------------------------------------------
EOF

#######################################
# Optional: Check Vault health or confirm connectivity
# (Requires that 'vault' CLI is installed and configured)
#######################################
echo "Checking Vault connectivity..."
if ! curl --fail -s "${VAULT_URL}/v1/sys/health" >/dev/null; then
  echo "Warning: Could not verify Vault at ${VAULT_URL}. Continuing anyway..."
fi

#######################################
# Parse ConfigMap data using 'yq'
# We want key-value pairs from ".data"
#######################################
# This command extracts all keys from the .data section and outputs "KEY=VALUE KEY2=VALUE2 ..."
# Explanation of the yq command:
#   - .data | to_entries        => turn the 'data' dict into a list of {key, value} objects
#   - map("\(.key)=\(.value)")  => transform each object into "KEY=VALUE" string
#   - join(" ")                 => join them all by space
#######################################
echo "Parsing key-value pairs from ConfigMap..."
KV_PAIRS=$(
  yq e '.data | to_entries | map("\(.key)=\(.value|@sh)") | join(" ")' "${CONFIGMAP_FILE}"
)

# If no data is found, KV_PAIRS could be empty or "null"
if [ -z "${KV_PAIRS}" ] || [ "${KV_PAIRS}" = "null" ]; then
  echo "No data found in the ConfigMap's .data section! Nothing to upload."
  exit 0
fi

echo "Key-value pairs extracted from ${CONFIGMAP_FILE}:"
echo "  ${KV_PAIRS}"
echo

#######################################
# Upload to Vault
# Using 'vault kv put <path> <key>=<value> ...'
#
# IMPORTANT:
#   1) For KVv2, if your engine is named 'secret/' at the root path,
#      'vault kv put secret/myapp ...' is typically enough (no 'data/' needed).
#      Check your environment for correct usage.
#   2) This uses Bash word-splitting on $KV_PAIRS.  
#      Make sure your keys/values do not have spaces in them.
#######################################
echo "Uploading key-value pairs to Vault: vault kv put ${VAULT_PATH} ${KV_PAIRS}"
# shellcheck disable=SC2086
vault kv put "${VAULT_PATH}" ${KV_PAIRS}

echo
echo "Upload complete!"
echo "-------------------------------------------------------"
echo "You can verify with: vault kv get ${VAULT_PATH}"
echo "-------------------------------------------------------"
