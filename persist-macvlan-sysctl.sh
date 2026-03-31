#!/usr/bin/env bash

# 🧠 Persist IPv6 settings for macvlan-shim to disable autoconf and RA
# Safe to run multiple times

SYSCTL_FILE="/etc/sysctl.d/99-macvlan-shim.conf"

echo "📝 Writing sysctl settings to $SYSCTL_FILE..."
sudo tee "$SYSCTL_FILE" >/dev/null <<EOF
net.ipv6.conf.macvlan-shim.autoconf=0
net.ipv6.conf.macvlan-shim.accept_ra=0
EOF

echo "🔄 Reloading sysctl settings..."
sudo sysctl --system

echo "✅ IPv6 settings for macvlan-shim have been persisted."
