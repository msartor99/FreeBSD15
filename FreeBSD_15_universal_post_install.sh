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
    
    pkg update -y
    
    if ! command -v sudo >/dev/null 2>&1; then
        bsddialog --infobox "Installing sudo..." 5 40
        pkg install -y sudo
    fi
    
    pkg install -y bash doas unzip libzip wget git htop neofetch python3 bashtop smartmontools ipmitool nvme-cli btop pciutils

    sysrc linux_enable=YES
    kldload linux 2>/dev/null
    kldload linux64 2>/dev/null
    service linux start 2>/dev/null
    
    pkg install -y linux-rl9

    sed -i '' 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    add_line_if_missing "PermitRootLogin yes" /etc/ssh/sshd_config
    service sshd restart
    
    PAGER=cat freebsd-update fetch install

    sysrc -f /boot/loader.conf boot_mute=YES splash_changer_enable=YES autoboot_delay=3
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    sysrc rc_startmsgs=NO
    add_line_if_missing "kern.sched.preempt_thresh=224" /etc/sysctl.conf
    add_line_if_missing "kern.ipc.shm_allow_removed=1" /etc/sysctl.conf
    sysctl net.local.stream.recvspace=65536 net.local.stream.sendspace=65536
    sysrc -f /boot/loader.conf tmpfs_load=YES aio_load=YES nvme_load=YES

    sysrc smartd_enable=YES
    [ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
    service smartd restart 2>/dev/null || service smartd start

    CPU_TYPE=$(bsddialog --menu "Select CPU Type & Energy Management:" 13 85 2 \
        "Intel" "Intel CPU Firmware, Coretemp, IPMI & SMBus (I5 /I7 /I9 /Xeon )" \
        "AMD" "AMD CPU Firmware, AMDtemp, IPMI & SMBus (AMD Ryzen )" 3>&1 1>&2 2>&3)
        
    case $CPU_TYPE in
        Intel) 
            pkg install -y cpu-microcode sensors
            sysrc -f /boot/loader.conf coretemp_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
            sysrc -f /boot/loader.conf ipmi_load="YES"
            sysrc -f /boot/loader.conf intsmb_load="YES"
            sysrc -f /boot/loader.conf ichsmb_load="YES"
            
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
            sysrc -f /boot/loader.conf ipmi_load="YES"
            sysrc -f /boot/loader.conf amdsmb_load="YES"
            
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

    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme xorg dbus avahi signal-cli seatd sddm cups gutenprint cups-filters hplip system-config-printer cups-pk-helper fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
    sysrc sound_load="YES" snd_hda_load="YES"
    add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
    sysrc dbus_enable=YES avahi_enable=YES seatd_enable=YES sddm_enable=YES
    sysrc cupsd_enable=YES devfs_system_ruleset=localrules
    sysrc kld_list+=fusefs kld_list+=ext2fs
    add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

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

    if bsddialog --title "Keyboard Type" --yesno "Are you using an Apple Mac keyboard?\n(This ensures correct mapping for @, Command ⌘, etc.)" 8 60; then
        IS_MAC="YES"
    else
        IS_MAC="NO"
    fi

    clean_locales
    mkdir -p /usr/local/etc/X11/xorg.conf.d/

    case $LOC_CHOICE in
        English)
            echo 'defaultclass=default' > /etc/adduser.conf
            USER_CLASS="default"
            sysrc sddm_lang="en_US"
            KBD_LAYOUT="us"
            [ "$IS_MAC" = "YES" ] && KBD_VARIANT="mac" || KBD_VARIANT=""
            [ -n "$KBD_VARIANT" ] && VAR_STR="Option \"XkbVariant\" \"$KBD_VARIANT\"" || VAR_STR=""
            cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "$KBD_LAYOUT"
    $VAR_STR
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
            KBD_LAYOUT="ch"
            [ "$IS_MAC" = "YES" ] && KBD_VARIANT="fr-mac" || KBD_VARIANT="fr"
            cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "$KBD_LAYOUT"
    Option "XkbVariant" "$KBD_VARIANT"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
            ;;
        Custom)
            CUSTOM_LANG=$(bsddialog --inputbox "Enter System Locale (e.g., de_DE.UTF-8, es_ES.UTF-8):" 9 55 "en_US.UTF-8" 3>&1 1>&2 2>&3)
            CUSTOM_KBD=$(bsddialog --inputbox "Enter Keyboard Layout Code (e.g., de, es, gb, fr):" 9 55 "us" 3>&1 1>&2 2>&3)
            CUSTOM_VAR=$(bsddialog --inputbox "Enter Keyboard Variant (leave empty if none):" 9 55 "" 3>&1 1>&2 2>&3)
            [ -z "$CUSTOM_LANG" ] && CUSTOM_LANG="en_US.UTF-8"
            [ -z "$CUSTOM_KBD" ] && CUSTOM_KBD="us"
            [ -z "$CUSTOM_VAR" ] && [ "$IS_MAC" = "YES" ] && CUSTOM_VAR="mac"
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
            SDDM_L=$(echo "$CUSTOM_LANG" | cut -d'.' -f1)
            sysrc sddm_lang="$SDDM_L"
            KBD_LAYOUT="$CUSTOM_KBD"
            KBD_VARIANT="$CUSTOM_VAR"
            [ -n "$CUSTOM_VAR" ] && VAR_STR="Option \"XkbVariant\" \"$CUSTOM_VAR\"" || VAR_STR=""
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

    mkdir -p /usr/local/etc/xdg
    cat > /usr/local/etc/xdg/kxkbrc <<EOF
