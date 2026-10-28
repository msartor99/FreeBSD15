#!/bin/sh

# ==============================================================================
# File    : install-workstation-v1.28.sh
# Version : 1.28
# Date    : October 2026
# Role    : Post-installation script for FreeBSD workstation (amd64)
# Notes   : Fixed SDDM keyboard layout & flag using 99-keyboard.conf priority,
#           console keymap, sddm_lang, and executable Xsetup.
# ==============================================================================

set -e # Exit on unhandled error

NASA_URL="https://raw.githubusercontent.com/msartor99/FreeBSD14/main/nasa2560login.jpg"
NASA_WALLPAPER="/tmp/nasa2560login.jpg"

TMP_DIALOG=$(mktemp -t bsddialog)
trap 'rm -f $TMP_DIALOG' EXIT INT TERM HUP

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# Safeguard function: verifies each package exists in the repo before installing
install_available_pkgs() {
    VALID_PKGS=""
    MISSING_PKGS=""
    for pkg in "$@"; do
        if pkg rquery "%n" "$pkg" >/dev/null 2>&1 || pkg info -e "$pkg" >/dev/null 2>&1; then
            VALID_PKGS="$VALID_PKGS $pkg"
        else
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo ">>> WARNING: The following packages are currently unavailable in the FreeBSD repository and will be skipped:$MISSING_PKGS"
    fi

    if [ -n "$VALID_PKGS" ]; then
        # shellcheck disable=SC2086
        pkg install -y $VALID_PKGS
    fi
}

