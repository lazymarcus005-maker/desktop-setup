#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu VPS bootstrap:
# - Git
# - Docker Engine
# - Docker Buildx
# - Docker Compose plugin
# - Dokploy
#
# Usage:
#   sudo bash install-git-docker-dokploy.sh

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32mOK:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "Installation failed at line $LINENO. Inspect the error above."' ERR

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash $0"
[[ -r /etc/os-release ]] || die "Cannot detect operating system."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == "ubuntu" ]] || die "This script supports Ubuntu only. Detected: ${ID:-unknown}"

export DEBIAN_FRONTEND=noninteractive

log "1/7 — Updating Ubuntu and installing base packages"
apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg

log "2/7 — Removing conflicting Docker packages"
for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

log "3/7 — Adding Docker official APT repository"
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

log "4/7 — Installing Docker Engine and Docker Compose"
apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker

docker version >/dev/null
docker compose version >/dev/null

ok "$(git --version)"
ok "$(docker --version)"
ok "$(docker compose version)"

log "5/7 — Checking Dokploy requirements"
TOTAL_RAM_MB="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
FREE_DISK_GB="$(df -Pk / | awk 'NR==2 {printf "%d", $4/1024/1024}')"

(( TOTAL_RAM_MB >= 1900 )) \
  || die "Dokploy requires approximately 2 GB RAM. Detected: ${TOTAL_RAM_MB} MB"

(( FREE_DISK_GB >= 30 )) \
  || die "Dokploy requires at least 30 GB free disk. Detected: ${FREE_DISK_GB} GB"

PORT_CONFLICTS="$(ss -lntH | awk '{print $4}' | grep -E '(^|:)(80|443|3000)$' || true)"
if [[ -n "${PORT_CONFLICTS}" ]]; then
  printf '%s\n' "${PORT_CONFLICTS}"
  die "One or more Dokploy ports (80, 443, 3000) are already in use."
fi

ok "RAM, disk and required ports passed validation"

log "6/7 — Installing Dokploy"
curl -fsSL https://dokploy.com/install.sh | sh

log "7/7 — Verifying installation"
docker info --format '{{.Swarm.LocalNodeState}}' | grep -q '^active$' \
  || die "Docker Swarm is not active."

docker service ls

PUBLIC_IPV4="$(curl -4fsS --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')"

cat <<EOF

============================================================
Installation completed

Dokploy:
  http://${PUBLIC_IPV4}:3000

Installed:
  $(git --version)
  $(docker --version)
  $(docker compose version)

Required inbound ports:
  80/tcp
  443/tcp
  3000/tcp

This script does not modify SSH or firewall settings.
============================================================
EOF