[Layout]
DisplayNames=
LayoutList=${KBD_LAYOUT}
LayoutLoopCount=-1
Model=pc105
ResetOldOptions=true
ShowFlag=false
ShowLabel=true
ShowLayoutIndicator=true
ShowSingle=false
SwitchMode=Global
Use=true
VariantList=${KBD_VARIANT}
EOF

    USER_NAME=$(bsddialog --inputbox "User Configuration:\nEnter main user name:" 9 50 3>&1 1>&2 2>&3)
    if [ -n "$USER_NAME" ]; then
        export USER_NAME
        pw usermod "$USER_NAME" -G wheel,operator,video -L "$USER_CLASS"
    fi
    pw usermod root -L "$USER_CLASS"
    mark_done "1"
}

set_monitor_resolution() {
    RES_CHOICE=$(bsddialog --title "Display Resolution" --menu "Select base resolution for SDDM/X11:" 17 75 6 \
        "Native" "Maximum Monitor Capability (Default)" \
        "3840x2160" "Force 3840x2160 (4K UHD)" \
        "2560x1440" "Force 2560x1440 (27\" 4K optimized)" \
        "1920x1200" "Force 1920x1200" \
        "1920x1080" "Force 1920x1080" \
        "Custom" "Type custom resolution" 3>&1 1>&2 2>&3)

    [ -z "$RES_CHOICE" ] && return
    
    if [ "$RES_CHOICE" = "Custom" ]; then
        RES_CHOICE=$(bsddialog --inputbox "Enter custom resolution (e.g., 2560x1080):" 9 50 "2560x1440" 3>&1 1>&2 2>&3)
        [ -z "$RES_CHOICE" ] && RES_CHOICE="Native"
    fi

    mkdir -p /usr/local/share/sddm/scripts/
    if [ "$RES_CHOICE" != "Native" ]; then
        sysrc allscreens_flags="-f terminus-b32"
        cat > /usr/local/share/sddm/scripts/Xsetup <<EOF
#!/bin/sh
OUTPUT=\$(xrandr | grep " connected" | awk '{print \$1}' | head -n 1)
[ -n "\$OUTPUT" ] && xrandr --output "\$OUTPUT" --mode $RES_CHOICE
EOF
        chmod +x /usr/local/share/sddm/scripts/Xsetup
        mkdir -p /usr/local/etc/xdg/autostart/
        cat > /usr/local/etc/xdg/autostart/force-resolution.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Force Resolution
Exec=sh -c "OUTPUT=\$(xrandr | grep ' connected' | awk '{print \$1}' | head -n 1); xrandr --output \$OUTPUT --mode $RES_CHOICE"
X-KDE-autostart-phase=1
EOF
    fi
}

# --- UNIFIED SMART GPU CONFIGURATION ---
install_nvidia_interactive() {
    local IS_HYBRID="$1"
    local GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | grep -o '\[.*\]' | tr -d '[]')
    [ -z "$GPU_INFO" ] && GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | cut -d "'" -f 2)
    [ -z "$GPU_INFO" ] && GPU_INFO="Unknown Nvidia GPU"
    
    local REC_DRIVER="nvidia-driver"
    if echo "$GPU_INFO" | grep -iqE "Quadro P|GTX 10|Pascal"; then REC_DRIVER="nvidia-driver-580"
    elif echo "$GPU_INFO" | grep -iqE "Quadro M|GTX 9|Maxwell"; then REC_DRIVER="nvidia-driver-470"
    elif echo "$GPU_INFO" | grep -iqE "Quadro K|GTX 7|Kepler"; then REC_DRIVER="nvidia-driver-390"; fi

    local CHOICE=$(bsddialog --title "NVIDIA Configuration" --menu "Detected: $GPU_INFO\nRecommended: $REC_DRIVER" 17 85 5 \
        "nvidia-driver" "Latest" "nvidia-driver-580" "Legacy 580" "nvidia-driver-470" "Legacy 470" "nvidia-driver-390" "Legacy 390" "Back" "Cancel" 3>&1 1>&2 2>&3)
    [ "$CHOICE" = "Back" ] || [ -z "$CHOICE" ] && return 0
    
    local DRIVER_PKG="$CHOICE"
    local LINUX_LIBS="linux-nvidia-libs"
    [ "$DRIVER_PKG" != "nvidia-driver" ] && LINUX_LIBS="linux-nvidia-libs-$(echo $DRIVER_PKG | cut -d'-' -f3)"
    
    pkg install -y "$DRIVER_PKG" "$LINUX_LIBS" libc6-shim nvidia-settings nvidia-xconfig
    sysrc kld_list+="nvidia-modeset"
    add_line_if_missing "hw.nvidiadrm.modeset=\"1\"" /boot/loader.conf
    
    if [ "$IS_HYBRID" != "YES" ]; then
        nvidia-xconfig
    fi
}

