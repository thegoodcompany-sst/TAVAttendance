#!/usr/bin/env bash
# Per-boot runtime bring-up for the TAVA Attendance dev environment.
# Starts the Docker daemon (no systemd in the VM), the Supabase local stack,
# and writes the local web env file. Safe to run repeatedly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Configuring nested-container networking"
# Bridged same-subnet container traffic must bypass the host iptables FORWARD
# chain, otherwise Supabase services cannot reach the local Postgres container.
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true

echo "==> Ensuring Docker daemon is running"
if ! sudo docker info >/dev/null 2>&1; then
  sudo nohup dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 60); do
    [ -S /var/run/docker.sock ] && sudo docker info >/dev/null 2>&1 && break
    sleep 1
  done
fi
# Let the agent user reach the daemon without sudo.
sudo chmod 666 /var/run/docker.sock || true

if ! docker info >/dev/null 2>&1; then
  echo "!! Docker daemon did not become ready; see /tmp/dockerd.log" >&2
  exit 1
fi

echo "==> Starting Supabase local stack (applies migrations + seed)"
( cd "$REPO_ROOT" && supabase start )

echo "==> Writing web/.env.local from local Supabase credentials"
# These are the well-known deterministic local Supabase dev keys, not secrets.
eval "$(cd "$REPO_ROOT" && supabase status -o env \
  | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
cat > "$REPO_ROOT/web/.env.local" <<EOF
NEXT_PUBLIC_SUPABASE_URL=${API_URL}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
SITE_URL=http://localhost:3000
EOF
chmod 600 "$REPO_ROOT/web/.env.local"

echo "==> start.sh complete — Supabase API at ${API_URL}, Studio at http://127.0.0.1:54323"
