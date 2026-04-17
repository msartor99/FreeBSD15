#!/bin/sh

# --- CONFIGURATION AND VERIFICATION ---
TITLE="FreeBSD 15 Post-Installation (Idempotent) - Multi-Hardware"
BACKTITLE="Workstation Configuration by Gemini"
DB_PREFIX="/var/db/.fbsd_setup_done_"

if ! command -v bsddialog >/dev/null 2>&1; then
    echo "Installing bsddialog..."
    pkg update && pkg install -y bsddialog
fi

# Utility function to add a line to a file only if it doesn't already exist
add_line_if_missing() {
    grep -qF -- "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

# Check if running inside a VirtualBox VM
is_vbox_guest() {
    kenv smbios.system.product | grep -iq "VirtualBox"
}

# --- TRACKING FUNCTIONS (Persistent) ---
mark_done() {
    local OPTION_UPPER=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    touch "${DB_PREFIX}${OPTION_UPPER}"
    bsddialog --msgbox "OK: Option ${OPTION_UPPER} completed successfully!" 6 45
}

get_label() {
    local OPTION_UPPER=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    if [ -f "${DB_PREFIX}${OPTION_UPPER}" ]; then
        echo "$2 [DONE]"
    else
        echo "$2"
    fi
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
for providing their beautiful public domain images, \
used here to enhance the login theme and the boot splash screen.\n\n\
Do you accept these conditions to continue?"

    if ! bsddialog --backtitle "$BACKTITLE" --title "Warning & Credits" --yesno "$msg" 18 75; then
        clear
        echo "Installation cancelled."
        exit 1
    fi
}

# --- FUSED INITIAL SETUP (Option 1) ---

initial_setup() {
    bsddialog --infobox "Starting System, Hardware Monitoring & Base Setup..." 5 60
    
    # 1. Base System & Vital Packages
    pkg update -y
    
    # Explicit Sudo verification
    if ! command -v sudo >/dev/null 2>&1; then
        bsddialog --infobox "Installing sudo..." 5 40
        pkg install -y sudo
    fi
    
    pkg install -y doas unzip libzip wget git linux-rl9 htop neofetch python3 bashtop smartmontools ipmitool nvme-cli btop pciutils

    sed -i '' 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    add_line_if_missing "PermitRootLogin yes" /etc/ssh/sshd_config
    service sshd restart
    freebsd-update fetch install

    # Boot & Kernel Tuning
    sysrc -f /boot/loader.conf boot_mute=YES splash_changer_enable=YES autoboot_delay=3
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    sysrc rc_startmsgs=NO
    add_line_if_missing "kern.sched.preempt_thresh=224" /etc/sysctl.conf
    add_line_if_missing "kern.ipc.shm_allow_removed=1" /etc/sysctl.conf
    sysctl net.local.stream.recvspace=65536 net.local.stream.sendspace=65536
    sysrc -f /boot/loader.conf tmpfs_load=YES aio_load=YES nvme_load=YES
    
    # Linux Compat & Services
    sysrc linux_enable=YES linux64_enable=YES
    service linux restart 2>/dev/null || service linux start

    sysrc smartd_enable=YES
    [ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
    service smartd restart 2>/dev/null || service smartd start

    # 2. CPU Management & Power/Sensor Configuration
    CPU_TYPE=$(bsddialog --menu "Select CPU Type & Energy Management:" 13 70 2 \
        "Intel" "Intel Ucode, Coretemp, IPMI & SMBus" \
        "AMD" "AMD Ucode, Amdtemp, IPMI & SMBus (Lenovo P620)" 3>&1 1>&2 2>&3)
        
    case $CPU_TYPE in
        Intel) 
            pkg install -y cpu-microcode sensors
            sysrc -f /boot/loader.conf coretemp_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
            
            # Specific Workstation Power & Monitoring modules for Intel
            sysrc -f /boot/loader.conf ipmi_load="YES"
            sysrc -f /boot/loader.conf intsmb_load="YES"
            sysrc -f /boot/loader.conf ichsmb_load="YES"
            
            # Devfs rules for NVMe AND IPMI sensors so KDE/btop can read them
            if ! grep -q "localrules" /etc/devfs.rules 2>/dev/null; then
                cat >> /etc/devfs.rules <<EOF
[localrules=10]
add path 'nvme*' mode 0660 group operator
add path 'nvd*' mode 0660 group operator
add path 'da*' mode 0660 group operator
add path 'ada*' mode 0660 group operator
add path 'ipmi0' mode 0660 group operator
EOF
            fi
            sysrc devfs_system_ruleset="localrules"
            service devfs restart
            ;;
        AMD) 
            pkg install -y sensors cpu-microcode
            sysrc -f /boot/loader.conf amdtemp_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
            
            # Specific Workstation/P620 Power & Monitoring modules
            sysrc -f /boot/loader.conf ipmi_load="YES"
            sysrc -f /boot/loader.conf amdsmb_load="YES"
            
            # Devfs rules for NVMe AND IPMI sensors so KDE/btop can read them
            if ! grep -q "localrules" /etc/devfs.rules 2>/dev/null; then
                cat >> /etc/devfs.rules <<EOF
[localrules=10]
add path 'nvme*' mode 0660 group operator
add path 'nvd*' mode 0660 group operator
add path 'da*' mode 0660 group operator
add path 'ada*' mode 0660 group operator
add path 'ipmi0' mode 0660 group operator
EOF
            fi
            sysrc devfs_system_ruleset="localrules"
            service devfs restart
            ;;
    esac

    # 3. Hardware Base
    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme xorg dbus avahi signal-cli seatd sddm cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
    sysrc sound_load="YES" snd_hda_load="YES"
    add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
    sysrc dbus_enable=YES avahi_enable=YES seatd_enable=YES sddm_enable=YES
    sysrc cupsd_enable=YES devfs_system_ruleset=localrules
    sysrc kld_list+=fusefs kld_list+=ext2fs
    add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

    # 4. Localization & Keyboard Menu (Idempotent)
    clean_locales() {
        if [ -f /etc/login.conf ]; then
            sed -i '' '/french|French Users Accounts:/,/:tc=default:/d' /etc/login.conf
            sed -i '' '/custom_locale|Custom Users Accounts:/,/:tc=default:/d' /etc/login.conf
            cap_mkdb /etc/login.conf
        fi
        rm -f /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
    }

    LOC_CHOICE=$(bsddialog --menu "Select System Language & Keyboard:" 14 65 3 \
        "English" "Default English (US Keyboard)" \
        "Swiss_French" "Swiss French Locales (CH/FR Keyboard)" \
        "Custom" "Define custom Country and Keyboard" 3>&1 1>&2 2>&3)

    clean_locales
    mkdir -p /usr/local/etc/X11/xorg.conf.d/

    case $LOC_CHOICE in
        English)
            echo 'defaultclass=default' > /etc/adduser.conf
            USER_CLASS="default"
            sysrc sddm_lang="en_US"
            
            cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "us"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
            ;;
        Swiss_French)
            cat >> /etc/login.conf <<EOF

