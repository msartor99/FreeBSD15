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
    
    # Bypass the pager to avoid script pausing during updates
    PAGER=cat freebsd-update fetch install

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
    CPU_TYPE=$(bsddialog --menu "Select CPU Type & Energy Management:" 13 85 2 \
        "Intel" "Intel CPU Firmware, Coretemp, IPMI & SMBus (I5 /I7 /I9 /Xeon )" \
        "AMD" "AMD CPU Firmware, AMDtemp, IPMI & SMBus (AMD Ryzen )" 3>&1 1>&2 2>&3)
        
    case $CPU_TYPE in
        Intel) 
            pkg install -y cpu-microcode sensors
            sysrc -f /boot/loader.conf coretemp_load="YES"
            sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
            
            # Specific Workstation Power & Monitoring modules for Intel
            sysrc -f /boot/loader.conf ipmi_load="YES"
            sysrc -f /boot/loader.conf intsmb_load="YES"
            sysrc -f /boot/loader.conf ichsmb_load="YES"
            
            # Devfs rules for NVMe AND IPMI sensors
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
            
            # Devfs rules for NVMe AND IPMI sensors
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

    # 3. Hardware Base (Added cups-pk-helper for all desktops)
    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme xorg dbus avahi signal-cli seatd sddm cups gutenprint cups-filters hplip system-config-printer cups-pk-helper fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
    sysrc sound_load="YES" snd_hda_load="YES"
    add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
    sysrc dbus_enable=YES avahi_enable=YES seatd_enable=YES sddm_enable=YES
    sysrc cupsd_enable=YES devfs_system_ruleset=localrules
    sysrc kld_list+=fusefs kld_list+=ext2fs
    add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

    # 4. Localization & Keyboard Menu
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
            CUSTOM_VAR=$(bsddialog --inputbox "Enter Keyboard Variant (leave empty if none):" 9 55 "" 3>&1 1>&2 2>&3)
            
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
            
            SDDM_L=$(echo "$CUSTOM_LANG" | cut -d'.' -f1)
            sysrc sddm_lang="$SDDM_L"

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

# --- GPU CONFIGURATIONS ---

nvidia_config() {
    GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | grep -o '\[.*\]' | tr -d '[]')
    [ -z "$GPU_INFO" ] && GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | cut -d "'" -f 2)
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
        pkg install -y virtualbox-ose-additions; sysrc vboxguest_enable="YES"; sysrc vboxservice_enable="YES"
        add_line_if_missing "vboxvideo_load=\"YES\"" /boot/loader.conf; DRM_DRIVER="vboxvideo"
    else
        case "$VGA_VENDOR" in
            *Intel*) 
                DRM_DRIVER="i915kms"
                pkg install -y drm-kmod gpu-firmware-kmod mixertui libva-intel-media-driver libva-intel-driver libva-utils
                kldload i915kms 2>/dev/null
                sleep 2
                DP_PCM=$(cat /dev/sndstat 2>/dev/null | grep -iE 'hdmi|dp' | grep -o 'pcm[0-9]*' | sed 's/pcm//' | head -n 1)
                if [ -n "$DP_PCM" ]; then
                    sed -i '' '/hw.snd.default_unit/d' /etc/sysctl.conf
                    echo "hw.snd.default_unit=$DP_PCM" >> /etc/sysctl.conf
                fi
                ;;
            *AMD*|*ATI*) 
                if echo "$VGA_DEVICE" | grep -iqE "Radeon HD|Radeon R[579]|FirePro"; then DRM_DRIVER="radeonkms"; else DRM_DRIVER="amdgpu"; fi 
                pkg install -y drm-kmod gpu-firmware-kmod
                ;;
            *) bsddialog --msgbox "No supported GPU detected." 8 50; return ;;
        esac
    fi
    
    if pciconf -lv | grep -iq "NVIDIA" || [ -f "${DB_PREFIX}2" ]; then
        bsddialog --infobox "NVIDIA detected. Skipping Wayland to prevent conflicts." 5 60
    else
        pkg install -y wayland xwayland
    fi
    
    ! sysrc -n kld_list | grep -q "$DRM_DRIVER" && sysrc kld_list+="$DRM_DRIVER"
    set_monitor_resolution
    mark_done "3"
}

# --- DESKTOP ENVIRONMENTS ---

plasma_config() { 
    bsddialog --infobox "Installing Plasma 6 (KDE) + Printers + KWallet..." 5 65
    pkg install -y --g "plasma6-*" "kf6*"
    # Added plasma6-print-manager for GUI printers and kwalletmanager for Chromium stability
    pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum octopkg plasma6-print-manager kwalletmanager
    mark_done "4"
}

mate_config() { 
    bsddialog --infobox "Installing MATE Desktop..." 5 50
    pkg install -y mate mate-desktop octopkg pavucontrol eom remmina xdg-user-dirs
    mark_done "5"
}

xfce_config() {
    bsddialog --infobox "Installing XFCE4 Desktop..." 5 50
    pkg install -y xfce xfce4-goodies octopkg pavucontrol remmina xdg-user-dirs
    rm -f /usr/local/share/wayland-sessions/xfce*.desktop 2>/dev/null
    mkdir -p /usr/local/share/xsessions
    cat > /usr/local/share/xsessions/xfce.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=XFCE Session (X11)
Exec=startxfce4
Type=Application
DesktopNames=XFCE
EOF
    mark_done "6"
}

# --- SERVICES & APPS ---

apps_config() { 
    bsddialog --infobox "Installing Apps & Configuring Webcam..." 5 60
    pkg install -y firefox chromium thunderbird vlc ffmpeg webcamd ImageMagick7 cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
    
    # Vital Webcam Configuration
    sysrc webcamd_enable="YES"
    ! sysrc -n kld_list | grep -q "cuse" && sysrc kld_list+="cuse"
    [ -n "$USER_NAME" ] && pw groupmod webcamd -m "$USER_NAME" 2>/dev/null
    
    mark_done "7"
}

