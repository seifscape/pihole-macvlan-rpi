#!/usr/bin/env bash
# https://blog.ivansmirnov.name/set-up-pihole-using-docker-macvlan-network/
# 🧠 Pi-hole VLAN + macvlan Network Setup Script
# Creates a macvlan network with static IPv4 and IPv6 addresses for Pi-hole & Unbound
# IPv6 is configured to use a Unique Local Address (ULA) prefix (fd00::/8)
# Author: You 😉
set -e
set -x

echo "🚀 Starting macvlan setup..."

IPV6_PREFIX="fd00:beef"

RETRIES=30
while ! docker info >/dev/null 2>&1; do
  ((RETRIES--))
  if [ $RETRIES -le 0 ]; then
    echo "🛑 Docker not ready after 30 seconds. Exiting."
    exit 1
  fi
  echo "⏳ Waiting for Docker to be ready..."
  sleep 1
done
echo "✅ Docker is ready."

if ! docker network inspect pihole_macvlan >/dev/null 2>&1; then
  echo "🔧 Creating Docker macvlan network..."
  docker network create -d macvlan \
    --ipv6 \
    --subnet=192.168.1.0/24 \
    --gateway=192.168.1.1 \
    --subnet=${IPV6_PREFIX}::/64 \
    --gateway=${IPV6_PREFIX}::1 \
    -o parent=eth0 \
    pihole_macvlan
  echo "✅ Docker macvlan network created."
else
  echo "ℹ️ Docker macvlan network already exists. Skipping creation."
fi

if ip link show macvlan-shim >/dev/null 2>&1; then
  echo "🧽 Removing existing macvlan-shim interface..."
  ip link delete macvlan-shim
fi

ip link add macvlan-shim link eth0 type macvlan mode bridge
ip addr flush dev macvlan-shim
ip addr add 192.168.1.250/24 dev macvlan-shim
ip addr add ${IPV6_PREFIX}::250/64 dev macvlan-shim
ip link set macvlan-shim up

# 🚫 Prevent autoconf global IPv6
sysctl -w net.ipv6.conf.macvlan-shim.autoconf=0
sysctl -w net.ipv6.conf.macvlan-shim.accept_ra=0

if ! ip route show | grep -q "192.168.1.0/24"; then
  ip route add 192.168.1.0/24 dev macvlan-shim
fi

if ! ip -6 route show | grep -q "${IPV6_PREFIX}::/64"; then
  ip -6 route add ${IPV6_PREFIX}::/64 dev macvlan-shim
fi

echo "🎉 Macvlan setup completed successfully."

# ✅ Persist IPv6 RA/autoconf settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSIST_SCRIPT="${SCRIPT_DIR}/persist-macvlan-sysctl.sh"

if [ -x "$PERSIST_SCRIPT" ]; then
  echo "📦 Running persist-macvlan-sysctl.sh..."
  "$PERSIST_SCRIPT"
else
  echo "⚠️  persist-macvlan-sysctl.sh not found or not executable"
fi
