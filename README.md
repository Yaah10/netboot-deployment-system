# NetBoot Deployment System

A fully automated PXE network boot server that boots diskless clients over LAN using DHCP, TFTP, and NFS. Built from scratch on Ubuntu 22.04.

---

## What it does

A client machine with no OS and no hard disk powers on, connects to the network, and boots into a full Ubuntu shell — entirely served from this server. No local disk required on the client.

---

## How it works

```
Client powers on
      ↓
DHCP  →  gets IP address from server (dnsmasq)
      ↓
TFTP  →  downloads bootloader + kernel from server (dnsmasq)
      ↓
NFS   →  mounts root filesystem from server (nfs-kernel-server)
      ↓
Ubuntu shell — running entirely over the network
```

---

## Requirements

- Ubuntu 22.04 server (physical machine or VirtualBox VM)
- Two network adapters:
  - Adapter 1: internet access (NAT or DHCP)
  - Adapter 2: lab network with static IP (Host-Only or LAN)
- Client machine with PXE boot support (or a diskless VM)

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Yaah10/netboot-deployment-system.git
cd netboot-deployment-system

# Run the automated setup script
sudo bash setup.sh
```

The script will ask for:
- Server IP address (default: 192.168.56.10)
- Network interface (auto-detected)
- DHCP range start and end
- Root password for netboot clients

Total setup time: approximately 10 minutes (mostly debootstrap building the root filesystem).

---

## Repository Structure

```
netboot-deployment-system/
├── setup.sh                     ← automated setup script — run this
├── config/
│   ├── dnsmasq.conf             ← DHCP + TFTP server configuration
│   ├── exports                  ← NFS exports configuration
│   ├── 50-cloud-init.yaml       ← static IP netplan configuration
│   └── pxelinux.cfg/
│       └── default              ← PXE boot menu definition
├── docs/
│   ├── architecture.md          ← detailed how it works
│   └── troubleshooting.md       ← common problems and fixes
└── screenshots/
    ├── boot-menu.png            ← PXE boot menu on client
    └── client-login.png         ← Ubuntu shell on diskless client
```

---

## Technologies Used

| Technology | Role | Port |
|------------|------|------|
| dnsmasq | DHCP server — gives clients an IP address | UDP 67/68 |
| dnsmasq | TFTP server — serves bootloader and kernel | UDP 69 |
| pxelinux | PXE bootloader — first program client runs | — |
| nfs-kernel-server | Serves root filesystem over network | TCP 2049 |
| debootstrap | Builds Ubuntu root filesystem into a folder | — |
| bash | Automates the entire server setup | — |

---

## Network Layout

```
[Server]  192.168.56.10          [Client]  192.168.56.100
     |                                |
     └──────── 192.168.56.0/24 ───────┘
               Host-Only Network
```

---

## Boot Sequence in Detail

### Step 1 — DHCP (UDP port 67/68)
Client has no IP. It broadcasts: *"I need an IP address"*.
Server replies: *"Take 192.168.56.100. Your boot file is pxelinux.0 at 192.168.56.10"*

### Step 2 — TFTP (UDP port 69)
Client downloads over TFTP in order:
1. `pxelinux.0` — first stage bootloader
2. `ldlinux.c32` — required core library
3. `pxelinux.cfg/default` — boot menu configuration
4. `menu.c32` — menu renderer
5. `vmlinuz` — Linux kernel
6. `initrd.gz` — initial RAM disk

### Step 3 — NFS (TCP port 2049)
Kernel starts in RAM. It reads boot parameters: `root=/dev/nfs nfsroot=192.168.56.10:/srv/nfs/rootfs`.
It mounts the server's `/srv/nfs/rootfs` folder as its `/` directory over NFS.
Every file the OS reads — `/bin/bash`, `/etc/passwd`, everything — comes from the server over the network.

### Step 4 — Login
Ubuntu boots, presents login prompt. Client is fully running with no local disk involved at any point.

---

## Real Hardware Usage

This setup works on physical machines too:

1. Change `SERVER_IP` in `setup.sh` to your real LAN IP
2. Ensure no other DHCP server is running on the same network (or configure dnsmasq to only respond to specific MACs)
3. Client machines boot via PXE by pressing F12 (or equivalent) at startup
4. Works with any machine that supports network boot — dual boot machines included

---

## What I Learned Building This

- Linux server administration — systemd, netplan, UFW, file permissions
- Networking fundamentals — DHCP, TFTP, NFS, TCP/UDP, subnets, ARP
- PXE boot chain — how a machine boots with no OS using only a network card
- Bash scripting — automated setup with error handling, user input, colored output
- Debugging with tcpdump, journalctl, ss, and exportfs
- VirtualBox networking — Host-Only adapters, NAT, static IP configuration

---

## Author

Yash Shende  
[GitHub](https://github.com/Yaah10)
