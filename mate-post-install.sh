#!/bin/sh
# =============================================================================
# FreeBSD 15.1 RELEASE Post-Install Script
# Repository: https://github.com/msartor99
# 
# Features:
# - Interactive UI: bsddialog (Disclaimer, Smart User Setup)
# - Desktop: MATE Desktop Environment + SDDM (Maldives theme)
# - GPU: Nvidia Quadro P1000 (Legacy branch) with Dynamic BusID
# - Softwares: Firefox, VLC, Multimedia tools
# - Localization: Auto-detected via /etc/rc.conf keymap
# - Extras: NTFS support, Network Printers, Audio config, Native Lua PNG Splash
# - Boot Resolution: Forced to verified GOP mode (1920x1200)
# =============================================================================

# --- CONFIGURATION ---
BOOT_RES="1920x1200"
NVIDIA_DRIVER_VERSION="580"
# ---------------------

# -----------------------------------------------------------------------------
# 0. ROOT CHECK & INTERACTIVE DIALOGS
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

bsddialog --title "DISCLAIMER & TERMS" --clear --yesno \
"This post-installation script will modify core system files, install packages, and configure the X11 environment with proprietary Nvidia drivers.\n\n\
The author (msartor99) takes NO RESPONSIBILITY for any system breakage, data loss, or boot failure.\n\n\
Do you understand the risks and wish to proceed with the installation?" 14 70

if [ $? -ne 0 ]; then
    echo "Installation aborted by operator."
    exit 1
fi

# Smart User Detection: Find the first actual user directory in /home
FOUND_USER=$(ls -1 /home/ 2>/dev/null | grep -v '^\.' | head -n 1)
if [ -z "$FOUND_USER" ]; then
    FOUND_USER="administrateur" # Fallback if /home is empty
fi

TMP_FILE=$(mktemp -t bsddialog)
bsddialog --title "User Configuration" --clear --inputbox \
"Please enter the name of the main user you want to configure or create.\n\
(If the user does not exist, it will be created):" 12 60 "$FOUND_USER" 2> "$TMP_FILE"

USER_RESP=$?
TARGET_USER=$(cat "$TMP_FILE")
rm -f "$TMP_FILE"

if [ $USER_RESP -ne 0 ] || [ -z "$TARGET_USER" ]; then
    echo "No valid user provided. Installation aborted."
    exit 1
fi

echo "=== Starting FreeBSD Post-Installation for user: $TARGET_USER ==="
echo "=== Boot Resolution Target: $BOOT_RES ==="

# -----------------------------------------------------------------------------
# 1. IDEMPOTENCY FUNCTIONS
# -----------------------------------------------------------------------------
add_sysctl() {
    local key="$1"
    local value="$2"
    if ! grep -q "^${key}=${value}" /etc/sysctl.conf; then
        echo "${key}=${value}" >> /etc/sysctl.conf
        sysctl "${key}=${value}" >/dev/null 2>&1 || true
    fi
}

add_fstab() {
    local entry="$1"
    if ! grep -qF "$entry" /etc/fstab; then
        echo "$entry" >> /etc/fstab
    fi
}

# -----------------------------------------------------------------------------
# 2. DYNAMIC LOCALIZATION (KEYMAP -> LOCALE)
# -----------------------------------------------------------------------------
CURRENT_KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "us.kbd")

echo "-> Analyzing keymap: $CURRENT_KEYMAP"

case "$CURRENT_KEYMAP" in
    *ch*|*swiss*fr*) XKB_LAYOUT="ch"; XKB_VARIANT="fr"; LOGIN_CLASS="french"; SDDM_LANG="fr_CH"; SYS_LANG="fr_CH.UTF-8" ;;
    *sg*|*swiss*de*) XKB_LAYOUT="ch"; XKB_VARIANT="de"; LOGIN_CLASS="german"; SDDM_LANG="de_CH"; SYS_LANG="de_CH.UTF-8" ;;
    *fr*) XKB_LAYOUT="fr"; XKB_VARIANT=""; LOGIN_CLASS="french"; SDDM_LANG="fr_FR"; SYS_LANG="fr_FR.UTF-8" ;;
    *be*) XKB_LAYOUT="be"; XKB_VARIANT=""; LOGIN_CLASS="french"; SDDM_LANG="fr_BE"; SYS_LANG="fr_BE.UTF-8" ;;
    *de*) XKB_LAYOUT="de"; XKB_VARIANT=""; LOGIN_CLASS="german"; SDDM_LANG="de_DE"; SYS_LANG="de_DE.UTF-8" ;;
    *es*) XKB_LAYOUT="es"; XKB_VARIANT=""; LOGIN_CLASS="spanish"; SDDM_LANG="es_ES"; SYS_LANG="es_ES.UTF-8" ;;
    *it*) XKB_LAYOUT="it"; XKB_VARIANT=""; LOGIN_CLASS="italian"; SDDM_LANG="it_IT"; SYS_LANG="it_IT.UTF-8" ;;
    *uk*|*gb*) XKB_LAYOUT="gb"; XKB_VARIANT=""; LOGIN_CLASS="english"; SDDM_LANG="en_GB"; SYS_LANG="en_GB.UTF-8" ;;
    *) XKB_LAYOUT="us"; XKB_VARIANT=""; LOGIN_CLASS="default"; SDDM_LANG="en_US"; SYS_LANG="en_US.UTF-8" ;;
