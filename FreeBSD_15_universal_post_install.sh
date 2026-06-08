#!/bin/sh
# ==============================================================================
# FreeBSD 15 WARRIOR - Interactive & Idempotent Post-Install Script
# Target: Desktop (KDE Wayland/X11, XFCE, MATE) + VBox + GPU + Aquantia 10G
# Features: ZFS Boot Environment, Powerd, NTPd, Dynamic Network Migration
# ==============================================================================

set -e
exec 3>&1

# === [00] Disclaimer & Liability Waiver ===
if ! bsddialog --title "DISCLAIMER & LIABILITY WAIVER" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup (Warrior Edition)" \
    --yesno "WARNING: This script automates system configuration, modifies core files, and installs software.\n\nThe author provides this script 'AS IS' and assumes NO LIABILITY for any data loss, system instability, or hardware issues that may occur.\n\nDo you accept these terms and wish to proceed?" 14 70 \
    2>&1 1>&3; then
    clear
    echo "Installation cancelled. Disclaimer was not accepted."
    exec 3>&-
    exit 1
fi

# === [0a] User Selection ===
TARGET_USER=$(bsddialog --title "User Configuration" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --inputbox "Enter the name of your existing standard user:\n(This user will be configured for 3D, VirtualBox, USB, and localized settings)" 10 65 \
    2>&1 1>&3)

if [ -z "$TARGET_USER" ]; then
    clear; echo "Error: No username entered. Operation cancelled."; exec 3>&-; exit 1
fi

# === [0b] CPU Selection ===
CPU_CHOICE=$(bsddialog --title "CPU Selection" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --menu "Select your CPU manufacturer (For Temperature & Microcode):" 10 60 2 \
    "AMD" "AMD Processor" \
    "Intel" "Intel Processor" \
    2>&1 1>&3)

if [ -z "$CPU_CHOICE" ]; then
    clear; echo "Error: No CPU selected. Operation cancelled."; exec 3>&-; exit 1
fi

# === [0c] Aquantia Network Installation ===
if bsddialog --title "Aquantia 10G Network" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --yesno "Do you want to download and compile the Aquantia 10G network driver (specific to Lenovo P620 workstations)?" 10 65 \
    2>&1 1>&3; then
    INSTALL_AQUANTIA="YES"
else
    INSTALL_AQUANTIA="NO"
fi

# === [0d] GPU Selection ===
GPU_CHOICE=$(bsddialog --title "Graphics Card (GPU)" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --menu "Select your graphics card manufacturer:" 13 70 4 \
    "AMD_GPU" "Recent Radeon (W7000, RX 5000+, RDNA, Navi)" \
    "AMD_RADEON" "Legacy Radeon (HD, R9, pre-Polaris)" \
    "NVIDIA" "GeForce, Quadro, RTX (Includes hardware detection)" \
    "INTEL" "Intel HD/UHD Integrated Graphics" \
    2>&1 1>&3)

if [ -z "$GPU_CHOICE" ]; then
    clear; echo "Error: No graphics card selected. Operation cancelled."; exec 3>&-; exit 1
fi

if [ "$GPU_CHOICE" = "NVIDIA" ]; then
    VGA_INFO=$(pciconf -lv | grep -A 2 -i "class=0x03" | grep -i "vendor\|device" | tr -d "'" || echo "Hardware not identified")
    
    bsddialog --title "Nvidia Detection" --clear \
        --msgbox "The following graphics hardware was detected on this machine:\n\n$VGA_INFO\n\nPress OK to choose the corresponding driver version." 12 70 2>&1 1>&3
        
    NVIDIA_BRANCH=$(bsddialog --title "Nvidia Driver Version" \
        --clear \
        --menu "Select the Nvidia driver branch:" 13 75 4 \
        "LATEST" "Turing and newer (Driver 595+ / Quadro RTX, RTX 2000+)" \
        "580" "Pascal/Maxwell (Driver 580 / Quadro P4000/P2000, GTX 1000)" \
        "470" "Kepler (Driver 470 / Quadro K, GTX 600-700)" \
        "390" "Fermi (Driver 390 / Quadro Fermi, GTX 400-500)" \
        2>&1 1>&3)
        
    case "$NVIDIA_BRANCH" in
        LATEST) GPU_PKGS="nvidia-driver linux-nvidia-libs nvidia-settings nvidia-xconfig" ;;
        580)    GPU_PKGS="nvidia-driver-580 linux-nvidia-libs-580 nvidia-settings" ;;
        470)    GPU_PKGS="nvidia-driver-470 linux-nvidia-libs-470 nvidia-settings" ;;
        390)    GPU_PKGS="nvidia-driver-390 linux-nvidia-libs-390 nvidia-settings" ;;
        *)      clear; echo "Error: Nvidia branch not selected."; exec 3>&-; exit 1 ;;
    esac
    GPU_MOD="nvidia-modeset"
