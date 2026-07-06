#!/bin/sh
#
# MASTER SCRIPT : Post-installation Workstation - FreeBSD 15.1-RELEASE
# Environnement : NsCDE (look CDE / Solaris)
# Matériel : NVMe, GPU NVIDIA Quadro K5200
# Caractéristiques : Idempotent, Localisation fr_CH, Son complet, 
#                   USB (NTFS/EXT2), Optimisations Desktop, Linux Compat,
#                   Explorateur Thunar/GVFS, Editeur Geany

echo "============================================================"
echo " Initialisation Workstation FreeBSD 15.1"
echo "============================================================"

if [ "$(id -u)" != "0" ]; then
    echo "ERREUR : Ce script doit être exécuté en tant que root."
    exit 1
fi

# ============================================================
# 1. Installation de tous les paquets
# ============================================================
echo "-> Mise à jour des catalogues pkg..."
pkg update

echo "-> Installation des composants Xorg, Bureau et NVIDIA..."
pkg install -y xorg dbus lightdm lightdm-gtk-greeter nscde \
    nvidia-driver-470 nvidia-settings

echo "-> Installation de l'Explorateur de Fichiers et de l'Éditeur Texte..."
pkg install -y thunar gvfs geany

echo "-> Installation des dépendances Linux et Utilitaires Système..."
pkg install -y linux-rl9 doas unzip libzip wget git htop neofetch \
    python3 smartmontools octopkg

echo "-> Installation de l'Audio et Polices..."
pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme \
    cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji \
    roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf

echo "-> Installation Bureautique et Multimédia..."
pkg install -y firefox thunderbird chromium signal-cli remmina eom \
    vlc ffmpeg mpv multimedia/mpv gstreamer1-plugins-all gstreamer1-libav \
    libva-vdpau-driver libva-utils libdvdread libdvdnav libbluray \
    xdg-user-dirs

echo "-> Installation Impression et Disques (USB)..."
pkg install -y cups gutenprint cups-filters hplip system-config-printer avahi \
    fusefs-ntfs fusefs-ext2 fusefs-hfsfuse automount

# ============================================================
# 2. Configuration du chargeur de démarrage (loader.conf)
# ============================================================
echo "-> Optimisation de /boot/loader.conf..."
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc -f /boot/loader.conf sound_load="YES"
sysrc -f /boot/loader.conf snd_hda_load="YES"

# ============================================================
# 3. Optimisations du noyau et du système (sysctl.conf)
# ============================================================
echo "-> Application des optimisations Desktop dans sysctl.conf..."
sysrc -f /etc/sysctl.conf kern.sched.preempt_thresh="224"
sysrc -f /etc/sysctl.conf kern.ipc.shm_allow_removed="1"
sysrc -f /etc/sysctl.conf net.local.stream.recvspace="65536"
sysrc -f /etc/sysctl.conf net.local.stream.sendspace="65536"
sysrc -f /etc/sysctl.conf vfs.usermount="1"
sysrc -f /etc/sysctl.conf hw.snd.default_unit="1"

# ============================================================
# 4. Activation des services (rc.conf)
# ============================================================
echo "-> Activation des services système..."
sysrc dbus_enable="YES"
sysrc lightdm_enable="YES"
sysrc cupsd_enable="YES"
sysrc avahi_enable="YES"
sysrc smartd_enable="YES"
sysrc linux_enable="YES"
sysrc linux64_enable="YES"
sysrc devfs_system_ruleset="localrules"

echo "-> Configuration des modules noyau supplémentaires..."
for mod in nvidia-modeset fusefs ext2fs; do
    if ! sysrc -n kld_list | grep -qw "$mod"; then
        sysrc kld_list+="$mod"
    fi
done

# ============================================================
# 5. Points de montage vitaux (fstab)
# ============================================================
echo "-> Configuration de fstab (procfs & fdescfs)..."
if ! grep -q "procfs" /etc/fstab; then
    echo "proc /proc procfs rw 0 0" >> /etc/fstab
fi
if ! grep -q "fdescfs" /etc/fstab; then
    echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab
fi

# ============================================================
# 6. Règles de périphériques (devfs.rules)
# ============================================================
echo "-> Création des règles devfs (USB, CD, Imprimantes)..."
cat > /etc/devfs.rules << 'EOF'
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
add path 'lpt*' mode 0660 group cups
EOF

# ============================================================
# 7. Localisation, Utilisateurs et Sécurité
# ============================================================
echo "-> Création de la classe locale fr_CH dans login.conf..."
if ! grep -q "^french|" /etc/login.conf; then
    cat >> /etc/login.conf << 'EOF'

french|French Users Accounts:\
     :charset=UTF-8:\
     :lang=fr_CH.UTF-8:\
     :lc_all=fr_CH.UTF-8:\
     :lc_collate=fr_CH.UTF-8:\
     :lc_ctype=fr_CH.UTF-8:\
     :lc_messages=fr_CH.UTF-8:\
     :tc=default:
EOF
    cap_mkdb /etc/login.conf
    echo "defaultclass=french" > /etc/adduser.conf
fi

echo "-> Mise à jour des utilisateurs administrateur et root..."
pw usermod administrateur -G wheel,operator,video,cups -L french
pw usermod root -L french

echo "-> Configuration de doas..."
if [ ! -f /usr/local/etc/doas.conf ]; then
    echo "permit persist :wheel" > /usr/local/etc/doas.conf
fi

# ============================================================
# 8. Configuration stricte de X11 (Vidéo et Clavier)
# ============================================================
echo "-> Création du répertoire de configuration Xorg..."
mkdir -p /usr/local/etc/X11/xorg.conf.d

echo "-> Configuration forcée du pilote NVIDIA..."
cat > /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf << 'EOF'
Section "Device"
        Identifier "NVIDIA Quadro"
        Driver "nvidia"
EndSection
EOF

echo "-> Configuration du clavier suisse romand pour X11..."
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << 'EOF'
Section "ServerFlags"
        Option "DontZap" "false"
EndSection

Section "InputClass"
        Identifier "All Keyboards"
        MatchIsKeyboard "yes"
        Option "XkbLayout" "ch"
        Option "XkbVariant" "fr"
        Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

# ============================================================
# 9. Session graphique NsCDE et finalisation
# ============================================================
echo "-> Configuration des variables globales pour NsCDE..."
# Définition des variables globales pour aider NsCDE à détecter les outils
if ! grep -q "EDITOR=geany" /etc/profile; then
    echo 'export EDITOR=geany' >> /etc/profile
    echo 'export VISUAL=geany' >> /etc/profile
fi

echo "-> Configuration de NsCDE pour l'utilisateur administrateur..."
echo "exec nscde" > /home/administrateur/.xsession
echo "exec nscde" > /home/administrateur/.xinitrc
chown administrateur:administrateur /home/administrateur/.xsession /home/administrateur/.xinitrc

# Création du fichier de config SMART
if [ ! -f /usr/local/etc/smartd.conf ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi

echo "============================================================"
echo " Terminé ! Votre Workstation est prête."
echo "============================================================"
echo "Veuillez redémarrer la machine avec la commande 'reboot'."
echo "============================================================"