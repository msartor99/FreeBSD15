#!/bin/sh

# 1. Root privileges check
if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run with root privileges." >&2
    exit 1
fi

# 2. Disclaimer and confirmation
bsddialog --title " WARNING " --yesno \
"This script will configure a complete FreeBSD workstation:\n\n- GPU configuration (AMD or Intel)\n- Custom boot screen (Silent PNG Splash Screen)\n- Desktop Environment choice (GNOME, XFCE, Plasma, MATE, LXQt)\n- Printing (CUPS, Network, mDNS), USB/FUSE user mount\n- SDDM Maldives and auto-detection of regional keyboard\n\nAre you sure you want to continue?" 17 75

if [ $? -ne 0 ]; then
    clear
    echo "Operation cancelled."
    exit 1
fi

# 3. GPU Manufacturer choice (AMD vs Intel)
VENDOR_CHOICE=$(bsddialog --title " Step 1: GPU Manufacturer " --clear \
    --menu "Who is the manufacturer of your graphics card?" 12 60 2 \
    "1" "AMD (Radeon, RX, etc.)" \
    "2" "Intel (HD Graphics, Iris, etc.)" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] || [ -z "$VENDOR_CHOICE" ] && clear && exit 1

if [ "$VENDOR_CHOICE" = "1" ]; then
    GPU_CHOICE=$(bsddialog --title " Step 1b: AMD Model " --clear \
        --menu "Select your hardware generation:" 14 75 2 \
        "1" "Recent (amdgpu - GCN 3.0 / Radeon RX 400 and newer)" \
        "2" "Legacy (radeonkms - Radeon HD 7000 and older)" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] || [ -z "$GPU_CHOICE" ] && clear && exit 1

    if [ "$GPU_CHOICE" = "2" ]; then
        KMOD="radeonkms"; XORG_DRIVER="xf86-video-ati"; IDENTIFIER="Radeon"
    else
        KMOD="amdgpu"; XORG_DRIVER="xf86-video-amdgpu"; IDENTIFIER="AMD"
    fi
    EXTRA_PKG="vdpauinfo"
elif [ "$VENDOR_CHOICE" = "2" ]; then
    KMOD="i915kms"; XORG_DRIVER="xf86-video-intel"; IDENTIFIER="Intel"
    EXTRA_PKG="libva-intel-driver intel-media-driver"
fi

# 4. Desktop Environment choice
DE_CHOICE=$(bsddialog --title " Step 2: Desktop Environment " --clear \
    --menu "Choose the GUI to install:" 17 75 7 \
    "1" "GNOME (Full desktop, launched via SDDM with theme)" \
    "2" "XFCE 4 (Light, fast and classic)" \
    "3" "KDE Plasma 6 (Complete, modern and customizable)" \
    "4" "MATE (Robust traditional desktop)" \
    "5" "LXQt (Light and modern Qt-based desktop)" \
    "6" "Xorg only (No desktop, minimal configuration)" \
    "7" "Do not install a graphical interface" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] || [ -z "$DE_CHOICE" ] && clear && exit 1

DE_PKGS=""
DM_TARGET="none"
HAS_XORG="YES"

case "$DE_CHOICE" in
    1) DE_PKGS="xorg sddm gnome"; DM_TARGET="sddm" ;;
    2) DE_PKGS="xorg sddm xfce"; DM_TARGET="sddm" ;;
    3) DE_PKGS="xorg sddm plasma6-plasma dolphin konsole"; DM_TARGET="sddm" ;;
    4) DE_PKGS="xorg sddm mate"; DM_TARGET="sddm" ;;
    5) DE_PKGS="xorg sddm lxqt"; DM_TARGET="sddm" ;;
    6) DE_PKGS="xorg" ;;
    7) HAS_XORG="NO" ;;
esac

