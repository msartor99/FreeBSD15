#!/bin/sh
# ==============================================================================
# PROJECT MODERN-BSD : FreeBSD 15 + Cinnamon + NVIDIA (Master Auto-Installer)
# EDITION      : Developer / Ultimate Edition (English & Universal)
# FEATURES     : ZFS Boot Env, Doas, Qt/GTK Bridge, Microcodes, Advanced Logging
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

BACKTITLE="FreeBSD 15 Universal Workstation Installer"
LOG_FILE="/var/log/modern_bsd_installer.log"

# Initialize a clean log file for this run
: > "$LOG_FILE"

log_message() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# Advanced execution wrapper that logs everything transparently
log_exec() {
    local cmd_desc="$1"
    shift
    log_message "START: $cmd_desc"
    log_message "COMMAND: $*"
    
    # Run the command, redirect output to log file
    "$@" >> "$LOG_FILE" 2>&1
    local ret=$?
    
    if [ $ret -ne 0 ]; then
        log_message "ERROR: '$cmd_desc' failed with exit code $ret"
    else
        log_message "SUCCESS: '$cmd_desc' completed successfully."
    fi
    return $ret
}

# Write initial log header
log_message "================================================================="
log_message "STARTING MODERN-BSD AUTOMATED INSTALLER"
log_message "OS: $(uname -srm)"
log_message "================================================================="

# ==============================================================================
# BLOCK 1: DISCLAIMER & INTERACTIVE MENUS
# ==============================================================================

show_disclaimer() {
    local msg="DISCLAIMER OF LIABILITY\n\n\
This script deeply modifies the configuration of your FreeBSD system. \
It is provided 'as is', without any express or implied warranty. \
By using it, you agree that the author cannot be held responsible \
for any data loss, system failure, or other damage.\n\n\
Do you accept these terms to continue?"

    if ! bsddialog --backtitle "$BACKTITLE" --title "Warning & Disclaimer" --yesno "$msg" 14 75; then
        clear
        echo "Installation cancelled by the user. No changes were made."
        log_message "Installation cancelled by user at the disclaimer prompt."
        exit 1
    fi
}

# Run the disclaimer first
show_disclaimer

SYS_KBD=$(sysrc -n keymap 2>/dev/null | grep -Eo '^[a-z]{2}' || echo "us")
DEFAULT_LANG="en_US.UTF-8"
DEFAULT_X11_KBD="us"

case "$SYS_KBD" in
    fr) DEFAULT_LANG="fr_FR.UTF-8"; DEFAULT_X11_KBD="fr" ;;
    ch) DEFAULT_LANG="fr_CH.UTF-8"; DEFAULT_X11_KBD="ch-fr" ;;
    de) DEFAULT_LANG="de_DE.UTF-8"; DEFAULT_X11_KBD="de" ;;
esac

USER_LOCALE=$(bsddialog --backtitle "$BACKTITLE" --title "Language & Region" --default-item "$DEFAULT_LANG" --menu "Select System Language:" 15 60 8 \
    "en_US.UTF-8" "English (US)" \
    "en_GB.UTF-8" "English (UK)" \
    "fr_FR.UTF-8" "French (France)" \
    "fr_CH.UTF-8" "French (Switzerland)" \
    "de_DE.UTF-8" "German (Germany)" \
    "de_CH.UTF-8" "German (Switzerland)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; log_message "Installation aborted during language selection."; exit 1; fi

X11_KBD=$(bsddialog --backtitle "$BACKTITLE" --title "Keyboard (X11)" --default-item "$DEFAULT_X11_KBD" --menu "Select Keyboard Layout:" 15 60 8 \
    "us" "US English" \
    "gb" "UK English" \
    "fr" "French (AZERTY)" \
    "ch-fr" "Swiss French (QWERTZ)" \
    "ch-de" "Swiss German (QWERTZ)" \
    "de" "German (QWERTZ)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; log_message "Installation aborted during keyboard layout selection."; exit 1; fi

case "$X11_KBD" in
    *-*) XKBLAYOUT="${X11_KBD%%-*}"; XKBVARIANT="${X11_KBD##*-}" ;;
    *)   XKBLAYOUT="$X11_KBD"; XKBVARIANT="" ;;
