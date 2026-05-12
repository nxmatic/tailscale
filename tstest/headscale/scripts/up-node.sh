#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <node-name> <auth-key>" >&2
  exit 1
fi

NODE_NAME="$1"
AUTH_KEY="$2"

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "$LAB_DIR/../.." && pwd)"
BIN_DIR="$LAB_DIR/bin"
STATE_DIR="$LAB_DIR/state/$NODE_NAME"
SOCKET="$STATE_DIR/tailscaled.sock"
PID_FILE="$STATE_DIR/tailscaled.pid"
LOG_FILE="$STATE_DIR/tailscaled.log"
HEADSCALE_URL="${HEADSCALE_URL:-http://127.0.0.1:18080}"
CGO_ENABLED="${CGO_ENABLED:-0}"

mkdir -p "$BIN_DIR" "$STATE_DIR"

build_if_missing() {
  local out="$1"
  local pkg="$2"
  if [[ ! -x "$out" ]]; then
    echo "Building $(basename "$out") from $pkg ..."
    (
      cd "$REPO_ROOT"
      CGO_ENABLED="$CGO_ENABLED" go build -o "$out" "$pkg"
    )
  fi
}

build_if_missing "$BIN_DIR/tailscaled" ./cmd/tailscaled
build_if_missing "$BIN_DIR/tailscale" ./cmd/tailscale

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "tailscaled for $NODE_NAME is already running (pid $(cat "$PID_FILE"))"
else
  rm -f "$PID_FILE"
  echo "Starting tailscaled for $NODE_NAME ..."
  (
    cd "$STATE_DIR"
    exec "$BIN_DIR/tailscaled" \
      --tun=userspace-networking \
      --statedir="$STATE_DIR" \
      --socket="$SOCKET" \
      >"$LOG_FILE" 2>&1
  ) &
  echo $! > "$PID_FILE"
fi

echo "Waiting for local API socket..."
until "$BIN_DIR/tailscale" --socket="$SOCKET" status >/dev/null 2>&1; do
  sleep 1
done

echo "Running tailscale up for $NODE_NAME ..."
"$BIN_DIR/tailscale" --socket="$SOCKET" up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTH_KEY" \
  --hostname="$NODE_NAME" \
  --ssh \
  --accept-dns=false \
  --reset

NODE_IP="$("$BIN_DIR/tailscale" --socket="$SOCKET" ip -4 | head -n1)"

cat <<EOF

Node $NODE_NAME is up.
  socket: $SOCKET
  state:  $STATE_DIR
  ip:     $NODE_IP
  log:    $LOG_FILE

EOF