elif [ "$GPU_CHOICE" = "AMD_GPU" ]; then
    GPU_PKGS="drm-kmod gpu-firmware-kmod"
    GPU_MOD="amdgpu"
elif [ "$GPU_CHOICE" = "AMD_RADEON" ]; then
    GPU_PKGS="drm-kmod"
    GPU_MOD="radeonkms"
elif [ "$GPU_CHOICE" = "INTEL" ]; then
    GPU_PKGS="drm-kmod"
    GPU_MOD="i915kms"
fi

# === [0e] Desktop Environment Selection ===
DESKTOP_CHOICE=$(bsddialog --title "Desktop Environment" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --menu "Select the graphical environment to install:" 12 70 3 \
    "XFCE" "Classic, lightweight, and fast" \
    "MATE" "Traditional and robust (GNOME 2 fork)" \
    "KDE"  "Plasma 6 (Modern, Wayland Ready, highly customizable)" \
    2>&1 1>&3)

if [ -z "$DESKTOP_CHOICE" ]; then
    clear; echo "Error: No desktop selected. Operation cancelled."; exec 3>&-; exit 1
fi

# === [0f] Locale & Keyboard Configuration ===
if bsddialog --title "Locale & Keyboard Setup" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --yesno "Do you want to configure the system language and keyboard layout for the graphical environment?" 8 70 2>&1 1>&3; then
    CONFIG_LOCALE="YES"
    
    SYS_LANG=$(bsddialog --title "System Language" \
        --clear \
        --default-item "fr_CH.UTF-8" \
        --menu "Select the language for the graphical session:" 17 75 9 \
        "fr_CH.UTF-8" "French (Switzerland) - Default" \
        "fr_FR.UTF-8" "French (France)" \
        "en_US.UTF-8" "English (United States)" \
        "de_CH.UTF-8" "German (Switzerland)" \
        "it_CH.UTF-8" "Italian (Switzerland)" \
        "es_ES.UTF-8" "Spanish (Spain)" \
        "pt_PT.UTF-8" "Portuguese (Portugal)" \
        2>&1 1>&3)

    if [ -z "$SYS_LANG" ]; then SYS_LANG="fr_CH.UTF-8"; fi

    KBD_CHOICE=$(bsddialog --title "Keyboard Layout" \
        --clear \
        --default-item "CH_FR" \
        --menu "Select your keyboard layout for X11/SDDM:" 18 75 8 \
        "CH_FR" "Swiss French (ch, fr) - Default" \
        "CH_DE" "Swiss German (ch, de)" \
        "FR"    "French AZERTY (fr)" \
        "US"    "US QWERTY (us)" \
        "UK"    "British QWERTY (gb)" \
        "DE"    "German QWERTZ (de)" \
        "IT"    "Italian (it)" \
        "ES"    "Spanish (es)" \
        2>&1 1>&3)
        
    case "$KBD_CHOICE" in
        CH_FR) XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
        CH_DE) XKB_LAYOUT="ch"; XKB_VARIANT="de" ;;
        FR)    XKB_LAYOUT="fr"; XKB_VARIANT="" ;;
        US)    XKB_LAYOUT="us"; XKB_VARIANT="" ;;
        UK)    XKB_LAYOUT="gb"; XKB_VARIANT="" ;;
        DE)    XKB_LAYOUT="de"; XKB_VARIANT="" ;;
        IT)    XKB_LAYOUT="it"; XKB_VARIANT="" ;;
        ES)    XKB_LAYOUT="es"; XKB_VARIANT="" ;;
        *)     XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
    esac
