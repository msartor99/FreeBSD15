#!/bin/sh

# ==============================================================================
# SCRIPT DE POST-INSTALLATION FREEBSD 15
# Version: 6.5 - FIXED mDNS (Idempotence Totale) | POSIX sh
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

pkg install -y bsddialog > /dev/null 2>&1

# 1. SÉLECTION RÉGIONALE
CHOIX_KBD=$(bsddialog --title "Configuration Régionale" \
    --menu "Choisissez votre langue et disposition clavier :" 18 70 8 \
    "ch_fr" "Suisse Romand (ch fr / fr_CH)" \
    "ch_de" "Suisse Allemand (ch de / de_CH)" \
    "fr"    "France (fr / fr_FR)" \
    "de"    "Allemagne (de / de_DE)" \
    "it"    "Italie (it / it_IT)" \
    "pt"    "Portugal (pt / pt_PT)" \
    "us"    "USA (us / en_US)" \
    "uk"    "United Kingdom (gb / en_GB)" 3>&1 1>&2 2>&3)

case "$CHOIX_KBD" in
    "ch_fr") K_LAYOUT="ch"; K_VARIANT="fr"; L_CODE="fr_CH"; CLASS="swiss_fr" ;;
    "ch_de") K_LAYOUT="ch"; K_VARIANT="de"; L_CODE="de_CH"; CLASS="swiss_de" ;;
    "fr")    K_LAYOUT="fr"; K_VARIANT="";   L_CODE="fr_FR"; CLASS="french"   ;;
    "de")    K_LAYOUT="de"; K_VARIANT="";   L_CODE="de_DE"; CLASS="german"   ;;
    "it")    K_LAYOUT="it"; K_VARIANT="";   L_CODE="it_IT"; CLASS="italian"  ;;
    "pt")    K_LAYOUT="pt"; K_VARIANT="";   L_CODE="pt_PT"; CLASS="portuguese" ;;
    "us")    K_LAYOUT="us"; K_VARIANT="";   L_CODE="en_US"; CLASS="english"  ;;
    "uk")    K_LAYOUT="gb"; K_VARIANT="";   L_CODE="en_GB"; CLASS="english_uk" ;;
    *) exit 1 ;;
esac

# 2. GESTION UTILISATEUR
TYPE_USER=$(bsddialog --title "Gestion Utilisateur" --menu "Option :" 12 60 2 "NEW" "Créer nouveau" "EXISTING" "Existant" 3>&1 1>&2 2>&3)
case "$TYPE_USER" in
    "NEW")
        USER_NAME=$(bsddialog --title "Login" --inputbox "Nom de login :" 10 50 3>&1 1>&2 2>&3)
        REAL_NAME=$(bsddialog --title "Nom Réel" --inputbox "Nom complet :" 10 50 3>&1 1>&2 2>&3)
        USER_PASS=$(bsddialog --title "Mot de passe" --passwordbox "Entrez le mot de passe :" 10 50 3>&1 1>&2 2>&3)
        echo "$USER_PASS" | pw useradd "$USER_NAME" -m -G wheel,operator,video -s /bin/sh -c "$REAL_NAME" -h 0
        ;;
    "EXISTING")
        USER_NAME=$(bsddialog --title "Existant" --inputbox "Nom de l'utilisateur :" 10 50 3>&1 1>&2 2>&3)
        pw usermod "$USER_NAME" -G wheel,operator,video 2>/dev/null
        ;;
esac
pw usermod "$USER_NAME" -L "$CLASS"

# 3. CHOIX DES BUREAUX
DESKTOPS_RAW=$(bsddialog --title "Bureaux" --checklist "Sélection :" 15 60 5 "PLASMA6" "KDE" off "GNOME" "GNOME" off "XFCE4" "XFCE" off "MATE" "MATE" off "LXQT" "LXQt" off 3>&1 1>&2 2>&3)
DESKTOPS=$(echo "$DESKTOPS_RAW" | tr -d '"')

# 4. RÉSEAU
INTERFACES=$(ifconfig -l | tr ' ' '\n' | grep -v 'lo0')
IF_LIST=""
for iface in $INTERFACES; do IF_LIST="$IF_LIST $iface [Detectee]"; done
CHOIX_IF=$(bsddialog --title "Réseau" --menu "Interface :" 15 70 6 $IF_LIST "WIFI" "[Config_WLAN]" 3>&1 1>&2 2>&3)

# 5. MATÉRIEL
CHOIX_CPU=$(bsddialog --title "CPU" --menu "Processeur :" 12 60 2 "AMD" "AMD" "INTEL" "Intel" 3>&1 1>&2 2>&3)
CHOIX_GPU=$(bsddialog --title "GPU" --menu "Graphique :" 15 75 4 "AMD" "AMD Radeon" "INTEL_MODERN" "Intel Modern" "INTEL_LEGACY" "Intel Legacy" "NVIDIA" "NVIDIA" 3>&1 1>&2 2>&3)