french|French Users Accounts:\\
    :charset=UTF-8:\\
    :lang=fr_CH.UTF-8:\\
    :lc_all=fr_CH.UTF-8:\\
    :lc_collate=fr_CH.UTF-8:\\
    :lc_ctype=fr_CH.UTF-8:\\
    :lc_messages=fr_CH.UTF-8:\\
    :tc=default:
EOF
            cap_mkdb /etc/login.conf
            echo 'defaultclass=french' > /etc/adduser.conf
            USER_CLASS="french"
            sysrc sddm_lang="fr_CH"

            cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
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
            ;;
        Custom)
            CUSTOM_LANG=$(bsddialog --inputbox "Enter System Locale (e.g., de_DE.UTF-8, es_ES.UTF-8):" 9 55 "en_US.UTF-8" 3>&1 1>&2 2>&3)
            CUSTOM_KBD=$(bsddialog --inputbox "Enter Keyboard Layout Code (e.g., de, es, gb, fr):" 9 55 "us" 3>&1 1>&2 2>&3)
            CUSTOM_VAR=$(bsddialog --inputbox "Enter Keyboard Variant (leave empty if none, e.g., mac, nodeadkeys):" 9 55 "" 3>&1 1>&2 2>&3)
            
            [ -z "$CUSTOM_LANG" ] && CUSTOM_LANG="en_US.UTF-8"
            [ -z "$CUSTOM_KBD" ] && CUSTOM_KBD="us"

            cat >> /etc/login.conf <<EOF

