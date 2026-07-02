#!/bin/sh
# -------------------------------------------------------------------
# Interactive ZFS Pool Configuration Script for FreeBSD 15
# Inspired by bsdinstall
# GitHub-ready & Universally Shared Version
# -------------------------------------------------------------------

# Ensure bsddialog is used (Default in FreeBSD 15)
: ${DIALOG=bsddialog}

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# 0. DISCLAIMER & ACCEPTANCE
$DIALOG --title "DISCLAIMER & TERMS OF USE" \
    --yesno "WARNING: This script automates ZFS pool configuration and WILL permanently destroy data on the selected physical disks.\n\nThis script is provided 'AS IS', without warranty of any kind, express or implied. The author assumes no liability for any data loss, system malfunction, or damage resulting from the use of this tool. You are solely responsible for ensuring you have selected the correct disks.\n\nDo you understand these risks and accept these terms?" 15 75

if [ $? -ne 0 ]; then
    clear
    echo "You have declined the terms of use. Exiting script."
    exit 0
fi

# 1. IDEMPOTENCY & SAFETY: Check existing ZFS pools (EXCLUDING zroot)
# 'zroot' is filtered out so the operator cannot accidentally destroy the boot pool
EXISTING_POOLS=$(zpool list -H -o name 2>/dev/null | grep -v "^zroot$")

if [ -n "$EXISTING_POOLS" ]; then
    # Dynamically build options for the radiolist
    POOL_OPTIONS="None Do_not_destroy_any_pool_and_continue on"
    for p in $EXISTING_POOLS; do
        POOL_OPTIONS="$POOL_OPTIONS $p Existing_ZFS_Pool off"
    done

    exec 3>&1
    POOL_TO_DESTROY=$($DIALOG --title "Existing ZFS Pools Detected" \
        --radiolist "The following non-boot pools were found. Select one to DESTROY (or select None):" 20 75 10 \
        $POOL_OPTIONS 2>&1 1>&3)
    exec 3>&-

    # If the user selected an existing pool to destroy
    if [ -n "$POOL_TO_DESTROY" ] && [ "$POOL_TO_DESTROY" != "None" ]; then
        # Double confirmation for safety
        $DIALOG --title "CRITICAL WARNING: POOL DESTRUCTION" \
            --yesno "WARNING: You are about to destroy the pool '$POOL_TO_DESTROY'.\nAll data on this pool will be permanently lost.\n\nAre you sure you want to proceed?" 12 65
        
        if [ $? -eq 0 ]; then
            clear
            echo "Destroying ZFS pool '$POOL_TO_DESTROY'..."
            zpool destroy -f "$POOL_TO_DESTROY"
            if [ $? -eq 0 ]; then
                $DIALOG --title "Success" --msgbox "Pool '$POOL_TO_DESTROY' has been successfully destroyed." 8 55
            else
                $DIALOG --title "Error" --msgbox "Failed to destroy pool '$POOL_TO_DESTROY'. It might be in use by the system." 8 60
            fi
        fi
    fi
fi

# 2. PROMPT: Ask to create a new pool
$DIALOG --title "ZFS Configuration" \
    --yesno "Do you want to create a new ZFS pool now?" 10 50

if [ $? -ne 0 ]; then
    clear
    echo "Operation completed. No new pool was created."
    exit 0
fi

# 3. Gather available physical disks
DISKS=$(sysctl -n kern.disks)

if [ -z "$DISKS" ]; then
    $DIALOG --title "Error" --msgbox "No physical disks detected on this system." 8 60
    clear
    exit 1
fi

# Build disk list for the checklist
DISK_OPTIONS=""
for d in $DISKS; do
    DISK_OPTIONS="$DISK_OPTIONS $d Physical_Disk off"
done

# 4. MENU: Disk Selection
exec 3>&1
SELECTED_DISKS=$($DIALOG --title "Disk Selection" \
    --checklist "Select the disks to include in the new ZFS pool (Press Spacebar to check/uncheck):" 20 65 10 \
    $DISK_OPTIONS 2>&1 1>&3)