esac

while true; do
    TARGET_USER=$(bsddialog --backtitle "$BACKTITLE" --title "Target User" --inputbox "Enter the target username (e.g., admin):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$TARGET_USER" ]; then clear; log_message "Installation aborted during user selection."; exit 1; fi
    if id "$TARGET_USER" >/dev/null 2>&1; then break; else bsddialog --title "Error" --msgbox "User '$TARGET_USER' does not exist." 8 50; fi
done
USER_HOME=$(eval echo "~$TARGET_USER")

CPU_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "CPU Selection" --menu "Select Processor for Microcode Updates:" 12 55 3 \
    1 "Intel CPU" 2 "AMD CPU" 3 "Skip (Virtual Machine)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; log_message "Installation aborted during CPU selection."; exit 1; fi

GPU_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "GPU Selection" --menu "Select Graphics Card Vendor:" 12 50 3 \
    1 "AMD" 2 "NVIDIA" 3 "Intel" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; log_message "Installation aborted during GPU selection."; exit 1; fi

if [ "$GPU_CHOICE" = "2" ]; then
    NV_VER=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Version" --menu "Select NVIDIA Driver Branch:" 12 60 3 \
        1 "Latest (595+)" 2 "Legacy 580" 3 "Legacy 470" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then clear; log_message "Installation aborted during NVIDIA driver branch selection."; exit 1; fi
fi

clear
log_message "Configuration parsed: User=$TARGET_USER, Locale=$USER_LOCALE, X11_Kbd=$XKBLAYOUT/$XKBVARIANT, CPU_Choice=$CPU_CHOICE, GPU_Choice=$GPU_CHOICE"

step_start() { 
    printf "\n\033[1;36m================================================================================\033[0m\n"
    printf "\033[1;36m %s \033[0m\n" "$1"
    printf "\033[1;36m================================================================================\033[0m\n"
    printf "→ Check execution logs inside: %s\n\n" "$LOG_FILE"
}

# ==============================================================================
# BLOCK 2: INFRASTRUCTURE & FREEBSD FIXES
# ==============================================================================
step_start "1/8: Core Services & FreeBSD Fixes"

printf "Enabling system daemons (dbus, sddm, cupsd, autofs)...\n"
log_exec "sysrc_dbus" sysrc dbus_enable="YES"
log_exec "sysrc_sddm" sysrc sddm_enable="YES"
log_exec "sysrc_cupsd" sysrc cupsd_enable="YES"
log_exec "sysrc_autofs" sysrc autofs_enable="YES"

printf "Configuring filesystem subsystems (procfs, fdescfs)...\n"
if ! grep -q "procfs" /etc/fstab; then 
    echo "proc    /proc    procfs    rw    0    0" >> /etc/fstab
    log_exec "mount_procfs" mount -t procfs proc /proc
fi
if ! grep -q "fdescfs" /etc/fstab; then 
    echo "fdesc   /dev/fd   fdescfs   rw   0   0" >> /etc/fstab
    log_exec "mount_fdescfs" mount -t fdescfs fdesc /dev/fd
fi

printf "Generating system machine-id and local hosts mapping...\n"
if [ ! -s /etc/machine-id ]; then 
    log_exec "dbus_uuid" sh -c "dbus-uuidgen > /etc/machine-id"
fi
if ! grep -q "localhost $(hostname)" /etc/hosts; then 
    echo "127.0.0.1 localhost $(hostname)" >> /etc/hosts
fi

printf "Bootstrapping package manager databases...\n"
log_exec "pkg_bootstrap" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap -f
log_exec "pkg_update" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg update -f

