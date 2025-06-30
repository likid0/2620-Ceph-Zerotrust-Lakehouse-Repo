#!/usr/bin/env bash
set -euo pipefail

# ─── Colour palette ────────────────────────────────────────────────────────────
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
RESET="\033[0m"
SPINNER=( '|' '/' '-' '\\' )

# ─── Resolve repo root (one level up from this script) ─────────────────────────
SCRIPT_DIR="/root/script"
REPO_DIR="/root/lakehouse"

# ─── Paths inside the repo ─────────────────────────────────────────────────────
CEPH_TF_DIR="/root/terraform/ceph"
POLARIS_TF_DIR="/root/terraform/polaris"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"
COMPOSE_ENV_FILE="${REPO_DIR}/.compose-aws.env"
TOKENS_FILE="${REPO_DIR}/notebooks/tokens.json"
POLARIS_HEALTH_URL="http://localhost:8182/healthcheck"

# ─── Banner & UI helpers ───────────────────────────────────────────────────────
show_banner() {
  local LINE="  C E P H   ↔   P O L A R I S  "
  local WIDTH=${#LINE}
  local BORDER
  BORDER=$(printf '═%.0s' $(seq 1 "${WIDTH}"))
  echo -e "${BLUE}╔${BORDER}╗${RESET}"
  echo -e "${BLUE}║${GREEN}${LINE}${BLUE}║${RESET}"
  echo -e "${BLUE}╚${BORDER}╝${RESET}\n"
}

display_step() {
  echo -ne "${BLUE}Press Enter to review next step...${RESET}"
  read -r
  clear
  show_banner
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${BLUE}▶ $1${RESET}"
  echo -e "${GREEN}========================================${RESET}"
  echo -e "  • $2"
  [ -n "${3-}" ] && printf "\n%s\n" "$(cat "$3")"
  echo
  echo -ne "${BLUE}Press Enter to execute this step...${RESET}"
  read -r
  echo
}

log() { printf "\n${BLUE}▶ %s${RESET}\n" "$*"; }

usage() { echo "Usage: $0 {up|containers|destroy}"; exit 1; }

# ─── Terraform helpers ────────────────────────────────────────────────────────
terraform_init()    { terraform -chdir="$1" init -upgrade -input=false; }
terraform_apply()   { terraform -chdir="$1" apply   -auto-approve; }
terraform_destroy() { terraform -chdir="$1" destroy -auto-approve; }

safe_import() {
  dir=$1 addr=$2 id=$3
  terraform -chdir="$dir" state show "$addr" &>/dev/null && return 0
  terraform -chdir="$dir" import "$addr" "$id" 2>/dev/null || true
}

wait_for_polaris() {
  log "Waiting for Polaris healthcheck…"
  for i in $(seq 0 $(( ${#SPINNER[@]} * 10 ))); do
    if curl -fsSL "$POLARIS_HEALTH_URL" &>/dev/null; then
      echo -e " ${GREEN}OK${RESET}"
      return
    fi
    printf "\b${SPINNER[i % ${#SPINNER[@]}]}"
    sleep 0.2
  done
  echo -e " ${RED}FAILED${RESET}"
  exit 1
}

# ─── Helper: (re)generate .compose-aws.env ─────────────────────────────────────
make_env_file() {
  if [[ -f "$COMPOSE_ENV_FILE" ]]; then
      log "Using existing ${COMPOSE_ENV_FILE}"
      return
  fi
  log "Creating ${COMPOSE_ENV_FILE} from Terraform outputs"

  ADMIN_ACCESS_KEY=$(terraform -chdir="$CEPH_TF_DIR" output -raw admin_access_key)
  ADMIN_SECRET_KEY=$(terraform -chdir="$CEPH_TF_DIR" output -raw admin_secret_key)
  CEPH_ENDPOINT=$(grep -E '^[[:space:]]*ceph_endpoint' "$CEPH_TF_DIR/terraform.tfvars" | \
                  awk -F= '{print $2}' | tr -d ' "')

  cat > "$COMPOSE_ENV_FILE" <<EOF
AWS_ACCESS_KEY_ID=${ADMIN_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${ADMIN_SECRET_KEY}
AWS_REGION=default
S3_ENDPOINT=${CEPH_ENDPOINT}
EOF
  log "✔ Wrote ${COMPOSE_ENV_FILE}"
}

# ─── Full “up” target: Terraform + containers ─────────────────────────────────
cmd_up() {
  show_banner

  display_step "1️⃣ Ceph Terraform Stack" \
               "Provision bucket, IAM user, role & policy" \
               "${CEPH_TF_DIR}/terraform.tfvars"

  terraform_init "$CEPH_TF_DIR"
  safe_import "$CEPH_TF_DIR" aws_s3_bucket.catalog_bucket     "polarisdemo"
  safe_import "$CEPH_TF_DIR" aws_iam_user.catalog_admin       "admin"
  safe_import "$CEPH_TF_DIR" aws_iam_role.catalog_client_role "client"
  terraform_apply "$CEPH_TF_DIR"

  make_env_file   # <── generate env‑file after Ceph stack

  display_step "2️⃣ Container Stack" \
               "Launch Polaris · Trino · Jupyter · Superset"
  podman compose -f "$COMPOSE_FILE" \
                 --env-file "$COMPOSE_ENV_FILE" \
                 up -d --remove-orphans
  wait_for_polaris

  display_step "3️⃣ Polaris Terraform Stack" \
               "Configure catalog, namespace, principals & roles"
  terraform_init  "$POLARIS_TF_DIR"
  terraform_apply "$POLARIS_TF_DIR"

  display_step "4️⃣ Generate Tokens JSON" \
               "Extract tokens for Admin, Engineer, Compliance & Analyst"

  ADMIN_TOKEN=$(terraform -chdir="$POLARIS_TF_DIR" output -raw admin_token)
  ENGINEER_TOKEN=$(terraform -chdir="$POLARIS_TF_DIR" output -raw engineer_token)
  COMPLIANCE_TOKEN=$(terraform -chdir="$POLARIS_TF_DIR" output -raw compliance_token)
  ANALYST_TOKEN=$(terraform -chdir="$POLARIS_TF_DIR" output -raw analyst_token)

  jq -n \
    --arg admin      "$ADMIN_TOKEN" \
    --arg engineer   "$ENGINEER_TOKEN" \
    --arg compliance "$COMPLIANCE_TOKEN" \
    --arg analyst    "$ANALYST_TOKEN" \
    '{admin:$admin, engineer:$engineer, compliance:$compliance, analyst:$analyst}' >"$TOKENS_FILE"
  log "Tokens written to $TOKENS_FILE"

  mkdir -p "${REPO_DIR}/trino/catalog"
  cat > "${REPO_DIR}/trino/catalog/prod.properties" <<EOF
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://polaris:8181/api/catalog
iceberg.rest-catalog.warehouse=prod
iceberg.rest-catalog.security=OAUTH2
iceberg.rest-catalog.oauth2.token=$ANALYST_TOKEN
fs.native-s3.enabled=true
s3.endpoint=$(grep -oP '(?<=S3_ENDPOINT=).*' "$COMPOSE_ENV_FILE")
s3.path-style-access=true
s3.region=default
iceberg.rest-catalog.vended-credentials-enabled=true
EOF
  log "✔ trino/catalog/prod.properties rendered"
  podman restart trino

  display_step "5️⃣ Jupyter Ready" "Copy this URL into your browser"
  podman compose logs --tail 25 jupyter 2>/tmp/jup.log
  TOKEN=$(grep -Eo 'token=[0-9a-f]+' /tmp/jup.log | head -1 | cut -d= -f2)
  echo -e "\n${GREEN}Jupyter Lab:${RESET} http://localhost:8888/lab?token=${TOKEN}\n"
}

# ─── Containers‑only target ───────────────────────────────────────────────────
cmd_containers() {
  show_banner
  make_env_file   # <── build env‑file if user already ran Terraform manually

  display_step "🚀 Launch analytic stack" \
               "Start Polaris · Trino · Jupyter · Superset"
  podman compose -f "$COMPOSE_FILE" \
                 --env-file "$COMPOSE_ENV_FILE" \
                 up -d --remove-orphans
  wait_for_polaris

  display_step "✅ Services running" \
               "Polaris is healthy; container list and URLs below."
  podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

  podman compose logs --tail 25 jupyter 2>/tmp/jup.log
  TOKEN=$(grep -Eo 'token=[0-9a-f]+' /tmp/jup.log | head -1 | cut -d= -f2)
  echo
  echo -e "${GREEN}Polaris UI:${RESET}   http://localhost:8182"
  echo -e "${GREEN}Superset:${RESET}     http://localhost:8088"
  echo -e "${GREEN}Jupyter Lab:${RESET}  http://localhost:8888/lab?token=${TOKEN}\n"
}

# ─── Destroy target ───────────────────────────────────────────────────────────
cmd_destroy() {
  show_banner

  display_step "🛑 Tear Down: Containers" \
               "Stop & remove Polaris container stack"
  podman compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" down -v || true

  display_step "🛑 Tear Down: Polaris Terraform" \
               "Destroy catalog, roles & principals"
  terraform_init  "$POLARIS_TF_DIR" && terraform_destroy "$POLARIS_TF_DIR" || true

  display_step "🛑 Tear Down: Ceph Terraform" \
               "Destroy bucket & IAM resources"
  terraform_init  "$CEPH_TF_DIR" && terraform_destroy "$CEPH_TF_DIR" || true

  rm -f "$COMPOSE_ENV_FILE" "$TOKENS_FILE" 2>/dev/null || true
  log "Cleanup complete"
}

# ─── CLI entrypoint ───────────────────────────────────────────────────────────
case "${1:-}" in
  up)         cmd_up         ;;
  containers) cmd_containers ;;
  destroy)    cmd_destroy    ;;
  *)          usage          ;;
esac

