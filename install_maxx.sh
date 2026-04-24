#!/usr/local/bin/bash
# ==============================================================================
# INSTALLATEUR INTERACTIF MAXX DESKTOP POUR FREEBSD 15
# Transactions Pkg Séparées - Radar PCI Strict - fetch natif
# ==============================================================================

# 0. Vérification Root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR : Ce script doit être exécuté en tant que root (su -)."
    exit 1
fi

echo -e "\033[1;36mInitialisation du gestionnaire de paquets...\033[0m"
env ASSUME_ALWAYS_YES=YES pkg bootstrap
pkg install -y bsddialog

# ==============================================================================
# FONCTIONS D'INTERFACE
# ==============================================================================
BTITLE="MaXX Desktop (SGI IRIX) pour FreeBSD"

step_start() { 
    clear
    echo -e "\033[1;34m================================================================================\033[0m"
    echo -e "\033[1;37m $1 \033[0m"
    echo -e "\033[1;34m================================================================================\033[0m\n"
}

step_done() { 
    bsddialog --backtitle "$BTITLE" --title " Étape Terminée " --colors --msgbox "\n $1\n\n \Zb\Z4👉 Appuyez sur [Entrée] pour continuer...\Zn" 9 75
}

# ==============================================================================
# DÉTECTION MATÉRIELLE ET SÉLECTION GRAPHIQUE
# ==============================================================================

VGA_INFO=$(pciconf -lv | awk '/class=0x030000/,/subclass/' | grep -E '^[[:space:]]*device[[:space:]]*=' | cut -d"'" -f2 | head -n 1)
[ -z "$VGA_INFO" ] && VGA_INFO="Carte non identifiée"

bsddialog --backtitle "$BTITLE" --title " Bienvenue " --colors --msgbox "\n\Zb\Z4Bienvenue dans l'installeur hybride MaXX Desktop.\Zn\n\nCe script va configurer FreeBSD, la cage Linuxulator, et installer l'environnement SGI IRIX étape par étape.\n\n \Zb👉 Appuyez sur [Entrée] pour démarrer l'installation.\Zn" 11 75

GPU_CHOICE=$(bsddialog --backtitle "$BTITLE" --title " Carte Graphique " --colors --clear --menu "\nMatériel détecté : \Zb\Z4$VGA_INFO\Zn\n\nSélectionnez le constructeur de votre carte graphique :" 13 70 3 \
    "1" "AMD (Radeon RX, etc.)" \
    "2" "NVIDIA (Quadro, GeForce, RTX...)" \
    "3" "Intel (HD/UHD Graphics)" \
    2>&1 >/dev/tty)

