#!/bin/sh
# ==============================================================================
# FreeBSD 15.1 - Universal Workstation Setup Script (FINAL X11 EDITION)
# Target: Lenovo P620 / Nvidia RTX 3060 / SDDM / X11 / Plasma 6
# Author: msartor99 (Adapted for GitHub)
# ==============================================================================

set -e

# 1. Vérification des droits root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR: Ce script doit être exécuté en root." >&2
    exit 1
fi

# ==============================================================================
# CONFIRMATION ET UTILISATEUR
# ==============================================================================
bsddialog --title "FREEBSD 15.1 - STATION DE TRAVAIL X11" \
          --clear \
          --yesno "Ce script va configurer un environnement de production stable :\n\n  - Moteur graphique X11 pur (Aucun module DRM expérimental).\n  - Pilote Nvidia classique (Haute performance et stabilité).\n  - Bureau KDE Plasma 6 via SDDM.\n  - Clavier, Locale et Splash Screen dynamique configurés.\n\nVoulez-vous procéder à l'installation ?" 15 75

if [ $? -ne 0 ]; then
    clear
    echo ">>> Installation annulée."
    exit 0
fi

TMP_USER_FILE="/tmp/setup_target_user.txt"
bsddialog --title "CONFIGURATION UTILISATEUR" \
          --clear \
          --inputbox "Veuillez entrer le nom de l'utilisateur cible :\n(Sera ajouté aux groupes: wheel, operator, video)" 10 75 "administrateur" 2>"$TMP_USER_FILE"

if [ $? -ne 0 ]; then
    clear
    echo ">>> Installation annulée."
    rm -f "$TMP_USER_FILE"
    exit 0
fi

TARGET_USER=$(cat "$TMP_USER_FILE")
rm -f "$TMP_USER_FILE"
[ -z "$TARGET_USER" ] && TARGET_USER="administrateur"

clear
echo ">>> Déploiement de la station X11 en cours..."

# 2. Installation de la forteresse X11 et de KDE
echo ">>> Installation des paquets requis..."
pkg update
pkg install -y \
    xorg-server \
    xinit \
    sddm \
    plasma6-plasma \
    nvidia-driver \
    nvidia-settings \
    plasma6-kde-gtk-config \
    plasma6-breeze \
    ImageMagick7 \
    ca_root_nss

# 3. Activation des services indispensables
echo ">>> Activation des services systèmes..."
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"

# 4. Configuration Nvidia (Modeset classique uniquement)
echo ">>> Configuration du pilote Nvidia..."
if ! sysrc -n kld_list 2>/dev/null | grep -q "nvidia-modeset"; then
    sysrc kld_list+=" nvidia-modeset" >/dev/null
fi

# 5. Localisation et mapping Clavier
echo ">>> Configuration de la localisation système..."
SYS_KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "us.kbd")

case "${SYS_KEYMAP}" in
    *ch*|*swiss*) SYS_LOCALE="fr_CH.UTF-8"; XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
    *fr*)         SYS_LOCALE="fr_FR.UTF-8"; XKB_LAYOUT="fr"; XKB_VARIANT="" ;;
    *de*)         SYS_LOCALE="de_DE.UTF-8"; XKB_LAYOUT="de"; XKB_VARIANT="" ;;
    *)            SYS_LOCALE="en_US.UTF-8"; XKB_LAYOUT="us"; XKB_VARIANT="" ;;
esac

mkdir -p /etc/login.conf.d
cat <<EOF > /etc/login.conf.d/10-locale.conf
default:\\
	:charset=UTF-8:\\
	:lang=${SYS_LOCALE}:
EOF
cap_mkdb /etc/login.conf

# 6. Forcer Xorg et SDDM à utiliser la bonne configuration
echo ">>> Création des fichiers de configuration X11..."
mkdir -p /usr/local/etc/X11/xorg.conf.d

cat <<EOF > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier "Nvidia Card"
    Driver "nvidia"
EndSection
EOF

cat <<EOF > /usr/local/etc/X11/xorg.conf.d/30-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${XKB_LAYOUT}"
    Option "XkbVariant" "${XKB_VARIANT}"
EndSection
EOF

mkdir -p /usr/local/etc/sddm.conf.d
cat <<EOF > /usr/local/etc/sddm.conf.d/10-x11.conf
[General]
DisplayServer=x11

[Theme]
Current=breeze
EOF

# 7. Création de l'utilisateur
echo ">>> Configuration du compte: ${TARGET_USER}..."
if ! pw usershow "${TARGET_USER}" >/dev/null 2>&1; then
    pw useradd "${TARGET_USER}" -m -G wheel,operator,video -s /bin/sh -c "Workstation User"
    echo "    *** VEUILLEZ DÉFINIR LE MOT DE PASSE POUR ${TARGET_USER} ***"
    passwd "${TARGET_USER}"
else
    for grp in wheel operator video; do 
        pw groupmod "$grp" -m "${TARGET_USER}" 2>/dev/null || true
    done
fi

# 8. Le Boot Splash (Détection dynamique de l'écran et redimensionnement)
echo ">>> Configuration du Boot Splash Screen..."
mkdir -p /boot/images

SPLASH_URL="https://kamila.is/media/v2.png"
SPLASH_PNG="/boot/images/splash.png"
SPLASH_BMP="/boot/images/splash.bmp"

if fetch -q -o "${SPLASH_PNG}" "${SPLASH_URL}"; then
    # Détection de la résolution de l'écran (Framebuffer VT)
    FB_W=$(sysctl -n kern.vt.fb.width 2>/dev/null || echo "1920")
    FB_H=$(sysctl -n kern.vt.fb.height 2>/dev/null || echo "1080")
    echo "    -> Résolution de la console détectée : ${FB_W}x${FB_H}"

    # Redimensionnement magique : on couvre tout l'écran (^), on centre, et on coupe ce qui dépasse (-extent)
    magick "${SPLASH_PNG}" \
        -resize "${FB_W}x${FB_H}^" \
        -gravity center \
        -extent "${FB_W}x${FB_H}" \
        -type truecolor "${SPLASH_BMP}"
    
    # Injection propre dans loader.conf (idempotente)
    sysrc -f /boot/loader.conf splash_bmp_load="YES" >/dev/null
    sysrc -f /boot/loader.conf bitmap_load="YES" >/dev/null
    sysrc -f /boot/loader.conf bitmap_name="${SPLASH_BMP}" >/dev/null
    
    # Nettoyage
    rm -f "${SPLASH_PNG}"
    echo "    -> Image retaillée au pixel près et configurée avec succès."
else
    echo "    -> AVERTISSEMENT: Échec du téléchargement du Splash Screen." >&2
fi

# ==============================================================================
bsddialog --title "INSTALLATION TERMINÉE" \
          --clear \
          --msgbox "Votre station FreeBSD 15.1 (X11) est prête et configurée.\n\nL'accélération matérielle, SDDM, Plasma 6 et le Splash Screen dynamique sont opérationnels.\n\nVeuillez redémarrer la machine." 10 75

clear
echo ">>> Installation terminée avec succès. Tapez : reboot"