custom_locale|Custom Users Accounts:\\
    :charset=UTF-8:\\
    :lang=${CUSTOM_LANG}:\\
    :lc_all=${CUSTOM_LANG}:\\
    :lc_collate=${CUSTOM_LANG}:\\
    :lc_ctype=${CUSTOM_LANG}:\\
    :lc_messages=${CUSTOM_LANG}:\\
    :tc=default:
EOF
            cap_mkdb /etc/login.conf
            echo 'defaultclass=custom_locale' > /etc/adduser.conf
            USER_CLASS="custom_locale"
            
            # Format SDDM lang (remove .UTF-8)
            SDDM_L=$(echo "$CUSTOM_LANG" | cut -d'.' -f1)
            sysrc sddm_lang="$SDDM_L"

            if [ -n "$CUSTOM_VAR" ]; then
                VAR_STR="Option \"XkbVariant\" \"$CUSTOM_VAR\""
            else
                VAR_STR=""
            fi

            cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "$CUSTOM_KBD"
    $VAR_STR
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
            ;;
    esac

    # User creation/modification
    USER_NAME=$(bsddialog --inputbox "User Configuration:\nEnter main user name:" 9 50 3>&1 1>&2 2>&3)
    if [ -n "$USER_NAME" ]; then
        export USER_NAME
        pw usermod "$USER_NAME" -G wheel,operator,video -L "$USER_CLASS"
    fi
    pw usermod root -L "$USER_CLASS"
    mark_done "1"
}

# --- RESOLUTION SETTING FUNCTION ---
set_monitor_resolution() {
    RES_CHOICE=$(bsddialog --title "Display Resolution" --menu "Select base resolution for SDDM/X11:\n(Useful to avoid tiny text on 27-inch 4K monitors)" 15 75 3 \
        "Native" "Maximum Monitor Capability (Default)" \
        "2560x1440" "Force 2560x1440 (Better text size for 27\" 4K)" \
        "1920x1080" "Force 1920x1080 (Standard Full HD)" 3>&1 1>&2 2>&3)

    mkdir -p /usr/local/share/sddm/scripts/
    
    if [ "$RES_CHOICE" = "2560x1440" ] || [ "$RES_CHOICE" = "1920x1080" ]; then
        # Force SDDM Login screen resolution
        cat > /usr/local/share/sddm/scripts/Xsetup <<EOF
#!/bin/sh
# Auto-detect connected output and force resolution
OUTPUT=\$(xrandr | grep " connected" | awk '{print \$1}' | head -n 1)
if [ -n "\$OUTPUT" ]; then
    xrandr --output "\$OUTPUT" --mode $RES_CHOICE
fi
EOF
        chmod +x /usr/local/share/sddm/scripts/Xsetup
        
        # Force KDE X11 User Session resolution
        mkdir -p /usr/local/etc/xdg/autostart/
        cat > /usr/local/etc/xdg/autostart/force-resolution.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Force Resolution
Exec=sh -c "OUTPUT=\$(xrandr | grep ' connected' | awk '{print \$1}' | head -n 1); xrandr --output \$OUTPUT --mode $RES_CHOICE"
X-KDE-autostart-phase=1
EOF
        bsddialog --infobox "Resolution will be forced to $RES_CHOICE via xrandr." 4 60
        sleep 2
    else
        # Native: Clean up scripts if they existed
        rm -f /usr/local/share/sddm/scripts/Xsetup 2>/dev/null
        rm -f /usr/local/etc/xdg/autostart/force-resolution.desktop 2>/dev/null
    fi
}

