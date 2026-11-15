#!/bin/sh
# ==============================================================================
# File    : setup_nextstep_freebsd.sh
# Version : 2.0 (Based on workstation-v1.28 architecture)
# System  : FreeBSD 15.1 (amd64)
# Role    : Idempotent NeXTSTEP (Window Maker + GNUstep) Workstation Deployment
# Notes   : Includes pkg rquery safeguard, PCI BusID detection for P620,
#           99-keyboard.conf priority, UseDNS SSH fix, and 1920x1200 splash.
# Usage   : ./setup_nextstep_freebsd.sh [--yes] [--nvidia=latest|580|550|470]
# ==============================================================================

set -eu

SPLASH_URL="https://raw.githubusercontent.com/msartor99/FreeBSD14/main/v2-blue.png"
TMP_SPLASH="/tmp/v2-blue.png"

TMP_DIALOG=$(mktemp -t bsddialog)
trap 'rm -f "$TMP_DIALOG" "$TMP_SPLASH"' EXIT INT TERM HUP

AUTO_ACCEPT="no"
NVIDIA_CHOICE=""
TARGET_USER=""
TARGET_UID=""
USER_HOME=""
GPU_DETECTED=""
NVIDIA_PKG=""
NVIDIA_KMOD_PKG=""
NVIDIA_LINUX_PKG=""
SYS_LANG=""
XKB_LAYOUT=""
XKB_VARIANT=""

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --yes|-y)
                AUTO_ACCEPT="yes"
                ;;
            --nvidia=latest|--nvidia=580|--nvidia=550|--nvidia=470)
                NVIDIA_CHOICE="${arg#--nvidia=}"
                ;;
            *)
                echo "Error: Unknown option '$arg'." >&2
                echo "Usage: $0 [--yes] [--nvidia=latest|580|550|470]" >&2
                exit 1
                ;;
        esac
    done
}

# Fonction bouclier : vérifie que chaque paquet existe dans le dépôt avant de l'installer
install_available_pkgs() {
    VALID_PKGS=""
    MISSING_PKGS=""
    for pkg in "$@"; do
        if pkg info -e "$pkg" >/dev/null 2>&1; then
            continue
        elif pkg rquery "%n" "$pkg" >/dev/null 2>&1; then
            VALID_PKGS="$VALID_PKGS $pkg"
        else
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo ">>> WARNING: The following packages are unavailable in the repo and will be skipped:$MISSING_PKGS"
    fi

    if [ -n "$VALID_PKGS" ]; then
        echo ">>> Installing packages:$VALID_PKGS"
        # shellcheck disable=SC2086
        pkg install -y $VALID_PKGS
    else
        echo ">>> All requested packages in this group are already installed."
    fi
}

detect_user() {
    if getent passwd 1001 >/dev/null 2>&1; then
        TARGET_USER=$(getent passwd 1001 | cut -d: -f1)
    elif getent passwd 1000 >/dev/null 2>&1; then
        TARGET_USER=$(getent passwd 1000 | cut -d: -f1)
    else
        TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65000 && $1 != "nobody" { print $3, $1 }' | sort -n | head -n 1 | awk '{print $2}')
    fi

    if [ -z "$TARGET_USER" ] || ! pw usershow "$TARGET_USER" >/dev/null 2>&1; then
        echo "Error: Unable to automatically detect a standard user (UID >= 1000)." >&2
        exit 1
    fi

    TARGET_UID=$(id -u "$TARGET_USER")
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    echo ">>> Auto-detected target user: $TARGET_USER (UID: $TARGET_UID, Home: $USER_HOME)"
}

