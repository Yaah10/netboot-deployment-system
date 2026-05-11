#!/bin/bash
set -e

# ── Colors ──────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Helpers ──────────────────────────
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Global variables ─────────────────
SERVER_IP="192.168.56.10"
INTERFACE="enp0s8"
TFTP_DIR="/var/lib/tftpboot"
NFS_ROOT="/srv/nfs/rootfs"
DHCP_START="192.168.56.100"
DHCP_END="192.168.56.200"

# ── Step 1: Check root ───────────────
check_root() {
    info "Checking root privileges..."
    if [ $(id -u) -ne 0 ]; then
        error "Run with: sudo bash setup.sh"
    fi
    info "Root check passed."
}

# ── Step 2: Get user input ───────────
get_config() {
    info "Gathering configuration..."
    read -p "Enter server IP address [192.168.56.10]: " input
    SERVER_IP=${input:-$SERVER_IP}

    read -p "Enter lab network interface [enp0s8]: " input
    INTERFACE=${input:-$INTERFACE}

    read -p "Enter DHCP range start [192.168.56.100]: " input
    DHCP_START=${input:-$DHCP_START}

    read -p "Enter DHCP range end [192.168.56.200]: " input
    DHCP_END=${input:-$DHCP_END}

    info "Config: IP=$SERVER_IP | Interface=$INTERFACE | DHCP=$DHCP_START-$DHCP_END"
}
# ── Step 3: Install packages ─────────
install_packages() {
    info "Updating package list..."
    apt-get update -qq
    info "Installing required packages..."
    apt-get install -y dnsmasq pxelinux syslinux-common nfs-kernel-server debootstrap wget -qq
    info "Packages installed."
}

# ── Step 4: Setup TFTP ───────────────
setup_tftp() {
    info "Setting up TFTP..."
    mkdir -p $TFTP_DIR
    chmod 755 $TFTP_DIR

    cp /usr/lib/PXELINUX/pxelinux.0 $TFTP_DIR/
    for FILE in ldlinux.c32 libcom32.c32 libutil.c32 menu.c32; do
        cp /usr/lib/syslinux/modules/bios/$FILE $TFTP_DIR/
    done

    info "Downloading kernel and initrd..."
    wget -q http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux -O $TFTP_DIR/vmlinuz
    wget -q http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz -O $TFTP_DIR/initrd.gz
    chmod 644 $TFTP_DIR/vmlinuz $TFTP_DIR/initrd.gz

    info "Creating boot menu..."
    mkdir -p $TFTP_DIR/pxelinux.cfg
    cat > $TFTP_DIR/pxelinux.cfg/default << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 500
MENU TITLE NetBoot Lab

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0

LABEL ubuntu
  MENU LABEL Boot Ubuntu from network
  KERNEL vmlinuz
  APPEND root=/dev/nfs nfsroot=${SERVER_IP}:${NFS_ROOT},vers=3 rw ip=dhcp initrd=initrd.gz
EOF
    info "TFTP setup done."
}

# ── Step 5: Setup DHCP ───────────────
# ── Step 5: Setup DHCP ───────────────
setup_dhcp() {
    info "Configuring dnsmasq..."

    # Stop dnsmasq before making changes
    systemctl stop dnsmasq 2>/dev/null || true

    # Backup existing config
    [ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup

    cat > /etc/dnsmasq.conf << EOF
port=0
interface=${INTERFACE}
bind-interfaces

dhcp-range=${DHCP_START},${DHCP_END},12h
dhcp-boot=pxelinux.0,pxeserver,${SERVER_IP}
enable-tftp
tftp-root=${TFTP_DIR}
log-dhcp
EOF

    # Verify config before starting
    dnsmasq --test 2>/dev/null || error "dnsmasq config test failed"

    systemctl restart dnsmasq || error "dnsmasq failed to start. Run: journalctl -xeu dnsmasq"
    systemctl enable dnsmasq
    info "DHCP setup done."
}

# ── Step 6: Setup NFS ────────────────
setup_nfs() {
    info "Building root filesystem with debootstrap (this takes 5-10 mins)..."
    mkdir -p $NFS_ROOT
    debootstrap --arch=amd64 jammy $NFS_ROOT http://archive.ubuntu.com/ubuntu

    info "Installing kernel into rootfs..."
    chroot $NFS_ROOT apt-get install -y linux-image-generic -qq

    info "Copying kernel to TFTP..."
    KERNEL=$(ls $NFS_ROOT/boot/vmlinuz-* | head -1)
    INITRD=$(ls $NFS_ROOT/boot/initrd.img-* | head -1)
    cp $KERNEL $TFTP_DIR/vmlinuz
    cp $INITRD $TFTP_DIR/initrd.gz
    chmod 644 $TFTP_DIR/vmlinuz $TFTP_DIR/initrd.gz

    info "Configuring NFS exports..."
    grep -q "$NFS_ROOT" /etc/exports 2>/dev/null || \
        echo "$NFS_ROOT 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
    systemctl restart nfs-kernel-server
    systemctl enable nfs-kernel-server

    info "Opening firewall for NFS..."
    ufw allow from 192.168.56.0/24 to any port nfs 2>/dev/null || true
    ufw allow from 192.168.56.0/24 to any port 111 2>/dev/null || true

    info "Setting root password for client..."
    read -s -p "Enter root password for netboot client: " ROOT_PASS
    echo
    echo "root:$ROOT_PASS" | chroot $NFS_ROOT chpasswd
    info "NFS setup done."
}

# ── Step 7: Final report ─────────────
print_summary() {
    echo ""
    echo -e "${GREEN}==============================${NC}"
    echo -e "${GREEN}  NetBoot Server Ready!${NC}"
    echo -e "${GREEN}==============================${NC}"
    echo ""
    info "Server IP:     $SERVER_IP"
    info "Interface:     $INTERFACE"
    info "DHCP range:    $DHCP_START - $DHCP_END"
    info "TFTP root:     $TFTP_DIR"
    info "NFS root:      $NFS_ROOT"
    echo ""
    info "Boot your client VM and select 'Boot Ubuntu from network'"
    echo ""
}

# ── Main ─────────────────────────────
info "NetBoot Automated Setup"
info "========================"
check_root
get_config
install_packages
setup_tftp
setup_dhcp
setup_nfs
print_summary