# --- GPU CONFIGURATIONS ---

nvidia_config() {
    # Extraction propre du nom de la carte (entre les crochets) pour un affichage net
    GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | grep -o '\[.*\]' | tr -d '[]')
    
    # Fallback au cas où les crochets ne sont pas présents dans la sortie pciconf
    if [ -z "$GPU_INFO" ]; then
        GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | cut -d "'" -f 2)
    fi
    [ -z "$GPU_INFO" ] && GPU_INFO="Unknown Nvidia GPU"
    
    REC_DRIVER="nvidia-driver"
    if echo "$GPU_INFO" | grep -iqE "Quadro P|GTX 10|Pascal"; then REC_DRIVER="nvidia-driver-580"
    elif echo "$GPU_INFO" | grep -iqE "Quadro M|GTX 9|Maxwell"; then REC_DRIVER="nvidia-driver-470"
    elif echo "$GPU_INFO" | grep -iqE "Quadro K|GTX 7|Kepler"; then REC_DRIVER="nvidia-driver-390"; fi

    CHOICE=$(bsddialog --title "Nvidia Config" --menu "Detected: $GPU_INFO\nRecommended: $REC_DRIVER" 17 85 5 \
        "nvidia-driver" "Latest" "nvidia-driver-580" "Legacy 580" "nvidia-driver-470" "Legacy 470" "nvidia-driver-390" "Legacy 390" "Back" "Cancel" 3>&1 1>&2 2>&3)
    [ "$CHOICE" = "Back" ] || [ -z "$CHOICE" ] && return
    DRIVER_PKG="$CHOICE"
    [ "$DRIVER_PKG" = "nvidia-driver" ] && LINUX_LIBS="linux-nvidia-libs" || LINUX_LIBS="linux-nvidia-libs-$(echo $DRIVER_PKG | cut -d'-' -f3)"
    pkg install -y "$DRIVER_PKG" "$LINUX_LIBS" libc6-shim nvidia-settings nvidia-xconfig
    sysrc kld_list+="nvidia-modeset"
    add_line_if_missing "hw.nvidiadrm.modeset=\"1\"" /boot/loader.conf
    nvidia-xconfig
    
    set_monitor_resolution
    mark_done "2"
}

