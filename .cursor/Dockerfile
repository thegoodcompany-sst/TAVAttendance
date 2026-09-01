FROM ubuntu:24.04

# Stable system dependencies for the TAVA Attendance dev environment.
# - docker.io + fuse-overlayfs: run the Supabase local stack (nested containers)
# - postgresql-client: psql for the Supabase SQL security regressions
# - python3-venv/pip: arrival-station daemon + its unit tests
# - Supabase CLI is pinned to the version used by CI (.github/workflows/ci.yml)
# - Bun is the web dashboard's package manager and runner
ARG SUPABASE_CLI_VERSION=2.109.1
ARG BUN_VERSION=1.3.14

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        sudo \
        unzip \
        docker.io \
        fuse-overlayfs \
        iptables \
        uidmap \
        postgresql-client \
        python3 \
        python3-venv \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Supabase CLI, pinned to the CI version so the bundled Postgres base image and
# default role grants match what the SQL security tests expect.
RUN curl -fsSL -o /tmp/supabase.deb \
        "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.deb" \
    && dpkg -i /tmp/supabase.deb \
    && rm -f /tmp/supabase.deb

# Bun, installed to a system location so it is on PATH for every user.
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}" \
    && ln -sf /usr/local/bin/bun /usr/local/bin/bunx

# Docker daemon uses the fuse-overlayfs storage driver, which works inside the
# nested-container Cloud Agent VM where the default overlayfs driver cannot mount.
RUN mkdir -p /etc/docker \
    && printf '{"storage-driver":"fuse-overlayfs"}\n' > /etc/docker/daemon.json

# The default `ubuntu` user (uid 1000) runs the agent. Give it passwordless sudo
# (needed to start dockerd and set kernel params at boot) and Docker access.
RUN groupadd -f docker \
    && usermod -aG docker,sudo ubuntu \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ubuntu-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-ubuntu-nopasswd

USER ubuntu
WORKDIR /home/ubuntu
