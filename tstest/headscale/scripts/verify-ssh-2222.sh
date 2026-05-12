#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$LAB_DIR/bin"
NODE_A="${NODE_A_NAME:-node-a}"
NODE_B="${NODE_B_NAME:-node-b}"
NODE_A_SOCKET="$LAB_DIR/state/$NODE_A/tailscaled.sock"
NODE_B_SOCKET="$LAB_DIR/state/$NODE_B/tailscaled.sock"
SSH_USER="${SSH_USER:-$(id -un)}"
TAILSCALE_BIN="$BIN_DIR/tailscale"
SSH_BIN="${SSH_BIN:-ssh}"

if [[ ! -x "$TAILSCALE_BIN" ]]; then
  echo "missing $TAILSCALE_BIN; run up-node.sh first" >&2
  exit 1
fi
if [[ ! -S "$NODE_A_SOCKET" || ! -S "$NODE_B_SOCKET" ]]; then
  echo "missing node sockets; start both lab nodes first" >&2
  exit 1
fi

NODE_B_IP="$("$TAILSCALE_BIN" --socket="$NODE_B_SOCKET" ip -4 | head -n1)"

echo "Verifying control-plane connectivity from $NODE_A to $NODE_B_IP ..."
"$TAILSCALE_BIN" --socket="$NODE_A_SOCKET" ping --timeout=10s "$NODE_B_IP"

proxy_cmd="$TAILSCALE_BIN --socket=$NODE_A_SOCKET nc %h %p"
ssh_common=(-o "ProxyCommand=$proxy_cmd" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "Expecting Tailscale SSH success on port 2222 ..."
"$SSH_BIN" "${ssh_common[@]}" -p 2222 "$SSH_USER@$NODE_B_IP" "printf 'ssh-ok\n'"

echo "Expecting plain port 22 to fail now that interception moved to 2222 ..."
if "$SSH_BIN" "${ssh_common[@]}" -o ConnectTimeout=5 -p 22 "$SSH_USER@$NODE_B_IP" "printf 'unexpected\n'"; then
  echo "unexpected success on port 22" >&2
  exit 1
fi

echo
printf 'Verified: headscale policy + tailscaled SSH interception on port 2222.\n'
