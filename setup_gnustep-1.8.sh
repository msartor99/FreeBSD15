#!/bin/sh
# Idempotent deployment script for NeXTSTEP (Window Maker + GNUstep) on FreeBSD 15.1
# Hardware & Services: NVIDIA, USB Automount, Network, Printers, Webcam, Seatd, Linuxulator, SMART
# Desktop Tweaks: Silent boot, Splash Screens, IPC/Scheduler tuning, CPU Microcode, devfs, fstab
# NeXTSTEP Desktop: Full Window Maker Dockapps, GNUstep native apps, enriched WMRootMenu
# Usage: ./setup_nextstep_freebsd.sh [--yes] [--nvidia=latest|580|470]

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

AUTO_ACCEPT="no"
NVIDIA_CHOICE=""

for arg in "$@"; do
    case "$arg" in
        --yes|-y)
            AUTO_ACCEPT="yes"
            ;;
        --nvidia=latest|--nvidia=580|--nvidia=470)
            NVIDIA_CHOICE="${arg#--nvidia=}"
            ;;
        *)
            echo "Error: Unknown option '$arg'." >&2
            echo "Usage: $0 [--yes] [--nvidia=latest|580|470]" >&2
            exit 1
            ;;
    esac
done

if [ "$AUTO_ACCEPT" != "yes" ]; then
    bsddialog --title "WARNING AND DISCLAIMER" --clear --yesno \
"This script will modify the system configuration of this FreeBSD 15.1 machine:

  - Install packages (Xorg, SDDM, NVIDIA, Window Maker, Utilities...)
  - Install GNUstep apps & Dockapps (SystemPreferences, wmclock, wmix...)
  - Tune system (Sysctl, Silent Boot, Custom Splash, Linuxulator, procfs)
  - Configure SDDM 'maldives' theme and the NeXTSTEP X11 session
  - Configure device permissions (devfs.rules), seatd, and webcamd
  - Apply French login class and advanced Xorg keyboard options

This script is provided AS IS, without warranty of any kind. Please ensure
you have backed up any important data before proceeding.

Do you accept these changes and wish to continue?" 18 75
    
    if [ $? -ne 0 ]; then
        clear
        echo "Operation aborted by operator."
        exit 0
    fi
    clear
fi

if [ -z "$NVIDIA_CHOICE" ]; then
    GPU_DETECTED=$(pciconf -lv | grep -m1 -B2 -i "class.*display" | awk -F"'" '/vendor/ {v=$2} /device/ {d=$2} END {print v " " d}' | xargs)
    [ -z "$GPU_DETECTED" ] && GPU_DETECTED="Unidentified Display Controller"

    if [ "$AUTO_ACCEPT" = "yes" ]; then
        NVIDIA_CHOICE="latest"
    else
        exec 3>&1
        NVIDIA_CHOICE=$(bsddialog --title "NVIDIA DISPLAY DRIVER SELECTION" --clear \
            --menu "Detected GPU: $GPU_DETECTED\n\nSelect NVIDIA driver version to install:" 15 75 3 \
            "latest" "Current branch (RTX 20xx, 30xx, 40xx, 50xx)" \
            "580"    "Legacy branch (GTX 7xx-10xx, Maxwell/Pascal/Volta)" \
            "470"    "Legacy branch (Kepler / GeForce 600-700 series)" \
            2>&1 1>&3)
        EXIT_CODE=$?
        exec 3>&-
        clear

        if [ $EXIT_CODE -ne 0 ]; then
            echo "Operation aborted during driver selection."
            exit 0
        fi
    fi
fi

case "$NVIDIA_CHOICE" in
    latest) NVIDIA_PKG="nvidia-driver" ; NVIDIA_LINUX_PKG="linux-nvidia-libs" ;;
    580)    NVIDIA_PKG="nvidia-driver-580" ; NVIDIA_LINUX_PKG="linux-nvidia-libs-580" ;;
    470)    NVIDIA_PKG="nvidia-driver-470" ; NVIDIA_LINUX_PKG="linux-nvidia-libs-470" ;;