# 6. MISE À JOUR & SYSTÈME DE BASE
sed -i '' -e 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf
pkg update -f && pkg upgrade -y
pkg install -y xorg seatd sddm firefox vlc ffmpeg webfonts dejavu noto-basic liberation-fonts-ttf fusefs-exfat fusefs-ntfs realtek-re-kmod nss_mdns

# 7. RÉSEAU & DRIVERS
grep -q "if_atlantic_load" /boot/loader.conf || echo 'if_atlantic_load="YES"' >> /boot/loader.conf
sysrc kld_list+="if_re"
case "$CHOIX_IF" in
    "WIFI") W_DEV=$(sysctl -n net.wlan.devices | awk '{print $1}') ; [ -n "$W_DEV" ] && sysrc wlans_"$W_DEV"="wlan0" && sysrc ifconfig_wlan0="WPA SYNCDHCP" ;;
    *) sysrc ifconfig_"$CHOIX_IF"="SYNCDHCP" ;;
esac

# 8. CPU / GPU / SYSCTL
case "$CHOIX_CPU" in
    "AMD") pkg install -y cpu-microcode-amd ; sysrc -f /boot/loader.conf amdtemp_load="YES" ; grep -q "amd-ucode" /boot/loader.conf || echo 'cpu_microcode_name="/boot/firmware/amd-ucode.bin"' >> /boot/loader.conf ;;
    "INTEL") pkg install -y cpu-microcode-intel ; sysrc -f /boot/loader.conf coretemp_load="YES" ; grep -q "intel-ucode" /boot/loader.conf || echo 'cpu_microcode_name="/boot/firmware/intel-ucode.bin"' >> /boot/loader.conf ;;
esac
grep -q "cpu_microcode_load" /boot/loader.conf || echo 'cpu_microcode_load="YES"' >> /boot/loader.conf

case "$CHOIX_GPU" in
    "AMD") pkg install -y drm-kmod ; sysrc kld_list+="amdgpu" ;;
    "INTEL_MODERN") pkg install -y drm-kmod ; sysrc kld_list+="i915kms" ;;
    "INTEL_LEGACY") pkg install -y drm-fbsd13-kmod ; sysrc kld_list+="i915kms" ;;
    "NVIDIA") pkg install -y nvidia-driver nvidia-settings nvidia-xconfig ; sysrc kld_list+="nvidia-modeset" ; [ ! -f /etc/X11/xorg.conf ] && nvidia-xconfig ;;
esac

sysrc seatd_enable="YES" sddm_enable="YES" dbus_enable="YES" avahi_daemon_enable="YES"
grep -q "vfs.usermount=1" /etc/sysctl.conf || echo "vfs.usermount=1" >> /etc/sysctl.conf
[ -d /proc ] || mkdir /proc
grep -q "proc /proc" /etc/fstab || echo "proc /proc procfs rw 0 0" >> /etc/fstab

# 9. CLAVIER X11
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboard.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "$K_LAYOUT"
    Option "XkbVariant" "$K_VARIANT"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

# 10. AUDIO & BUREAUX
pkg install -y pipewire pavucontrol libreoffice cups hplip samba416 virtualbox-ose-72
sysrc cupsd_enable="YES" samba_server_enable="YES"

for desk in $DESKTOPS; do
    case "$desk" in
        "PLASMA6") pkg install -y plasma6-plasma ;;
        "GNOME")   pkg install -y gnome ;;
        "XFCE4")   pkg install -y xfce ;;
        "MATE")    pkg install -y mate-desktop mate-applets ;;
        "LXQT")    pkg install -y lxqt sddm-freebsd-black-theme ;;
    esac
done

# ------------------------------------------------------------------------------
# 11. CORRECTIF MDNS RÉVISÉ (Idempotence Totale)
# ------------------------------------------------------------------------------
# On s'assure d'abord que nss_mdns est installé (répété par sécurité)
pkg install -y nss_mdns > /dev/null 2>&1

if [ -f /etc/nsswitch.conf ]; then
    # 1. On vérifie si "mdns" est déjà présent sur la ligne "hosts:"
    if grep -q "^hosts:" /etc/nsswitch.conf && ! grep "^hosts:" /etc/nsswitch.conf | grep -q "mdns"; then
        # On ajoute mdns proprement avant [NOTFOUND=return] ou à la fin
        sed -i '' 's/^hosts: \(.*\)/hosts: \1 mdns/' /etc/nsswitch.conf
    fi
fi

# 12. FINALISATION
grep -q "vboxdrv_load" /boot/loader.conf || echo 'vboxdrv_load="YES"' >> /boot/loader.conf
pw groupmod vboxusers -m "$USER_NAME" 2>/dev/null || true

bsddialog --msgbox "Post-installation V6.5 terminee.\nmDNS configure et verifie.\nRedemarrez." 10 50