# ==============================================================================
# BLOCK 3: CPU MICROCODE & PACKAGE INSTALLATION
# ==============================================================================
step_start "2/8: CPU Microcode & System Packages"

if [ "$CPU_CHOICE" = "1" ]; then
    printf "Installing and configuring Intel CPU firmware microcodes...\n"
    log_exec "pkg_intel_ucode" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y devcpu-data-intel
    log_exec "loader_intel_1" sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    log_exec "loader_intel_2" sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    log_exec "sysrc_microcode" sysrc microcode_update_enable="YES"
elif [ "$CPU_CHOICE" = "2" ]; then
    printf "Installing and configuring AMD CPU firmware microcodes...\n"
    log_exec "pkg_amd_ucode" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y devcpu-data-amd
    log_exec "loader_amd_1" sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    log_exec "loader_amd_2" sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    log_exec "sysrc_microcode" sysrc microcode_update_enable="YES"
fi

printf "Deploying core meta-packages (X11, Desktop Environment, Themes, Applications)...\n"
printf "Note: This process may take a few minutes. Outputs redirected to logs.\n"
log_exec "pkg_install_master_list" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y \
    xorg xprop xorg-apps sddm pulseaudio pavucontrol cups system-config-printer automount fusefs-ntfs fusefs-exfat gvfs \
    cinnamon cinnamon-screensaver doas unzip wget alacritty flameshot htop neofetch firefox vlc \
    gtk-arc-themes papirus-icon-theme qt5-style-plugins qt5ct qt6ct

# ==============================================================================
# BLOCK 4: GPU CONFIGURATION
# ==============================================================================
step_start "3/8: GPU Configuration"
case $GPU_CHOICE in
    2)
        printf "Configuring NVIDIA proprietary graphics pipelines...\n"
        KMOD_DRIVER="nvidia-modeset"
        case $NV_VER in 2) NV_BASE="nvidia-driver-580" ;; 3) NV_BASE="nvidia-driver-470" ;; *) NV_BASE="nvidia-driver" ;; esac
        log_exec "pkg_nvidia" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y "$NV_BASE" nvidia-xconfig nvidia-settings
        if [ -f /usr/local/bin/nvidia-xconfig ]; then 
            log_exec "nvidia_xconfig" nvidia-xconfig
        fi
        ;;
    3) 
        printf "Configuring Intel integrated graphics kernel modesetting...\n"
        KMOD_DRIVER="i915kms"
        log_exec "pkg_intel_graphics" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod libva-intel-driver 
        ;;
    *) 
        printf "Configuring AMD Radeon open-source kernel modesetting...\n"
        KMOD_DRIVER="amdgpu"
        log_exec "pkg_amd_graphics" env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod 
        ;;
esac

printf "Registering graphics module into kernel load list...\n"
CURRENT_KMODS=$(sysrc -n kld_list)
case "$CURRENT_KMODS" in *"$KMOD_DRIVER"*) ;; *) log_exec "sysrc_kld" sysrc kld_list+="$KMOD_DRIVER" ;; esac

# ==============================================================================
# BLOCK 5: SECURITY (DOAS), KEYBOARD & PERMISSIONS
# ==============================================================================
step_start "4/8: Pure Philosophy: Doas, Keyboard & Device Permissions"

printf "Writing lightweight escalation policy (/usr/local/etc/doas.conf)...\n"
mkdir -p /usr/local/etc
if ! grep -q "permit persist :wheel" /usr/local/etc/doas.conf 2>/dev/null; then
    echo "permit persist :wheel" > /usr/local/etc/doas.conf
    echo "permit nopass :operator cmd /sbin/shutdown" >> /usr/local/etc/doas.conf
fi
log_exec "symlink_sudo" ln -sf /usr/local/bin/doas /usr/local/bin/sudo

