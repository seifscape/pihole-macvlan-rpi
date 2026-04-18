# Pi-hole + Unbound on Docker macvlan (Raspberry Pi)

![Pi-hole](https://img.shields.io/badge/Pi--hole-96060C?style=for-the-badge&logo=pi-hole&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-A22846?style=for-the-badge&logo=raspberrypi&logoColor=white)
![Unbound](https://img.shields.io/badge/Unbound-DNS--over--TLS-4B9CD3?style=for-the-badge&logoColor=white)

Self-contained setup for running Pi-hole with Unbound as an upstream DNS resolver, using a Docker macvlan network so containers get real IPs on your LAN — no port-forwarding or NAT needed. Includes full IPv6 support.

## Network Layout

| Role | IPv4 | IPv6 |
|---|---|---|
| Router | 192.168.1.1 | fd00:beef::1 |
| Pi-hole | 192.168.1.244 | fd00:beef::244 |
| Unbound | 192.168.1.245 | fd00:beef::245 |
| Host shim | 192.168.1.250 | fd00:beef::250 |

The host shim (`macvlan-shim`) is a virtual interface that lets the Raspberry Pi itself talk to the macvlan containers (macvlan siblings can't talk to each other by default).

## How It Works

```
Client → Pi-hole (192.168.1.244:53)
       → Unbound (192.168.1.245:5335)
       → Cloudflare DNS-over-TLS (1.1.1.1@853)
```

Pi-hole handles ad-blocking and local DNS. Unbound handles recursive resolution with DNSSEC and DNS-over-TLS upstream to Cloudflare.

## Prerequisites

- Raspberry Pi running Raspberry Pi OS (64-bit recommended)
- Docker and Docker Compose installed
- Host network interface is `eth0` (adjust `pi-vlan.sh` if using `wlan0` or similar)

## Enable IPv6 for Docker on Raspberry Pi OS

Docker does not enable IPv6 by default. You need to enable it in the daemon config before running this stack.

### 1. Enable IPv6 in the Docker daemon

```bash
sudo nano /etc/docker/daemon.json
```

Add or merge the following (create the file if it doesn't exist):

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00:beef:2::/64",
  "experimental": true,
  "ip6tables": true
}
```

> The `fixed-cidr-v6` is for the default Docker bridge network — use any ULA prefix that doesn't clash with your macvlan prefix (`fd00:beef::/64`).

Then restart Docker:

```bash
sudo systemctl restart docker
```

### 2. Verify IPv6 is active on the host

```bash
ip -6 addr show eth0
```

You should see a `fe80::` link-local address. If you don't see any IPv6 at all, check that IPv6 isn't disabled in the kernel:

```bash
sysctl net.ipv6.conf.eth0.disable_ipv6
# Should return 0. If it returns 1, run:
sudo sysctl -w net.ipv6.conf.eth0.disable_ipv6=0
# To make it permanent:
echo "net.ipv6.conf.eth0.disable_ipv6=0" | sudo tee /etc/sysctl.d/98-enable-ipv6.conf
sudo sysctl --system
```

## Installation

### 1. Clone this repo

```bash
git clone <repo-url> pihole-macvlan-setup
cd pihole-macvlan-setup
```

### 2. Set your password

```bash
cp .env.example .env
nano .env  # set PIHOLE_PASSWORD to something secure
```

### 3. Install the macvlan setup scripts

```bash
sudo cp pi-vlan.sh /usr/local/bin/pi-vlan.sh
sudo cp persist-macvlan-sysctl.sh /usr/local/bin/persist-macvlan-sysctl.sh
sudo chmod +x /usr/local/bin/pi-vlan.sh /usr/local/bin/persist-macvlan-sysctl.sh
```

`pi-vlan.sh` calls `persist-macvlan-sysctl.sh` automatically after setup to write `/etc/sysctl.d/99-macvlan-shim.conf`, which disables IPv6 autoconf/RA on `macvlan-shim` across reboots. Both scripts must be in the same directory.

### 4. Install and enable the systemd service

This makes the macvlan network persist across reboots.

```bash
sudo cp systemd/pi-vlan.service /etc/systemd/system/pi-vlan.service
sudo systemctl daemon-reload
sudo systemctl enable --now pi-vlan
```

Verify it ran:

```bash
sudo systemctl status pi-vlan
ip addr show macvlan-shim
```

### 5. Start the stack

```bash
docker compose up -d
```

### 6. Configure custom DNS entries (optional)

Edit `etc-pihole/custom.list` with your local hostnames before starting, or add them via the Pi-hole web UI at `http://192.168.1.244/admin`.

## Customization

### Change IPs or subnet

Edit all occurrences of `192.168.1.244`, `192.168.1.245`, `192.168.1.250`, and `fd00:beef` across:
- `pi-vlan.sh`
- `docker-compose.yml`
- `unbound.d/custom.conf` (access-control lines)

### Change the network interface

If your Pi uses `wlan0` instead of `eth0`, update the `-o parent=eth0` line in `pi-vlan.sh` and the `parent: eth0` line in `docker-compose.yml` (if using the inline network definition).

### Change the IPv6 prefix

Replace `fd00:beef` with your preferred ULA prefix. Generate one at https://unique-local-ipv6.com/ if you want a random one. Update `pi-vlan.sh`, `docker-compose.yml`, and `unbound.d/custom.conf`.

## Point Your Router at Pi-hole

For Pi-hole to filter DNS for your whole network, your router needs to hand out Pi-hole's IP as the DNS server via DHCP — not the router's own IP.

### OpenWrt

1. Go to **Network → DHCP and DNS** (or **Network → Interfaces → LAN → Edit → DHCP Server → Advanced Settings**)
2. Under **DHCP Server → Advanced Settings**, set **DHCP-Options** to:
   ```
   6,192.168.1.244
   ```
   Option 6 is the DNS option. This tells every DHCP client to use Pi-hole for DNS.
3. Optionally add the IPv6 DNS server under **IPv6 Settings → Announced DNS servers**:
   ```
   fd00:beef::244
   ```
4. **Save & Apply**, then renew DHCP leases on your clients (`sudo dhclient -r && sudo dhclient` on Linux, or reconnect on other devices).

> If you set the router's own upstream DNS to Pi-hole's IP instead, only the router benefits — clients get the router's IP as DNS and bypass Pi-hole.

### Other routers

Look for a **DNS Server** field in your LAN/DHCP settings and set it to `192.168.1.244`. Avoid setting it in the WAN/upstream DNS field — that only affects the router itself.

### Verify clients are using Pi-hole

```bash
# From any client on the LAN
dig +short whoami.akamai.net          # should return your Pi's LAN IP if routed through Pi-hole
cat /etc/resolv.conf                   # Linux: should show 192.168.1.244
ipconfig /all | findstr "DNS Servers"  # Windows
```

## Verification

```bash
# Pi-hole web UI
curl -s http://192.168.1.244/admin | grep -i pihole

# DNS query through Pi-hole
dig @192.168.1.244 google.com

# DNS query through Unbound directly
dig @192.168.1.245 -p 5335 google.com

# DNSSEC check
dig @192.168.1.244 dnssec.works

# IPv6 DNS
dig AAAA @fd00:beef::244 google.com

# Check macvlan-shim is up
ip addr show macvlan-shim
ip -6 addr show macvlan-shim
```

## Reboot Persistence

The `pi-vlan` systemd service runs `pi-vlan.sh` on every boot after `network-online.target`. The script:
1. Waits for Docker to be ready
2. Creates the `pihole_macvlan` Docker network (skips if already exists)
3. Creates the `macvlan-shim` host interface with static IPv4 + IPv6
4. Enables IPv6 autoconf/RA on the shim (written to `/etc/sysctl.d/99-macvlan-shim.conf`)

## Directory Structure

```
.
├── docker-compose.yml         # Pi-hole + Unbound services
├── .env.example               # Copy to .env and set PIHOLE_PASSWORD
├── pi-vlan.sh                 # macvlan network + host shim setup
├── persist-macvlan-sysctl.sh  # Persists IPv6 sysctl settings
├── systemd/
│   └── pi-vlan.service        # Systemd unit for boot persistence
├── unbound.d/
│   └── custom.conf            # Unbound DNS resolver config
└── etc-pihole/
    └── custom.list            # Local DNS records (edit before first run)
```
