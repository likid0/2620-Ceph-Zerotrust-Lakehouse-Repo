#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/root/lakehouse"
TOKENS_FILE="${WORKDIR}/notebooks/tokens.json"

echo "🔑 Generating tokens.json from Terraform outputs…"
cd /root/terraform/polaris

# grab tokens
ADMIN_TOKEN=$(terraform output -raw admin_token)
ENGINEER_TOKEN=$(terraform output -raw engineer_token)
COMPLIANCE_TOKEN=$(terraform output -raw compliance_token)
ANALYST_TOKEN=$(terraform output -raw analyst_token)

# write them out
cat > "${TOKENS_FILE}" <<EOF
{
  "admin":      "${ADMIN_TOKEN}",
  "engineer":   "${ENGINEER_TOKEN}",
  "compliance": "${COMPLIANCE_TOKEN}",
  "analyst":    "${ANALYST_TOKEN}"
}
EOF
echo "→ Wrote ${TOKENS_FILE}"

# ──────────────────────────────────────────────────────────────
# Render Trino catalog/prod.properties for Iceberg REST + OAUTH2
# ──────────────────────────────────────────────────────────────

TRINO_CFG_DIR="${WORKDIR}/trino/catalog"
mkdir -p "${TRINO_CFG_DIR}"

echo "🔧 Rendering Trino catalog configuration…"
cat > "${TRINO_CFG_DIR}/prod.properties" <<EOF
connector.name=iceberg

iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://polaris:8181/api/catalog
iceberg.rest-catalog.warehouse=prod

iceberg.rest-catalog.security=OAUTH2
iceberg.rest-catalog.oauth2.token=${ENGINEER_TOKEN}

fs.native-s3.enabled=true
s3.endpoint=http://ceph-node2
s3.path-style-access=true
s3.region=${TF_VAR_s3_region:-default}

iceberg.rest-catalog.vended-credentials-enabled=true
iceberg.rest-catalog.nested-namespace-enabled=false
iceberg.rest-catalog.case-insensitive-name-matching=false
EOF

echo "→ Wrote ${TRINO_CFG_DIR}/prod.properties"
echo "⏳ Restarting Trino container to pick up changes…"
podman restart trino
echo "✔ Trino container restarted."


echo
echo "📓 Fetching JupyterLab URL (via podman compose logs)…"
podman compose -f "${WORKDIR}/docker-compose.yml" logs --tail 50 jupyter 2> /tmp/jupyter.logs
TOKEN=$(grep -Eo 'token=[0-9a-f]+' /tmp/jupyter.logs | head -1 | cut -d= -f2)
HOST_IP=$(ip route get 8.8.8.8 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' \
            | head -1)

echo
echo -e "🚀 JupyterLab is up!  Open here:\n\n    http://${HOST_IP}:8888/lab?token=${TOKEN}\n"
