#!/bin/sh
# ==============================================================================
# FREEBSD VAULT - Interactive & Idempotent Mirror Setup (ZFS + Nginx Cache)
# Hardware Target: Lenovo P500 (4x SATA HDD + 1x NVMe)
# ==============================================================================

set -e
exec 3>&1

# --- 0. DISCLAIMER ---
if ! bsddialog --title "FREEBSD VAULT DEPLOYMENT" --clear \
    --yesno "WARNING: This script configures ZFS storage, Nginx reverse proxy, and network settings to build a local FreeBSD mirror.\n\nIt is idempotent (safe to rerun) but modifies disks if creating a new pool.\n\nProceed?" 12 60 2>&1 1>&3; then
    clear; echo "Operation cancelled."; exec 3>&-; exit 1
fi

# --- 1. INTERACTIVE CONFIGURATION (Pre-filled Defaults) ---

HOSTNAME=$(bsddialog --title "1. System Hostname" --clear \
    --inputbox "Enter the FQDN (Fully Qualified Domain Name) for this mirror:" 10 60 \
    "mirror.idealservice.ch" 2>&1 1>&3)
[ -z "$HOSTNAME" ] && exit 1

DISKS=$(bsddialog --title "2. Storage Disks (HDD)" --clear \
    --inputbox "Enter the SATA/SAS disks for the main storage (separated by space):" 10 60 \
    "ada0 ada1 ada2 ada3" 2>&1 1>&3)
[ -z "$DISKS" ] && exit 1

RAID_TYPE=$(bsddialog --title "3. RAID Topology" --clear \
    --menu "Select the ZFS RAID topology for the storage disks:" 12 60 3 \
    "raidz1" "RAID 5 equivalent (1 disk fault tolerance)" \
    "raidz2" "RAID 6 equivalent (2 disks fault tolerance)" \
    "mirror" "RAID 1 equivalent (Mirrored pairs)" \
    2>&1 1>&3)
[ -z "$RAID_TYPE" ] && exit 1

CACHE_DISK=$(bsddialog --title "4. Fast Cache Disk (NVMe/SSD)" --clear \
    --inputbox "Enter the disk used for the system and L2ARC cache:" 10 60 \
    "nda0" 2>&1 1>&3)
[ -z "$CACHE_DISK" ] && exit 1

CACHE_SIZE=$(bsddialog --title "5. Cache Size" --clear \
    --inputbox "Enter the size of the L2ARC cache partition to create:" 10 60 \
    "50G" 2>&1 1>&3)
[ -z "$CACHE_SIZE" ] && exit 1

WEB_USER=$(bsddialog --title "6. Security: Username" --clear \
    --inputbox "Enter the HTTP/HTTPS username for the mirror:" 10 60 \
    "admin" 2>&1 1>&3)
[ -z "$WEB_USER" ] && exit 1

WEB_PASS=$(bsddialog --title "7. Security: Password" --clear \
    --passwordbox "Enter the HTTP/HTTPS password for the mirror:" 10 60 \
    2>&1 1>&3)
[ -z "$WEB_PASS" ] && exit 1

exec 3>&-
clear
echo "====================================================================="
echo " DEPLOYING FREEBSD VAULT: $HOSTNAME"
echo "====================================================================="

# --- 2. HOSTNAME CONFIGURATION ---
echo "[*] Configuring hostname..."
sysrc hostname="$HOSTNAME"
hostname "$HOSTNAME"

# --- 3. ZFS POOL CREATION (IDEMPOTENT) ---
echo "[*] Checking ZFS Pool 'zmirror'..."
if ! zpool list zmirror >/dev/null 2>&1; then
    echo " -> Creating ZFS Pool 'zmirror' ($RAID_TYPE) on $DISKS..."
    zpool create -f zmirror $RAID_TYPE $DISKS
    zfs set compression=zstd zmirror
    zfs set atime=off zmirror
