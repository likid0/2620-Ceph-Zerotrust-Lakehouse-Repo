#!/usr/bin/env bash
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
TOKENS_JSON="${TOKENS_JSON:-./notebooks/tokens.json}"
DEFAULT_PRINCIPAL="${DEFAULT_PRINCIPAL:-charlie}"

# pick principal from $1 or default; shift it off so $@ is only the real CLI args
PRINCIPAL="${1:-$DEFAULT_PRINCIPAL}"
if [ $# -gt 0 ]; then
  shift
fi

# container, catalog, schema defaults
CONTAINER="${TRINO_CONTAINER:-trino}"
TRINO_SERVER="${TRINO_SERVER:-localhost:8080}"
CATALOG="${TRINO_CATALOG:-prod}"
SCHEMA="${TRINO_SCHEMA:-prod_ns}"

# ─── Pull the static token ─────────────────────────────────────────────────────
POLARIS_TOKEN=$(jq -r --arg p "$PRINCIPAL" '.[$p]' "$TOKENS_JSON")
if [ -z "$POLARIS_TOKEN" ] || [ "$POLARIS_TOKEN" = "null" ]; then
  echo "ERROR: no token for '$PRINCIPAL' in $TOKENS_JSON" >&2
  exit 2
fi

# ─── Build the argument array ─────────────────────────────────────────────────
args=( --server "$TRINO_SERVER" --catalog "$CATALOG" --schema "$SCHEMA" )

# only append the user’s extra args if there _are_ any
if [ "$#" -gt 0 ]; then
  args+=( "$@" )
fi

show_demo_queries() {
  # ANSI codes
  local BLUE='\e[1;34m'
  local GREEN='\e[1;32m'
  local RESET='\e[0m'

  # Banner
  echo -e "${BLUE}==========================================${RESET}"
  echo -e "${BLUE}          🔥  Trino Demo Queries 🔥          ${RESET}"
  echo -e "${BLUE}==========================================${RESET}"
  echo

  # Query list
  echo -e "  ${GREEN}1) SHOW TABLES;${RESET}"
  echo -e "  ${GREEN}2) SELECT * FROM products LIMIT 5;${RESET}"
  echo -e "  ${GREEN}3) INSERT INTO products ("
  echo -e "       product_id, product_name, description, price,"
  echo -e "       category, created_at, updated_at"
  echo -e "     ) VALUES ("
  echo -e "       7, 'Demo Plus', 'Inserted via Trino', 49.99,"
  echo -e "       'demo', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP"
  echo -e "     );${RESET}"
  echo -e "  ${GREEN}4) SELECT * FROM eu_user;${RESET}"
  echo
  echo -e "${BLUE}Type or paste any of the above, or just start your own SQL!${RESET}"
  echo
}

# Call it before launching Trino:
show_demo_queries

# Now exec into Trino
exec podman exec -it \
     -e POLARIS_TOKEN="$POLARIS_TOKEN" \
     "$CONTAINER" \
     trino \
       --server "$TRINO_SERVER" \
       --catalog "$CATALOG" \
       --schema "$SCHEMA" \
       "$@"


# Call it just before launching the CLI:
show_demo_queries


# ─── Exec Trino CLI inside the container ───────────────────────────────────────
exec podman exec -it \
     -e POLARIS_TOKEN="$POLARIS_TOKEN" \
     -i "$CONTAINER" \
     trino "${args[@]}"