drm_config() {
    VGA_VENDOR=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "vendor" | cut -d "'" -f 2)
    VGA_DEVICE=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "device" | cut -d "'" -f 2)
    DRM_DRIVER=""
    
    if is_vbox_guest; then
        bsddialog --infobox "VirtualBox VM detected. Installing Guest Additions..." 5 50
        pkg install -y virtualbox-ose-additions; sysrc vboxguest_enable="YES"; sysrc vboxservice_enable="YES"
        add_line_if_missing "vboxvideo_load=\"YES\"" /boot/loader.conf; DRM_DRIVER="vboxvideo"
    else
        case "$VGA_VENDOR" in
            *Intel*) 
                DRM_DRIVER="i915kms"
                bsddialog --infobox "Intel GPU detected. Installing DRM, Firmware, VAAPI & Audio Routing..." 5 70
                # Ajout des pilotes Media/VAAPI pour l'accélération vidéo matérielle Intel
                pkg install -y drm-kmod gpu-firmware-intel-kmod mixertui intel-media-driver libva-intel-driver libva-utils
                
                # Chargement temporaire pour initialiser les sondes audio intégrées
                kldload i915kms 2>/dev/null
                sleep 2
                
                # Auto-détection intelligente du canal DisplayPort / HDMI via sndstat
                DP_PCM=$(cat /dev/sndstat 2>/dev/null | grep -iE 'hdmi|dp' | grep -o 'pcm[0-9]*' | sed 's/pcm//' | head -n 1)
                if [ -n "$DP_PCM" ]; then
                    sed -i '' '/hw.snd.default_unit/d' /etc/sysctl.conf
                    echo "hw.snd.default_unit=$DP_PCM" >> /etc/sysctl.conf
                    sysctl hw.snd.default_unit=$DP_PCM >/dev/null 2>&1
                fi
                ;;
            *AMD*|*ATI*) 
                if echo "$VGA_DEVICE" | grep -iqE "Radeon HD|Radeon R[579]|FirePro"; then DRM_DRIVER="radeonkms"; else DRM_DRIVER="amdgpu"; fi 
                pkg install -y drm-kmod
                ;;
            *) bsddialog --msgbox "No supported GPU detected." 8 50; return ;;
        esac
    fi
    
    # --- NVIDIA / WAYLAND SAFETY CHECK ---
    if pciconf -lv | grep -iq "NVIDIA" || [ -f "${DB_PREFIX}2" ]; then
        bsddialog --infobox "NVIDIA GPU or configuration detected.\nSkipping Wayland/Xwayland installation to prevent conflicts." 5 65
        sleep 2
    else
        pkg install -y wayland xwayland
    fi
    
    if ! sysrc -n kld_list | grep -q "$DRM_DRIVER"; then sysrc kld_list+="$DRM_DRIVER"; fi
    
    set_monitor_resolution
    mark_done "3"
}

plasma_config() { 
    bsddialog --infobox "Installing Plasma 6 (KDE) and native tools..." 5 60
    pkg install -y --g "plasma6-*" "kf6*"
    pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum octopkg
    mark_done "4"
}

mate_config() { 
    bsddialog --infobox "Installing MATE Desktop..." 5 50
    # Installation propre de MATE avec pavucontrol et outils supplémentaires
    pkg install -y mate mate-desktop octopkg pavucontrol eom remmina xdg-user-dirs
    mark_done "5"
}

samba_config() { 
    pkg install -y samba416
    mkdir -p /home/share && chmod 777 /home/share
    [ ! -f /usr/local/etc/smb4.conf ] && cat > /usr/local/etc/smb4.conf <<EOF
[global]
    workgroup = HOMELAB
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    guest ok = yes
EOF
    sysrc samba_server_enable="YES"; service samba_server restart 2>/dev/null || service samba_server start
    mark_done "6"
}

xrdp_config() { 
    pkg install -y xrdp xorgxrdp; sysrc xrdp_enable="YES" xrdp_sesman_enable="YES"
    [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ] && mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup
    echo 'export LANG=fr_FR.UTF-8' > /usr/local/etc/xrdp/startwm.sh; echo 'exec startplasma-x11' >> /usr/local/etc/xrdp/startwm.sh; chmod 555 /usr/local/etc/xrdp/startwm.sh
    mark_done "7"
}

vbox_host_config() {
    if is_vbox_guest; then bsddialog --msgbox "VirtualBox Host blocked inside a VM." 8 50; return; fi
    pkg install -y virtualbox-ose-72; sysrc -f /boot/loader.conf vboxdrv_load="YES" vboxnet_load="YES"; sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root; [ -n "$USER_NAME" ] && pw groupmod vboxusers -m "$USER_NAME"
    mark_done "8"
}

apps_config() { 
    bsddialog --infobox "Installing general applications and fonts..." 5 60
    pkg install -y firefox chromium thunderbird vlc ffmpeg webcamd ImageMagick7 cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
    sysrc webcamd_enable=YES
    mark_done "9"
}

multimedia_config() {
    bsddialog --infobox "Installing Multimedia Creation tools (GIMP, Blender, OBS, etc.)..." 5 70
    pkg install -y gimp inkscape krita blender kdenlive obs-studio audacity ardour ffmpeg gstreamer1-plugins-all
    mark_done "A"
}