# 5. Additional software choice
APPS_CHOICE=$(bsddialog --title " Step 3: Additional Software " --clear \
    --checklist "Select programs to install (Space to check):" 15 70 3 \
    "firefox" "Mozilla Firefox Web Browser" on \
    "thunderbird" "Thunderbird Email Client" on \
    "vlc" "VLC Media Player" on \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && clear && exit 1

APP_PKGS=$(echo "$APPS_CHOICE" | tr -d '"')

clear
echo "=== Beginning system configuration ==="

# 6. Hardware base and related services (Printing, FUSE, Avahi, mDNS)
echo "-> [1/10] Installing hardware base, printing and FUSE..."
pkg install -y drm-kmod "$XORG_DRIVER" mesa-dri vulkan-loader vulkan-tools libva-utils dbus avahi-app \
    cups gutenprint cups-filters hplip system-config-printer nss_mdns \
    fusefs-ntfs fusefs-ext2 fusefs-hfsfuse $EXTRA_PKG

# 7. Splash Screen download (Native PNG support on FreeBSD 15)
echo "-> [2/10] Configuring boot image (PNG Splash Screen)..."
mkdir -p /usr/local/share/pixmaps

if fetch -q -o /usr/local/share/pixmaps/splash_kamila.png https://kamila.is/media/v2.png; then
    sysrc -f /boot/loader.conf splash_png_load="YES"
    sysrc -f /boot/loader.conf bitmap_load="YES"
    sysrc -f /boot/loader.conf bitmap_name="/usr/local/share/pixmaps/splash_kamila.png"
fi

# 8. Silent Boot Configuration
echo "-> [3/10] Configuring silent boot..."
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc rc_startmsgs="NO"
sysrc rc_info="NO"

if grep -q "run_rc_script \${_rc_elem} \${_boot}$" /etc/rc; then
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}$/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
fi

# 9. Desktop Environment and applications installation
if [ -n "$DE_PKGS" ] || [ -n "$APP_PKGS" ]; then
    echo "-> [4/10] Installing selected desktop and software..."
    pkg install -y $DE_PKGS $APP_PKGS
fi

# 10. User configuration (Language class and Groups)
echo "-> [5/10] Configuring users (root, administrateur)..."
pw usermod root -L french
if id "administrateur" >/dev/null 2>&1; then
    pw usermod administrateur -G wheel,operator,video,cups -L french
fi

# 11. Fstab
echo "-> [6/10] Configuring /etc/fstab (procfs)..."
if ! grep -q "^proc" /etc/fstab 2>/dev/null; then
    echo "proc /proc procfs rw 0 0" >> /etc/fstab
    mount -t procfs proc /proc 2>/dev/null || true
fi

# 12. DevFS Rules (USB, Scanner, Printing)
echo "-> [7/10] Configuring /etc/devfs.rules (USB, Scanner, Printing)..."
if ! grep -q "\[localrules=5\]" /etc/devfs.rules 2>/dev/null; then
    cat >> /etc/devfs.rules <<EOF

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
add path 'unlpt*' mode 0660 group cups
add path 'ulpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF
fi

# 13. Sysctl (Audio and user mount)
echo "-> [8/10] Configuring kernel parameters (Sysctl)..."
SYSCTL_CONF="/etc/sysctl.conf"
if ! grep -q "vfs.usermount=1" "$SYSCTL_CONF" 2>/dev/null; then
    echo "vfs.usermount=1" >> "$SYSCTL_CONF"
    sysctl vfs.usermount=1 >/dev/null
fi
if ! grep -q "hw.snd.default_auto=1" "$SYSCTL_CONF" 2>/dev/null; then
    echo "hw.snd.default_auto=1" >> "$SYSCTL_CONF"
    sysctl hw.snd.default_auto=1 >/dev/null
fi

# 14. Services, Kernel Modules and SDDM Wallpaper
echo "-> [9/10] Enabling system services and modules..."
sysrc dbus_enable="YES"
sysrc avahi_daemon_enable="YES"
sysrc cupsd_enable="YES"
sysrc cups_browsed_enable="YES"
sysrc devfs_system_ruleset="localrules"

# mDNS resolution configuration for network printers
if grep -q "^hosts:" /etc/nsswitch.conf && ! grep -q "mdns" /etc/nsswitch.conf; then
    sed -i '' 's/^hosts:.*/& mdns/' /etc/nsswitch.conf
fi

if [ "$DM_TARGET" = "sddm" ]; then
    sysrc sddm_enable="YES"
    # Keeping default lang as fr_CH.UTF-8 for the system preference
    sysrc sddm_lang="fr_CH.UTF-8"
    
    SDDM_CONF_DIR="/usr/local/etc/sddm.conf.d"
    mkdir -p "$SDDM_CONF_DIR"
    cat << EOF > "$SDDM_CONF_DIR/10-theme.conf"
