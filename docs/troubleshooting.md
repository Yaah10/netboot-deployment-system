# Troubleshooting

## Client shows "No more network devices"

**Cause:** dnsmasq is not running or not responding.

**Fix:**
```bash
sudo systemctl status dnsmasq
sudo systemctl restart dnsmasq
sudo journalctl -u dnsmasq -f
```

## dnsmasq fails to start

**Cause:** Port 53 conflict with systemd-resolved.

**Fix:** Ensure `port=0` is in /etc/dnsmasq.conf — this
disables DNS and avoids the conflict.

## Client gets IP but boot menu does not appear

**Cause:** TFTP files missing from /var/lib/tftpboot.

**Fix:**
```bash
ls -lh /var/lib/tftpboot/
sudo systemctl restart dnsmasq
```

## Kernel panic — not syncing

**Cause:** Kernel cannot find NFS root filesystem.

**Fix:** Check NFS is running and exported correctly:
```bash
sudo exportfs -v
sudo systemctl status nfs-server
sudo ufw status
```

## Debugging tools

Watch DHCP traffic live:
```bash
sudo journalctl -u dnsmasq -f
```

Watch raw packets:
```bash
sudo tcpdump -i enp0s8 port 67 or port 68 -n
```

Watch NFS mounts:
```bash
sudo journalctl -u nfs-server -f
```