esac
echo "-> Detected Configuration | X11: $XKB_LAYOUT-$XKB_VARIANT | Locale: $SYS_LANG"

# -----------------------------------------------------------------------------
# 3. PRE-REQUISITES & PACKAGES INSTALLATION
# -----------------------------------------------------------------------------
echo "-> Updating pkg catalog..."
env ASSUME_ALWAYS_YES=yes pkg update

echo "-> Enabling Linux compatibility layer..."
sysrc linux_enable="YES"
sysrc linux64_enable="YES"
kldstat -m linux || kldload linux || true
kldstat -m linux64 || kldload linux64 || true
service linux start >/dev/null 2>&1 || true

echo "-> Cleaning up incompatible default Nvidia drivers..."
env ASSUME_ALWAYS_YES=yes pkg delete -y nvidia-driver >/dev/null 2>&1 || true

echo "-> Installing native Nvidia drivers ($NVIDIA_DRIVER_VERSION)..."
env ASSUME_ALWAYS_YES=yes pkg install -y nvidia-driver-${NVIDIA_DRIVER_VERSION}

echo "-> Installing Linux compatibility libraries for Nvidia..."
env ASSUME_ALWAYS_YES=yes pkg install -y linux-nvidia-libs-${NVIDIA_DRIVER_VERSION}

echo "-> Installing base tools and utilities..."
env ASSUME_ALWAYS_YES=yes pkg install -y doas unzip libzip wget git htop neofetch \
    python3 bashtop ImageMagick7 smartmontools sensors cpu-microcode

echo "-> Installing Desktop Environment (MATE) & Display Manager (SDDM)..."
env ASSUME_ALWAYS_YES=yes pkg install -y xorg mate mate-desktop sddm xdg-user-dirs xf86-input-libinput

echo "-> Installing Audio backend..."
env ASSUME_ALWAYS_YES=yes pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme

echo "-> Installing Multimedia & Office applications..."
env ASSUME_ALWAYS_YES=yes pkg install -y firefox vlc ffmpeg libva-vdpau-driver \
    libva-utils libdvdread libdvdnav signal-cli octopkg multimedia/mpv \
    gstreamer1-plugins-all gstreamer1-libav libbluray

echo "-> Installing NTFS, USB Automount & Network Printing (CUPS)..."
env ASSUME_ALWAYS_YES=yes pkg install -y fusefs-ntfs dsbmd dsbmc cups cups-filters

# -----------------------------------------------------------------------------
# 4. SYSTEM & BOOTLOADER CONFIGURATION
# -----------------------------------------------------------------------------
echo "-> Configuring rc.conf and loader.conf..."

sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc -f /boot/loader.conf coretemp_load="YES"
sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"

# === EFI GOP RESOLUTION & LUA PNG SPLASH ===
sysrc -f /boot/loader.conf efi_max_resolution="$BOOT_RES"
sysrc -f /boot/loader.conf kern.vt.fb.default_mode="$BOOT_RES"
sysrc -f /boot/loader.conf splash="/boot/images/splash.png"

sysrc dbus_enable="YES"
sysrc rc_startmsgs="NO"
sysrc smartd_enable="YES"
sysrc dsbmd_enable="YES"
sysrc cupsd_enable="YES"

sysrc kld_list="nvidia-modeset"
sysrc sound_load="YES"
sysrc snd_hda_load="YES"
sysrc sddm_enable="YES"
sysrc sddm_lang="$SDDM_LANG"

if ! grep -q 'run_rc_script ${_rc_elem} ${_boot} > /dev/null' /etc/rc; then
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
fi

# -----------------------------------------------------------------------------
# 5. SYSCTL & FSTAB
# -----------------------------------------------------------------------------
echo "-> Configuring sysctl and fstab..."
add_sysctl "kern.sched.preempt_thresh" "224"
add_sysctl "kern.ipc.shm_allow_removed" "1"
add_sysctl "net.local.stream.recvspace" "65536"
add_sysctl "net.local.stream.sendspace" "65536"
add_sysctl "hw.snd.default_unit" "1"
add_fstab "proc /proc procfs rw 0 0"

