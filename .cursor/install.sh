#!/usr/bin/env bash
# Idempotent repository bootstrap for the TAVA Attendance dev environment.
# Runs after the repo is checked out. Installs per-project dependencies only;
# system packages live in the Dockerfile and runtime services start in start.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Web: installing dependencies (bun, frozen lockfile)"
( cd "$REPO_ROOT/web" && bun install --frozen-lockfile )

echo "==> Arrival station: creating venv and installing package"
(
  cd "$REPO_ROOT/station"
  python3 -m venv .venv
  ./.venv/bin/pip install --quiet --upgrade pip
  ./.venv/bin/pip install --quiet -e .
)

echo "==> install.sh complete"
