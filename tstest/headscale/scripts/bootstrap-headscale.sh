#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$LAB_DIR/docker-compose.yaml"
CONFIG_FILE="/etc/headscale/config.yaml"
USER_NAME="${HEADSCALE_LAB_USER:-lab}"
HEADSCALE_URL="${HEADSCALE_URL:-http://127.0.0.1:18080}"
AUTH_ENV_FILE="$LAB_DIR/.generated.authkeys.env"
PYTHON_BIN="${PYTHON_BIN:-python3}"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

extract_user_id() {
  "$PYTHON_BIN" -c '
import json, sys
obj = json.load(sys.stdin)
if isinstance(obj, dict) and "id" in obj:
    print(obj["id"])
elif isinstance(obj, dict) and "users" in obj:
    users = obj["users"]
    if not users:
        raise SystemExit("no users in JSON output")
    print(users[0]["id"])
elif isinstance(obj, list):
    if not obj:
        raise SystemExit("no users in JSON output")
    print(obj[0]["id"])
else:
    raise SystemExit(f"unsupported JSON shape: {type(obj).__name__}")
'
}

extract_auth_key() {
  "$PYTHON_BIN" -c '
import json, sys
obj = json.load(sys.stdin)
if isinstance(obj, dict) and "key" in obj:
    print(obj["key"])
elif isinstance(obj, dict) and "pre_auth_key" in obj:
    print(obj["pre_auth_key"]["key"])
else:
    raise SystemExit("unable to find auth key in JSON output")
'
}

mkdir -p "$LAB_DIR/state"

compose up -d headscale

echo "Waiting for headscale to accept CLI commands..."
until compose exec -T headscale headscale -c "$CONFIG_FILE" users list >/dev/null 2>&1; do
  sleep 1
done

echo "Ensuring lab user '$USER_NAME' exists..."
user_json="$(compose exec -T headscale headscale -c "$CONFIG_FILE" users create "$USER_NAME" -o json 2>/dev/null || true)"
if [[ -z "$user_json" ]]; then
  user_json="$(compose exec -T headscale headscale -c "$CONFIG_FILE" users list --name "$USER_NAME" -o json)"
fi
user_id="$(printf '%s' "$user_json" | extract_user_id)"

echo "Creating reusable auth keys for two nodes..."
node_a_key="$(compose exec -T headscale headscale -c "$CONFIG_FILE" preauthkeys create --user "$user_id" --reusable --expiration 24h -o json | extract_auth_key)"
node_b_key="$(compose exec -T headscale headscale -c "$CONFIG_FILE" preauthkeys create --user "$user_id" --reusable --expiration 24h -o json | extract_auth_key)"

cat > "$AUTH_ENV_FILE" <<EOF
HEADSCALE_URL=$HEADSCALE_URL
HEADSCALE_LAB_USER=$USER_NAME
LAB_NODE_A_AUTHKEY=$node_a_key
LAB_NODE_B_AUTHKEY=$node_b_key
EOF

cat <<EOF

Headscale lab bootstrapped.

Generated auth key env file:
  $AUTH_ENV_FILE

Suggested next steps:
  source "$AUTH_ENV_FILE"
  bash "$LAB_DIR/scripts/up-node.sh" node-a "$node_a_key"
  bash "$LAB_DIR/scripts/up-node.sh" node-b "$node_b_key"
  bash "$LAB_DIR/scripts/verify-ssh-2222.sh"

EOF