development_config() {
    bsddialog --infobox "Installing Development Tools, Editors & Debuggers..." 5 70
    pkg install -y gcc python3 rust gmake cmake pkgconf gdb cgdb neovim vscode
    mark_done "B"
}

nasa_theme() { 
    bsddialog --infobox "Downloading and configuring NASA Theme..." 5 60
    
    [ -d /tmp/fb14_assets ] && rm -rf /tmp/fb14_assets
    [ -f /tmp/fb14_assets.zip ] && rm -f /tmp/fb14_assets.zip
    
    fetch -o /tmp/fb14_assets.zip https://github.com/msartor99/FreeBSD14/archive/refs/heads/main.zip
    unzip -q /tmp/fb14_assets.zip -d /tmp/
    mv /tmp/FreeBSD14-main /tmp/fb14_assets
    rm -f /tmp/fb14_assets.zip
    
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp -r /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/ 2>/dev/null
    cp -f /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
    
    if [ -f /usr/local/share/sddm/themes/nasa/theme.conf ]; then
        sed -i '' 's/^background=.*/background=background.jpg/' /usr/local/share/sddm/themes/nasa/theme.conf
    fi

    mkdir -p /usr/local/etc/sddm.conf.d
    cat > /usr/local/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=nasa
EOF

    mkdir -p /boot/images
    cp -f /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/
    cp -f /tmp/fb14_assets/freebsd-logo-rev.png /boot/images/
    cp -f /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
    
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
    sysrc -f /boot/loader.conf splash_bmp_load="YES"
    sysrc -f /boot/loader.conf splash_txt_load="YES"
    sysrc -f /boot/loader.conf splash_pcx_load="YES"
    
    mark_done "C"
}

switch_latest() { sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf; pkg update -f && pkg upgrade -y; mark_done "D"; }

# --- MAIN MENU ---

show_disclaimer

while true; do
    MAIN_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "$TITLE" \
        --menu "Select Installation Step (Use Up/Down or type the character):" 22 85 15 \
        "1" "$(get_label "1" "Initial Setup (System, Hardware, Language, User)")" \
        "2" "$(get_label "2" "GPU: NVIDIA (Auto-Detect Legacy/Latest)")" \
        "3" "$(get_label "3" "GPU/VM: DRM-KMOD & VBox Guest Auto-Setup")" \
        "4" "$(get_label "4" "Desktop: Plasma 6 + KDE Tools")" \
        "5" "$(get_label "5" "Desktop: MATE")" \
        "6" "$(get_label "6" "Samba Server")" \
        "7" "$(get_label "7" "XRDP Remote Desktop")" \
        "8" "$(get_label "8" "VirtualBox 7.2 Host (Blocked in VM)")" \
        "9" "$(get_label "9" "Basic Apps & Fonts (Web, Mail, VLC)")" \
        "A" "$(get_label "A" "Multimedia Creation (GIMP, Blender, OBS...)")" \
        "B" "$(get_label "B" "Dev Tools & Editors (GCC, Python, VSCode, GDB)")" \
        "C" "$(get_label "C" "NASA Theme (SDDM & Boot)")" \
        "D" "$(get_label "D" "Upgrade to LATEST Branch")" \
        "Q" "Quit" 3>&1 1>&2 2>&3)

    case $MAIN_CHOICE in
        1) initial_setup ;;
        2) nvidia_config ;;
        3) drm_config ;;
        4) plasma_config ;;
        5) mate_config ;;
        6) samba_config ;;
        7) xrdp_config ;;
        8) vbox_host_config ;;
        9) apps_config ;;
        A|a) multimedia_config ;;
        B|b) development_config ;;
        C|c) nasa_theme ;;
        D|d) switch_latest ;;
        Q|q|*) break ;;
    esac
done
clear
echo "Script finished. Persistence stored in /var/db/. Please reboot."