interactive_config() {
    GPU_DETECTED=$(pciconf -lv | grep -m1 -B2 -i "class.*display" | awk -F"'" '/vendor/ {v=$2} /device/ {d=$2} END {print v " " d}' | xargs)
    [ -z "$GPU_DETECTED" ] && GPU_DETECTED="Unidentified Display Controller"

    if [ "$AUTO_ACCEPT" != "yes" ]; then
        if ! bsddialog --title "WARNING AND DISCLAIMER - FreeBSD 15.1" --clear --yesno \
"This script will configure your NeXTSTEP (Window Maker + GNUstep) workstation:

  - User detected : $TARGET_USER (UID: $TARGET_UID)
  - GPU detected  : $GPU_DETECTED
  - Install Xorg, SDDM, NVIDIA drivers, Sound (PipeWire/Pulse), & Utilities
  - Install Window Maker, GNUstep apps, and Dockapps
  - Tune system (Sysctl, Silent Boot, 1920x1200 Splash, Linuxulator)
  - Configure device permissions (devfs.rules), CUPS/HPLIP, and USB automount
  - Preserve existing console keyboard & locale (99-keyboard.conf priority)

Are you sure you want to continue?" 19 78; then
            clear
            echo "Canceled by user."
            exit 0
        fi
        clear
    fi

    if [ -z "$NVIDIA_CHOICE" ]; then
        if [ "$AUTO_ACCEPT" = "yes" ]; then
            NVIDIA_CHOICE="latest"
        else
            if ! bsddialog --title "NVIDIA DISPLAY DRIVER SELECTION" --clear \
                --menu "Detected GPU: $GPU_DETECTED\n\nSelect NVIDIA driver version to install:" 15 75 4 \
                "latest" "Current branch (RTX 20xx, 30xx, 40xx, 50xx)" \
                "580"    "Branch 580 (GTX 7xx-10xx, Maxwell/Pascal/Volta & RTX)" \
                "550"    "Branch 550 ( Intermediate Production Branch)" \
                "470"    "Branch 470 (Legacy Kepler / GeForce 600-700 series)" \
                2> "$TMP_DIALOG"; then
                clear
                echo "Operation aborted during driver selection."
                exit 0
            fi
            NVIDIA_CHOICE=$(cat "$TMP_DIALOG")
            clear
        fi
    fi

    case "$NVIDIA_CHOICE" in
        latest)
            NVIDIA_PKG="nvidia-driver"
            NVIDIA_KMOD_PKG="nvidia-kmod"
            NVIDIA_LINUX_PKG="linux-nvidia-libs"
            ;;
        *)
            NVIDIA_PKG="nvidia-driver-${NVIDIA_CHOICE}"
            NVIDIA_KMOD_PKG="nvidia-kmod-${NVIDIA_CHOICE}"
            NVIDIA_LINUX_PKG="linux-nvidia-libs-${NVIDIA_CHOICE}"
            ;;
    esac

    echo ">>> Selected NVIDIA packages: $NVIDIA_PKG, $NVIDIA_KMOD_PKG, $NVIDIA_LINUX_PKG"
}

configure_tuning() {
    echo "=== 1. System Tuning (Silent Boot, Sysctl, Loader modules, Fstab) ==="
    sysrc -f /boot/loader.conf boot_mute="YES"
    sysrc -f /boot/loader.conf autoboot_delay="3"
    sysrc -f /boot/loader.conf tmpfs_load="YES"
    sysrc -f /boot/loader.conf aio_load="YES"
    sysrc -f /boot/loader.conf cuse_load="YES"
    sysrc rc_startmsgs="NO"

    if ! grep -q "> /dev/null" /etc/rc; then
        sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    fi

    SYSCTL_CONF="/etc/sysctl.conf"
    touch "$SYSCTL_CONF"
    for sysctl_val in \
        "kern.sched.preempt_thresh=224" \
        "kern.ipc.shm_allow_removed=1" \
        "net.local.stream.recvspace=65536" \
        "net.local.stream.sendspace=65536" \
        "vfs.usermount=1"; do
        key="${sysctl_val%%=*}"
        grep -q "^${key}=" "$SYSCTL_CONF" || echo "$sysctl_val" >> "$SYSCTL_CONF"
        sysctl "$sysctl_val" >/dev/null 2>&1 || true
    done

    grep -q "^proc" /etc/fstab || echo "proc      /proc       procfs      rw      0       0" >> /etc/fstab
    grep -q "^fdesc" /etc/fstab || echo "fdesc     /dev/fd     fdescfs     rw      0       0" >> /etc/fstab
    mount -a >/dev/null 2>&1 || true
}

enable_linux_compat() {
    echo "=== 2. Enabling Linux Compatibility in Kernel ==="
    sysrc -x linux64_enable >/dev/null 2>&1 || true
    sysrc linux_enable="YES"
    sysrc linux_mounts_enable="YES"
    if ! kldstat -q -m linux64; then
        kldload linux64 >/dev/null 2>&1 || true
    fi
    service linux start >/dev/null 2>&1 || echo ">>> Notice: Linux service will finish initializing after packages are installed."
}

