#!/bin/sh

# --- CONFIGURATION AND VERIFICATION ---
TITLE="FreeBSD 15 Post-Installation (Idempotent)"
BACKTITLE="Workstation Configuration by Gemini"

if ! command -v bsddialog >/dev/null 2>&1; then
    echo "Installing bsddialog..."
    pkg update && pkg install -y bsddialog
fi

# Utility function to add a line to a file if it doesn't already exist
add_line_if_missing() {
    # $1: line to add, $2: file
    grep -qF -- "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

# --- DISCLAIMER AND CREDITS ---
show_disclaimer() {
    local msg="DISCLAIMER OF LIABILITY\n\n\
This script deeply modifies your FreeBSD system configuration. \
It is provided 'as is', without any express or implied warranty. \
By using it, you agree that the author cannot be held responsible \
for any data loss, system breakage, or other damage.\n\n\
ACKNOWLEDGEMENTS\n\n\
A huge thanks to NASA (National Aeronautics and Space Administration) \
for providing their beautiful public domain images, used here to enhance \
the login theme and boot splash screen.\n\n\
Do you accept these conditions to continue?"

    if ! bsddialog --backtitle "$BACKTITLE" --title "Warning & Credits" --yesno "$msg" 18 75; then
        clear
        echo "Installation cancelled by the user. No changes have been made."
        exit 1
    fi
}

# --- FUNCTIONS ---

base_config() {
    bsddialog --infobox "Updating system and applying base configuration..." 5 50
    pkg update -y && pkg install -y sudo
    
    bsddialog --msgbox "Visudo will now open. Please add '%wheel ALL=(ALL:ALL) ALL' if not already done." 8 50
    visudo

    sed -i '' 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    add_line_if_missing "PermitRootLogin yes" /etc/ssh/sshd_config
    service sshd restart
    
    freebsd-update fetch install

    sysrc -f /boot/loader.conf boot_mute=YES splash_changer_enable=YES autoboot_delay=3
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    sysrc rc_startmsgs=NO
    
    add_line_if_missing "kern.sched.preempt_thresh=224" /etc/sysctl.conf
    add_line_if_missing "kern.ipc.shm_allow_removed=1" /etc/sysctl.conf
    sysrc -f /boot/loader.conf tmpfs_load=YES aio_load=YES
    
    sysctl net.local.stream.recvspace=65536 net.local.stream.sendspace=65536
    sysrc linux_enable=YES linux64_enable=YES
    service linux restart 2>/dev/null || service linux start

    pkg install -y doas unzip libzip wget git linux-rl9 htop neofetch python3 bashtop ImageMagick7 smartmontools
    sysrc smartd_enable=YES
    [ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
    service smartd restart 2>/dev/null || service smartd start

    # --- Localization (French/Swiss defaults kept for system logic) ---
    if ! grep -q "french|French Users Accounts" /etc/login.conf; then
        cat >> /etc/login.conf <<EOF

french|French Users Accounts:\\
    :charset=UTF-8:\\
    :lang=fr_FR.UTF-8:\\
    :lc_all=fr_FR:\\
    :lc_collate=fr_FR:\\
    :lc_ctype=fr_FR:\\
    :lc_messages=fr_FR:\\
    :tc=default:
EOF
        cap_mkdb /etc/login.conf
    fi
    echo 'defaultclass=french' > /etc/adduser.conf
    
    USER_NAME=$(bsddialog --inputbox "Local Configuration:\nEnter main user name:" 9 50 3>&1 1>&2 2>&3)
    if [ -n "$USER_NAME" ]; then
        export USER_NAME
        pw usermod "$USER_NAME" -G wheel,operator,video -L french
    fi
    pw usermod root -L french
}

cpu_config() {
    CHOICE=$(bsddialog --menu "Select CPU Type:" 12 50 2 "Intel" "Coretemp/Ucode" "AMD" "Amdtemp/Ucode" 3>&1 1>&2 2>&3)
    case $CHOICE in
        Intel) 
            pkg install -y cpu-microcode sensors
            sysrc -f /boot/loader.conf coretemp_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin" 
            ;;
        AMD) 
            pkg install -y sensors cpu-microcode
            sysrc -f /boot/loader.conf amdtemp_load="YES" 
            sysrc -f /boot/loader.conf cpu_microcode_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin" 
            ;;
    esac
}

