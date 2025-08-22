#!/usr/bin/env bash
# ceph-post-deploy-healthcheck.sh
# Basic post-deployment checks for Ceph: health OK, RGW running, Dashboard up on :8443

set -euo pipefail

# ---- Configurable knobs -------------------------------------------------------
: "${TIMEOUT_SEC:=10}"                        # curl and ceph command timeouts
: "${DASHBOARD_URL:=}"                        # optional override, e.g. https://ceph-node-00:8443/
: "${CEPH_BIN:=ceph}"                         # set to "sudo ceph" if needed
: "${REQUIRE_HEALTH:=HEALTH_OK}"              # expected health
: "${REQUIRE_ALL_RGW_RUNNING:=false}"         # true to require all RGW daemons running, else at least one
# --------------------------------------------------------------------------------

# Split CEPH_BIN into an array to support values like "sudo ceph"
read -ra CEPH <<< "$CEPH_BIN"

have_jq=false
if command -v jq >/dev/null 2>&1; then have_jq=true; fi

log()   { printf "%s\n" "$*"; }
ok()    { printf "[ OK ] %s\n" "$*"; }
warn()  { printf "[WARN] %s\n" "$*" >&2; }
fail()  { printf "[FAIL] %s\n" "$*" >&2; }

die()   { fail "$*"; exit 1; }

run_ceph() {
  # Add a basic timeout so we do not hang forever
  timeout "$TIMEOUT_SEC" "${CEPH[@]}" "$@"
}

# ---- Check 1: Cluster health --------------------------------------------------
check_health() {
  local status=""
  if $have_jq; then
    # health.status for newer releases; fall back to overall_status for older ones
    status="$(run_ceph status -f json | jq -r '.health.status // .health.overall_status // empty')"
  fi

  if [[ -z "${status:-}" ]]; then
    # Fallback to parsing text output
    status="$(run_ceph -s | awk -F': *' '/^ *health:/{print $2; exit}')"
    status="${status%% *}"   # take first token like HEALTH_OK
  fi

  [[ -z "${status:-}" ]] && die "Unable to determine cluster health."

  if [[ "$status" == "$REQUIRE_HEALTH" ]]; then
    ok "Cluster health is $status"
  else
    fail "Cluster health is $status; expected $REQUIRE_HEALTH"
    return 1
  fi
}

# ---- Check 2: RGW daemons running --------------------------------------------
check_rgw() {
  local total=0 running=0 not_running_names=""

  if $have_jq; then
    # cephadm orchestrator ps output in JSON
    local json
    if ! json="$(run_ceph orch ps --daemon-type rgw -f json 2>/dev/null)"; then
      # Older cephadm might not support --daemon-type; try filter in jq
      json="$(run_ceph orch ps -f json)"
      json="$(printf "%s" "$json" | jq '[.[] | select((.daemon_type // .daemon_name) | tostring | test("rgw"))]')"
    fi

    total="$(printf "%s" "$json" | jq 'length')"
    running="$(printf "%s" "$json" | jq '[.[] | select((.status_desc // .status // "") | ascii_downcase | test("^running$"))] | length')"
    # Collect non-running names for visibility
    not_running_names="$(printf "%s" "$json" | jq -r '.[] | select(((.status_desc // .status // "") | ascii_downcase) != "running") | (.daemon_name // .name // .service_name // "rgw-unknown")' | paste -sd, -)"
  else
    # Text fallback
    local ps
    ps="$(run_ceph orch ps 2>/dev/null || true)"
    total="$(printf "%s\n" "$ps" | grep -E '(^|[[:space:]])rgw(\.|-|[[:space:]])' | wc -l | awk '{print $1}')"
    running="$(printf "%s\n" "$ps" | grep -E '(^|[[:space:]])rgw(\.|-|[[:space:]])' | grep -i 'running' | wc -l | awk '{print $1}')"
    not_running_names="$(printf "%s\n" "$ps" \
        | grep -E '(^|[[:space:]])rgw(\.|-|[[:space:]])' \
        | grep -vi 'running' \
        | awk '{print $1}' | paste -sd, -)"
  fi

  if [[ "$total" -eq 0 ]]; then
    fail "No RGW daemons found by 'ceph orch ps'."
    return 1
  fi

  if [[ "${REQUIRE_ALL_RGW_RUNNING}" == "true" && "$running" -ne "$total" ]]; then
    fail "RGW daemons running: $running/$total. Not running: ${not_running_names:-none}."
    return 1
  fi

  if [[ "$running" -ge 1 ]]; then
    ok "RGW daemons running: $running/$total"
  else
    fail "RGW daemons running: 0/$total"
    return 1
  fi
}

# ---- Check 3: Dashboard on :8443 ---------------------------------------------
discover_dashboard_url() {
  local url=""
  if [[ -n "${DASHBOARD_URL}" ]]; then
    printf "%s" "$DASHBOARD_URL"
    return 0
  fi

  if $have_jq; then
    url="$(run_ceph mgr services -f json | jq -r '.dashboard // empty')"
  else
    # crude parse
    url="$(run_ceph mgr services | awk -F'"' '/dashboard/ {print $4; exit}')"
  fi

  if [[ -z "$url" ]]; then
    # Last resort; try localhost
    url="https://127.0.0.1:8443/"
  fi

  printf "%s" "$url"
}

check_dashboard() {
  local url http_code
  url="$(discover_dashboard_url)"

  # Accept 2xx and 3xx as healthy
  http_code="$(curl -sk -m "$TIMEOUT_SEC" -o /dev/null -w "%{http_code}" "$url" || true)"

  case "$http_code" in
    2*|3*)
      ok "Dashboard reachable at $url (HTTP $http_code)"
      ;;
    *)
      fail "Dashboard not healthy at $url; HTTP $http_code"
      return 1
      ;;
  esac
}

main() {
  local rc=0

  command -v timeout >/dev/null 2>&1 || die "'timeout' command not found."
  command -v curl >/dev/null 2>&1 || die "'curl' is required."
  command -v "${CEPH[0]}" >/dev/null 2>&1 || die "'$CEPH_BIN' not found in PATH."

  log "Starting Ceph post-deploy health checks..."
  check_health      || rc=1
  check_rgw         || rc=1
  check_dashboard   || rc=1

  if [[ "$rc" -eq 0 ]]; then
    ok "All checks passed."
  else
    fail "One or more checks failed."
  fi
  exit "$rc"
}

main "$@"