init_pkg() {
    echo "=== 3. Initializing and Updating Package Repositories ==="
    env ASSUME_ALWAYS_YES=YES pkg bootstrap
    pkg update

    for old_nv in nvidia-driver nvidia-driver-580 nvidia-driver-550 nvidia-driver-470 \
                  nvidia-kmod nvidia-kmod-580 nvidia-kmod-550 nvidia-kmod-470; do
        if [ "$old_nv" != "$NVIDIA_PKG" ] && [ "$old_nv" != "$NVIDIA_KMOD_PKG" ] && pkg info -e "$old_nv" >/dev/null 2>&1; then
            echo ">>> Removing conflicting NVIDIA package: $old_nv"
            pkg delete -y "$old_nv" || true
        fi
    done
}

configure_cpu_microcode() {
    echo "=== 4. CPU Configuration (Microcode, Thermal Sensors & SMART) ==="
    install_available_pkgs cpu-microcode smartmontools
    sysrc smartd_enable="YES"
    [ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf

    if sysctl hw.model | grep -iq "intel"; then
        sysrc -f /boot/loader.conf coretemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
        kldload coretemp >/dev/null 2>&1 || true
    elif sysctl hw.model | grep -iq "amd"; then
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
        kldload amdtemp >/dev/null 2>&1 || true
    fi
}

install_packages() {
    echo "=== 5. Installing Desktop, NeXTSTEP, GPU, Audio & Application Packages ==="
    # Base utilities & Linuxulator
    install_available_pkgs \
        doas unzip libzip wget git htop btop fastfetch python3 \
        seatd dbus avahi nss_mdns signal-cli linux_base-rl9 ImageMagick7 \
        xdg-user-dirs

    # Xorg, SDDM & NVIDIA GPU
    install_available_pkgs \
        xorg sddm "$NVIDIA_PKG" "$NVIDIA_KMOD_PKG" "$NVIDIA_LINUX_PKG" nvidia-settings

    # Sound & Multimedia Codecs (from v1.28)
    install_available_pkgs \
        pulseaudio pipewire wireplumber freedesktop-sound-theme \
        ffmpeg libva-vdpau-driver libva-utils libdvdread libdvdnav \
        gstreamer1-plugins-all gstreamer1-libav libbluray

    # NeXTSTEP Environment (Window Maker + GNUstep + Dockapps)
    install_available_pkgs \
        windowmaker wmakerconf gnustep gnustep-app gworkspace \
        systempreferences affiche wmsystemtray wmnd wmcpuload wmmemload \
        wmclock wmix wmweather+ xterm

    # Desktop Applications, Themes & Fonts
    install_available_pkgs \
        firefox thunderbird libreoffice fr-libreoffice vlc kdenlive gimp mpv \
        gtkchtheme lxappearance qt5ct adwaita-icon-theme papirus-icon-theme \
        twemoji-color-font-ttf noto-emoji cantarell-fonts droid-fonts-ttf \
        inconsolata-ttf roboto-fonts-ttf ubuntu-font
}

configure_peripherals() {
    echo "=== 6. Configuring Peripherals (CUPS, HPLIP, Devfs, USB Automount, Webcam) ==="
    install_available_pkgs \
        cups gutenprint cups-filters hplip system-config-printer \
        automount e2fsprogs fusefs-ntfs fusefs-ext2 fusefs-exfat fusefs-hfsfuse \
        webcamd v4l-utils

    sysrc cupsd_enable="YES"
    sysrc webcamd_enable="YES"

    for kmod in fusefs ext2fs; do
        if ! sysrc -n kld_list 2>/dev/null | grep -qw "$kmod"; then
            sysrc kld_list+="$kmod"
        fi
        kldstat -q -m "$kmod" 2>/dev/null || kldload "$kmod" 2>/dev/null || true
    done

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

    printf "%s\n" \
        "USERUMOUNT=YES" \
        "ATIME=NO" \
        "REMOVEDIRS=YES" \
        "USER=$TARGET_USER" \
        'FM="openapp GWorkspace"' > /usr/local/etc/automount.conf

    if [ -f /etc/nsswitch.conf ]; then
        if grep -q "^hosts:" /etc/nsswitch.conf && ! grep -q "^hosts:.*mdns" /etc/nsswitch.conf; then
            sed -i '' 's/^hosts:.*/hosts: files mdns dns/' /etc/nsswitch.conf
        fi
    fi

    # Fix SSH PuTTY slow login caused by mDNS reverse lookup
    if [ -f /etc/ssh/sshd_config ] && ! grep -q "^UseDNS no" /etc/ssh/sshd_config; then
        echo "UseDNS no" >> /etc/ssh/sshd_config
        service sshd restart >/dev/null 2>&1 || true
    fi
}

configure_locale() {
    echo "=== 7. Syncing Locales & Keyboard (99-keyboard.conf priority) ==="
    SYS_KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "")
    echo ">>> Detected console keymap in /etc/rc.conf: ${SYS_KEYMAP:-unset}"

    XKB_LAYOUT="ch"
    XKB_VARIANT="fr"
    SYS_LANG="fr_CH.UTF-8"

    case "$SYS_KEYMAP" in
        ch-fr*|swissfrench*) XKB_LAYOUT="ch"; XKB_VARIANT="fr"; SYS_LANG="fr_CH.UTF-8" ;;
        ch*)                 XKB_LAYOUT="ch"; XKB_VARIANT="";   SYS_LANG="de_CH.UTF-8" ;;
        fr*)                 XKB_LAYOUT="fr"; XKB_VARIANT="";   SYS_LANG="fr_FR.UTF-8" ;;
        de*)                 XKB_LAYOUT="de"; XKB_VARIANT="";   SYS_LANG="de_DE.UTF-8" ;;
        it*)                 XKB_LAYOUT="it"; XKB_VARIANT="";   SYS_LANG="it_IT.UTF-8" ;;
        us*)                 XKB_LAYOUT="us"; XKB_VARIANT="";   SYS_LANG="en_US.UTF-8" ;;
    esac

    sysrc sddm_lang="$SYS_LANG"

    if ! grep -q "^desktop|" /etc/login.conf; then
        cat >> /etc/login.conf <<EOF