hardware_config() {
    bsddialog --infobox "Installing Xorg, Audio, and Peripherals..." 5 50
    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme xorg dbus avahi signal-cli seatd sddm cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
    
    sysrc sound_load="YES" snd_hda_load="YES"
    add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
    sysrc dbus_enable=YES avahi_enable=YES seatd_enable=YES sddm_enable=YES sddm_lang="ch_FR"
    sysrc cupsd_enable=YES devfs_system_ruleset=localrules
    sysrc kld_list+=fusefs kld_list+=ext2fs
    
    add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

    if [ ! -f /etc/devfs.rules ] || ! grep -q "localrules" /etc/devfs.rules; then
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
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF
    fi
    service devfs restart

    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "ch"
    Option "XkbVariant" "fr"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
}

nvidia_config() {
    # Nvidia GPU Auto-Detection
    GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | cut -d "'" -f 2)
    [ -z "$GPU_INFO" ] && GPU_INFO="Unknown or undetected Nvidia GPU"

    # Recommendation Logic
    REC_DRIVER="nvidia-driver"
    
    if echo "$GPU_INFO" | grep -iqE "Quadro P|GTX 10|Pascal"; then
        REC_DRIVER="nvidia-driver-580"
    elif echo "$GPU_INFO" | grep -iqE "Quadro M|GTX 9|GTX 750|Maxwell"; then
        REC_DRIVER="nvidia-driver-470"
    elif echo "$GPU_INFO" | grep -iqE "Quadro K|GTX 7|GTX 6|Kepler"; then
        REC_DRIVER="nvidia-driver-390"
    fi

    CHOICE=$(bsddialog --title "Nvidia Configuration" --menu "Detected GPU: $GPU_INFO\n\nRecommended Driver: $REC_DRIVER\n\nChoose your driver version:" 17 85 5 \
        "nvidia-driver" "Latest (RTX, GTX 16+, Quadro RTX...)" \
        "nvidia-driver-580" "Legacy 580 (Pascal: Quadro P, GTX 10xx)" \
        "nvidia-driver-470" "Legacy 470 (Maxwell: Quadro M, GTX 9xx)" \
        "nvidia-driver-390" "Legacy 390 (Kepler: Quadro K, GTX 7xx)" \
        "Back" "Do not install anything" 3>&1 1>&2 2>&3)

    case $CHOICE in
        "nvidia-driver"|"nvidia-driver-580"|"nvidia-driver-470"|"nvidia-driver-390")
            DRIVER_PKG="$CHOICE"
            ;;
        *) return ;;
    esac

    # Dynamic adaptation of associated Linux libraries
    if [ "$DRIVER_PKG" = "nvidia-driver" ]; then
        LINUX_LIBS="linux-nvidia-libs"
    else
        SUFFIX=$(echo "$DRIVER_PKG" | cut -d'-' -f3)
        LINUX_LIBS="linux-nvidia-libs-${SUFFIX}"
    fi

    bsddialog --infobox "Installing $DRIVER_PKG and $LINUX_LIBS..." 5 50
    pkg install -y "$DRIVER_PKG" "$LINUX_LIBS" libc6-shim nvidia-settings nvidia-xconfig
    
    if ! sysrc -n kld_list | grep -q "nvidia-modeset"; then
        sysrc kld_list+="nvidia-modeset"
    fi
    sysrc nvidia_modeset_enable="YES"
    
    add_line_if_missing "hw.nvidiadrm.modeset=\"1\"" /boot/loader.conf
    add_line_if_missing "nvidia-drm.modeset=\"1\"" /boot/loader.conf
    add_line_if_missing "hw.nvidia.registry.EnableGpuFirmware=\"1\"" /boot/loader.conf
    
    nvidia-xconfig
    bsddialog --msgbox "Nvidia drivers configured successfully!" 6 60
}

amd_config() {
    # AMD/ATI GPU Auto-Detection
    GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*AMD\|ATI" | grep "device.*=" | cut -d "'" -f 2 | head -n 1)
    [ -z "$GPU_INFO" ] && GPU_INFO="Unknown or undetected AMD GPU"

    # Recommendation Logic
    REC_DRIVER="amdgpu" 
    
    if echo "$GPU_INFO" | grep -iqE "Radeon HD|Radeon R[579]|FirePro|Mobility Radeon"; then
        REC_DRIVER="radeonkms"
    fi

    CHOICE=$(bsddialog --title "AMD Configuration" --menu "Detected GPU: $GPU_INFO\n\nRecommended Driver: $REC_DRIVER\n\nChoose your driver:" 16 85 3 \
        "amdgpu" "Modern cards (RX 400+, Ryzen APU, Vega, Navi)" \
        "radeonkms" "Legacy cards (Radeon HD, R5/R7/R9 pre-GCN3)" \
        "Back" "Do not install anything" 3>&1 1>&2 2>&3)

    case $CHOICE in
        "amdgpu"|"radeonkms")
            DRIVER_PKG="$CHOICE"
            ;;
        *) return ;;
    esac

    bsddialog --infobox "Installing DRM packages, Wayland, and Xwayland..." 5 50
    pkg install -y wayland xwayland drm-kmod
    
    if ! sysrc -n kld_list | grep -q "$DRIVER_PKG"; then
        sysrc kld_list+="$DRIVER_PKG"
    fi
    
    bsddialog --msgbox "AMD Graphics Driver ($DRIVER_PKG) configured successfully!" 6 60
}