interactive_config() {
    if ! bsddialog --title "DISCLAIMER - FreeBSD Installation" \
        --yesno "This script will configure the desktop environment, GPU drivers, system tuning, peripherals, and applications.\n\nAre you sure you want to continue?" 10 70; then
        clear; echo "Canceled by user."; exit 0
    fi

    if ! bsddialog --title "User Configuration" \
        --inputbox "Enter the main user's name:" 10 60 "administrateur" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    TARGET_USER=$(cat "$TMP_DIALOG")
    [ -z "$TARGET_USER" ] && { clear; echo "Error: username cannot be empty."; exit 1; }

    if ! bsddialog --title "System Language" \
        --menu "Choose the environment language:" 15 50 5 \
        "fr" "French" "en" "English" "de" "German" "it" "Italian" "pt" "Portuguese" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    LANG_CHOICE=$(cat "$TMP_DIALOG")

    if ! bsddialog --title "Keyboard Layout" \
        --menu "Choose the keyboard layout:" 15 50 6 \
        "ch" "Swiss French" "fr" "French (AZERTY)" "us" "English (US QWERTY)" "de" "German (QWERTZ)" "it" "Italian" "pt" "Portuguese" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    KBD_CHOICE=$(cat "$TMP_DIALOG")

    if ! bsddialog --title "Desktop Environment" \
        --menu "Choose your desktop environment:" 15 55 5 \
        "xfce4" "XFCE 4" "plasma6" "KDE Plasma 6" "gnome" "GNOME" "mate" "MATE" "cinnamon" "Cinnamon" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    DE_CHOICE=$(cat "$TMP_DIALOG")
    
    case "$DE_CHOICE" in
        xfce4) DE_PKGS="xfce" ;;
        plasma6) DE_PKGS="plasma6-plasma kde" ;; 
        gnome) DE_PKGS="gnome" ;;
        mate) DE_PKGS="mate" ;;
        cinnamon) DE_PKGS="cinnamon" ;;
    esac

    if ! bsddialog --title "Additional Applications & Aesthetics" \
        --checklist "Select applications and options to install (leave themes unchecked for default FreeBSD look):" 21 75 11 \
        "firefox" "Firefox Web Browser" on \
        "chromium" "Chromium Web Browser (if available in repo)" off \
        "thunderbird" "Thunderbird Mail Client" off \
        "vlc" "VLC Video Player" on \
        "gimp" "GIMP Image Editor" off \
        "libreoffice" "LibreOffice Suite" off \
        "themes" "Emoji Fonts and Icon Themes" on \
        "nasa_theme" "NASA SDDM Theme & Boot Splash" off \
        "kamila_splash" "Kamila.is Boot Splash & Maldives SDDM Theme" off \
        "samba" "Samba Server (File Sharing)" off \
        "virtualbox" "VirtualBox (Virtualization)" off 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    
    APP_CHOICES=$(tr -d '"' < "$TMP_DIALOG")
    APP_PKGS=""
    INSTALL_SAMBA=0
    INSTALL_VBOX=0
    INSTALL_NASA=0
    INSTALL_KAMILA=0
    NEED_IMAGEMAGICK=0
    
    for app in $APP_CHOICES; do
        case "$app" in
            firefox) APP_PKGS="$APP_PKGS firefox" ;;
            chromium) APP_PKGS="$APP_PKGS chromium" ;;
            thunderbird) APP_PKGS="$APP_PKGS thunderbird" ;;
            vlc) APP_PKGS="$APP_PKGS vlc" ;;
            gimp) APP_PKGS="$APP_PKGS gimp" ;;
            libreoffice) APP_PKGS="$APP_PKGS libreoffice" ;;
            themes) APP_PKGS="$APP_PKGS twemoji-color-font-ttf noto-emoji ibus-uniemoji papirus-icon-theme cursor-neutral-white-theme qogir-icon-themes win98se-icon-theme" ;;
            nasa_theme) NEED_IMAGEMAGICK=1; INSTALL_NASA=1 ;;
            kamila_splash) NEED_IMAGEMAGICK=1; INSTALL_KAMILA=1 ;;
            samba) APP_PKGS="$APP_PKGS samba420"; INSTALL_SAMBA=1 ;;
            virtualbox) APP_PKGS="$APP_PKGS virtualbox-ose"; INSTALL_VBOX=1 ;;
        esac
    done

    if [ "$NEED_IMAGEMAGICK" -eq 1 ]; then
        APP_PKGS="$APP_PKGS ImageMagick7"
    fi

    if bsddialog --title "Network Configuration" \
        --yesno "Do you want to check or configure your network interfaces via bsdconfig?" 10 65; then
        clear; bsdconfig networking
    fi

    if ! bsddialog --title "Graphics Card" \
        --menu "Select your GPU manufacturer:" 15 50 3 "intel" "Intel" "amd" "AMD" "nvidia" "NVIDIA" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    GPU_CHOICE=$(cat "$TMP_DIALOG")

    GPU_PKGS=""
    HYBRID_INTEL=0
    
    if [ "$GPU_CHOICE" = "intel" ] || [ "$GPU_CHOICE" = "amd" ]; then
        if bsddialog --title "Wayland Support" \
            --yesno "Do you want to install and enable Wayland components for your $GPU_CHOICE GPU?\n\n(Recommended for Plasma 6 and GNOME)" 10 65; then
            GPU_PKGS="drm-kmod wayland wayland-protocols xwayland"
        else
            GPU_PKGS="drm-kmod"
        fi
    elif [ "$GPU_CHOICE" = "nvidia" ]; then
        if ! bsddialog --title "NVIDIA Drivers" \
            --menu "Select driver version:" 15 60 4 "latest" "Latest (Default)" "580" "Branch 580" "550" "Branch 550" "470" "Branch 470 (Legacy)" 2> "$TMP_DIALOG"; then
            clear; exit 0
        fi
        NVIDIA_VERSION=$(cat "$TMP_DIALOG")
        case "$NVIDIA_VERSION" in
            latest) GPU_PKGS="nvidia-driver nvidia-kmod nvidia-settings linux_base-rl9 linux-nvidia-libs" ;;
            *) GPU_PKGS="nvidia-driver-${NVIDIA_VERSION} nvidia-kmod-${NVIDIA_VERSION} nvidia-settings linux_base-rl9 linux-nvidia-libs-${NVIDIA_VERSION}" ;;
        esac

        if bsddialog --title "Hybrid Configuration (NVIDIA + Intel)" \
            --yesno "Does your PC also have an Intel integrated GPU (e.g., hybrid setup like the HP Z2 mini G5)?" 10 70; then
            HYBRID_INTEL=1
            
            if bsddialog --title "Wayland Support" \
                --yesno "Do you want to use Wayland as the display server?\n\nWARNING: On a hybrid setup, Wayland is currently incompatible with NVIDIA on FreeBSD. If you choose YES, the NVIDIA card will be disabled and only the Intel chip will be configured with Wayland." 12 70; then
                GPU_CHOICE="intel"
                GPU_PKGS="drm-kmod wayland wayland-protocols xwayland"
            else
                GPU_PKGS="$GPU_PKGS drm-kmod"
            fi
        fi
    fi

    if ! pw usershow "$TARGET_USER" >/dev/null 2>&1; then
        bsddialog --title "User Creation" \
            --msgbox "User not found. 'adduser' will be launched for '$TARGET_USER'." 10 60
        clear; adduser
        ! pw usershow "$TARGET_USER" >/dev/null 2>&1 && { echo "Fatal error: User not created."; exit 1; }
    fi
    clear
}