case $GPU_CHOICE in
    1)
        GPU_NAME="AMD Radeon"
        GPU_KMOD="amdgpu"
        GPU_ENV="export LIBVA_DRIVER_NAME=radeonsi\nexport VDPAU_DRIVER=radeonsi\nexport LIBGL_ALWAYS_SOFTWARE=1"
        ;;
    2)
        GPU_NAME="NVIDIA"
        GPU_KMOD="nvidia-modeset"
        GPU_ENV="export LIBVA_DRIVER_NAME=nvidia\nexport VDPAU_DRIVER=nvidia\nexport __GLX_VENDOR_LIBRARY_NAME=nvidia"
        
        NV_REC="1" 
        if echo "$VGA_INFO" | grep -qiE "Quadro P|GTX 10|GTX 9|M6000|GP10|GM20|Pascal|Maxwell"; then
            NV_REC="2"
            NV_SUGGESTION="Architecture Pascal/Maxwell -> Recommandation : Legacy 580"
        elif echo "$VGA_INFO" | grep -qiE "RTX|GTX 16|Turing|Ampere|Ada|TU10|GA10|AD10"; then
            NV_REC="1"
            NV_SUGGESTION="Architecture Turing ou + -> Recommandation : Latest 595+"
        elif echo "$VGA_INFO" | grep -qiE "GTX 7|GTX 6|Kepler|GK10"; then
            NV_REC="3"
            NV_SUGGESTION="Architecture Kepler -> Recommandation : Legacy 470"
        else
            NV_SUGGESTION="Architecture incertaine. Veuillez sélectionner manuellement."
        fi

        NV_CHOICE=$(bsddialog --backtitle "$BTITLE" --title " Version du Pilote NVIDIA " --colors --clear --default-item "$NV_REC" --menu "\nMatériel : \Zb\Z4$VGA_INFO\Zn\n\Z2$NV_SUGGESTION\Zn\n\nSélectionnez la branche binaire :" 17 75 3 \
            "1" "nvidia-driver     (Latest 595+)" \
            "2" "nvidia-driver-580 (Legacy LTS Pascal)" \
            "3" "nvidia-driver-470 (Legacy Kepler)" \
            2>&1 >/dev/tty)

        case $NV_CHOICE in
            1) NV_BASE="nvidia-driver"; NV_LIN="linux-nvidia-libs" ;;
            2) NV_BASE="nvidia-driver-580"; NV_LIN="linux-nvidia-libs-580" ;;
            3) NV_BASE="nvidia-driver-470"; NV_LIN="linux-nvidia-libs-470" ;;
            *) echo "Installation annulée."; exit 1 ;;
        esac
        ;;
    3)
        GPU_NAME="Intel"
        GPU_KMOD="i915kms"
        GPU_ENV="export LIBVA_DRIVER_NAME=iHD\nexport VDPAU_DRIVER=va_gl\nexport LIBGL_ALWAYS_SOFTWARE=1"
        ;;
    *) exit 1 ;;
esac

# --- ÉTAPE 1 ---
step_start "1/8 : Installation des dépendances natives FreeBSD... (Serveur X, Audio, Linuxulator, Firefox)"
pkg install -y xorg sddm firefox thunderbird xterm pulseaudio alsa-utils linux_base-rl9 xprop pciutils usbutils

echo -e "\n\033[1;36mInstallation du pilote graphique natif ($GPU_NAME)...\033[0m"
if [ "$GPU_NAME" = "NVIDIA" ]; then
    # Séparation stricte : On installe le pilote natif d'abord
    pkg install -y $NV_BASE
    
    echo -e "\n\033[1;36mInstallation de la surcouche 3D Linux ($NV_LIN)...\033[0m"
    # Le || echo permet de ne pas planter le script si les libs linux sont absentes du dépôt
    pkg install -y $NV_LIN || echo -e "\033[1;33m(Optionnel) $NV_LIN introuvable sur le dépôt. Suite de l'installation...\033[0m"
else
    pkg install -y drm-kmod
    [ "$GPU_NAME" = "Intel" ] && pkg install -y libva-intel-driver
fi
step_done "Toutes les dépendances FreeBSD, incluant les pilotes $GPU_NAME, sont installées."

# --- ÉTAPE 2 ---
step_start "2/8 : Configuration du noyau et des Périphériques Virtuels..."
sysrc linux_enable="YES"
sysrc kld_list+="$GPU_KMOD"
service linux start

add_fstab() { grep -q "$1" /etc/fstab || echo "$1 $2 $3 $4 $5 $6" >> /etc/fstab; }
add_fstab "fdescfs" "/dev/fd" "fdescfs" "rw" "0" "0"
add_fstab "procfs" "/proc" "procfs" "rw" "0" "0"
add_fstab "devfs" "/compat/linux/dev" "devfs" "rw,late" "0" "0"
add_fstab "fdescfs" "/compat/linux/dev/fd" "fdescfs" "rw,late,linrdlnk" "0" "0"
add_fstab "linsysfs" "/compat/linux/sys" "linsysfs" "rw,late" "0" "0"

mkdir -p /compat/linux/dev /compat/linux/dev/fd /compat/linux/sys
mount -a
step_done "Le noyau est configuré (Module graphique : $GPU_KMOD).\nLes points de montage virtuels sont fixés."