plasma_config() {
    bsddialog --infobox "Installing Plasma 6 (KDE)..." 5 50
    pkg install -y --g "plasma6-*" "kf6*"
    pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum
}

mate_config() {
    bsddialog --infobox "Installing MATE Desktop..." 5 50
    pkg install -y mate mate-desktop octopkg
}

samba_config() {
    pkg install -y samba416
    mkdir -p /home/share && chmod 777 /home/share
    if [ ! -f /usr/local/etc/smb4.conf ]; then
        cat > /usr/local/etc/smb4.conf <<EOF
[global]
    workgroup = HOMELAB
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    guest ok = yes
EOF
    fi
    sysrc samba_server_enable="YES"
    service samba_server restart 2>/dev/null || service samba_server start
}

xrdp_config() {
    pkg install -y xrdp xorgxrdp
    sysrc xrdp_enable="YES" xrdp_sesman_enable="YES"
    [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ] && mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup
    echo 'export LANG=fr_FR.UTF-8' > /usr/local/etc/xrdp/startwm.sh
    # Uncomment the line below and comment startplasma-x11 if you prefer to launch MATE remotely
    # echo 'exec mate-session' >> /usr/local/etc/xrdp/startwm.sh
    echo 'exec startplasma-x11' >> /usr/local/etc/xrdp/startwm.sh
    chmod 555 /usr/local/etc/xrdp/startwm.sh
}

vbox_config() {
    pkg install -y virtualbox-ose-72
    sysrc -f /boot/loader.conf vboxdrv_load="YES" vboxnet_load="YES"
    sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root
    [ -n "$USER_NAME" ] && pw groupmod vboxusers -m "$USER_NAME"
    add_line_if_missing 'own     vboxnetctl root:vboxusers' /etc/devfs.conf
    add_line_if_missing 'perm    vboxnetctl 0660' /etc/devfs.conf
}

nasa_theme() {
    [ -d /tmp/fb14_assets ] && rm -rf /tmp/fb14_assets
    git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14_assets
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp -r /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
    
    cat > /usr/local/etc/sddm.conf <<EOF
[Theme]
Current=nasa
EOF
    
    # Force overwrite boot menu logos
    mkdir -p /boot/images
    cp -f /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/freebsd-brand-rev.png
    cp -f /tmp/fb14_assets/freebsd-logo-rev.png /boot/images/freebsd-logo-rev.png
    
    # Splash screen
    cp -f /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
}

apps_config() {
    pkg install -y firefox chromium thunderbird vlc ffmpeg kdenlive webcamd win98se-icon-theme ImageMagick7
    pkg install -y cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
    sysrc webcamd_enable=YES
}

switch_latest() {
    sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf
    pkg update -f && pkg upgrade -y
}

# --- SCRIPT START ---

show_disclaimer

# --- MAIN MENU ---
while true; do
    MAIN_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "$TITLE" \
        --menu "Post-Installation Menu:" 22 85 13 \
        "1" "Base Config & Locales (SSH, Boot, Linux, User)" \
        "2" "CPU Management (Intel/AMD)" \
        "3" "Hardware Base (Audio, Xorg, USB, CUPS)" \
        "4" "GPU: NVIDIA (Auto-Detect)" \
        "5" "GPU: AMD / Radeon (Auto-Detect)" \
        "6" "Desktop (Plasma 6)" \
        "7" "Desktop (MATE)" \
        "8" "Samba Server" \
        "9" "XRDP Remote Desktop" \
        "10" "VirtualBox 7.2" \
        "11" "Applications & Fonts" \
        "12" "NASA Theme" \
        "13" "Upgrade to LATEST Branch" \
        "Q" "Quit" 3>&1 1>&2 2>&3)

    case $MAIN_CHOICE in
        1) base_config ;;
        2) cpu_config ;;
        3) hardware_config ;;
        4) nvidia_config ;;
        5) amd_config ;;
        6) plasma_config ;;
        7) mate_config ;;
        8) samba_config ;;
        9) xrdp_config ;;
        10) vbox_config ;;
        11) apps_config ;;
        12) nasa_theme ;;
        13) switch_latest ;;
        Q|q|*) break ;;
    esac
done
clear
echo "Script completed. A system reboot is highly recommended to apply all changes."
