# Headscale SSH 2222 lab

This is a small, opt-in lab for validating the patched Tailscale SSH path against a **real headscale control plane**.

It is intentionally separate from `tstest/integration/`, which uses Tailscale's in-repo fake control server.

## What this proves

- `headscale` is the coordination / policy server
- two local `tailscaled` instances can join the same tailnet
- SSH policy comes from headscale ACL / SSH policy
- this branch's patch moves Tailscale SSH interception from port `22` to `2222`

## Layout

- `docker-compose.yaml` — real headscale control plane
- `config/headscale.yaml` — minimal headscale config
- `config/acl.hujson` — ACL + SSH policy for the lab
- `scripts/bootstrap-headscale.sh` — starts headscale and generates auth keys
- `scripts/up-node.sh` — builds local binaries if needed and starts one userspace `tailscaled`
- `scripts/verify-ssh-2222.sh` — checks that SSH succeeds on `2222` and fails on `22`

## Prerequisites

- Docker with Compose support
- Go toolchain able to build this repo
- local `ssh` client

## Quick start

Run everything from the repo root or with full paths.

1. Bootstrap headscale and generate auth keys:

   `bash tstest/headscale/scripts/bootstrap-headscale.sh`

2. Load the generated auth keys:

   `source tstest/headscale/.generated.authkeys.env`

3. Start two local userspace nodes using the patched binaries from this repo:

   `bash tstest/headscale/scripts/up-node.sh node-a "$LAB_NODE_A_AUTHKEY"`

   `bash tstest/headscale/scripts/up-node.sh node-b "$LAB_NODE_B_AUTHKEY"`

4. Verify SSH behaviour:

   `bash tstest/headscale/scripts/verify-ssh-2222.sh`

## Notes

- This lab keeps **headscale in Docker** but runs the two patched Tailscale nodes on the host, which makes it easier to validate the exact `tailscaled` you changed on this branch.
- The verification script uses node A's local daemon as the transport via `tailscale nc` and then checks SSH to node B on ports `2222` and `22`.
- The sample policy is intentionally minimal and same-user. Once this works, extend it with a second headscale user or tagged nodes to prove deny / allow boundaries.
- Runtime artifacts are ignored under `tstest/headscale/state/` and `tstest/headscale/bin/`.
