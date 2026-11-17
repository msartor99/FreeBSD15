#!/bin/sh
set -e

# ==============================================================================
# VARIABLES A PERSONNALISER
# ==============================================================================
TARGET_USER="administrateur"
SDDM_THEME="maldives"          # Exemples : elarun, maldives, maya
LOCALE_LANG="fr_CH.UTF-8"      # Français Suisse (ou fr_FR.UTF-8)
ENABLE_ROOT_SSH="YES"          # YES pour autoriser root en SSH, NO pour bloquer

# ==============================================================================
# FONCTIONS UTILITAIRES IDEMPOTENTES
# ==============================================================================
add_sysctl() {
    key="$1"
    val="$2"
    if grep -q "^${key}=" /etc/sysctl.conf 2>/dev/null; then
        sed -i '' "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf
    else
        echo "${key}=${val}" >> /etc/sysctl.conf
    fi
    sysctl "${key}=${val}" >/dev/null 2>&1 || true
}

add_kld() {
    mod="$1"
    current=$(sysrc -n kld_list 2>/dev/null || true)
    case " $current " in
        *" $mod "*) ;;
        *) sysrc kld_list+="$mod" ;;
    esac
    kldstat -q -m "$mod" || kldload "$mod" >/dev/null 2>&1 || true
}

# ==============================================================================
# 1. VERIFICATIONS INITIALES
# ==============================================================================
if [ "$(id -u)" -ne 0 ]; then
    echo "Erreur : Ce script doit être exécuté en tant que root."
    exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Erreur : L'utilisateur '$TARGET_USER' n'existe pas."
    exit 1
fi

export ASSUME_ALWAYS_YES=yes

echo "=== 2. Installation des paquets (Système, VMware, Bureau, Multimédia) ==="
pkg update
pkg install -y \
    open-vm-tools \
    xorg \
    xf86-video-vmware \
    xf86-input-vmmouse \
    mate \
    sddm \
    firefox \
    vlc \
    doas \
    unzip \
    libzip \
    wget \
    git \
    htop \
    python3 \
    ImageMagick7 \
    cups \
    gutenprint \
    cups-filters \
    hplip \
    system-config-printer \
    fusefs-ntfs \
    fusefs-ext2 \
    fusefs-hfsfuse \
    pulseaudio \
    freedesktop-sound-theme \
    avahi \
    seatd \
    linux-rl9

# btop remplace bashtop et fastfetch remplace neofetch sur FreeBSD 14
pkg install -y btop fastfetch || true

echo "=== 3. Configuration SSH ==="
if [ "$ENABLE_ROOT_SSH" = "YES" ]; then
    if grep -q "^#*PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i '' 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi
fi
sysrc sshd_enable="YES"
service sshd restart || true

echo "=== 4. Paramètres de démarrage (/boot/loader.conf) et Noyau ==="
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc -f /boot/loader.conf sound_load="YES"
sysrc -f /boot/loader.conf snd_hda_load="YES"
sysrc -f /boot/loader.conf snd_es137x_load="YES"

sysrc rc_startmsgs="NO"

# Optimisations sysctl (Bureau, réseau local, USB et extinction VMware)
add_sysctl "kern.sched.preempt_thresh" "224"
add_sysctl "kern.ipc.shm_allow_removed" "1"
add_sysctl "net.local.stream.recvspace" "65536"
add_sysctl "net.local.stream.sendspace" "65536"
add_sysctl "vfs.usermount" "1"
add_sysctl "hw.usb.no_shutdown_wait" "1"
add_sysctl "hw.acpi.power_button_state" "S5"

echo "=== 5. Compatibilité Linux et Systèmes de fichiers ==="
sysrc linux_enable="YES"
sysrc linux_mounts_enable="YES"
add_kld "linux"
add_kld "linux64"
add_kld "fusefs"
add_kld "ext2fs"
service linux start >/dev/null 2>&1 || true

# Montage /proc et /dev/fd dans /etc/fstab
grep -q "^proc[[:space:]]*/proc" /etc/fstab || echo "proc /proc procfs rw 0 0" >> /etc/fstab
grep -q "^fdesc[[:space:]]*/dev/fd" /etc/fstab || echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab
mount | grep -q "on /proc " || mount /proc
mount | grep -q "on /dev/fd " || mount /dev/fd

echo "=== 6. Localisation Française ($LOCALE_LANG) ==="
if ! grep -q "^french|" /etc/login.conf; then
    cat << EOF >> /etc/login.conf

french|French Users Accounts:\\
	:charset=UTF-8:\\
	:lang=${LOCALE_LANG}:\\
	:tc=default:
EOF
    cap_mkdb /etc/login.conf
fi

echo "defaultclass=french" > /etc/adduser.conf
pw usermod "$TARGET_USER" -G wheel,operator,video -L french
pw usermod root -L french

# Configuration de doas (alternative légère à sudo pour le groupe wheel)
if [ ! -f /usr/local/etc/doas.conf ]; then
    echo "permit persist :wheel" > /usr/local/etc/doas.conf
fi

echo "=== 7. Permissions périphériques (USB, Disques, Imprimantes) ==="
cat << 'EOF' > /etc/devfs.rules
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
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF

sysrc devfs_system_ruleset="localrules"
service devfs restart

echo "=== 8. Services Bureau, Impression et VMware ==="
sysrc dbus_enable="YES"
sysrc avahi_daemon_enable="YES"
sysrc cupsd_enable="YES"
sysrc seatd_enable="YES"
sysrc sddm_enable="YES"

sysrc vmware_guest_vmblock_enable="YES"
sysrc vmware_guest_vmhgfs_enable="YES"
sysrc vmware_guest_vmmemctl_enable="YES"
sysrc vmware_guest_vmxnet_enable="YES"
sysrc vmware_guest_kmod_enable="YES"
sysrc vmware_guestd_enable="YES"

echo "=== 9. Configuration X11 (Carte graphique VMware & Clavier Suisse Romand) ==="
mkdir -p /usr/local/etc/X11/xorg.conf.d

cat << 'EOF' > /usr/local/etc/X11/xorg.conf.d/10-vmware.conf
Section "Device"
    Identifier "Card0"
    Driver     "vmware"
EndSection
EOF

cat << 'EOF' > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier      "All Keyboards"
    MatchIsKeyboard "yes"
    Option          "XkbLayout" "ch"
    Option          "XkbVariant" "fr"
    Option          "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

echo "=== 10. Configuration SDDM et Session MATE ==="
mkdir -p /usr/local/etc/sddm.conf.d
cat << EOF > /usr/local/etc/sddm.conf.d/theme.conf
[Theme]
Current=$SDDM_THEME
EOF

# Clavier Suisse Romand dès l'écran de connexion SDDM
mkdir -p /usr/local/share/sddm/scripts
if [ ! -f /usr/local/share/sddm/scripts/Xsetup ]; then
    printf "#!/bin/sh\nsetxkbmap ch fr\n" > /usr/local/share/sddm/scripts/Xsetup
    chmod +x /usr/local/share/sddm/scripts/Xsetup
fi

USER_HOME=$(pw usershow "$TARGET_USER" | cut -d: -f6)
if [ ! -f "$USER_HOME/.xinitrc" ]; then
    echo "exec ck-launch-session dbus-launch --exit-with-session mate-session" > "$USER_HOME/.xinitrc"
    chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.xinitrc"
fi

echo "=== Configuration terminée avec succès ! ==="
echo "Redémarrez avec 'shutdown -r now' pour appliquer tous les paramètres."