esac

echo ">>> Selected NVIDIA driver package: $NVIDIA_PKG (with $NVIDIA_LINUX_PKG)"

if getent passwd 1001 >/dev/null 2>&1; then
    TARGET_USER=$(getent passwd 1001 | cut -d: -f1)
elif getent passwd 1000 >/dev/null 2>&1; then
    TARGET_USER=$(getent passwd 1000 | cut -d: -f1)
else
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65000 && $1 != "nobody" { print $3, $1 }' | sort -n | head -n 1 | awk '{print $2}')
fi

if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Error: Unable to automatically detect a standard user (UID >= 1000)." >&2
    exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
echo ">>> Auto-detected target user: $TARGET_USER (UID: $TARGET_UID, Home: $USER_HOME)"

echo "=== 1. Enabling Linux Kernel Support (Pre-requisite for linux-rl9 & NVIDIA) ==="
sysrc linux_enable="YES"
if ! kldstat -q -m linux64; then
    kldload linux64 >/dev/null 2>&1 || true
fi

echo "=== 2. Checking and installing required packages for FreeBSD 15.1 ==="
pkg update
for old_nv in nvidia-driver nvidia-driver-580 nvidia-driver-470; do
    if [ "$old_nv" != "$NVIDIA_PKG" ] && pkg info -e "$old_nv" >/dev/null 2>&1; then
        echo "Removing conflicting NVIDIA driver package: $old_nv"
        pkg delete -y "$old_nv"
    fi
done

PACKAGES="xorg sddm $NVIDIA_PKG $NVIDIA_LINUX_PKG nvidia-settings windowmaker wmakerconf gnustep gnustep-app gworkspace systempreferences affiche wmsystemtray wmnd wmcpuload wmmemload wmclock wmix wmweather+ xterm firefox thunderbird libreoffice fr-libreoffice vlc kdenlive gimp gtkchtheme lxappearance qt5ct adwaita-icon-theme automount e2fsprogs cups cups-filters gutenprint hplip system-config-printer avahi nss_mdns"
EXTRA_TOOLS="cpu-microcode doas unzip libzip wget git linux-rl9 htop fastfetch python3 btop smartmontools seatd webcamd fusefs-ntfs fusefs-ext2 fusefs-hfsfuse signal-cli ImageMagick7"

MISSING_PKGS=""
for pkg_name in $PACKAGES $EXTRA_TOOLS; do
    if ! pkg info -e "$pkg_name" >/dev/null 2>&1; then
        MISSING_PKGS="$MISSING_PKGS $pkg_name"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    echo "Installing missing packages:$MISSING_PKGS"
    # shellcheck disable=SC2086
    pkg install -y $MISSING_PKGS
else
    echo "All required packages are already installed."
fi

echo "=== 3. System Tuning (Silent Boot, Sysctl, Loader modules) ==="
sysrc -f /boot/loader.conf boot_mute="YES" autoboot_delay="3" tmpfs_load="YES" aio_load="YES"
sysrc rc_startmsgs="NO"

touch /etc/sysctl.conf
for sysctl_val in \
    "kern.sched.preempt_thresh=224" \
    "kern.ipc.shm_allow_removed=1" \
    "net.local.stream.recvspace=65536" \
    "net.local.stream.sendspace=65536" \
    "vfs.usermount=1"; do
    
    key="${sysctl_val%%=*}"
    if ! grep -Eq "^${key}=" /etc/sysctl.conf; then
        echo "$sysctl_val" >> /etc/sysctl.conf
    fi
    sysctl "$sysctl_val" >/dev/null 2>&1 || true
done

if ! grep -qw "procfs" /etc/fstab; then
    echo "proc      /proc       procfs      rw      0       0" >> /etc/fstab
fi
if ! grep -qw "fdescfs" /etc/fstab; then
    echo "fdesc     /dev/fd     fdescfs     rw      0       0" >> /etc/fstab
fi
mount -a >/dev/null 2>&1 || true