gpu_config() {
    bsddialog --infobox "Analyzing PCI buses for Graphics Cards..." 4 50
    local VGA_LINES=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "vendor")
    local HAS_INTEL="NO"
    local HAS_AMD="NO"
    local HAS_NVIDIA="NO"
    
    echo "$VGA_LINES" | grep -iq "Intel" && HAS_INTEL="YES"
    echo "$VGA_LINES" | grep -iqE "AMD|ATI" && HAS_AMD="YES"
    echo "$VGA_LINES" | grep -iq "NVIDIA" && HAS_NVIDIA="YES"

    if is_vbox_guest; then
        bsddialog --msgbox "VirtualBox detected. Installing guest additions." 6 50
        pkg install -y virtualbox-ose-additions; sysrc vboxguest_enable="YES" vboxservice_enable="YES"
        add_line_if_missing "vboxvideo_load=\"YES\"" /boot/loader.conf
        set_monitor_resolution
        mark_done "2"
        return
    fi

    if [ "$HAS_INTEL" = "YES" ] && [ "$HAS_NVIDIA" = "YES" ]; then
        local msg="OPTIMUS HYBRID GRAPHICS DETECTED (Intel + NVIDIA)\n\nFreeBSD will use Intel as the primary display (for stability and battery) and install NVIDIA for PRIME Render Offloading.\n\nWe will install both drivers safely."
        bsddialog --msgbox "$msg" 12 70
        pkg install -y drm-kmod gpu-firmware-kmod mixertui libva-intel-media-driver libva-intel-driver libva-utils
        sysrc kld_list+="i915kms"
        install_nvidia_interactive "YES"
        
        local prime_msg="OPTIMUS CONFIGURED SAFELY!\n\nYour screen runs on Intel.\nTo run a specific app (e.g. blender) on the NVIDIA GPU, launch it via terminal like this:\n\n__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia blender"
        bsddialog --msgbox "$prime_msg" 12 70

    elif [ "$HAS_INTEL" = "YES" ] && [ "$HAS_AMD" = "YES" ]; then
        bsddialog --msgbox "HYBRID GRAPHICS DETECTED (Intel + AMD)\n\nInstalling drm-kmod. Intel will be the primary display." 10 70
        pkg install -y drm-kmod gpu-firmware-kmod libva-intel-media-driver libva-intel-driver libva-utils
        sysrc kld_list+="i915kms amdgpu"
        
    elif [ "$HAS_INTEL" = "YES" ]; then
        bsddialog --infobox "Intel Graphics detected. Installing i915kms..." 4 50
        pkg install -y drm-kmod gpu-firmware-kmod mixertui libva-intel-media-driver libva-intel-driver libva-utils
        sysrc kld_list+="i915kms"
        kldload i915kms 2>/dev/null; sleep 2
        local DP_PCM=$(cat /dev/sndstat 2>/dev/null | grep -iE 'hdmi|dp' | grep -o 'pcm[0-9]*' | sed 's/pcm//' | head -n 1)
        if [ -n "$DP_PCM" ]; then
            sed -i '' '/hw.snd.default_unit/d' /etc/sysctl.conf
            echo "hw.snd.default_unit=$DP_PCM" >> /etc/sysctl.conf
        fi

    elif [ "$HAS_AMD" = "YES" ]; then
        bsddialog --infobox "AMD Graphics detected. Installing drm-kmod..." 4 50
        pkg install -y drm-kmod gpu-firmware-kmod
        local VGA_DEVICE=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "device" | cut -d "'" -f 2)
        if echo "$VGA_DEVICE" | grep -iqE "Radeon HD|Radeon R[579]|FirePro"; then 
            sysrc kld_list+="radeonkms"
        else 
            sysrc kld_list+="amdgpu"
        fi 

    elif [ "$HAS_NVIDIA" = "YES" ]; then
        bsddialog --infobox "NVIDIA Dedicated Graphics detected..." 4 50
        install_nvidia_interactive "NO"
    else
        bsddialog --msgbox "No recognized GPU detected. Falling back to default VESA/SCFB." 6 60
    fi

    set_monitor_resolution
    mark_done "2"
}

# --- DESKTOP ENVIRONMENTS ---