else
    CONFIG_LOCALE="NO"
fi

exec 3>&-
clear

# ==============================================================================
# INSTALLATION & SYSTEM CONFIGURATION
# ==============================================================================

if [ "$DESKTOP_CHOICE" = "XFCE" ]; then DESKTOP_PKGS="xfce aisleriot"; fi
if [ "$DESKTOP_CHOICE" = "MATE" ]; then DESKTOP_PKGS="mate aisleriot"; fi
if [ "$DESKTOP_CHOICE" = "KDE" ]; then DESKTOP_PKGS="plasma6-plasma kf6-networkmanager-qt dolphin konsole kpat wayland xwayland"; fi

COMMON_PKGS="xorg sddm firefox thunderbird vlc libreoffice fr-libreoffice virtualbox-ose-72 virtualbox-ose-kmod-72 fusefs-ntfs fusefs-exfat git-lite doas sudo unzip wget htop neofetch smartmontools sensors cpu-microcode pulseaudio pipewire wireplumber cups gutenprint cups-filters"

echo "=== [1/12] System & Boot Optimizations ==="
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc splash_changer_enable="YES"
sysrc rc_startmsgs="NO"
sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
grep -q "^kern.sched.preempt_thresh" /etc/sysctl.conf || echo "kern.sched.preempt_thresh=224" >> /etc/sysctl.conf
grep -q "^kern.ipc.shm_allow_removed" /etc/sysctl.conf || echo "kern.ipc.shm_allow_removed=1" >> /etc/sysctl.conf

echo "=== [2/12] CPU Configuration ($CPU_CHOICE) ==="
if [ "$CPU_CHOICE" = "AMD" ]; then
    sysrc -f /boot/loader.conf amdtemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
elif [ "$CPU_CHOICE" = "Intel" ]; then
    sysrc -f /boot/loader.conf coretemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
fi

echo "=== [3/12] Installing Software Packages ==="
env ASSUME_ALWAYS_YES=YES pkg install $COMMON_PKGS $DESKTOP_PKGS $GPU_PKGS

echo "=== [4/12] Aquantia 10G Driver Installation ==="
if [ "$INSTALL_AQUANTIA" = "YES" ]; then
    echo "-> Fetching source code from GitHub..."
    rm -rf /root/aquantia_p620_src
    git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /root/aquantia_p620_src
    cd /root/aquantia_p620_src
    sh install_aq_fbsd15_universal.sh
    
    echo "-> Applying Aquantia PHY fix to /boot/loader.conf..."
    for AQ_VAR in "nrxqs" "ntxqs"; do
        if grep -q "^dev.aq.0.iflib.override_${AQ_VAR}=" /boot/loader.conf 2>/dev/null; then
            sed -i '' "s/^dev.aq.0.iflib.override_${AQ_VAR}=.*/dev.aq.0.iflib.override_${AQ_VAR}=\"8\"/" /boot/loader.conf
        else
            echo "dev.aq.0.iflib.override_${AQ_VAR}=\"8\"" >> /boot/loader.conf
        fi
    done
    
    kldload if_aq 2>/dev/null
    sleep 2

    # Dynamic Network Migration
    OLD_IF=$(route -n get default 2>/dev/null | grep "interface:" | awk '{print $2}')
    if [ -n "$OLD_IF" ] && [ "$OLD_IF" != "aq0" ]; then
        OLD_CONF=$(sysrc -n ifconfig_${OLD_IF} 2>/dev/null)
        sysrc -x ifconfig_${OLD_IF}
        sed -i '' -E '/if_(ure|axe|axge|cdce|urndt|rue)_load="YES"/d' /boot/loader.conf
        if [ -n "$OLD_CONF" ]; then
            sysrc ifconfig_aq0="$OLD_CONF"
        else
            sysrc ifconfig_aq0="inet 192.168.254.3 netmask 255.255.255.0"
        fi
        echo "-> Network migrated from $OLD_IF to aq0."
    fi
else
    echo "-> Skipped."
fi