exec 3>&-

if [ -z "$SELECTED_DISKS" ]; then
    clear
    echo "Operation canceled or no disks selected."
    exit 1
fi

SELECTED_DISKS=$(echo "$SELECTED_DISKS" | tr -d '"')

# 5. MENU: ZFS Topology (RAID Type)
exec 3>&1
ZFS_MODE=$($DIALOG --title "ZFS Topology Configuration" \
    --radiolist "Choose the redundancy type for your new pool:" 20 75 5 \
    "stripe" "Stripe (No redundancy, maximized performance)" on \
    "mirror" "Mirror (N identical disks, high reliability)" off \
    "raidz1" "RAIDZ-1 (1-disk fault tolerance, RAID5 equivalent)" off \
    "raidz2" "RAIDZ-2 (2-disk fault tolerance, RAID6 equivalent)" off \
    "raidz3" "RAIDZ-3 (3-disk fault tolerance, maximum redundancy)" off 2>&1 1>&3)
exec 3>&-

if [ -z "$ZFS_MODE" ]; then
    clear
    echo "Operation canceled."
    exit 1
fi

# 6. MENU: Pool Name
exec 3>&1
POOL_NAME=$($DIALOG --title "ZFS Pool Name" \
    --inputbox "Enter a name for the new ZFS pool (e.g., data, storage):" 10 50 "data" 2>&1 1>&3)
exec 3>&-

if [ -z "$POOL_NAME" ]; then
    clear
    echo "Operation canceled."
    exit 1
fi

# IDEMPOTENCY CHECK: Ensure the pool name does not already exist
if zpool list "$POOL_NAME" >/dev/null 2>&1; then
    $DIALOG --title "Error: Pool Exists" \
        --msgbox "A ZFS pool named '$POOL_NAME' already exists.\n\nTo ensure idempotency and prevent data corruption, this script will now exit. Please choose a different name or destroy the existing pool first." 12 65
    clear
    exit 1
fi

# 7. MENU: Mount Point
exec 3>&1
MOUNT_POINT=$($DIALOG --title "Mount Point" \
    --inputbox "Where should this pool be permanently mounted?" 10 50 "/$POOL_NAME" 2>&1 1>&3)
exec 3>&-

if [ -z "$MOUNT_POINT" ]; then
    clear
    echo "Operation canceled."
    exit 1
fi

# 8. Final Critical Confirmation
$DIALOG --title "Critical Confirmation" \
    --yesno "WARNING: You are about to create the ZFS pool '$POOL_NAME'.\n\nTopology: $ZFS_MODE\nDisks: $SELECTED_DISKS\nPermanent Mount: $MOUNT_POINT\n\nALL DATA ON THE SELECTED DISKS WILL BE DESTROYED.\nDo you want to continue?" 17 70

if [ $? -ne 0 ]; then
    clear
    echo "Pool creation canceled by the user."
    exit 0
fi

clear
echo "Creating ZFS pool '$POOL_NAME'..."

ZFS_KEYWORD="$ZFS_MODE"
if [ "$ZFS_MODE" = "stripe" ]; then
    ZFS_KEYWORD=""
fi

# 9. EXECUTION: Create the pool
zpool create -f -m "$MOUNT_POINT" "$POOL_NAME" $ZFS_KEYWORD $SELECTED_DISKS

if [ $? -eq 0 ]; then
    # 10. IDEMPOTENCY: Safely enable ZFS at boot via sysrc
    echo "Enabling ZFS service at system boot..."
    sysrc zfs_enable="YES" > /dev/null

    STATUS=$(zpool status $POOL_NAME)
    $DIALOG --title "Success" --msgbox "The pool '$POOL_NAME' has been successfully created!\n\nMounted at: $MOUNT_POINT\nZFS is configured to automatically mount this pool at boot.\n\n$STATUS" 22 80
else
    $DIALOG --title "Fatal Error" --msgbox "An error occurred while creating the ZFS pool. Please check the console output for details." 10 60
fi

clear