[Theme]
Current=maldives
EOF

    THEME_CONF="/usr/local/share/sddm/themes/maldives/theme.conf"
    if [ -f "/usr/local/share/pixmaps/splash_kamila.png" ] && [ -f "$THEME_CONF" ]; then
        cp /usr/local/share/pixmaps/splash_kamila.png /usr/local/share/sddm/themes/maldives/
        sed -i '' 's/^background=.*/background=splash_kamila.png/' "$THEME_CONF"
    fi
fi

for mod in "$KMOD" fusefs ext2fs; do
    if ! sysrc -n kld_list 2>/dev/null | grep -q "\b${mod}\b"; then
        sysrc kld_list+="$mod"
    fi
done

service devfs restart >/dev/null 2>&1 || true

# 15. Xorg and Keyboard configuration
if [ "$HAS_XORG" = "YES" ]; then
    echo "-> [10/10] Automatic configuration of Xorg and Keyboard..."
    CONF_DIR="/usr/local/etc/X11/xorg.conf.d"
    CONF_FILE="$CONF_DIR/20-${KMOD}.conf"
    mkdir -p "$CONF_DIR"

    if [ ! -f "$CONF_FILE" ]; then
        cat << EOF > "$CONF_FILE"
Section "Device"
    Identifier "$IDENTIFIER"
    Driver "${XORG_DRIVER#xf86-video-}" 
    Option "TearFree" "true"
EndSection
EOF
    fi

    # Automatic translation of console configuration (rc.conf) to Xorg
    RC_KEYMAP=$(sysrc -n keymap 2>/dev/null | sed 's/\.kbd//')
    case "$RC_KEYMAP" in
        ch*|swissfrench*) XKBLAYOUT="ch"; XKBVARIANT="fr" ;;
        sg*|swissgerman*) XKBLAYOUT="ch"; XKBVARIANT="" ;;
        fr*|french*)      XKBLAYOUT="fr"; XKBVARIANT="" ;;
        be*|belgian*)     XKBLAYOUT="be"; XKBVARIANT="" ;;
        uk*|gb*)          XKBLAYOUT="gb"; XKBVARIANT="" ;;
        ca*|canadian*)    XKBLAYOUT="ca"; XKBVARIANT="fr" ;;
        de*|german*)      XKBLAYOUT="de"; XKBVARIANT="" ;;
        es*|spanish*)     XKBLAYOUT="es"; XKBVARIANT="" ;;
        it*|italian*)     XKBLAYOUT="it"; XKBVARIANT="" ;;
        pt*|portuguese*)  XKBLAYOUT="pt"; XKBVARIANT="" ;;
        us*|usa*|"")      XKBLAYOUT="us"; XKBVARIANT="" ;;
        *) 
            XKBLAYOUT=$(echo "$RC_KEYMAP" | cut -d. -f1 | cut -c1-2)
            XKBVARIANT=""
            ;;
    esac

    KBD_CONF="$CONF_DIR/00-keyboard.conf"
    cat << EOF > "$KBD_CONF"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKBLAYOUT"
EOF
    [ -n "$XKBVARIANT" ] && echo "    Option \"XkbVariant\" \"$XKBVARIANT\"" >> "$KBD_CONF"
    cat << EOF >> "$KBD_CONF"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

    if [ "$DM_TARGET" = "sddm" ]; then
        XSETUP="/usr/local/share/sddm/scripts/Xsetup"
        mkdir -p "$(dirname "$XSETUP")"
        
        if [ ! -f "$XSETUP" ]; then
            echo "#!/bin/sh" > "$XSETUP"
            chmod +x "$XSETUP"
        fi
        
        SETXKB_CMD="/usr/local/bin/setxkbmap $XKBLAYOUT"
        [ -n "$XKBVARIANT" ] && SETXKB_CMD="$SETXKB_CMD -variant $XKBVARIANT"
        
        sed -i '' '/setxkbmap/d' "$XSETUP" 2>/dev/null
        echo "$SETXKB_CMD" >> "$XSETUP"
    fi
else
    echo "-> [10/10] Xorg not installed, skipping graphical configuration."
fi

# 16. Final summary
echo "-> Finalizing..."
bsddialog --title " Installation Complete " --msgbox \
"Your system is fully configured!\n\nThe user 'administrateur' has been granted the 'french' login class and necessary groups.\nThe network (mDNS) is ready for network printer discovery.\n\nPlease reboot the machine." 12 75

clear
echo "Operation finished. Type 'reboot' to restart."