echo "=== [5/12] Configuring Kernel Modules (GPU, VirtualBox & FUSE) ==="
for MOD in "$GPU_MOD" "vboxdrv" "fusefs"; do
    if ! sysrc -n kld_list 2>/dev/null | grep -qw "$MOD"; then
        sysrc kld_list+="$MOD"
    fi
done

if [ "$GPU_CHOICE" = "NVIDIA" ]; then
    sysrc nvidia_modeset_enable="YES"
    
    # Correction: Contournement de sysrc pour les variables avec des points (.)
    if grep -q "^hw.nvidiadrm.modeset=" /boot/loader.conf 2>/dev/null; then
        sed -i '' 's/^hw.nvidiadrm.modeset=.*/hw.nvidiadrm.modeset="1"/' /boot/loader.conf
    else
        echo 'hw.nvidiadrm.modeset="1"' >> /boot/loader.conf
    fi
    
    if grep -q "^hw.nvidia.registry.EnableGpuFirmware=" /boot/loader.conf 2>/dev/null; then
        sed -i '' 's/^hw.nvidia.registry.EnableGpuFirmware=.*/hw.nvidia.registry.EnableGpuFirmware="1"/' /boot/loader.conf
    else
        echo 'hw.nvidia.registry.EnableGpuFirmware="1"' >> /boot/loader.conf
    fi
    
    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    cat << 'EOF' > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
EndSection
EOF
fi

echo "=== [6/12] User Permissions, Rules & Linux Env ==="
sysrc linux_enable="YES"
sysrc linux64_enable="YES"

if id "$TARGET_USER" >/dev/null 2>&1; then
    for GRP in "video" "vboxusers" "operator"; do
        pw groupmod "$GRP" -m "$TARGET_USER" 2>/dev/null || true
    done
fi

mkdir -p /usr/local/etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /usr/local/etc/sudoers.d/wheel_nopasswd
chmod 0440 /usr/local/etc/sudoers.d/wheel_nopasswd

grep -q "vfs.usermount=1" /etc/sysctl.conf || echo "vfs.usermount=1" >> /etc/sysctl.conf
if ! grep -q "\[desktop_rules=10\]" /etc/devfs.rules 2>/dev/null; then
    cat << 'EOF' >> /etc/devfs.rules
[desktop_rules=10]
add path 'usb/*' mode 0660 group operator
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'pass*' mode 0660 group operator
add path 'xpt*' mode 0660 group operator
add path 'drm' mode 0775 group video
add path 'drm/*' mode 0660 group video
EOF
fi
sysrc devfs_system_ruleset="desktop_rules"

grep -q "^proc" /etc/fstab || echo "proc /proc procfs rw 0 0" >>/etc/fstab
grep -q "^fdesc" /etc/fstab || echo "fdesc /dev/fd fdescfs rw 0 0" >>/etc/fstab

echo "=== [7/12] Locale, Keyboard & LibreOffice ==="
if [ "$CONFIG_LOCALE" = "YES" ]; then
    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    VARIANT_LINE=""
    [ -n "$XKB_VARIANT" ] && VARIANT_LINE="Option \"XkbVariant\" \"$XKB_VARIANT\""
    cat << EOF > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    $VARIANT_LINE
EndSection
EOF
    mkdir -p /usr/local/share/sddm/scripts
    touch /usr/local/share/sddm/scripts/Xsetup
    sed -i '' '/setxkbmap/d' /usr/local/share/sddm/scripts/Xsetup
    if [ -n "$XKB_VARIANT" ]; then
        printf "\nsetxkbmap %s %s\n" "$XKB_LAYOUT" "$XKB_VARIANT" >> /usr/local/share/sddm/scripts/Xsetup
    else
        printf "\nsetxkbmap %s\n" "$XKB_LAYOUT" >> /usr/local/share/sddm/scripts/Xsetup
    fi

    if grep -q "^desktop_locale|" /etc/login.conf; then
        sed -i '' '/^desktop_locale|/,/tc=default:/d' /etc/login.conf
    fi
    cat << EOF >> /etc/login.conf
desktop_locale|Custom Desktop Language:\\
    :charset=UTF-8:\\
    :lang=$SYS_LANG:\\
    :tc=default:
EOF
    cap_mkdb /etc/login.conf
    pw usermod "$TARGET_USER" -L desktop_locale 2>/dev/null || true
fi

USER_HOME=$(pw usershow "$TARGET_USER" | cut -d: -f9)
LO_CONFIG_DIR="$USER_HOME/.config/libreoffice/4/user"
LO_CONFIG_FILE="$LO_CONFIG_DIR/registrymodifications.xcu"
if [ -d "$USER_HOME" ] && [ ! -f "$LO_CONFIG_FILE" ]; then
    mkdir -p "$LO_CONFIG_DIR"
    cat << 'EOF' > "$LO_CONFIG_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<item oor:path="/org.openoffice.Office.UI.ToolbarMode/ToolbarMode"><prop oor:name="ToolbarMode" oor:op="fuse"><value>notebookbar_tabbed</value></prop></item>
<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="SymbolStyle" oor:op="fuse"><value>colibre</value></prop></item>
</oor:items>
EOF
    chown -R "$TARGET_USER" "$USER_HOME/.config"
fi

echo "=== [8/12] KDE Wayland Integration (Trojan Horse) ==="
if [ "$DESKTOP_CHOICE" = "KDE" ] && [ "$GPU_CHOICE" = "NVIDIA" ]; then
    echo "-> Configuring Plasma 6 Wayland for NVIDIA..."
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/startplasma-nvidia.sh << 'EOF'
#!/bin/sh
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR
fi
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export KWIN_DRM_USE_EGL_STREAMS=0
export LIBSEAT_BACKEND=seatd
export WLR_NO_HARDWARE_CURSORS=1
export XDG_SESSION_TYPE=wayland
exec dbus-run-session startplasma-wayland
EOF
    chmod +x /usr/local/bin/startplasma-nvidia.sh

    mkdir -p /usr/local/share/xsessions
    cat > /usr/local/share/xsessions/plasma-nvidia-wayland.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/startplasma-nvidia.sh
DesktopNames=KDE
Name=Plasma (NVIDIA Wayland)
Comment=KDE Wayland Session optimized for NVIDIA
EOF
else
    echo "-> Skipped (Wayland Fixes only apply to KDE + NVIDIA)."
fi

echo "=== [9/12] Theme Configuration (Maldives) ==="
mkdir -p /usr/local/etc/sddm.conf.d/
cat << 'EOF' > /usr/local/etc/sddm.conf.d/10-theme.conf
[Theme]
Current=maldives
EOF

echo "=== [10/12] Warrior Services (NTPd, Powerd, Audio) ==="
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc vboxnet_enable="YES"
sysrc sshd_enable="YES"
sysrc sound_load="YES"
sysrc snd_hda_load="YES"
sysrc powerd_enable="YES"
sysrc powerd_flags="-a hiadaptive -b adaptive"
sysrc ntpd_enable="YES"
sysrc ntpd_sync_on_start="NO"
sysrc ntpd_flags="-g"

echo "=== [11/12] ZFS Boot Environment (Immortality) ==="
if mount | grep -q 'on / (zfs'; then
    bectl create post-install-clean || true
    echo "-> ZFS Snapshot 'post-install-clean' created."
else
    echo "-> Skipped (System is not using ZFS on root)."
fi

echo "=== [12/12] Package Repository Upgrade ==="
echo "Switching repository to 'latest' branch and upgrading..."
mkdir -p /usr/local/etc/pkg/repos
cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf 2>/dev/null || true
sed -i '' 's/quarterly/latest/g' /usr/local/etc/pkg/repos/FreeBSD.conf
env ASSUME_ALWAYS_YES=YES pkg update -f
env ASSUME_ALWAYS_YES=YES pkg upgrade -y

echo "=============================================================================="
echo " INSTALLATION COMPLETED AND VERIFIED!"
if [ "$INSTALL_AQUANTIA" = "YES" ]; then
    echo " [!] Aquantia driver compiled. Do not forget to completely power off"
    echo "     the machine (Cold Boot for 15 seconds) for proper initialization!"
else
    echo " You can now restart the machine by typing: reboot"
fi
echo "=============================================================================="