echo "=== 4. Boot & Shutdown Splash Screen Setup ==="
mkdir -p /boot/images
echo ">>> Downloading and resizing splash image (1920x1200)..."
if wget -qO /tmp/v2-blue.png "https://raw.githubusercontent.com/msartor99/FreeBSD14/main/v2-blue.png"; then
    magick /tmp/v2-blue.png -resize '1920x1200!' /boot/images/custom-splash.png
    sysrc -f /boot/loader.conf splash="/boot/images/custom-splash.png"
    sysrc -f /boot/loader.conf shutdown_splash="/boot/images/custom-splash.png"
    rm -f /tmp/v2-blue.png
    echo ">>> Custom splash screen configured successfully."
else
    echo ">>> Warning: Failed to download custom splash image."
fi

echo "=== 5. Hardware Setup: CPU Microcode & Thermal sensors ==="
CPU_MODEL=$(sysctl -n hw.model)
sysrc -f /boot/loader.conf cpu_microcode_load="YES"
if echo "$CPU_MODEL" | grep -iq "AMD"; then
    sysrc -f /boot/loader.conf amdtemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    kldload amdtemp >/dev/null 2>&1 || true
elif echo "$CPU_MODEL" | grep -iq "Intel"; then
    sysrc -f /boot/loader.conf coretemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    kldload coretemp >/dev/null 2>&1 || true
fi

echo "=== 6. Hardware Setup: GPU & Filesystems Modules ==="
for kmod in nvidia-modeset fusefs ext2fs; do
    if ! sysrc -n kld_list 2>/dev/null | grep -qw "$kmod"; then
        sysrc kld_list+="$kmod"
    fi
    if ! kldstat -q -m "$kmod" 2>/dev/null; then
        kldload "$kmod" || true
    fi
done

mkdir -p /usr/local/etc/X11/xorg.conf.d
printf "%s\n" \
'Section "Device"' \
'    Identifier     "NVIDIA GPU"' \
'    Driver         "nvidia"' \
'    VendorName     "NVIDIA Corporation"' \
'EndSection' > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf

echo "=== 7. Background Services (Automount, Devfs, Seatd, Webcamd, SMART, Network...) ==="
if ! grep -q "\[localrules=5\]" /etc/devfs.rules 2>/dev/null; then
    cat >> /etc/devfs.rules << 'EOF'

[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'uscanner*' mode 0660 group operator
add path 'xpt*' mode 0660 group operator
add path 'pass*' mode 0660 group operator
add path 'md*' mode 0660 group operator
add path 'msdosfs/*' mode 0660 group operator
add path 'ext2fs/*' mode 0660 group operator
add path 'ntfs/*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'video*' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
add path 'vboxnetctl' mode 0660 group vboxusers
EOF
fi
sysrc devfs_system_ruleset="localrules"
service devfs restart

printf "%s\n" \
"USERUMOUNT=YES" \
"ATIME=NO" \
"REMOVEDIRS=YES" \
"USER=$TARGET_USER" \
'FM="openapp GWorkspace"' > /usr/local/etc/automount.conf

sysrc smartd_enable="YES"
sysrc seatd_enable="YES"
sysrc webcamd_enable="YES"
sysrc dbus_enable="YES" 
sysrc avahi_daemon_enable="YES" 
sysrc avahi_dnsconfd_enable="YES" 
sysrc cupsd_enable="YES"

if [ ! -f /usr/local/etc/smartd.conf ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi

if [ -f /etc/nsswitch.conf ]; then
    if grep -q "^hosts:" /etc/nsswitch.conf && ! grep -q "^hosts:.*mdns" /etc/nsswitch.conf; then
        sed -i '' 's/^hosts:.*/hosts: files mdns dns/' /etc/nsswitch.conf
    fi
fi

# Correction du délai de connexion SSH lié à la résolution mDNS
if [ -f /etc/ssh/sshd_config ] && ! grep -q "^UseDNS no" /etc/ssh/sshd_config; then
    echo "UseDNS no" >> /etc/ssh/sshd_config
    service sshd restart >/dev/null 2>&1 || true
fi

service linux status >/dev/null 2>&1 || service linux start >/dev/null 2>&1 || true

for svc in devd smartd seatd webcamd dbus avahi-daemon avahi-dnsconfd cupsd; do
    service "$svc" status >/dev/null 2>&1 || service "$svc" start >/dev/null 2>&1 || true
done

echo "=== 8. Syncing Xorg & SDDM keyboard and locale from system settings ==="
SYS_KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "")
XKB_LAYOUT=""
XKB_VARIANT=""
case "$SYS_KEYMAP" in
    ch-fr*|swissfrench*) XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
    ch*)                 XKB_LAYOUT="ch" ;;
    fr*)                 XKB_LAYOUT="fr" ;;
    de*)                 XKB_LAYOUT="de" ;;
    be*)                 XKB_LAYOUT="be" ;;
    ca*)                 XKB_LAYOUT="ca" ;;
    us*)                 XKB_LAYOUT="us" ;;