remote_access_config() { 
    bsddialog --infobox "Installing XRDP & x11vnc..." 5 60
    pkg install -y xrdp xorgxrdp x11vnc zenity
    sysrc xrdp_enable="YES" xrdp_sesman_enable="YES"
    [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ] && mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup
    cat > /usr/local/etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
export LANG=fr_FR.UTF-8
CHOICE=$(zenity --list --title="RDP Session" --text="Choose Desktop:" --radiolist --column="X" --column="Desktop" TRUE "Plasma 6 (KDE)" FALSE "MATE Desktop" FALSE "XFCE4" --width=350 --height=250 2>/dev/null)
case "$CHOICE" in
    "MATE Desktop") exec mate-session ;;
    "XFCE4") exec startxfce4 ;;
    *) exec startplasma-x11 ;;
esac
EOF
    chmod 555 /usr/local/etc/xrdp/startwm.sh
    VNC_PASS=$(bsddialog --title "VNC Console Setup" --insecure --passwordbox "VNC Password:" 9 60 3>&1 1>&2 2>&3)
    [ -n "$VNC_PASS" ] && x11vnc -storepasswd "$VNC_PASS" /usr/local/etc/x11vnc.pwd && chmod 600 /usr/local/etc/x11vnc.pwd
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

vbox_host_config() {
    is_vbox_guest && return
    pkg install -y virtualbox-ose-72; sysrc -f /boot/loader.conf vboxdrv_load="YES" vboxnet_load="YES"; sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root; [ -n "$USER_NAME" ] && pw groupmod vboxusers -m "$USER_NAME"
    mark_done "b"
}

multimedia_config() {
    pkg install -y gimp inkscape krita blender kdenlive obs-studio audacity audacity ffmpeg gstreamer1-plugins-all; mark_done "c"
}

development_config() {
    pkg install -y gcc python3 rust gmake cmake pkgconf gdb cgdb neovim vscode; mark_done "d"
}

nasa_theme() { 
    bsddialog --infobox "Downloading and configuring NASA Theme..." 5 60
    
    [ -d /tmp/fb14_assets ] && rm -rf /tmp/fb14_assets
    [ -f /tmp/fb14_assets.zip ] && rm -f /tmp/fb14_assets.zip
    
    fetch -o /tmp/fb14_assets.zip https://github.com/msartor99/FreeBSD14/archive/refs/heads/main.zip
    unzip -q /tmp/fb14_assets.zip -d /tmp/
    mv /tmp/FreeBSD14-main /tmp/fb14_assets
    rm -f /tmp/fb14_assets.zip
    
    # --- SDDM Theme ---
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

    # --- Boot Menu & Splash (Clean Architecture) ---
    mkdir -p /boot/images
    
    # We copy them under custom names to never overwrite default FreeBSD system files
    cp -f /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/nasa-brand.png
    cp -f /tmp/fb14_assets/freebsd-logo-rev.png /boot/images/nasa-logo.png
    cp -f /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
    
    # Tell the bootloader explicitly to use our new custom images
    sysrc -f /boot/loader.conf loader_brand="/boot/images/nasa-brand.png"
    sysrc -f /boot/loader.conf loader_logo="/boot/images/nasa-logo.png"
    sysrc -f /boot/loader.conf loader_color="YES"
    
    # Leave the splash screen configuration exactly as is
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
    sysrc -f /boot/loader.conf splash_bmp_load="YES"
    sysrc -f /boot/loader.conf splash_txt_load="YES"
    sysrc -f /boot/loader.conf splash_pcx_load="YES"
    
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
        --menu "Select Installation Step:" 22 85 16 \
        "1" "$(get_label "1" "Initial Setup (System, Hardware, Lang, User)")" \
        "2" "$(get_label "2" "GPU: NVIDIA (Auto-Legacy/Latest)")" \
        "3" "$(get_label "3" "GPU/VM: DRM-KMOD & VBox Guest Auto")" \
        "4" "$(get_label "4" "Desktop: Plasma 6 + Printing + KWallet")" \
        "5" "$(get_label "5" "Desktop: MATE")" \
        "6" "$(get_label "6" "Desktop: XFCE4")" \
        "7" "$(get_label "7" "Basic Apps & Fonts + Webcam Support")" \
        "8" "$(get_label "8" "Remote: XRDP (Desktop) & x11vnc (Console)")" \
        "9" "$(get_label "9" "WINE & Winetricks (Needs LATEST)")" \
        "a" "$(get_label "a" "Samba Server (Interactive Share)")" \
        "b" "$(get_label "b" "VirtualBox 7.2 Host")" \
        "c" "$(get_label "c" "Multimedia Creation (GIMP, OBS...)")" \
        "d" "$(get_label "d" "Dev Tools (GCC, Python, VSCode)")" \
        "e" "$(get_label "e" "NASA Theme (SDDM & Boot)")" \
        "f" "$(get_label "f" "Upgrade to LATEST Branch (WARNING)")" \
        "q" "Quit" 3>&1 1>&2 2>&3)

    case $MAIN_CHOICE in
        1) initial_setup ;; 2) nvidia_config ;; 3) drm_config ;; 4) plasma_config ;; 5) mate_config ;; 6) xfce_config ;;
        7) apps_config ;; 8) remote_access_config ;; 9) wine_config ;; a) samba_config ;; b) vbox_host_config ;;
        c) multimedia_config ;; d) development_config ;; e) nasa_theme ;; f) switch_latest ;; q|*) break ;;
    esac
done
clear
echo "Script finished. Please reboot."