desktop|Desktop Users Accounts:\\
	:charset=UTF-8:\\
	:lang=${SYS_LANG}:\\
	:tc=default:
EOF
    else
        sed -i '' "s/:lang=.*:/:lang=${SYS_LANG}:/" /etc/login.conf
    fi
    cap_mkdb /etc/login.conf
    grep -q "defaultclass=desktop" /etc/adduser.conf 2>/dev/null || echo 'defaultclass=desktop' >> /etc/adduser.conf

    pw usermod "$TARGET_USER" -L desktop
    pw usermod root -L desktop

    # Utilise 99-keyboard.conf pour surcharger 40-libinput.conf (méthode v1.28)
    mkdir -p /usr/local/etc/X11/xorg.conf.d
    rm -f /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf \
          /usr/local/etc/X11/xorg.conf.d/10-keyboard.conf \
          /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf

    cat > /usr/local/etc/X11/xorg.conf.d/99-keyboard.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    Option "XkbVariant" "$XKB_VARIANT"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
}

configure_gpu() {
    echo "=== 8. Configuring NVIDIA GPU & PCI BusID (P620 Workstation Support) ==="
    CURRENT_KLD=$(sysrc -n kld_list 2>/dev/null || echo "")
    case "$CURRENT_KLD" in
        *nvidia-modeset*) ;;
        *) sysrc kld_list+="nvidia-modeset" ;;
    esac
    kldstat -q -m nvidia-modeset 2>/dev/null || kldload nvidia-modeset 2>/dev/null || true

    # Détection exacte du BusID PCI (méthode v1.28 indispensable sur P620)
    NVIDIA_BUS=$(pciconf -lv | awk '/^vgapci[0-9]+@pci/ { split($1, a, ":"); bus=a[2]":"a[3]":"a[4] } /vendor.*NVIDIA/ && bus != "" { print "PCI:"bus; exit }')
    mkdir -p /usr/local/etc/X11/xorg.conf.d

    if [ -n "$NVIDIA_BUS" ]; then
        echo ">>> Writing Xorg configuration for NVIDIA GPU at $NVIDIA_BUS..."
        cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf <<EOF
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
    VendorName "NVIDIA Corporation"
    BusID      "$NVIDIA_BUS"
EndSection
EOF
    else
        cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf <<EOF
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
    VendorName "NVIDIA Corporation"