configure_tuning() {
    echo ">>> System tuning (sysctl and loader.conf)..."
    sysrc -f /boot/loader.conf boot_mute="YES"
    sysrc -f /boot/loader.conf autoboot_delay="3"
    sysrc rc_startmsgs="NO"
    
    if ! grep -q "> /dev/null" /etc/rc; then
        sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    fi

    sysrc -f /boot/loader.conf tmpfs_load="YES"
    sysrc -f /boot/loader.conf aio_load="YES"
    
    SYSCTL_CONF="/etc/sysctl.conf"
    grep -q "kern.sched.preempt_thresh" "$SYSCTL_CONF" || echo "kern.sched.preempt_thresh=224" >> "$SYSCTL_CONF"
    grep -q "kern.ipc.shm_allow_removed" "$SYSCTL_CONF" || echo "kern.ipc.shm_allow_removed=1" >> "$SYSCTL_CONF"
    grep -q "net.local.stream.recvspace" "$SYSCTL_CONF" || echo "net.local.stream.recvspace=65536" >> "$SYSCTL_CONF"
    grep -q "net.local.stream.sendspace" "$SYSCTL_CONF" || echo "net.local.stream.sendspace=65536" >> "$SYSCTL_CONF"
}

configure_cpu_microcode() {
    echo ">>> CPU Configuration (Microcode and sensors)..."
    install_available_pkgs cpu-microcode smartmontools
    sysrc smartd_enable="YES"
    [ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf

    if sysctl hw.model | grep -iq "intel"; then
        sysrc -f /boot/loader.conf coretemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    elif sysctl hw.model | grep -iq "amd"; then
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    fi
}

enable_linux_compat() {
    echo ">>> Enabling Linux compatibility in kernel..."
    sysrc -x linux64_enable >/dev/null 2>&1 || true
    sysrc -v linux_enable="YES"
    sysrc -v linux_mounts_enable="YES"
    service linux start || echo "Warning: Linux kernel module could not be loaded right now (will load on reboot)."
}

init_pkg() {
    env ASSUME_ALWAYS_YES=YES pkg bootstrap
    pkg update
}

install_packages() {
    echo ">>> Installing packages..."
    # shellcheck disable=SC2086
    install_available_pkgs \
        doas unzip libzip wget git htop fastfetch python3 bashtop \
        seatd dbus avahi signal-cli \
        xorg sddm \
        pulseaudio pipewire wireplumber freedesktop-sound-theme \
        $DE_PKGS $GPU_PKGS $APP_PKGS \
        ffmpeg libva-vdpau-driver libva-utils libdvdread libdvdnav \
        eom remmina xdg-user-dirs octopkg mpv \
        gstreamer1-plugins-all gstreamer1-libav libbluray \
        cantarell-fonts droid-fonts-ttf inconsolata-ttf noto noto-emoji roboto-fonts-ttf ubuntu-font
}

configure_peripherals() {
    echo ">>> Configuring peripherals (CUPS, Devfs, USB, Webcam)..."
    install_available_pkgs cups gutenprint cups-filters hplip system-config-printer \
                           fusefs-ntfs fusefs-ext2 fusefs-hfsfuse webcamd v4l-utils
                   
    sysrc cupsd_enable="YES"
    sysrc webcamd_enable="YES"
    
    sysrc kld_list+="fusefs ext2fs"
    sysrc -f /boot/loader.conf cuse_load="YES"
    grep -q "vfs.usermount=1" /etc/sysctl.conf || echo "vfs.usermount=1" >> /etc/sysctl.conf

    if ! grep -q "\[localrules=5\]" /etc/devfs.rules 2>/dev/null; then
        cat >>/etc/devfs.rules <<EOF

[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'uscanner*' mode 0660 group operator
add path 'xpt*' mode 660 group operator
add path 'pass*' mode 660 group operator
add path 'md*' mode 0660 group operator
add path 'msdosfs/*' mode 0660 group operator
add path 'ext2fs/*' mode 0660 group operator
add path 'ntfs/*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'video*' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF
    fi
    sysrc devfs_system_ruleset="localrules"
}

configure_locale() {
    echo ">>> Configuring locales and keyboard..."
    
    case "$LANG_CHOICE" in
        fr) SYS_LANG="fr_FR.UTF-8" ;;
        en) SYS_LANG="en_US.UTF-8" ;;
        de) SYS_LANG="de_DE.UTF-8" ;;
        it) SYS_LANG="it_IT.UTF-8" ;;
        pt) SYS_LANG="pt_PT.UTF-8" ;;
    esac

    KBD_VARIANT=""
    case "$KBD_CHOICE" in
        ch)
            X_LAYOUT="ch"
            KBD_VARIANT="fr"
            CONSOLE_KEYMAP="swissfrench.kbd"
            [ "$LANG_CHOICE" = "fr" ] && SYS_LANG="fr_CH.UTF-8"
            ;;
        fr) X_LAYOUT="fr"; CONSOLE_KEYMAP="fr.kbd" ;;
        us) X_LAYOUT="us"; CONSOLE_KEYMAP="us.kbd" ;;
        de) X_LAYOUT="de"; CONSOLE_KEYMAP="de.kbd" ;;
        it) X_LAYOUT="it"; CONSOLE_KEYMAP="it.kbd" ;;
        pt) X_LAYOUT="pt"; CONSOLE_KEYMAP="pt.kbd" ;;
    esac

    sysrc keymap="$CONSOLE_KEYMAP"
    sysrc sddm_lang="$SYS_LANG"

    if ! grep -q "^desktop|" /etc/login.conf; then
        cat >> /etc/login.conf <<EOF