esac

if [ -n "$XKB_LAYOUT" ]; then
    echo ">>> Applying X11 keyboard layout: layout='$XKB_LAYOUT' variant='${XKB_VARIANT:-none}'"
    {
        echo 'Section "ServerFlags"'
        echo '    Option "DontZap" "false"'
        echo 'EndSection'
        echo ''
        echo 'Section "InputClass"'
        echo '    Identifier "System Keyboard Layout"'
        echo '    MatchIsKeyboard "on"'
        echo "    Option \"XkbLayout\" \"$XKB_LAYOUT\""
        if [ -n "$XKB_VARIANT" ]; then
            echo "    Option \"XkbVariant\" \"$XKB_VARIANT\""
        fi
        echo '    Option "XkbOptions" "terminate:ctrl_alt_bksp"'
        echo 'EndSection'
    } > /usr/local/etc/X11/xorg.conf.d/10-keyboard.conf
fi

DETECTED_LANG=$(su - "$TARGET_USER" -c 'echo "SAFE_LANG_IS=${LANG:-}"' 2>/dev/null | grep "^SAFE_LANG_IS=" | cut -d= -f2 | tr -d '\r')
if [ -z "$DETECTED_LANG" ] || [ "$DETECTED_LANG" = "C" ] || [ "$DETECTED_LANG" = "C.UTF-8" ]; then
    DETECTED_LANG="fr_FR.UTF-8"
fi

echo "=== 9. Configuring SDDM (Maldives theme, Keyboard & Locale) ==="
sysrc sddm_enable="YES"
sysrc sddm_lang="$DETECTED_LANG"

if getent passwd sddm >/dev/null 2>&1 && getent group video >/dev/null 2>&1; then
    if ! id -Gn sddm | grep -qw "video"; then
        pw groupmod video -m sddm
    fi
fi

mkdir -p /usr/local/etc/sddm.conf.d
printf "%s\n" "[Theme]" "Current=maldives" > /usr/local/etc/sddm.conf.d/10-theme.conf

mkdir -p /usr/local/share/sddm/scripts
if [ -n "$XKB_LAYOUT" ]; then
    {
        echo '#!/bin/sh'
        if [ -n "$XKB_VARIANT" ]; then
            echo "/usr/local/bin/setxkbmap -layout \"$XKB_LAYOUT\" -variant \"$XKB_VARIANT\""
        else
            echo "/usr/local/bin/setxkbmap -layout \"$XKB_LAYOUT\""
        fi
    } > /usr/local/share/sddm/scripts/Xsetup
    chmod 755 /usr/local/share/sddm/scripts/Xsetup
fi

mkdir -p /usr/local/share/xsessions
printf "%s\n" \
"[Desktop Entry]" \
"Encoding=UTF-8" \
"Name=NeXTSTEP (Window Maker + GNUstep)" \
"Comment=NeXTSTEP Desktop Environment on FreeBSD 15.1" \
"Exec=/usr/local/bin/start-nextstep-session" \
"Type=Application" > /usr/local/share/xsessions/nextstep.desktop