# --- ÉTAPE 3 ---
step_start "3/8 : Téléchargement et Extraction de MaXX v2.2.0..."
mkdir -p /opt/MaXX
chmod 1777 /tmp
chmod 666 /dev/dri/* 2>/dev/null

cd /tmp
if [ ! -f "maxx_installer.sh" ]; then
    fetch -o maxx_installer.sh https://s3.ca-central-1.amazonaws.com/cdn.maxxinteractive.com/maxx-desktop-installer/MaXX-Desktop-LINUX-x86_64-2.2.0-Installer.sh
    chmod +x maxx_installer.sh
fi
./maxx_installer.sh --noexec --target /opt/MaXX
step_done "Archive MaXX 2.2.0 téléchargée et extraite avec succès dans /opt/MaXX !"

# --- ÉTAPE 4 ---
step_start "4/8 : Création des ponts FreeBSD <-> Linuxulator..."
ln -sf /usr/local/bin/bash /bin/bash
ln -sf /usr/local/bin/aplay /compat/linux/usr/bin/aplay
ln -sfn /opt/MaXX/share /share
ln -sf /sbin/dmesg /compat/linux/usr/bin/dmesg
ln -sf /usr/local/sbin/lspci /compat/linux/usr/bin/lspci
ln -sf /usr/local/sbin/lsusb /compat/linux/usr/bin/lsusb
ln -sf /compat/linux/usr/lib64/libtinfo.so.6 /compat/linux/usr/lib64/libtinfo.so.5

rm -rf /compat/linux/opt/MaXX
mkdir -p /compat/linux/opt
ln -sf /opt/MaXX /compat/linux/opt/MaXX

echo -e "\033[1;32mPonts terminés avec succès.\033[0m"
step_done "Les outils Linux SGI communiquent avec le matériel FreeBSD.\nLe cache fantôme a été neutralisé."

# --- ÉTAPE 5 ---
step_start "5/8 : Forgeage des Sas en Titane... (Isolation de Firefox et Thunderbird)"
cat > /compat/linux/usr/bin/firefox << 'EOF'
#!/bin/sh
unset LD_LIBRARY_PATH MAXX_ENV MAXX_BIN MAXX_LIB MAXX_SHARE MAXX_ETC LIBGL_ALWAYS_SOFTWARE
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export GDK_BACKEND=x11
export MOZ_ENABLE_WAYLAND=0
export DISPLAY=:0
exec /usr/local/bin/firefox "$@"
EOF
chmod +x /compat/linux/usr/bin/firefox

cat > /opt/MaXX/bin/thunderbird_wrapper << 'EOF'
#!/bin/sh
unset LD_LIBRARY_PATH MAXX_ENV MAXX_BIN MAXX_LIB MAXX_SHARE MAXX_ETC LIBGL_ALWAYS_SOFTWARE
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export GDK_BACKEND=x11
export MOZ_ENABLE_WAYLAND=0
export DISPLAY=:0
exec /usr/local/bin/thunderbird "$@"
EOF
chmod +x /opt/MaXX/bin/thunderbird_wrapper

cat > /opt/MaXX/bin/mxterm << 'EOF'
#!/bin/sh
unset LD_LIBRARY_PATH MAXX_ENV MAXX_BIN MAXX_LIB MAXX_SHARE MAXX_ETC
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
exec /usr/local/bin/xterm -name mxterm "$@"
EOF
chmod +x /opt/MaXX/bin/mxterm

echo -e "\033[1;32mWrappers générés avec succès.\033[0m"
step_done "Wrappers générés. Firefox et Thunderbird sont isolés."

# --- ÉTAPE 6 ---
step_start "6/8 : Chirurgie du Toolchest SGI..."
if [ -f /opt/MaXX/etc/system.chestrc ]; then
    sed -i '' 's/.*"Open Web Browser".*/    "Open Web Browser"        f.exec "\/compat\/linux\/usr\/bin\/firefox"/' /opt/MaXX/etc/system.chestrc
    sed -i '' 's/.*"Open MailBox".*/    "Open MailBox"        f.exec "\/opt\/MaXX\/bin\/thunderbird_wrapper"/' /opt/MaXX/etc/system.chestrc
    sed -i '' 's/f.checkexec.sh "WEBBROWSER /f.exec "\/compat\/linux\/usr\/bin\/firefox /g' /opt/MaXX/etc/system.chestrc