desktop|Desktop Users Accounts:\
     :charset=UTF-8:\
     :lang=${SYS_LANG}:\
     :tc=default:
EOF
    else
        sed -i '' "s/:lang=.*:/:lang=${SYS_LANG}:/" /etc/login.conf
    fi
    cap_mkdb /etc/login.conf
    grep -q "defaultclass=desktop" /etc/adduser.conf || echo 'defaultclass=desktop' >> /etc/adduser.conf

    USER_PROFILE="/home/$TARGET_USER/.profile"
    if ! grep -q "LANG=" "$USER_PROFILE" 2>/dev/null; then
        echo "export LANG=$SYS_LANG" >> "$USER_PROFILE"
        echo "export LC_ALL=$SYS_LANG" >> "$USER_PROFILE"
        chown "$TARGET_USER:$TARGET_USER" "$USER_PROFILE"
    fi

    # Remove old 20-keyboards.conf and use 99-keyboard.conf so it overrides 40-libinput.conf
    mkdir -p /usr/local/etc/X11/xorg.conf.d
    rm -f /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
    cat > /usr/local/etc/X11/xorg.conf.d/99-keyboard.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$X_LAYOUT"
    Option "XkbVariant" "$KBD_VARIANT"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
}

configure_desktop_env() {
    grep -q "^proc" /etc/fstab || echo "proc /proc procfs rw 0 0" >> /etc/fstab
    grep -q "^fdesc" /etc/fstab || echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab
}

download_nasa_wallpaper() {
    if [ ! -f "$NASA_WALLPAPER" ]; then
        echo ">>> Downloading NASA wallpaper from GitHub (msartor99)..."
        wget -qO "$NASA_WALLPAPER" "$NASA_URL" || rm -f "$NASA_WALLPAPER"
    fi
}