printf "%s\n" \
'#!/bin/sh' \
'if [ -x "$HOME/.xinitrc" ]; then' \
'    exec "$HOME/.xinitrc"' \
'fi' \
'if [ -f /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then' \
'    . /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh' \
'fi' \
'gdnc &' \
'gpbs &' \
'exec wmaker' > /usr/local/bin/start-nextstep-session
chmod 755 /usr/local/bin/start-nextstep-session

echo "=== 10. Configuring Permissions (groups, doas, login class) ==="
for grp in wheel video operator cups seatd webcamd; do
    if getent group "$grp" >/dev/null 2>&1; then
        if ! id -Gn "$TARGET_USER" | grep -qw "$grp"; then
            pw groupmod "$grp" -m "$TARGET_USER"
        fi
    fi
done

pw usermod "$TARGET_USER" -L french
pw usermod root -L french

if [ ! -f /usr/local/etc/doas.conf ] || ! grep -q "$TARGET_USER" /usr/local/etc/doas.conf; then
    echo "permit persist $TARGET_USER as root" >> /usr/local/etc/doas.conf
fi

if [ -x /usr/local/GNUstep/Applications/WPrefs.app/WPrefs ]; then
    ln -sf /usr/local/GNUstep/Applications/WPrefs.app/WPrefs /usr/local/bin/WPrefs
fi

echo "=== 11. Configuring user environment ($TARGET_USER) ==="
if [ ! -d "$USER_HOME/GNUstep/Defaults" ]; then
    su - "$TARGET_USER" -c "wmaker.inst --batch"
fi

mkdir -p "$USER_HOME/.config/gtk-3.0" "$USER_HOME/.config/qt5ct" "$USER_HOME/GNUstep/Defaults" "$USER_HOME/GNUstep/Library/WindowMaker"
GNUSTEP_SH="/usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh"
touch "$USER_HOME/.profile"
if [ -f "$GNUSTEP_SH" ] && ! grep -Fq "$GNUSTEP_SH" "$USER_HOME/.profile"; then
    printf '\n# GNUstep Environment\nif [ -f %s ]; then\n    . %s\nfi\n' "$GNUSTEP_SH" "$GNUSTEP_SH" >> "$USER_HOME/.profile"
fi

GNUSTEP_CSH="/usr/local/GNUstep/System/Library/Makefiles/GNUstep.csh"
touch "$USER_HOME/.cshrc"
if [ -f "$GNUSTEP_CSH" ] && ! grep -Fq "$GNUSTEP_CSH" "$USER_HOME/.cshrc"; then
    printf '\n# GNUstep Environment\nif ( -f %s ) then\n    source %s\nendif\n' "$GNUSTEP_CSH" "$GNUSTEP_CSH" >> "$USER_HOME/.cshrc"
fi

# Utilisation du script natif 'autostart' de Window Maker pour éviter le plantage
printf "%s\n" \
'#!/bin/sh' \
'wmsystemtray &' \
'wmcpuload &' \
'wmmemload &' \
'wmnd &' \
'wmclock &' \
'wmix &' \
'wmweather+ &' \
'openapp GWorkspace &' > "$USER_HOME/GNUstep/Library/WindowMaker/autostart"
chmod 755 "$USER_HOME/GNUstep/Library/WindowMaker/autostart"

# Le .xinitrc est nettoyé et charge juste Window Maker
printf "%s\n" \
'#!/bin/sh' \
'if [ -f "$HOME/.profile" ]; then' \
'    . "$HOME/.profile"' \
'fi' \
'if [ -f /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then' \
'    . /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh' \
'fi' \
'gdnc &' \
'gpbs &' \
'export QT_QPA_PLATFORMTHEME=qt5ct' \
'exec wmaker' > "$USER_HOME/.xinitrc"
chmod 755 "$USER_HOME/.xinitrc"

printf "%s\n" \
"[Settings]" \
"gtk-theme-name=Adwaita" \
"gtk-application-prefer-dark-theme=0" \
"gtk-font-name=Sans 10" > "$USER_HOME/.config/gtk-3.0/settings.ini"