printf "Generating X11 global keyboard geometry configurations...\n"
log_exec "sysrc_sddm_lang" sysrc sddm_lang="${USER_LOCALE%%.*}"
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$XKBLAYOUT"
        Option "XkbVariant" "$XKBVARIANT"
EndSection
EOF

XSETUP="/usr/local/share/sddm/scripts/Xsetup"
if [ -f "$XSETUP" ]; then
    sed -i '' '/setxkbmap/d' "$XSETUP" 2>/dev/null
    echo "setxkbmap -layout $XKBLAYOUT ${XKBVARIANT:+-variant $XKBVARIANT}" >> "$XSETUP"
fi

printf "Injecting device rules for users (USB storage, audio nodes, optical paths)...\n"
log_exec "sysctl_usermount" sysrc -f /etc/sysctl.conf vfs.usermount=1
sysctl vfs.usermount=1 >/dev/null
cat > /etc/devfs.rules << 'EOF'
[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'lpt*' mode 0660 group cups
add path 'ulpt*' mode 0660 group cups
add path 'unlpt*' mode 0660 group cups
EOF
log_exec "sysrc_devfs" sysrc devfs_system_ruleset="localrules"
log_exec "service_devfs" service devfs restart

printf "Compiling regional locale capabilities class database...\n"
CLASS_NAME="custom_${USER_LOCALE%%.*}"
sed -i '' "/^${CLASS_NAME}|/,/:tc=default:/d" /etc/login.conf 2>/dev/null
printf "%s|Custom User Class:\n\t:charset=UTF-8:\n\t:lang=%s:\n\t:tc=default:\n" "$CLASS_NAME" "$USER_LOCALE" >> /etc/login.conf
log_exec "cap_mkdb" cap_mkdb /etc/login.conf

printf "Modifying target user groups and system capability class...\n"
log_exec "pw_usermod" pw usermod "$TARGET_USER" -G wheel,operator,video,cups -L "$CLASS_NAME"

# ==============================================================================
# BLOCK 6: ULTIMATE WRAPPER & SDDM CONFIGURATION
# ==============================================================================
step_start "5/8: SDDM Configuration, Wrapper & Wallpapers"

printf "Setting up SDDM Maldives login environment configuration...\n"
mkdir -p /usr/local/etc/sddm.conf.d
printf "[Theme]\nCurrent=maldives\n" > /usr/local/etc/sddm.conf.d/10-theme.conf

mkdir -p /usr/local/share/backgrounds
if [ -f /usr/local/share/sddm/themes/maldives/background.jpg ]; then
    cp -f /usr/local/share/sddm/themes/maldives/background.jpg /usr/local/share/backgrounds/maldives-beach.jpg
    chmod 644 /usr/local/share/backgrounds/maldives-beach.jpg
fi

printf "Downloading Veligandu Island public asset from reference GitHub raw node...\n"
log_exec "fetch_wallpaper" fetch -o /usr/local/share/backgrounds/veligandu-island.jpg "https://raw.githubusercontent.com/msartor99/FreeBSD15/a14e0129b3fcfbe40901ce20c2ffaefe674e5201/veligandu-island.jpg"
chmod 644 /usr/local/share/backgrounds/veligandu-island.jpg

printf "Creating unified startup wrapper with environment bridges (/usr/local/bin/start-cinnamon)...\n"
cat > /usr/local/bin/start-cinnamon << EOF
#!/bin/sh
export LANG="$USER_LOCALE"
export LC_ALL="$USER_LOCALE"
export LANGUAGE="$USER_LOCALE"
export QT_QPA_PLATFORMTHEME="gtk3"

exec dbus-launch --exit-with-session /usr/local/bin/cinnamon-session
EOF
chmod +x /usr/local/bin/start-cinnamon

mkdir -p /usr/local/share/xsessions
cat > /usr/local/share/xsessions/cinnamon.desktop << 'EOF'
[Desktop Entry]
Name=Cinnamon
Comment=FreeBSD Custom Cinnamon Launcher
Exec=/usr/local/bin/start-cinnamon
TryExec=/usr/local/bin/start-cinnamon
Icon=
Type=Application
EOF

# ==============================================================================
# BLOCK 7: USER PROFILE & ALACRITTY
# ==============================================================================
step_start "6/8: Local Profile & Terminal Configuration"

printf "Writing Alacritty GPU-accelerated terminal definition block...\n"
mkdir -p "$USER_HOME/.config/dconf"
mkdir -p "$USER_HOME/.config/alacritty"

cat > "$USER_HOME/.config/alacritty/alacritty.toml" << 'EOF'
[window]
opacity = 0.85
padding = { x = 12, y = 12 }
dynamic_padding = true
[font]
size = 11.0
[colors.primary]
background = "#0f1c2e"
foreground = "#d8e2eb"
[colors.normal]
black   = "#0f1c2e"
red     = "#e06c75"
green   = "#98c379"
yellow  = "#e5c07b"
blue    = "#61afef"
magenta = "#c678dd"
cyan    = "#56b6c2"
white   = "#d8e2eb"
EOF

# ==============================================================================
# BLOCK 8: THEMATIC AUTOSTART INJECTION
# ==============================================================================
step_start "7/8: Preparing Theme Injection (Autostart)"

printf "Injecting self-destructing layout engine into XDG Autostart sequence...\n"
mkdir -p "$USER_HOME/.config/autostart"

cat > "$USER_HOME/.config/autostart/apply-cinnamon-theme.sh" << 'EOF'
#!/bin/sh
sleep 3
gsettings set org.cinnamon.desktop.background picture-uri "'file:///usr/local/share/backgrounds/veligandu-island.jpg'"
gsettings set org.cinnamon.desktop.background picture-options "'zoom'"
gsettings set org.cinnamon.desktop.interface gtk-theme "'Arc'"
gsettings set org.cinnamon.desktop.wm.preferences theme "'Arc'"
gsettings set org.cinnamon.theme name "'Arc'"
gsettings set org.cinnamon.desktop.interface icon-theme "'Papirus'"
gsettings set org.cinnamon.desktop.default-applications.terminal exec "'alacritty'"
rm -f "$HOME/.config/autostart/apply-cinnamon-theme.desktop"
rm -f "$0"
EOF
chmod +x "$USER_HOME/.config/autostart/apply-cinnamon-theme.sh"

cat > "$USER_HOME/.config/autostart/apply-cinnamon-theme.desktop" << EOF
[Desktop Entry]
Type=Application
Name=ThemeInjector
Exec=$USER_HOME/.config/autostart/apply-cinnamon-theme.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

log_exec "chown_user_home" chown -R "$TARGET_USER" "$USER_HOME"

# ==============================================================================
# BLOCK 9: ZFS INDESTRUCTIBILITY
# ==============================================================================
step_start "8/8: ZFS Securing"

if mount | grep -q 'on / (zfs,'; then
    printf "ZFS pool sublayer detected. Packaging Boot Environment 'sys_cinnamon_clean'...\n"
    log_exec "zfs_bectl_destroy" bectl destroy sys_cinnamon_clean 2>/dev/null
    log_exec "zfs_bectl_create" bectl create sys_cinnamon_clean
    printf "👉 ZFS System State immortalized. Recovery point active.\n"
else
    printf "Target root mountpoint does not reside on ZFS. Skipping recovery snapshot layer.\n"
fi

log_message "================================================================="
log_message "MODERN-BSD INSTALLATION SUCCESSFULLY COMPLETE"
log_message "================================================================="

printf "\n\033[1;32m[ SUCCESS ] Ultimate UNIX/Cinnamon installation completed successfully.\033[0m\n"
printf "Please reboot the machine (/sbin/shutdown -r now).\n"
printf "On first login, let the script apply the magic of the Maldives!\n\n"