configure_sddm() {
    mkdir -p /usr/local/etc
    SDDM_CONF="/usr/local/etc/sddm.conf"
    TARGET_THEME=""

    if [ "$INSTALL_NASA" -eq 1 ]; then
        echo ">>> Creating and configuring SDDM NASA Theme (based on Maldives)..."
        download_nasa_wallpaper

        THEMES_DIR="/usr/local/share/sddm/themes"
        MALDIVES_DIR="${THEMES_DIR}/maldives"
        NASA_DIR="${THEMES_DIR}/nasa"

        if [ -d "$MALDIVES_DIR" ]; then
            mkdir -p "$NASA_DIR"
            cp -R "${MALDIVES_DIR}/"* "$NASA_DIR/"

            if [ -f "$NASA_WALLPAPER" ]; then
                cp "$NASA_WALLPAPER" "${NASA_DIR}/nasa2560login.jpg"
                if [ -f "${NASA_DIR}/theme.conf" ]; then
                    sed -i '' 's|^background=.*|background=nasa2560login.jpg|' "${NASA_DIR}/theme.conf"
                else
                    cat > "${NASA_DIR}/theme.conf" <<EOF
[General]
background=nasa2560login.jpg
EOF
                fi
            else
                echo "Warning: Failed to download $NASA_URL. Keeping default maldives background."
            fi

            if [ -f "${NASA_DIR}/metadata.desktop" ]; then
                sed -i '' 's|^Name=.*|Name=NASA|' "${NASA_DIR}/metadata.desktop"
                sed -i '' 's|^Description=.*|Description=NASA Theme based on Maldives|' "${NASA_DIR}/metadata.desktop"
            fi
            TARGET_THEME="nasa"
        else
            echo "Warning: maldives theme directory not found."
        fi
    elif [ "$INSTALL_KAMILA" -eq 1 ]; then
        echo ">>> Configuring SDDM (Maldives theme)..."
        TARGET_THEME="maldives"
    else
        echo ">>> Preserving default SDDM theme configuration..."
    fi
    
    if [ -n "$TARGET_THEME" ]; then
        if ! grep -q "^\[Theme\]" "$SDDM_CONF" 2>/dev/null; then
            printf "\n[Theme]\nCurrent=%s\n" "$TARGET_THEME" >> "$SDDM_CONF"
        else
            sed -i '' "s/^Current=.*/Current=${TARGET_THEME}/" "$SDDM_CONF"
        fi
    fi

    XSETUP="/usr/local/share/sddm/scripts/Xsetup"
    mkdir -p /usr/local/share/sddm/scripts
    if [ -n "$KBD_VARIANT" ]; then
        KBD_CMD="setxkbmap $X_LAYOUT $KBD_VARIANT"
    else
        KBD_CMD="setxkbmap $X_LAYOUT"
    fi
    cat > "$XSETUP" <<EOF
#!/bin/sh
# Xsetup - run as root before the login dialog appears
$KBD_CMD
EOF
    chmod +x "$XSETUP"
}

configure_gpu() {
    echo ">>> Configuring graphics drivers loading..."
    CURRENT_KLD=$(sysrc -n kld_list 2>/dev/null || echo "")
    case "$GPU_CHOICE" in
        intel) 
            case "$CURRENT_KLD" in *i915kms*) ;; *) sysrc -v kld_list+="i915kms" ;; esac 
            ;;
        amd)   
            case "$CURRENT_KLD" in *amdgpu*) ;; *) sysrc -v kld_list+="amdgpu" ;; esac 
            ;;
        nvidia)
            if [ "$HYBRID_INTEL" = "1" ]; then
                case "$CURRENT_KLD" in *i915kms*) ;; *) sysrc -v kld_list+="i915kms" ;; esac
            else
                # Detect PCI BusID for dedicated NVIDIA cards (vital for multi-bus workstations like P620)
                NVIDIA_BUS=$(pciconf -lv | awk '/^vgapci[0-9]+@pci/ { split($1, a, ":"); bus=a[2]":"a[3]":"a[4] } /vendor.*NVIDIA/ && bus != "" { print "PCI:"bus; exit }')
                if [ -n "$NVIDIA_BUS" ]; then
                    echo ">>> Writing Xorg configuration for NVIDIA GPU at $NVIDIA_BUS..."
                    mkdir -p /usr/local/etc/X11/xorg.conf.d
                    cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf <<EOF
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
    VendorName "NVIDIA Corporation"
    BusID      "$NVIDIA_BUS"
EndSection
EOF
                fi
            fi
            case "$CURRENT_KLD" in *nvidia-modeset*) ;; *) sysrc -v kld_list+="nvidia-modeset" ;; esac 
            sysctl hw.snd.default_unit=1 || true
            ;;
    esac
}