printf "%s\n" \
"window, dialog, .background {" \
"    background-color: #aeaaae;" \
"    color: #000000;" \
"}" \
"headerbar, .titlebar {" \
"    background-color: #8e8a8e;" \
"    color: #ffffff;" \
"}" > "$USER_HOME/.config/gtk-3.0/gtk.css"

# Nouveau menu considérablement enrichi
printf "%s\n" \
'(' \
'  "NeXTSTEP Menu",' \
'  ("Applications",' \
'    ("Workspace Manager", EXEC, "openapp GWorkspace"),' \
'    ("System Preferences", EXEC, "openapp SystemPreferences"),' \
'    ("Terminal (GNUstep)", EXEC, "openapp Terminal"),' \
'    ("Mail (GNUMail)", EXEC, "openapp GNUMail"),' \
'    ("Image Viewer", EXEC, "openapp ImageViewer"),' \
'    ("Sticky Notes", EXEC, "openapp Affiche")' \
'  ),' \
'  ("Dockapps (Widgets)",' \
'    ("Clock", EXEC, "wmclock"),' \
'    ("Audio Mixer", EXEC, "wmix"),' \
'    ("Weather", EXEC, "wmweather+"),' \
'    ("Network Monitor", EXEC, "wmnd"),' \
'    ("CPU Monitor", EXEC, "wmcpuload"),' \
'    ("System Tray", EXEC, "wmsystemtray")' \
'  ),' \
'  ("Office & Internet",' \
'    ("Firefox Web Browser", EXEC, "firefox"),' \
'    ("Thunderbird Mail", EXEC, "thunderbird"),' \
'    ("LibreOffice Suite", EXEC, "libreoffice")' \
'  ),' \
'  ("Multimedia & Creation",' \
'    ("VLC Media Player", EXEC, "vlc"),' \
'    ("Kdenlive (Video Editor)", EXEC, "kdenlive"),' \
'    ("GIMP Image Editor", EXEC, "gimp")' \
'  ),' \
'  ("Printers & Hardware",' \
'    ("Printer Manager (CUPS)", EXEC, "firefox http://localhost:631"),' \
'    ("HP Device Manager", EXEC, "hp-toolbox"),' \
'    ("NVIDIA Settings", EXEC, "nvidia-settings")' \
'  ),' \
'  ("Appearance & Settings",' \
'    ("Window Maker Preferences (WPrefs)", EXEC, "/usr/local/GNUstep/Applications/WPrefs.app/WPrefs"),' \
'    ("GTK3 Appearance", EXEC, "lxappearance"),' \
'    ("GTK2 Appearance", EXEC, "gtk-chtheme"),' \
'    ("Qt5 Appearance", EXEC, "qt5ct")' \
'  ),' \
'  ("System Tools",' \
'    ("System Monitor (htop)", EXEC, "xterm -e htop"),' \
'    ("System Monitor (btop)", EXEC, "xterm -e btop"),' \
'    ("System Info (fastfetch)", EXEC, "xterm -hold -e fastfetch")' \
'  ),' \
'  ("Session",' \
'    ("Restart Window Maker", RESTART),' \
'    ("Exit Session", EXIT)' \
'  )' \
')' > "$USER_HOME/GNUstep/Defaults/WMRootMenu"

chown -R "$TARGET_USER:" "$USER_HOME/.profile" "$USER_HOME/.cshrc" "$USER_HOME/.xinitrc" "$USER_HOME/.config" "$USER_HOME/GNUstep"

echo "================================================================="
echo "Deployment completed successfully for user: $TARGET_USER (UID $TARGET_UID)"
echo "- Custom Splash: 1920x1200 image set for Boot AND Shutdown."
echo "- Workspace Manager: Added to auto-start (replicates NeXTSTEP File Viewer)."
echo "- Dockapps: Auto-started on first boot. Drag to dock and lock them."
echo "- UI: Window Maker Menu populated with native GNUstep apps."
echo "Next step: Run 'reboot' to boot into your optimized FreeBSD 15.1 Desktop."
echo "================================================================="