#!/usr/bin/env bash
#
# Simple helper for Terraform’s external data source.
# Usage: fetch_token.sh <client_id> <client_secret> <scope>
set -euo pipefail

CLIENT_ID="$1"
CLIENT_SECRET="$2"
SCOPE="$3"

HOST="${POLARIS_HOST:-localhost}"
PORT="${POLARIS_PORT:-8181}"

TOKEN=$(curl -s -X POST "http://${HOST}:${PORT}/api/catalog/v1/oauth/tokens" \
          -d grant_type=client_credentials \
          -d "client_id=${CLIENT_ID}" \
          -d "client_secret=${CLIENT_SECRET}" \
          -d "scope=${SCOPE}" | jq -r '.access_token')

# Terraform requires a valid JSON map on stdout
jq -n --arg access_token "$TOKEN" '{access_token:$access_token}'