configure_samba() {
    if [ "$INSTALL_SAMBA" -eq 1 ]; then
        echo ">>> Configuring Samba server..."
        mkdir -p /home/share
        chmod 777 /home/share
        
        if [ ! -f /usr/local/etc/smb4.conf ]; then
            cat >>/usr/local/etc/smb4.conf <<EOF
[global]
    unix charset = UTF-8
    workgroup = HOMELAB
    server string = FreeBSD
    interfaces = 127.0.0.0/8 192.168.22.0/24
    bind interfaces only = yes
    map to guest = bad user

[Share]
    path = /home/share
    writable = yes
    guest ok = yes
    guest only = yes
    force create mode = 777
    force directory mode = 777
EOF
        fi
        sysrc samba_server_enable="YES"
        service samba_server start || true
    fi
}

configure_virtualbox() {
    if [ "$INSTALL_VBOX" -eq 1 ]; then
        echo ">>> Configuring VirtualBox..."
        kldstat -q -m vboxdrv || kldload vboxdrv || true
        kldstat -q -m vboxnetflt || kldload vboxnetflt || true
        kldstat -q -m vboxnetadp || kldload vboxnetadp || true

        sysrc -f /boot/loader.conf vboxdrv_load="YES"
        sysrc -f /boot/loader.conf vboxnet_load="YES"
        sysrc vboxnet_enable="YES"

        if pw groupshow vboxusers >/dev/null 2>&1; then
            pw groupmod vboxusers -m root
            pw groupmod vboxusers -m "$TARGET_USER"
        fi

        grep -q "own.*vboxnetctl" /etc/devfs.conf || echo 'own     vboxnetctl root:vboxusers' >> /etc/devfs.conf
        grep -q "perm.*vboxnetctl" /etc/devfs.conf || echo 'perm    vboxnetctl 0660' >> /etc/devfs.conf
        
        service devfs restart || true
    fi
}

configure_services() {
    sysrc -v dbus_enable="YES"
    sysrc -v avahi_daemon_enable="YES"
    sysrc -v seatd_enable="YES"
    sysrc -v sddm_enable="YES"
}

configure_doas_and_groups() {
    DOAS_CONF="/usr/local/etc/doas.conf"
    if [ ! -f "$DOAS_CONF" ] || ! grep -q "^permit persist :wheel" "$DOAS_CONF"; then
        echo "permit persist :wheel" >> "$DOAS_CONF"
        chmod 0400 "$DOAS_CONF"
    fi

    for group in wheel operator video seatd cups; do
        if pw groupshow "$group" >/dev/null 2>&1; then
            if ! pw groupshow "$group" | grep -qiw "$TARGET_USER"; then
                pw groupmod "$group" -m "$TARGET_USER"
            fi
        fi
    done
}

configure_splash() {
    if [ "$INSTALL_NASA" -eq 1 ]; then
        echo ">>> Configuring NASA Boot Splash Screen..."
        download_nasa_wallpaper
        mkdir -p /boot/images

        if [ -f "$NASA_WALLPAPER" ]; then
            magick "$NASA_WALLPAPER" -resize 1920x1080 /boot/images/splash.png
            sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
            sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
            sysrc splash_changer_enable="YES"
        fi
    elif [ "$INSTALL_KAMILA" -eq 1 ]; then
        echo ">>> Downloading and configuring Kamila.is Boot Splash Screen..."
        mkdir -p /boot/images
        
        cd /tmp
        wget -qO v2.png https://kamila.is/media/v2.png || true
        if [ -f v2.png ]; then
            magick v2.png -resize 1920x1080 /boot/images/splash.png
            sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
            sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
            sysrc splash_changer_enable="YES"
        fi
        cd - >/dev/null
    else
        echo ">>> Preserving original FreeBSD boot splash configuration..."
    fi
}

main() {
    check_root
    interactive_config
    
    echo "=== Starting FreeBSD Installation (v1.28) ==="
    configure_tuning
    enable_linux_compat
    init_pkg
    configure_cpu_microcode
    install_packages
    configure_peripherals
    configure_desktop_env
    configure_locale
    configure_sddm
    configure_gpu
    configure_samba
    configure_virtualbox
    configure_splash
    configure_services
    configure_doas_and_groups
    
    echo "=== Installation successfully completed ==="
    echo "Please reboot the system to apply kernel changes."
}

main "$@"