# -----------------------------------------------------------------------------
# 6. X11, NVIDIA & LIBINPUT HOTPLUG FIX
# -----------------------------------------------------------------------------
if [ ! -f /usr/local/etc/smartd.conf ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi
service smartd start >/dev/null 2>&1 || true

rm -f /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
rm -f /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
rm -f /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier      "libinput keyboard catchall"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver          "libinput"
    Option          "xkb_layout" "${XKB_LAYOUT}"
    Option          "xkb_variant" "${XKB_VARIANT}"
    Option          "xkb_options" "terminate:ctrl_alt_bksp" 
EndSection

Section "InputClass"
    Identifier      "fallback keyboard catchall"
    MatchIsKeyboard "on"
    Option          "XkbLayout" "${XKB_LAYOUT}"
    Option          "XkbVariant" "${XKB_VARIANT}"
    Option          "XkbOptions" "terminate:ctrl_alt_bksp" 
EndSection
EOF

NVIDIA_BUSID=$(pciconf -l | awk '/vgapci/ {print $1}' | sed -E 's/.*pci[0-9]+:([0-9]+:[0-9]+:[0-9]+).*/\1/' | head -n 1)

if [ -n "$NVIDIA_BUSID" ]; then
    BUSID_LINE="BusID          \"PCI:${NVIDIA_BUSID}\""
else
    BUSID_LINE="# BusID dynamically not found"
fi

cat > /usr/local/etc/X11/xorg.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    Option         "DPMS" "true"
EndSection

Section "Device"
    Identifier     "Nvidia Card"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    ${BUSID_LINE}
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Nvidia Card"
    Monitor        "Monitor0"
    DefaultDepth    24
EndSection
EOF

# -----------------------------------------------------------------------------
# 7. USERS & LOGIN CLASSES
# -----------------------------------------------------------------------------
echo "-> Configuring /etc/login.conf..."
if [ "$LOGIN_CLASS" != "default" ]; then
    if ! grep -q "^${LOGIN_CLASS}|" /etc/login.conf; then
        cat >> /etc/login.conf <<EOF

${LOGIN_CLASS}|Localized ${LOGIN_CLASS} Users Accounts:\
	:charset=UTF-8:\
	:lang=${SYS_LANG}:\
	:tc=default:
EOF
    fi
fi
cap_mkdb /etc/login.conf

pw usermod root -L "$LOGIN_CLASS" || true
if id -u "$TARGET_USER" >/dev/null 2>&1; then
    pw usermod "$TARGET_USER" -G wheel,operator,video -L "$LOGIN_CLASS"
else
    pw useradd "$TARGET_USER" -m -G wheel,operator,video -L "$LOGIN_CLASS" -s /bin/sh
fi

# -----------------------------------------------------------------------------
# 8. SDDM THEMING & STARTUP SCRIPT FIX
# -----------------------------------------------------------------------------
echo "-> Configuring SDDM (Maldives theme & Startup Xkb)..."
mkdir -p /usr/local/etc/sddm.conf.d
cat >/usr/local/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=maldives
EOF

mkdir -p /usr/local/share/sddm/scripts
XSETUP_FILE="/usr/local/share/sddm/scripts/Xsetup"
if [ ! -f "$XSETUP_FILE" ]; then echo "#!/bin/sh" > "$XSETUP_FILE"; fi
if ! grep -q "setxkbmap" "$XSETUP_FILE"; then
    if [ -n "$XKB_VARIANT" ]; then
        echo "setxkbmap ${XKB_LAYOUT} -variant ${XKB_VARIANT}" >> "$XSETUP_FILE"
    else
        echo "setxkbmap ${XKB_LAYOUT}" >> "$XSETUP_FILE"
    fi
fi
chmod +x "$XSETUP_FILE"

# -----------------------------------------------------------------------------
# 9. SPLASH SCREEN (NATIVE LUA PNG HANDLING)
# -----------------------------------------------------------------------------
echo "-> Configuring modern Lua PNG boot splash screen ($BOOT_RES)..."

mkdir -p /media /boot/images

if [ ! -f /boot/images/splash.png ]; then
    cd /media
    if [ ! -f v2.png ]; then wget -q https://kamila.is/media/v2.png || true; fi
    
    if [ -f v2.png ]; then
        if command -v magick >/dev/null; then
            # Clean and modern PNG resize handled dynamically via Lua loader
            magick v2.png -resize ${BOOT_RES} /boot/images/splash.png
        else
            echo "Warning: ImageMagick not found. Splash screen skipped."
        fi
    fi
    cd /
fi

# Cleanup old legacy module variables if present
sysrc -f /boot/loader.conf -x splash_bmp_load >/dev/null 2>&1 || true
sysrc -f /boot/loader.conf -x bitmap_load >/dev/null 2>&1 || true
sysrc -f /boot/loader.conf -x bitmap_name >/dev/null 2>&1 || true
sysrc -f /boot/loader.conf -x bitmap_type >/dev/null 2>&1 || true

# Activate the splash cycle system service
sysrc splash_changer_enable="YES"

echo "=== Post-Installation Completed Successfully! ==="
echo "Please reboot your system."