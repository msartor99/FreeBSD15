#!/bin/sh

# ==============================================================================
# Fichier : bootstrap-workstation-v1.15.sh
# Version : 1.15
# Date    : Octobre 2026
# Rôle    : Script de post-installation pour station de travail FreeBSD (amd64)
# Notes   : Correction des noms de paquets (plasma6-plasma)
# ==============================================================================

set -e # Arrêt du script en cas d'erreur non gérée

TMP_DIALOG=$(mktemp -t bsddialog)
trap 'rm -f $TMP_DIALOG' EXIT INT TERM HUP

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Erreur : Ce script doit être exécuté en tant que root."
        exit 1
    fi
}

interactive_config() {
    if ! bsddialog --title "DISCLAIMER - Bootstrap FreeBSD" \
        --yesno "Ce script va configurer l'environnement de bureau, les pilotes GPU, le tuning système, les périphériques et les applications.\n\nÊtes-vous sûr de vouloir continuer ?" 10 70; then
        clear; echo "Annulé."; exit 0
    fi

    if ! bsddialog --title "Configuration de l'utilisateur" \
        --inputbox "Saisissez le nom de l'utilisateur principal :" 10 60 "administrateur" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    TARGET_USER=$(cat "$TMP_DIALOG")
    [ -z "$TARGET_USER" ] && { clear; echo "Erreur : nom vide."; exit 1; }

    if ! bsddialog --title "Langue du système" \
        --menu "Choisissez la langue :" 15 50 5 \
        "fr" "Français" "en" "English" "de" "Deutsch" "it" "Italiano" "pt" "Português" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    LANG_CHOICE=$(cat "$TMP_DIALOG")

    if ! bsddialog --title "Disposition du clavier" \
        --menu "Choisissez le clavier :" 15 50 6 \
        "ch" "Suisse Romand" "fr" "Français" "us" "Anglais" "de" "Allemand" "it" "Italien" "pt" "Portugais" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    KBD_CHOICE=$(cat "$TMP_DIALOG")

    if ! bsddialog --title "Environnement de Bureau" \
        --menu "Choisissez votre gestionnaire :" 15 55 5 \
        "xfce4" "XFCE 4" "plasma6" "KDE Plasma 6" "gnome" "GNOME" "mate" "MATE" "cinnamon" "Cinnamon" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    DE_CHOICE=$(cat "$TMP_DIALOG")
    
    case "$DE_CHOICE" in
        xfce4) DE_PKGS="xfce" ;;
        # CORRECTION : plasma6-plasma est le nom officiel FreeBSD
        plasma6) DE_PKGS="plasma6-plasma kde" ;; 
        gnome) DE_PKGS="gnome" ;;
        mate) DE_PKGS="mate" ;;
        cinnamon) DE_PKGS="cinnamon" ;;
    esac

    if ! bsddialog --title "Applications Supplémentaires" \
        --checklist "Sélectionnez les applications :" 18 70 8 \
        "firefox" "Navigateur Web" on \
        "thunderbird" "Client Mail" off \
        "vlc" "Lecteur Vidéo" on \
        "gimp" "Éditeur d'images" off \
        "libreoffice" "Suite Bureautique" off \
        "themes" "Polices Emojis et Thèmes (Esthétique)" on \
        "samba" "Serveur Samba (Partage de fichiers)" off \
        "virtualbox" "VirtualBox (Virtualisation)" off 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    
    APP_CHOICES=$(tr -d '"' < "$TMP_DIALOG")
    APP_PKGS=""
    INSTALL_SAMBA=0
    INSTALL_VBOX=0
    
    for app in $APP_CHOICES; do
        case "$app" in
            firefox) APP_PKGS="$APP_PKGS firefox" ;;
            thunderbird) APP_PKGS="$APP_PKGS thunderbird" ;;
            vlc) APP_PKGS="$APP_PKGS vlc" ;;
            gimp) APP_PKGS="$APP_PKGS gimp" ;;
            libreoffice) APP_PKGS="$APP_PKGS libreoffice" ;;
            themes) APP_PKGS="$APP_PKGS twemoji-color-font-ttf noto-emoji ibus-uniemoji papirus-icon-theme cursor-neutral-white-theme qogir-icon-themes win98se-icon-theme" ;;
            samba) APP_PKGS="$APP_PKGS samba420"; INSTALL_SAMBA=1 ;;
            virtualbox) APP_PKGS="$APP_PKGS virtualbox-ose"; INSTALL_VBOX=1 ;;
        esac
    done

    if bsddialog --title "Configuration Réseau" \
        --yesno "Voulez-vous vérifier vos interfaces réseau via bsdconfig ?" 10 65; then
        clear; bsdconfig networking
    fi

    if ! bsddialog --title "Carte Graphique" \
        --menu "Constructeur :" 15 50 3 "intel" "Intel" "amd" "AMD" "nvidia" "NVIDIA" 2> "$TMP_DIALOG"; then
        clear; exit 0
    fi
    GPU_CHOICE=$(cat "$TMP_DIALOG")

    GPU_PKGS=""
    HYBRID_INTEL=0
    if [ "$GPU_CHOICE" = "nvidia" ]; then
        if ! bsddialog --title "Pilotes NVIDIA" \
            --menu "Version :" 15 60 4 "latest" "Récents (Défaut)" "580" "Br. 580" "550" "Br. 550" "470" "Br. 470 (Legacy)" 2> "$TMP_DIALOG"; then
            clear; exit 0
        fi
        NVIDIA_VERSION=$(cat "$TMP_DIALOG")
        case "$NVIDIA_VERSION" in
            latest) GPU_PKGS="nvidia-driver nvidia-settings linux_base-rl9 linux-nvidia-libs" ;;
            *) GPU_PKGS="nvidia-driver-${NVIDIA_VERSION} nvidia-settings linux_base-rl9 linux-nvidia-libs-${NVIDIA_VERSION}" ;;
        esac

        if bsddialog --title "Configuration Hybride (NVIDIA + Intel)" \
            --yesno "Votre PC possède-t-il également une carte graphique Intel intégrée au CPU (ex: configuration hybride comme sur le HP Z2 mini G5) ?" 10 70; then
            HYBRID_INTEL=1
            GPU_PKGS="$GPU_PKGS drm-kmod"
        fi
    else
        GPU_PKGS="drm-kmod"
    fi

    if ! pw usershow "$TARGET_USER" >/dev/null 2>&1; then
        bsddialog --title "Création d'utilisateur" \
            --msgbox "Utilisateur introuvable. 'adduser' va être lancé pour '$TARGET_USER'." 10 60
        clear; adduser
        ! pw usershow "$TARGET_USER" >/dev/null 2>&1 && { echo "Erreur fatale : Utilisateur non créé."; exit 1; }
    fi
    clear
}