macos_plasma_theme() {
    bsddialog --infobox "Downloading and building WhiteSur macOS Theme for KDE Plasma 6 & SDDM...\n(Extracting files globally for all users)" 6 70
    
    pkg install -y bash git sassc glib coreutils gsed qt5-graphicaleffects qt5-quickcontrols2
    
    # Wrap GNU tools for icon script compatibility
    mkdir -p /tmp/gnu_wrap
    ln -sf /usr/local/bin/greadlink /tmp/gnu_wrap/readlink
    ln -sf /usr/local/bin/gsed /tmp/gnu_wrap/sed
    echo '#!/bin/sh' > /tmp/gnu_wrap/setterm
    echo 'exit 0' >> /tmp/gnu_wrap/setterm
    chmod +x /tmp/gnu_wrap/setterm
    OLD_PATH=$PATH
    export PATH="/tmp/gnu_wrap:$PATH"
    
    [ -d /tmp/WhiteSur-kde ] && rm -rf /tmp/WhiteSur-kde
    [ -d /tmp/WhiteSur-icon-theme ] && rm -rf /tmp/WhiteSur-icon-theme
    
    # 1. KDE Theme (Manual Global Extraction - The "FreeBSD Way")
    git clone https://github.com/vinceliuice/WhiteSur-kde.git /tmp/WhiteSur-kde
    mkdir -p /usr/local/share/color-schemes
    mkdir -p /usr/local/share/plasma/desktoptheme
    mkdir -p /usr/local/share/plasma/look-and-feel
    mkdir -p /usr/local/share/aurorae/themes
    mkdir -p /usr/local/share/Kvantum
    cp -r /tmp/WhiteSur-kde/color-schemes/* /usr/local/share/color-schemes/ 2>/dev/null
    cp -r /tmp/WhiteSur-kde/plasma/desktoptheme/* /usr/local/share/plasma/desktoptheme/ 2>/dev/null
    cp -r /tmp/WhiteSur-kde/plasma/look-and-feel/* /usr/local/share/plasma/look-and-feel/ 2>/dev/null
    cp -r /tmp/WhiteSur-kde/aurorae/* /usr/local/share/aurorae/themes/ 2>/dev/null
    cp -r /tmp/WhiteSur-kde/Kvantum/* /usr/local/share/Kvantum/ 2>/dev/null
    
    # 2. Icons
    git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon-theme
    cd /tmp/WhiteSur-icon-theme
    mkdir -p /usr/local/share/icons
    bash ./install.sh -d /usr/local/share/icons -a
    gtk-update-icon-cache -f -t /usr/local/share/icons/WhiteSur 2>/dev/null
    gtk-update-icon-cache -f -t /usr/local/share/icons/WhiteSur-Dark 2>/dev/null
    
    # 3. Download Wallpaper
    mkdir -p /usr/local/share/backgrounds
    fetch -o /usr/local/share/backgrounds/WhiteSur-light.jpg https://raw.githubusercontent.com/vinceliuice/WhiteSur-wallpapers/main/4k/WhiteSur-light.jpg
    
    # 4. SDDM Theme
    mkdir -p /usr/local/share/sddm/themes
    cp -r /tmp/WhiteSur-kde/sddm/WhiteSur /usr/local/share/sddm/themes/ 2>/dev/null
    mkdir -p /usr/local/etc/sddm.conf.d
    echo "[Theme]" > /usr/local/etc/sddm.conf.d/theme.conf
    echo "Current=WhiteSur" >> /usr/local/etc/sddm.conf.d/theme.conf
    if [ -f /usr/local/share/sddm/themes/WhiteSur/theme.conf ]; then
        sed -i '' 's|^background=.*|background=/usr/local/share/backgrounds/WhiteSur-light.jpg|' /usr/local/share/sddm/themes/WhiteSur/theme.conf
    fi
    
    rm -rf /tmp/WhiteSur-kde /tmp/WhiteSur-icon-theme /tmp/gnu_wrap
    export PATH=$OLD_PATH
    
    # 5. First Boot Autostart Magic for KDE Plasma
    mkdir -p /usr/local/etc/xdg/autostart
    cat > /usr/local/etc/xdg/autostart/whitesur-plasma-apply.desktop <<'EOF'
[Desktop Entry]
Name=Apply WhiteSur KDE Theme
Comment=Applies Mac theme automatically on first login
Exec=sh -c 'if [ ! -f ~/.whitesur_kde_applied ]; then sleep 4; lookandfeeltool -a com.github.vinceliuice.WhiteSur-Dark; plasma-apply-wallpaperimage /usr/local/share/backgrounds/WhiteSur-light.jpg; touch ~/.whitesur_kde_applied; fi'
Terminal=false
Type=Application
OnlyShowIn=KDE;
EOF
    
    local msg="WhiteSur Theme, Icons, Wallpaper & SDDM Login Screen installed for Plasma 6!\n\nWhen you log into Plasma for the first time, everything will transform into macOS automatically.\n\nTip for the Mac Dock:\nPlasma 6 has a powerful built-in panel! Right-click your bottom panel -> 'Enter Edit Mode'. Change its width to 'Fit Content', center it, and enable 'Auto-Hide' to make a perfect Mac Dock!"
    bsddialog --msgbox "$msg" 18 75
}

plasma_config() { 
    bsddialog --infobox "Installing Plasma 6 (KDE) + Printers + KWallet..." 5 65
    pkg install -y --g "plasma6-*" "kf6*"
    pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum octopkg plasma6-print-manager kwalletmanager
    
    local theme_msg="Do you want to install the WhiteSur macOS Theme for KDE Plasma 6?\n\n(This will download the theme, icons, SDDM Login, and fully automate the Mac layout for your first login)"
    if bsddialog --title "KDE Plasma macOS Theme" --yesno "$theme_msg" 8 70; then
        macos_plasma_theme
    fi
    
    mark_done "3"
}

mate_config() { 
    bsddialog --infobox "Installing MATE Desktop..." 5 50
    pkg install -y mate mate-desktop octopkg pavucontrol eom remmina xdg-user-dirs
    mark_done "4"
}

macos_xfce_theme() {
    bsddialog --infobox "Downloading and building WhiteSur macOS Theme for XFCE4 & SDDM...\n(This might take a moment to fetch from GitHub)" 6 65
    
    pkg install -y bash git gtk-murrine-engine gtk-engines2 sassc glib coreutils gsed plank qt5-graphicaleffects qt5-quickcontrols2
    
    mkdir -p /tmp/gnu_wrap
    ln -sf /usr/local/bin/greadlink /tmp/gnu_wrap/readlink
    ln -sf /usr/local/bin/gsed /tmp/gnu_wrap/sed
    echo '#!/bin/sh' > /tmp/gnu_wrap/setterm
    echo 'exit 0' >> /tmp/gnu_wrap/setterm
    chmod +x /tmp/gnu_wrap/setterm
    
    OLD_PATH=$PATH
    export PATH="/tmp/gnu_wrap:$PATH"
    
    [ -d /tmp/WhiteSur-gtk-theme ] && rm -rf /tmp/WhiteSur-gtk-theme
    [ -d /tmp/WhiteSur-icon-theme ] && rm -rf /tmp/WhiteSur-icon-theme
    [ -d /tmp/WhiteSur-kde ] && rm -rf /tmp/WhiteSur-kde
    
    git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-gtk-theme
    cd /tmp/WhiteSur-gtk-theme
    mkdir -p /usr/local/share/themes
    bash ./install.sh -d /usr/local/share/themes -t all -N glassy
    
    mkdir -p /usr/local/share/plank/themes
    cp -r src/other/plank/theme-* /usr/local/share/plank/themes/ 2>/dev/null
    
    git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon-theme
    cd /tmp/WhiteSur-icon-theme
    mkdir -p /usr/local/share/icons
    bash ./install.sh -d /usr/local/share/icons -a
    
    gtk-update-icon-cache -f -t /usr/local/share/icons/WhiteSur 2>/dev/null
    gtk-update-icon-cache -f -t /usr/local/share/icons/WhiteSur-Dark 2>/dev/null
    
    mkdir -p /usr/local/share/backgrounds
    fetch -o /usr/local/share/backgrounds/WhiteSur-light.jpg https://raw.githubusercontent.com/vinceliuice/WhiteSur-wallpapers/main/4k/WhiteSur-light.jpg
    
    git clone https://github.com/vinceliuice/WhiteSur-kde.git /tmp/WhiteSur-kde
    mkdir -p /usr/local/share/sddm/themes
    cp -r /tmp/WhiteSur-kde/sddm/WhiteSur /usr/local/share/sddm/themes/ 2>/dev/null
    mkdir -p /usr/local/etc/sddm.conf.d
    echo "[Theme]" > /usr/local/etc/sddm.conf.d/theme.conf
    echo "Current=WhiteSur" >> /usr/local/etc/sddm.conf.d/theme.conf
    if [ -f /usr/local/share/sddm/themes/WhiteSur/theme.conf ]; then
        sed -i '' 's|^background=.*|background=/usr/local/share/backgrounds/WhiteSur-light.jpg|' /usr/local/share/sddm/themes/WhiteSur/theme.conf
    fi
    
    rm -rf /tmp/WhiteSur-gtk-theme /tmp/WhiteSur-icon-theme /tmp/WhiteSur-kde /tmp/gnu_wrap
    export PATH=$OLD_PATH
    
    mkdir -p /usr/local/etc/xdg/autostart
    cat > /usr/local/etc/xdg/autostart/plank.desktop <<EOF
[Desktop Entry]
Name=Plank
Comment=Stupidly simple dock
Exec=plank
Icon=plank
Terminal=false
Type=Application
Categories=Utility;
OnlyShowIn=XFCE;
EOF

    if [ -f /usr/local/etc/xdg/xfce4/panel/default.xml ]; then
        sed -i '' '/<value type="int" value="2"\/>/d' /usr/local/etc/xdg/xfce4/panel/default.xml
    fi
    for user_home in /home/* /root; do
        panel_xml="$user_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
        if [ -f "$panel_xml" ]; then
            sed -i '' '/<value type="int" value="2"\/>/d' "$panel_xml"
        fi
    done

    cat > /usr/local/etc/xdg/autostart/whitesur-auto-apply.desktop <<'EOF'
[Desktop Entry]
Name=Apply WhiteSur Theme
Comment=Applies Mac theme automatically on first login
Exec=sh -c 'if [ ! -f ~/.whitesur_applied ]; then sleep 3; xfconf-query -c xsettings -p /Net/ThemeName -s "WhiteSur-Dark" --create -t string; xfconf-query -c xsettings -p /Net/IconThemeName -s "WhiteSur" --create -t string; xfconf-query -c xfwm4 -p /general/theme -s "WhiteSur-Dark" --create -t string; gsettings set net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/ theme "WhiteSur"; for prop in $(xfconf-query -c xfce4-desktop -p /backdrop -l | grep -E "last-image$"); do xfconf-query -c xfce4-desktop -p "$prop" -s "/usr/local/share/backgrounds/WhiteSur-light.jpg"; done; touch ~/.whitesur_applied; fi'
Terminal=false
Type=Application
OnlyShowIn=XFCE;
EOF
    
    local msg="WhiteSur Theme, Plank Dock, Wallpaper & SDDM Login Screen installed and completely AUTOMATED!\n\nWhen you reboot, your login screen will be macOS styled.\nWhen you log into XFCE for the first time, everything (Windows, Icons, Dock, and Wallpaper) will transform automatically."
    bsddialog --msgbox "$msg" 16 75
}

xfce_config() {
    bsddialog --infobox "Installing XFCE4 Desktop..." 5 50
    pkg install -y xfce xfce4-goodies octopkg pavucontrol remmina xdg-user-dirs xarchiver plank
    mkdir -p /usr/local/share/xsessions
    cat > /usr/local/share/xsessions/xfce.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=XFCE Session (X11)
Exec=startxfce4
Type=Application
DesktopNames=XFCE
EOF
    
    local theme_msg="Do you want to install the WhiteSur macOS Theme for XFCE4?\n\n(This will download the theme, icons, SDDM Login, and fully automate the Mac layout for your first login)"
    if bsddialog --title "XFCE4 macOS Theme" --yesno "$theme_msg" 8 70; then
        macos_xfce_theme
    fi
    mark_done "5"
}

# --- SERVICES & APPS ---

apps_config() { 
    bsddialog --infobox "Installing Apps & Configuring Webcam..." 5 60
    pkg install -y firefox chromium thunderbird vlc ffmpeg webcamd ImageMagick7 cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
    sysrc webcamd_enable="YES"
    ! sysrc -n kld_list | grep -q "cuse" && sysrc kld_list+="cuse"
    [ -n "$USER_NAME" ] && pw groupmod webcamd -m "$USER_NAME" 2>/dev/null
    mark_done "6"
}

xrdp_config() { 
    bsddialog --infobox "Installing XRDP Server..." 5 50
    pkg install -y xrdp xorgxrdp
    sysrc xrdp_enable="YES" xrdp_sesman_enable="YES"

    DE_CHOICE=$(bsddialog --title "XRDP Desktop Environment" --menu "Select the default desktop to launch for RDP sessions:" 13 65 3 \
        "Plasma" "KDE Plasma 6" \
        "XFCE" "XFCE4" \
        "MATE" "MATE Desktop" 3>&1 1>&2 2>&3)

    [ -z "$DE_CHOICE" ] && return

    [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ] && mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup

    cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=fr_FR.UTF-8
EOF

    case "$DE_CHOICE" in
        Plasma) echo "exec startplasma-x11" >> /usr/local/etc/xrdp/startwm.sh ;;
        XFCE) echo "exec startxfce4" >> /usr/local/etc/xrdp/startwm.sh ;;
        MATE) echo "exec mate-session" >> /usr/local/etc/xrdp/startwm.sh ;;
    esac

    chmod 555 /usr/local/etc/xrdp/startwm.sh
    mark_done "7"
}

vnc_config() {
    bsddialog --infobox "Installing x11vnc Console Shadowing..." 5 50
    pkg install -y x11vnc
    
    VNC_PASS=$(bsddialog --title "VNC Console Setup" --insecure --passwordbox "Create VNC Password:" 9 60 3>&1 1>&2 2>&3)
    if [ -n "$VNC_PASS" ]; then
        x11vnc -storepasswd "$VNC_PASS" /usr/local/etc/x11vnc.pwd
        chmod 600 /usr/local/etc/x11vnc.pwd
    fi
    
    cat > /usr/local/etc/rc.d/x11vnc << 'EOF'
#!/bin/sh
# REQUIRE: LOGIN dbus sddm
# PROVIDE: x11vnc
. /etc/rc.subr
name="x11vnc"; rcvar="x11vnc_enable"; command="/usr/sbin/daemon"
command_args="-f sh -c 'sleep 5 && AUTH=\$(find /var/run/sddm -type f | head -n 1) && exec /usr/local/bin/x11vnc -display :0 -auth \"\$AUTH\" -forever -loop -noxdamage -repeat -rfbauth /usr/local/etc/x11vnc.pwd -rfbport 5900 -shared -o /var/log/x11vnc.log'"
load_rc_config $name
: ${x11vnc_enable:="NO"}
run_rc_command "$1"
EOF
    chmod +x /usr/local/etc/rc.d/x11vnc; sysrc x11vnc_enable="YES"
    mark_done "8"
}

wine_config() {
    if grep -q "quarterly" /etc/pkg/FreeBSD.conf; then
        local msg="WARNING: WINE works best on 'latest' branch. Switch now?"
        if bsddialog --title "WINE Configuration" --defaultno --yesno "$msg" 10 60; then
            sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf; pkg update -f && pkg upgrade -y
        else
            return
        fi
    fi
    pkg install -y wine winetricks; mark_done "9"
}

samba_config() { 
    pkg install -y samba416
    SMB_PATH=$(bsddialog --title "Samba Path" --inputbox "Path to share:" 9 60 "/home/data" 3>&1 1>&2 2>&3)
    [ -z "$SMB_PATH" ] && SMB_PATH="/home/data"
    SMB_USER=$(bsddialog --title "Samba Owner" --inputbox "FreeBSD user owner:" 9 60 "${USER_NAME:-nobody}" 3>&1 1>&2 2>&3)
    [ -z "$SMB_USER" ] && SMB_USER="nobody"
    bsddialog --yesno "Make share writable?" 7 40 && SMB_WRITABLE="yes" || SMB_WRITABLE="no"
    if bsddialog --yesno "Allow GUEST access?" 7 40; then
        SMB_GUEST="yes"; VALID_USERS_LINE=""; SMB_PASS=""
    else
        SMB_GUEST="no"; VALID_USERS_LINE="valid users = $SMB_USER"
        SMB_PASS=$(bsddialog --title "Samba Password" --insecure --passwordbox "Create Samba password for $SMB_USER:" 9 60 3>&1 1>&2 2>&3)
    fi
    mkdir -p "$SMB_PATH"; chown "$SMB_USER" "$SMB_PATH"
    [ "$SMB_GUEST" = "yes" ] && [ "$SMB_WRITABLE" = "yes" ] && chmod 777 "$SMB_PATH" || chmod 755 "$SMB_PATH"
    SHARE_NAME=$(basename "$SMB_PATH")
    cat > /usr/local/etc/smb4.conf <<EOF
[global]
    workgroup = HOMELAB
    map to guest = bad user
    security = user
[$SHARE_NAME]
    path = $SMB_PATH
    $VALID_USERS_LINE
    writable = $SMB_WRITABLE
    guest ok = $SMB_GUEST
    force user = $SMB_USER
EOF
    sysrc samba_server_enable="YES"; service samba_server restart 2>/dev/null
    [ "$SMB_GUEST" = "no" ] && [ -n "$SMB_PASS" ] && (echo "$SMB_PASS"; echo "$SMB_PASS") | smbpasswd -s -a "$SMB_USER"
    mark_done "a"
}

bluetooth_config() {
    local msg="Warning: Bluetooth is not fully integrated in FreeBSD, are you sure?"
    if ! bsddialog --title "Bluetooth Warning" --defaultno --yesno "$msg" 8 60; then
        return
    fi
    bsddialog --infobox "Configuring Bluetooth & Audio bridge..." 5 60
    pkg install -y virtual_oss blueman
    ! sysrc -n kld_list | grep -q "ng_ubt" && sysrc kld_list+="ng_ubt"
    sysrc hcsecd_enable="YES" bthidd_enable="YES" sdpd_enable="YES"
    [ -n "$USER_NAME" ] && pw groupmod network -m "$USER_NAME" 2>/dev/null
    mark_done "g"
}

macbook_2010_config() {
    local msg="WARNING: This configures legacy Broadcom Wi-Fi, FireWire, Apple SMC and Trackpad.\nYou MUST have an active Ethernet connection right now to download the proprietary Wi-Fi firmware.\n\nContinue?"
    if ! bsddialog --title "MacBook Pro 2010" --defaultno --yesno "$msg" 10 70; then
        return
    fi
    bsddialog --infobox "Installing Apple MacBook Pro 2010 specific drivers..." 5 60
    pkg install -y bwn-firmware-kmod
    sysrc -f /boot/loader.conf if_bwn_load="YES" bwn_v4_ucode_load="YES" asmc_load="YES" wsp_load="YES"
    ! sysrc -n kld_list | grep -q "firewire" && sysrc kld_list+="firewire"

    local warn_msg="MACBOOK 2010 POST-INSTALL TIPS:\n\n1. KEYBOARD: This is handled! Just answer YES when Option 1 asks if you are using an Apple Mac keyboard.\n\n2. GPU: Use Option 2 (Auto-Detect GPU) to safely configure your graphics.\n\n3. AUDIO: Run 'cat /dev/sndstat' to find speakers, then set 'sysctl hw.snd.default_unit=X'.\n\n4. WI-FI: Once rebooted, use Option 'w' to configure Wi-Fi."
    bsddialog --msgbox "$warn_msg" 18 75
    mark_done "h"
}

wifi_config() {
    clear
    if [ -x /usr/libexec/bsdinstall/netconfig ]; then
        bsdinstall netconfig
        mark_done "w"
    else
        bsddialog --msgbox "Error: The bsdinstall network utility was not found on this system." 6 70
    fi
}

vbox_host_config() {
    is_vbox_guest && return
    pkg install -y virtualbox-ose-72; sysrc -f /boot/loader.conf vboxdrv_load="YES" vboxnet_load="YES"; sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root; [ -n "$USER_NAME" ] && pw groupmod vboxusers -m "$USER_NAME"
    mark_done "b"
}

multimedia_config() {
    pkg install -y gimp inkscape krita blender kdenlive obs-studio audacity ffmpeg gstreamer1-plugins-all; mark_done "c"
}

development_config() {
    pkg install -y gcc python3 rust gmake cmake pkgconf gdb cgdb neovim vscode; mark_done "d"
}

nasa_theme() { 
    bsddialog --infobox "Downloading and configuring NASA Theme..." 5 60
    [ -d /tmp/fb14_assets ] && rm -rf /tmp/fb14_assets
    fetch -o /tmp/fb14_assets.zip https://github.com/msartor99/FreeBSD14/archive/refs/heads/main.zip
    unzip -q /tmp/fb14_assets.zip -d /tmp/; mv /tmp/FreeBSD14-main /tmp/fb14_assets
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp -r /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/ 2>/dev/null
    cp -f /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
    [ -f /usr/local/share/sddm/themes/nasa/theme.conf ] && sed -i '' 's/^background=.*/background=background.jpg/' /usr/local/share/sddm/themes/nasa/theme.conf
    mkdir -p /usr/local/etc/sddm.conf.d; echo "[Theme]\nCurrent=nasa" > /usr/local/etc/sddm.conf.d/theme.conf
    mkdir -p /boot/images
    cp -f /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/nasa-brand.png
    cp -f /tmp/fb14_assets/freebsd-logo-rev.png /boot/images/nasa-logo.png
    cp -f /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
    sysrc -f /boot/loader.conf -x loader_brand 2>/dev/null
    sysrc -f /boot/loader.conf -x loader_logo 2>/dev/null
    [ ! -L "/boot/images/freebsd-brand-rev.png" ] && [ -f "/boot/images/freebsd-brand-rev.png" ] && mv -f /boot/images/freebsd-brand-rev.png /boot/images/freebsd-brand-rev.png.bak
    [ ! -L "/boot/images/freebsd-logo-rev.png" ] && [ -f "/boot/images/freebsd-logo-rev.png" ] && mv -f /boot/images/freebsd-logo-rev.png /boot/images/freebsd-logo-rev.png.bak
    ln -sf /boot/images/nasa-brand.png /boot/images/freebsd-brand-rev.png
    ln -sf /boot/images/nasa-logo.png /boot/images/freebsd-logo-rev.png
    sysrc -f /boot/loader.conf loader_color="YES" splash="/boot/images/splash.png" splash_bmp_load="YES" splash_txt_load="YES" splash_pcx_load="YES"
    mark_done "e"
}

