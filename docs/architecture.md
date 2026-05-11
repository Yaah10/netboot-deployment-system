# Architecture

## Overview

The NetBoot Deployment System turns a standard Ubuntu server into a network boot server. A client machine with no OS and no hard disk powers on and boots into a full Ubuntu shell entirely over the network — no local disk involved at any point.

---

## Network Layout

```
                    192.168.56.0/24
                   Host-Only Network

    [Server VM]                      [Client VM]
    192.168.56.10                    192.168.56.100
         |                                |
         |          enp0s8               |
         └────────────────────────────────┘

    [Server VM]
    192.168.56.10  ←── lab network (enp0s8)
    10.0.2.15      ←── internet/NAT (enp0s3)
```

---

## Services Running on Server

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| dnsmasq | 67/68 | UDP | DHCP — assigns IP addresses to clients |
| dnsmasq | 69 | UDP | TFTP — serves bootloader and kernel files |
| nfs-kernel-server | 2049 | TCP | NFS — serves root filesystem to clients |
| rpcbind | 111 | TCP/UDP | RPC portmapper — required by NFS |

---

## Boot Sequence

### Step 1 — Power on (client has nothing)
The client machine has no OS, no IP address, no disk.
The network card's built-in PXE firmware starts and broadcasts a DHCP request to the entire network.

```
Client → broadcast: "I need an IP. My MAC is 08:00:27:b3:45:a3"
```

### Step 2 — DHCP handshake (UDP port 67/68)
dnsmasq on the server hears the broadcast and replies with an IP address and boot instructions.

```
DHCPDISCOVER  →  client broadcasts to 255.255.255.255
DHCPOFFER     ←  server offers 192.168.56.100
DHCPREQUEST   →  client accepts the offer
DHCPACK       ←  server confirms the lease
```

Server also tells the client:
- Boot file: `pxelinux.0`
- TFTP server: `192.168.56.10`

### Step 3 — TFTP file transfer (UDP port 69)
Client connects to the TFTP server and downloads files in order:

```
1. pxelinux.0          ← first stage bootloader
2. ldlinux.c32         ← core library required by pxelinux
3. pxelinux.cfg/default ← boot menu configuration
4. menu.c32            ← renders the boot menu on screen
5. libutil.c32         ← menu support library
6. vmlinuz             ← Linux kernel
7. initrd.gz           ← initial RAM disk
```

### Step 4 — Boot menu
pxelinux reads the boot menu config and displays options on screen.
The user selects "Boot Ubuntu from network".

### Step 5 — Kernel loads
vmlinuz and initrd.gz are loaded into the client's RAM.
The kernel starts executing entirely in RAM.
It reads its boot parameters:

```
root=/dev/nfs
nfsroot=192.168.56.10:/srv/nfs/rootfs,vers=3
rw
ip=dhcp
```

### Step 6 — NFS mount (TCP port 2049)
The kernel connects to the NFS server and mounts `/srv/nfs/rootfs` as its root filesystem `/`.
Every file the OS reads — `/bin/bash`, `/etc/passwd`, `/lib` — is transparently fetched from the server over the network.

### Step 7 — Ubuntu boots
With `/` mounted over NFS, the kernel finds `/sbin/init`, starts all services, and presents a login prompt.
The client is now running a full Ubuntu 22.04 shell with no local disk involved.

---

## File Layout on Server

```
/etc/dnsmasq.conf           ← DHCP + TFTP configuration
/etc/exports                ← NFS export definitions
/var/lib/tftpboot/          ← TFTP root — all boot files served from here
    pxelinux.0
    ldlinux.c32
    libcom32.c32
    libutil.c32
    menu.c32
    vmlinuz
    initrd.gz
    pxelinux.cfg/
        default             ← boot menu config
/srv/nfs/rootfs/            ← Ubuntu root filesystem served over NFS
    bin/
    etc/
    lib/
    usr/
    var/
    boot/
        vmlinuz-5.15.0-25-generic
        initrd.img-5.15.0-25-generic
```

---

## Why Each Technology Was Chosen

| Technology | Why |
|------------|-----|
| dnsmasq | Single package handles both DHCP and TFTP — simpler than running two separate servers |
| pxelinux | Industry standard PXE bootloader — works with any BIOS/UEFI client |
| NFS | Lightweight, built into Linux kernel, no extra client software needed |
| debootstrap | Builds a clean minimal Ubuntu rootfs without needing a full ISO |
| bash script | Portable, no dependencies, runs on any Ubuntu server |

---

## Packet Flow Diagram

```
CLIENT                          SERVER
  |                               |
  |── DHCP DISCOVER (broadcast) ──▶|  dnsmasq receives
  |                               |
  |◀─ DHCP OFFER ─────────────────|  offers 192.168.56.100
  |                               |
  |── DHCP REQUEST ───────────────▶|
  |                               |
  |◀─ DHCP ACK ───────────────────|  confirmed
  |                               |
  |── TFTP GET pxelinux.0 ────────▶|
  |◀─ TFTP DATA ──────────────────|  42KB transferred
  |                               |
  |── TFTP GET ldlinux.c32 ───────▶|
  |◀─ TFTP DATA ──────────────────|  116KB transferred
  |                               |
  |── TFTP GET pxelinux.cfg/default▶|
  |◀─ TFTP DATA ──────────────────|  menu config
  |                               |
  |── TFTP GET vmlinuz ───────────▶|
  |◀─ TFTP DATA ──────────────────|  8MB transferred
  |                               |
  |── TFTP GET initrd.gz ─────────▶|
  |◀─ TFTP DATA ──────────────────|  39MB transferred
  |                               |
  |── NFS MOUNT /srv/nfs/rootfs ──▶|  TCP port 2049
  |◀─ NFS OK ─────────────────────|
  |                               |
  LOGIN PROMPT APPEARS
```