configure_tuning() {
    echo ">>> Optimisations sysctl et loader.conf..."
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
    echo ">>> Configuration CPU (Microcode et sondes)..."
    pkg install -y cpu-microcode smartmontools
    sysrc smartd_enable="YES"
    [ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf

    if sysctl hw.model | grep -iq "intel"; then
        sysrc -f /boot/loader.conf coretemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    elif sysctl hw.model | grep -iq "amd"; then
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    fi
}

enable_linux_compat() {
    echo ">>> Activation Linux dans le noyau..."
    sysrc -v linux_enable="YES"
    sysrc -v linux64_enable="YES"
    sysrc -v linux_mounts_enable="YES"
    kldstat -q -m linux64 || kldload linux64 || true
}

init_pkg() {
    env ASSUME_ALWAYS_YES=YES pkg bootstrap
    pkg update
}

install_packages() {
    echo ">>> Installation des paquets..."
    pkg install -y \
        doas unzip libzip wget git htop fastfetch python3 bashtop \
        seatd dbus avahi signal-cli \
        xorg sddm \
        pulseaudio pipewire wireplumber audio/freedesktop-sound-theme \
        $DE_PKGS $GPU_PKGS $APP_PKGS \
        ffmpeg libva-vdpau-driver libva-utils libdvdread libdvdnav \
        eom remmina xdg-user-dirs octopkg chromium mpv \
        gstreamer1-plugins-all gstreamer1-libav libbluray \
        cantarell-fonts droid-fonts-ttf inconsolata-ttf noto noto-emoji roboto-fonts-ttf ubuntu-font
}

configure_peripherals() {
    echo ">>> Configuration périphériques (CUPS, Devfs, USB, Webcam)..."
    pkg install -y cups gutenprint cups-filters hplip system-config-printer \
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
    echo ">>> Configuration des locales et du clavier..."
    
    case "$LANG_CHOICE" in
        fr) SYS_LANG="fr_FR.UTF-8" ;;
        en) SYS_LANG="en_US.UTF-8" ;;
        de) SYS_LANG="de_DE.UTF-8" ;;
        it) SYS_LANG="it_IT.UTF-8" ;;
        pt) SYS_LANG="pt_PT.UTF-8" ;;
    esac

    if ! grep -q "^desktop|" /etc/login.conf; then
        cat >> /etc/login.conf <<EOF