else
    echo " -> Pool 'zmirror' already exists. Skipping creation."
fi

# --- 4. ZFS L2ARC CACHE CREATION (IDEMPOTENT) ---
echo "[*] Checking ZFS L2ARC Cache on $CACHE_DISK..."
if ! zpool status zmirror | grep -q "cache"; then
    echo " -> Creating $CACHE_SIZE cache partition on $CACHE_DISK..."
    # Create partition only if a freebsd-zfs partition doesn't already exist for cache
    if ! gpart show "$CACHE_DISK" | grep -q "cache_miroir"; then
        gpart add -t freebsd-zfs -s "$CACHE_SIZE" -l cache_miroir "$CACHE_DISK"
    fi
    zpool add zmirror cache gpt/cache_miroir
else
    echo " -> Cache already attached to pool. Skipping."
fi

# --- 5. NGINX & DIRECTORIES SETUP ---
echo "[*] Setting up Nginx Reverse Proxy Cache..."
env ASSUME_ALWAYS_YES=YES pkg install nginx apache-htpasswd

mkdir -p /zmirror/cache
mkdir -p /zmirror/isos
chown -R www:www /zmirror

# Create Basic Auth File
htpasswd -b -c /usr/local/etc/nginx/.htpasswd "$WEB_USER" "$WEB_PASS" >/dev/null 2>&1

# Generate Rock-Solid Nginx Config
cat << EOF > /usr/local/etc/nginx/nginx.conf
user www;
worker_processes auto;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;

    # Massive 10TB Cache, Kept for 10 years
    proxy_cache_path /zmirror/cache levels=1:2 keys_zone=fbsd_cache:100m max_size=10000g inactive=3650d use_temp_path=off;

    server {
        listen 80;
        server_name $HOSTNAME;

        auth_basic "FreeBSD Vault Secure Access";
        auth_basic_user_file /usr/local/etc/nginx/.htpasswd;

        location /pkg/ {
            proxy_pass http://pkg.freebsd.org/;
            proxy_set_header Host pkg.freebsd.org;
            proxy_set_header Authorization ""; 
            proxy_cache fbsd_cache;
            proxy_cache_valid 200 302 3650d;
            proxy_cache_valid 404 1m;
            proxy_cache_lock on;
        }

        location /update/ {
            proxy_pass http://update.freebsd.org/;
            proxy_set_header Host update.freebsd.org;
            proxy_set_header Authorization "";
            proxy_cache fbsd_cache;
            proxy_cache_valid 200 302 3650d;
        }

        location /isos/ {
            alias /zmirror/isos/;
            autoindex on;
        }
    }
}
EOF

sysrc nginx_enable="YES"
service nginx restart

echo "====================================================================="
echo " VAULT DEPLOYMENT SUCCESSFUL!"
echo "====================================================================="
echo ""
echo " --- CLIENT CONFIGURATION GUIDE ---"
echo ""
echo "1. For PKG (Packages):"
echo "   Edit /usr/local/etc/pkg/repos/FreeBSD.conf on your clients:"
echo "   url: \"http://$WEB_USER:$WEB_PASS@$HOSTNAME/pkg/\${ABI}/latest\""
echo ""
echo "2. For FREEBSD-UPDATE (System Updates):"
echo "   Edit /etc/freebsd-update.conf and set:"
echo "   ServerName $HOSTNAME/update"
echo "   "
echo "   Then run updates via environment variable injection:"
echo "   env HTTP_AUTH=\"basic:*:$WEB_USER:$WEB_PASS\" freebsd-update fetch"
echo ""
echo "3. For WGET or FETCH (ISOs):"
echo "   fetch http://$WEB_USER:$WEB_PASS@$HOSTNAME/isos/filename.iso"
echo "   wget --http-user=$WEB_USER --http-password=$WEB_PASS http://$HOSTNAME/isos/filename.iso"
echo "====================================================================="