EndSection
EOF
    fi
}

configure_splash() {
    echo "=== 9. Configuring Boot & Shutdown Splash Screen (1920x1200) ==="
    mkdir -p /boot/images
    if wget -qO "$TMP_SPLASH" "$SPLASH_URL"; then
        magick "$TMP_SPLASH" -resize '1920x1200!' /boot/images/splash.png
        sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
        sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
        sysrc splash_changer_enable="YES"
        rm -f "$TMP_SPLASH"
        echo ">>> Custom splash screen (1920x1200) configured successfully."
    else
        echo ">>> Warning: Failed to download $SPLASH_URL."
    fi
}

configure_sddm() {
    echo "=== 10. Configuring SDDM (Maldives Theme, Xsetup & NeXTSTEP Session) ==="
    mkdir -p /usr/local/etc /usr/local/etc/sddm.conf.d
    SDDM_CONF="/usr/local/etc/sddm.conf"

    if ! grep -q "^\[Theme\]" "$SDDM_CONF" 2>/dev/null; then
        printf "\n[Theme]\nCurrent=maldives\n" >> "$SDDM_CONF"
    else
        sed -i '' "s/^Current=.*/Current=maldives/" "$SDDM_CONF"
    fi
    printf "%s\n" "[Theme]" "Current=maldives" > /usr/local/etc/sddm.conf.d/10-theme.conf

    if pw usershow sddm >/dev/null 2>&1 && pw groupshow video >/dev/null 2>&1; then
        pw groupmod video -m sddm
    fi

    XSETUP="/usr/local/share/sddm/scripts/Xsetup"
    mkdir -p /usr/local/share/sddm/scripts
    if [ -n "$XKB_VARIANT" ]; then
        KBD_CMD="/usr/local/bin/setxkbmap $XKB_LAYOUT $XKB_VARIANT"
    else
        KBD_CMD="/usr/local/bin/setxkbmap $XKB_LAYOUT"
    fi
    cat > "$XSETUP" <<EOF
#!/bin/sh
# Xsetup - run as root before the login dialog appears
$KBD_CMD
EOF
    chmod 755 "$XSETUP"

    mkdir -p /usr/local/share/xsessions
    cat > /usr/local/share/xsessions/nextstep.desktop << 'EOF'
[Desktop Entry]
Encoding=UTF-8
Name=NeXTSTEP (Window Maker + GNUstep)
Comment=NeXTSTEP Desktop Environment on FreeBSD 15.1
Exec=/usr/local/bin/start-nextstep-session
Type=Application
EOF

    cat > /usr/local/bin/start-nextstep-session << 'EOF'
#!/bin/sh
if [ -x "$HOME/.xinitrc" ]; then
    exec "$HOME/.xinitrc"
fi
if [ -f /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then
    . /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh
fi
gdnc &
gpbs &
exec wmaker
EOF
    chmod 755 /usr/local/bin/start-nextstep-session
}

configure_doas_and_groups() {
    echo "=== 11. Configuring Permissions (doas & User Groups) ==="
    DOAS_CONF="/usr/local/etc/doas.conf"
    touch "$DOAS_CONF"
    grep -q "^permit persist :wheel" "$DOAS_CONF" || echo "permit persist :wheel" >> "$DOAS_CONF"
    grep -q "permit persist $TARGET_USER" "$DOAS_CONF" || echo "permit persist $TARGET_USER as root" >> "$DOAS_CONF"
    chmod 0400 "$DOAS_CONF"

    for group in wheel operator video seatd cups webcamd; do
        if pw groupshow "$group" >/dev/null 2>&1; then
            if ! pw groupshow "$group" | grep -qiw "$TARGET_USER"; then
                pw groupmod "$group" -m "$TARGET_USER"
            fi
        fi
    done

    if [ -x /usr/local/GNUstep/Applications/WPrefs.app/WPrefs ]; then
        ln -sf /usr/local/GNUstep/Applications/WPrefs.app/WPrefs /usr/local/bin/WPrefs
    fi
}

configure_nextstep_user() {
    echo "=== 12. Configuring NeXTSTEP Environment & Autostart for $TARGET_USER ==="
    if [ ! -d "$USER_HOME/GNUstep/Defaults" ]; then
        su - "$TARGET_USER" -c "wmaker.inst --batch" || true
    fi

    mkdir -p "$USER_HOME/.config/gtk-3.0" \
             "$USER_HOME/.config/qt5ct" \
             "$USER_HOME/GNUstep/Defaults" \
             "$USER_HOME/GNUstep/Library/WindowMaker"

    USER_PROFILE="$USER_HOME/.profile"
    touch "$USER_PROFILE"
    if ! grep -q "LANG=" "$USER_PROFILE" 2>/dev/null; then
        echo "export LANG=$SYS_LANG" >> "$USER_PROFILE"
        echo "export LC_ALL=$SYS_LANG" >> "$USER_PROFILE"
    fi

    GNUSTEP_SH="/usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh"
    if [ -f "$GNUSTEP_SH" ] && ! grep -Fq "$GNUSTEP_SH" "$USER_PROFILE"; then
        printf '\n# GNUstep Environment\nif [ -f %s ]; then\n    . %s\nfi\n' "$GNUSTEP_SH" "$GNUSTEP_SH" >> "$USER_PROFILE"
    fi

    GNUSTEP_CSH="/usr/local/GNUstep/System/Library/Makefiles/GNUstep.csh"
    touch "$USER_HOME/.cshrc"
    if [ -f "$GNUSTEP_CSH" ] && ! grep -Fq "$GNUSTEP_CSH" "$USER_HOME/.cshrc"; then
        printf '\n# GNUstep Environment\nif ( -f %s ) then\n    source %s\nendif\n' "$GNUSTEP_CSH" "$GNUSTEP_CSH" >> "$USER_HOME/.cshrc"
    fi

    # Script autostart de Window Maker : source GNUstep.sh, démarre gdnc/gpbs et attend 2s avant GWorkspace
    cat > "$USER_HOME/GNUstep/Library/WindowMaker/autostart" << 'EOF'
#!/bin/sh
if [ -f /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then
    . /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh
fi

pgrep -x gdnc >/dev/null 2>&1 || gdnc &
pgrep -x gpbs >/dev/null 2>&1 || gpbs &

command -v wmsystemtray >/dev/null 2>&1 && wmsystemtray &
command -v wmcpuload    >/dev/null 2>&1 && wmcpuload &
command -v wmmemload    >/dev/null 2>&1 && wmmemload &
command -v wmnd         >/dev/null 2>&1 && wmnd &
command -v wmclock      >/dev/null 2>&1 && wmclock &
command -v wmix         >/dev/null 2>&1 && wmix &
command -v wmweather+   >/dev/null 2>&1 && wmweather+ &

# Délai de 2 secondes pour laisser Window Maker et gdnc s'initialiser avant d'ouvrir GWorkspace (File Viewer)
(sleep 2 && openapp GWorkspace) &
EOF
    chmod 755 "$USER_HOME/GNUstep/Library/WindowMaker/autostart"

    cat > "$USER_HOME/.xinitrc" << 'EOF'
#!/bin/sh
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
if [ -f /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then
    . /usr/local/GNUstep/System/Library/Makefiles/GNUstep.sh
fi
pgrep -x gdnc >/dev/null 2>&1 || gdnc &
pgrep -x gpbs >/dev/null 2>&1 || gpbs &
export QT_QPA_PLATFORMTHEME=qt5ct
exec wmaker
EOF
    chmod 755 "$USER_HOME/.xinitrc"

    cat > "$USER_HOME/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Papirus
gtk-application-prefer-dark-theme=0
gtk-font-name=Sans 10
EOF

    cat > "$USER_HOME/.config/gtk-3.0/gtk.css" << 'EOF'
window, dialog, .background {
    background-color: #aeaaae;
    color: #000000;
}
headerbar, .titlebar {
    background-color: #8e8a8e;
    color: #ffffff;
}
EOF

    cat > "$USER_HOME/GNUstep/Defaults/WMRootMenu" << 'EOF'
(
  "NeXTSTEP Menu",
  ("Applications",
    ("Workspace Manager (File Viewer)", EXEC, "openapp GWorkspace"),
    ("System Preferences", EXEC, "openapp SystemPreferences"),
    ("Terminal (GNUstep)", EXEC, "openapp Terminal"),
    ("Terminal (XTerm)", EXEC, "xterm -bg black -fg white"),
    ("Mail (GNUMail)", EXEC, "openapp GNUMail"),
    ("Sticky Notes (Affiche)", EXEC, "openapp Affiche")
  ),
  ("Dockapps (Widgets)",
    ("Clock", EXEC, "wmclock"),
    ("Audio Mixer", EXEC, "wmix"),
    ("Weather", EXEC, "wmweather+"),
    ("Network Monitor", EXEC, "wmnd"),
    ("CPU Monitor", EXEC, "wmcpuload"),
    ("Memory Monitor", EXEC, "wmmemload"),
    ("System Tray", EXEC, "wmsystemtray")
  ),
  ("Office & Internet",
    ("Firefox Web Browser", EXEC, "firefox"),
    ("Thunderbird Mail", EXEC, "thunderbird"),
    ("LibreOffice Suite", EXEC, "libreoffice")
  ),
  ("Multimedia & Creation",
    ("VLC Media Player", EXEC, "vlc"),
    ("MPV Media Player", EXEC, "mpv --player-operation-mode=pseudo-gui"),
    ("Kdenlive (Video Editor)", EXEC, "kdenlive"),
    ("GIMP Image Editor", EXEC, "gimp")
  ),
  ("Printers & Hardware",
    ("Printer Manager (GUI)", EXEC, "system-config-printer"),
    ("Printer Manager (CUPS Web)", EXEC, "firefox http://localhost:631"),
    ("HP Device Manager", EXEC, "hp-toolbox"),
    ("NVIDIA Settings", EXEC, "nvidia-settings")
  ),
  ("Appearance & Settings",
    ("Window Maker Preferences (WPrefs)", EXEC, "/usr/local/GNUstep/Applications/WPrefs.app/WPrefs"),
    ("GTK3 Appearance", EXEC, "lxappearance"),
    ("GTK2 Appearance", EXEC, "gtk-chtheme"),
    ("Qt5 Appearance", EXEC, "qt5ct")
  ),
  ("System Tools",
    ("System Monitor (btop)", EXEC, "xterm -e btop"),
    ("System Monitor (htop)", EXEC, "xterm -e htop"),
    ("System Info (fastfetch)", EXEC, "xterm -hold -e fastfetch")
  ),
  ("Session",
    ("Restart Window Maker", RESTART),
    ("Exit Session", EXIT)
  )
)
EOF

    chown -R "$TARGET_USER:$TARGET_USER" \
        "$USER_HOME/.profile" \
        "$USER_HOME/.cshrc" \
        "$USER_HOME/.xinitrc" \
        "$USER_HOME/.config" \
        "$USER_HOME/GNUstep"
}

configure_services() {
    echo "=== 13. Enabling and Starting System Services ==="
    sysrc dbus_enable="YES"
    sysrc avahi_daemon_enable="YES"
    sysrc avahi_dnsconfd_enable="YES"
    sysrc seatd_enable="YES"
    sysrc sddm_enable="YES"

    for svc in devfs devd linux smartd seatd webcamd dbus avahi-daemon avahi-dnsconfd cupsd; do
        service "$svc" restart >/dev/null 2>&1 || service "$svc" start >/dev/null 2>&1 || true
    done
}

main() {
    check_root
    parse_args "$@"
    detect_user
    interactive_config

    echo "=== Starting FreeBSD 15.1 NeXTSTEP Workstation Deployment ==="
    configure_tuning
    enable_linux_compat
    init_pkg
    configure_cpu_microcode
    install_packages
    configure_peripherals
    configure_locale
    configure_gpu
    configure_splash
    configure_sddm
    configure_doas_and_groups
    configure_nextstep_user
    configure_services

    echo "================================================================="
    echo "Deployment completed successfully for user: $TARGET_USER (UID $TARGET_UID)"
    echo "- Safeguard: 'pkg rquery' verified all packages before installation."
    echo "- GPU: $NVIDIA_PKG + $NVIDIA_KMOD_PKG with PCI BusID configured."
    echo "- Splash: 1920x1200 v2-blue.png set for Boot and Shutdown."
    echo "- Keyboard & Locale: 99-keyboard.conf ($XKB_LAYOUT $XKB_VARIANT) & $SYS_LANG."
    echo "- NeXTSTEP: GWorkspace & Dockapps set in WindowMaker/autostart."
    echo "Please run 'reboot' to apply all kernel and session changes."
    echo "================================================================="
}

main "$@"