desktop|Desktop Users Accounts:\
     :charset=UTF-8:\
     :lang=${SYS_LANG}:\
     :tc=default:
EOF
        cap_mkdb /etc/login.conf
    fi
    grep -q "defaultclass=desktop" /etc/adduser.conf || echo 'defaultclass=desktop' >> /etc/adduser.conf

    USER_PROFILE="/home/$TARGET_USER/.profile"
    if ! grep -q "LANG=" "$USER_PROFILE" 2>/dev/null; then
        echo "export LANG=$SYS_LANG" >> "$USER_PROFILE"
        echo "export LC_ALL=$SYS_LANG" >> "$USER_PROFILE"
        chown "$TARGET_USER:$TARGET_USER" "$USER_PROFILE"
    fi

    KBD_VARIANT=""
    case "$KBD_CHOICE" in
        ch) X_LAYOUT="ch"; KBD_VARIANT="fr" ;;
        fr) X_LAYOUT="fr" ;;
        us) X_LAYOUT="us" ;;
        de) X_LAYOUT="de" ;;
        it) X_LAYOUT="it" ;;
        pt) X_LAYOUT="pt" ;;
    esac

    mkdir -p /usr/local/etc/X11/xorg.conf.d
    cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
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

configure_sddm() {
    mkdir -p /usr/local/etc
    SDDM_CONF="/usr/local/etc/sddm.conf"
    
    if ! grep -q "^\[Theme\]" "$SDDM_CONF" 2>/dev/null; then
        echo -e "\n[Theme]\nCurrent=maldives" >> "$SDDM_CONF"
    else
        sed -i '' 's/^Current=.*/Current=maldives/' "$SDDM_CONF"
    fi

    XSETUP="/usr/local/share/sddm/scripts/Xsetup"
    if [ -f "$XSETUP" ]; then
        if ! grep -q "setxkbmap" "$XSETUP"; then
            [ -n "$KBD_VARIANT" ] && echo "setxkbmap -layout $X_LAYOUT -variant $KBD_VARIANT" >> "$XSETUP" || echo "setxkbmap -layout $X_LAYOUT" >> "$XSETUP"
        fi
    fi
}

configure_gpu() {
    echo ">>> Configuration du chargement des pilotes graphiques..."
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
            fi
            case "$CURRENT_KLD" in *nvidia-modeset*) ;; *) sysrc -v kld_list+="nvidia-modeset" ;; esac 
            sysctl hw.snd.default_unit=1 || true
            ;;
    esac
}

configure_samba() {
    if [ "$INSTALL_SAMBA" -eq 1 ]; then
        echo ">>> Configuration du serveur Samba..."
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
        echo ">>> Configuration de VirtualBox..."
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
    sysrc -v avahi_enable="YES"
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
    if [ ! -f /boot/images/splash.png ]; then
        echo ">>> Téléchargement et configuration du Splash Screen..."
        pkg install -y ImageMagick7 wget
        mkdir -p /boot/images
        
        cd /tmp
        wget -qO v2.png https://kamila.is/media/v2.png || true
        if [ -f v2.png ]; then
            magick convert v2.png -resize 1920x1080 v2hd.png
            cp v2hd.png /boot/images/splash.png
            sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
            sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
            sysrc splash_changer_enable="YES"
        fi
        cd - >/dev/null
    fi
}

main() {
    check_root
    interactive_config
    
    echo "=== Début du bootstrap FreeBSD (v1.15) ==="
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
    
    echo "=== Bootstrap terminé avec succès ==="
    echo "Redémarrez le système pour appliquer les nouveautés du noyau."
}

main "$@"