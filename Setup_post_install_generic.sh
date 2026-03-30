#!/bin/sh

# ==============================================================================
# SCRIPT DE POST-INSTALLATION FREEBSD 15
# Version: 3.6 - Création utilisateur (Login, Nom, Pass) + CPU/GPU
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

pkg install -y bsddialog > /dev/null 2>&1

# 1. GESTION DE L'UTILISATEUR
TYPE_USER=$(bsddialog --title "Gestion Utilisateur" \
    --menu "Choisissez une option :" 15 60 2 \
    "NEW" "Créer un nouvel utilisateur complet" \
    "EXISTING" "Utiliser un utilisateur existant" 3>&1 1>&2 2>&3)

case $TYPE_USER in
    "NEW")
        USER_NAME=$(bsddialog --title "Nouvel Utilisateur" --inputbox "Nom de login (ex: jdoe) :" 10 50 3>&1 1>&2 2>&3)
        [ -z "$USER_NAME" ] && exit 1
        
        REAL_NAME=$(bsddialog --title "Nom Réel" --inputbox "Nom complet (ex: John Doe) :" 10 50 3>&1 1>&2 2>&3)
        
        # Saisie du mot de passe (cachée)
        USER_PASS=$(bsddialog --title "Mot de passe" --passwordbox "Entrez le mot de passe :" 10 50 3>&1 1>&2 2>&3)
        
        # Création technique de l'utilisateur
        # -c : commentaire (nom réel) | -m : crée le home | -h 0 : lit le pass sur stdin
        echo "$USER_PASS" | pw useradd "$USER_NAME" -m -G wheel,operator,video -s /bin/sh -c "$REAL_NAME" -h 0
        
        bsddialog --msgbox "Utilisateur $USER_NAME ($REAL_NAME) créé avec succès." 10 50
        ;;
    "EXISTING")
        USER_NAME=$(bsddialog --title "Utilisateur Existant" --inputbox "Nom de l'utilisateur à configurer :" 10 50 3>&1 1>&2 2>&3)
        [ -z "$USER_NAME" ] && exit 1
        pw usermod "$USER_NAME" -G wheel,operator,video 2>/dev/null
        ;;
    *) exit 1 ;;
esac

# 2. SÉLECTION DU PROCESSEUR
CHOIX_CPU=$(bsddialog --title "Type de Processeur" \
    --menu "Sélectionnez votre CPU :" 15 60 2 \
    "AMD" "Processeur AMD (amdtemp + amd-ucode)" \
    "INTEL" "Processeur Intel (coretemp + intel-ucode)" 3>&1 1>&2 2>&3)

# 3. SÉLECTION DU GPU
CHOIX_GPU=$(bsddialog --title "Configuration Vidéo" \
    --menu "Choisissez votre matériel graphique :" 15 60 2 \
    "AMD" "Support Wayland & X11 (amdgpu)" \
    "NVIDIA" "Support X11 uniquement (pilote propriétaire)" 3>&1 1>&2 2>&3)

# --- FONCTIONS ---
add_to_loader() { grep -q "$1" /boot/loader.conf || echo "$1" >> /boot/loader.conf; }
add_to_sysctl() { grep -q "$1" /etc/sysctl.conf || echo "$1" >> /etc/sysctl.conf; }

# 4. Réseau & Dépôts
sed -i '' -e 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf
pkg update -f && pkg upgrade -y
pkg install -y realtek-re-kmod
sysrc kld_list+="if_re"

# 5. CONFIGURATION CPU
case $CHOIX_CPU in
    "AMD")
        pkg install -y cpu-microcode-amd
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        add_to_loader 'cpu_microcode_load="YES"'
        add_to_loader 'cpu_microcode_name="/boot/firmware/amd-ucode.bin"'
        ;;
    "INTEL")
        pkg install -y cpu-microcode-intel
        sysrc -f /boot/loader.conf coretemp_load="YES"
        add_to_loader 'cpu_microcode_load="YES"'
        add_to_loader 'cpu_microcode_name="/boot/firmware/intel-ucode.bin"'
        ;;
esac

# 6. CLAVIER CH-FR
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboard.conf <<EOF
Section "InputClass"
    Identifier "KeyboardDefaults"
    MatchIsKeyboard "on"
    Option "XkbLayout" "ch"
    Option "XkbVariant" "fr"
EndSection
EOF

# 7. Localisation & Logiciels
if ! grep -q "french" /etc/login.conf; then
    cat >> /etc/login.conf <<EOF
french|French Users Accounts:\\
    :charset=UTF-8:\\
    :lang=fr_FR.UTF-8:\\
    :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
echo 'defaultclass=french' > /etc/adduser.conf
pw usermod "$USER_NAME" -L french

pkg install -y xorg dbus avahi-app seatd sddm plasma6-plasma
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc sddm_lang="fr_CH.UTF-8"
pkg install -y firefox vlc ffmpeg libva-utils pavucontrol kate konsole dolphin

# 8. Logique GPU
case $CHOIX_GPU in
    "AMD")
        pkg install -y drm-kmod wayland xwayland wayfire wf-shell
        sysrc kld_list+="amdgpu"
        USER_HOME="/home/$USER_NAME"
        if [ -d "$USER_HOME" ]; then
            mkdir -p "$USER_HOME/.config/wayfire"
            cp /usr/local/share/examples/wayfire/wayfire.ini "$USER_HOME/.config/wayfire/"
            cat >> "$USER_HOME/.config/wayfire/wayfire.ini" <<EOF
[input]
xkb_layout = ch
xkb_variant = fr
[core]
xwayland = true
EOF
            chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"
        fi
        ;;
    "NVIDIA")
        pkg install -y nvidia-driver nvidia-settings nvidia-xconfig
        sysrc kld_list+="nvidia-modeset"
        nvidia-xconfig
        ;;
esac

# 9. SAMBA
pkg install -y samba416
mkdir -p /home/share && chmod 777 /home/share
cat > /usr/local/etc/smb4.conf <<EOF
[global]
    unix charset = UTF-8
    workgroup = MAISON
    interfaces = 127.0.0.1 192.168.1.0/24
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    guest ok = yes
    guest only = yes
    force create mode = 777
    force directory mode = 777
EOF
sysrc samba_server_enable="YES"

# 10. VirtualBox
pkg install -y virtualbox-ose-72
add_to_loader 'vboxdrv_load="YES"'
pw groupmod vboxusers -m "$USER_NAME" 2>/dev/null || true

bsddialog --msgbox "Post-installation terminée !\nUtilisateur : $USER_NAME ($REAL_NAME)\nClavier : Suisse Romand\nRedémarrez le système." 15 60