switch_latest() { 
    local msg="WARNING: Switching to LATEST branch can lead to temporary package breakage or GUI instability. Proceed?"
    if bsddialog --title "DANGER: LATEST Branch" --defaultno --yesno "$msg" 10 70; then
        sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf; pkg update -f && pkg upgrade -y; mark_done "f"
    fi
}

# --- MAIN MENU ---

show_disclaimer

while true; do
    MAIN_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "$TITLE" \
        --menu "Select Installation Step:" 26 88 19 \
        "1" "$(get_label "1" "Initial Setup (System, Hardware, Lang, User)")" \
        "2" "$(get_label "2" "GPU Auto-Config (Intel/AMD/NVIDIA/Hybrid)")" \
        "3" "$(get_label "3" "Desktop: Plasma 6 (With optional macOS Theme)")" \
        "4" "$(get_label "4" "Desktop: MATE")" \
        "5" "$(get_label "5" "Desktop: XFCE4 (With optional macOS Theme)")" \
        "6" "$(get_label "6" "Basic Apps & Fonts + Webcam Support")" \
        "7" "$(get_label "7" "Remote: XRDP (RDP Desktop Session)")" \
        "8" "$(get_label "8" "Remote: x11vnc (Console Shadowing)")" \
        "9" "$(get_label "9" "WINE & Winetricks (Needs LATEST)")" \
        "a" "$(get_label "a" "Samba Server (Interactive Share)")" \
        "b" "$(get_label "b" "VirtualBox 7.2 Host")" \
        "c" "$(get_label "c" "Multimedia Creation (GIMP, OBS...)")" \
        "d" "$(get_label "d" "Dev Tools (GCC, Python, VSCode)")" \
        "e" "$(get_label "e" "NASA Theme (SDDM & Boot)")" \
        "h" "$(get_label "h" "MacBook Pro 2010 (Wi-Fi, Trackpad, FireWire)")" \
        "w" "$(get_label "w" "Wi-Fi Configuration (Native bsdinstall GUI)")" \
        "g" "$(get_label "g" "Bluetooth Support (WARNING)")" \
        "f" "$(get_label "f" "Upgrade to LATEST Branch (WARNING)")" \
        "q" "Quit" 3>&1 1>&2 2>&3)

    case $MAIN_CHOICE in
        1) initial_setup ;; 2) gpu_config ;; 3) plasma_config ;; 4) mate_config ;; 5) xfce_config ;;
        6) apps_config ;; 7) xrdp_config ;; 8) vnc_config ;; 9) wine_config ;; a) samba_config ;; 
        b) vbox_host_config ;; c) multimedia_config ;; d) development_config ;; e) nasa_theme ;; 
        h) macbook_2010_config ;; w) wifi_config ;; g) bluetooth_config ;; f) switch_latest ;; q|*) break ;;
    esac
done
clear
echo "Script finished. Please reboot."