fi

rm -f /home/*/.chestrc /root/.chestrc > /dev/null 2>&1
echo -e "\033[1;32mMenu Toolchest réparé, anciens fantômes purgés.\033[0m"
step_done "Menu Toolchest réparé avec la syntaxe exacte.\nLes anciens menus fantômes ont été purgés."

# --- ÉTAPE 7 ---
step_start "7/8 : Génération du chef d'orchestre global (start_maxx)..."
cat > /usr/local/bin/start_maxx << 'EOF'
#!/usr/local/bin/bash
exec > ~/maxx_debug.log 2>&1
echo "=== DEBUT DE LA SESSION MAXX ==="
[ -n "$XAUTHORITY" ] && cp "$XAUTHORITY" ~/.Xauthority 2>/dev/null
export XAUTHORITY=~/.Xauthority
pulseaudio --start 2>/dev/null &

mkdir -p ~/.maxxdesktop/Xdefaults.d
echo "14" > ~/.maxxdesktop/TerminalFontSize
echo "fixed" > ~/.maxxdesktop/TerminalFontName
echo "12" > ~/.maxxdesktop/SmallFontSize
echo "fixed" > ~/.maxxdesktop/SmallFontName
echo "YES" > ~/.maxxdesktop/IsSudoer
touch ~/.maxxdesktop/Xdefaults.d/Xdefaults.Gr_osview.dark

# === PARAMÈTRES GRAPHIQUES INJECTÉS ===
EOF

echo -e "$GPU_ENV" >> /usr/local/bin/start_maxx

cat >> /usr/local/bin/start_maxx << 'EOF'
# === FIN PARAMÈTRES GRAPHIQUES ===

xprop -root -remove _XROOTPMAP_ID 2>/dev/null
xprop -root -remove ESETROOT_PMAP_ID 2>/dev/null
xsetroot -solid "#395E79" &

export MAXX_ENV=/opt/MaXX
export MAXX_BIN=/opt/MaXX/bin
export MAXX_LIB=/opt/MaXX/lib
export MAXX_SHARE=/opt/MaXX/share
export MAXX_ETC=/opt/MaXX/etc
export PATH=$MAXX_BIN:/compat/linux/bin:/compat/linux/usr/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=$MAXX_LIB
export XUSERFILESEARCHPATH=$MAXX_SHARE/X11/app-defaults/%N

$MAXX_BIN/toolchest &
exec $MAXX_BIN/5Dwm
EOF
chmod +x /usr/local/bin/start_maxx
echo -e "\033[1;32mScript /usr/local/bin/start_maxx généré avec succès.\033[0m"
step_done "Script de démarrage SGI généré (Optimisé pour $GPU_NAME)."

# --- ÉTAPE 8 ---
step_start "8/8 : Inscription dans SDDM..."
mkdir -p /usr/local/share/xsessions
cat > /usr/local/share/xsessions/maxx.desktop << 'EOF'
[Desktop Entry]
Name=MaXX Desktop (SGI IRIX)
Exec=/usr/local/bin/start_maxx
Type=Application
EOF
echo -e "\033[1;32mSession SDDM créée.\033[0m"
step_done "Session enregistrée dans SDDM."

# ==============================================================================
# FIN
# ==============================================================================
bsddialog --backtitle "$BTITLE" --title " Opération Terminée ! " --colors --msgbox "\n \Zb\Z2L'installation hybride ($GPU_NAME) est un succès absolu.\Zn\n\n\Z1IMPORTANT :\Zn\n1. Redémarrez l'ordinateur (tapez \Zb\Z4reboot\Zn).\n2. Dans Firefox et Thunderbird : activez la 'Barre de titre' dans 'Personnaliser la barre d'outils'.\n\nBon voyage en 1995 !" 14 75
