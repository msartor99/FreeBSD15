#!/bin/sh

# ==============================================================================
# ULTIMATE POST-INSTALL SCRIPT : FREEBSD 15 + NVIDIA + PLASMA WAYLAND/X11
# ==============================================================================

# --- 0. DISCLAIMER & USER ACCEPTANCE (bsddialog) ---
bsddialog --title "DISCLAIMER & WARNING" --yesno \
"WARNING:\n\n\
This post-installation script deeply modifies the FreeBSD configuration \
(KMS, DRM, network, user groups, Wayland, SDDM, ZFS).\n\n\
The author assumes no responsibility for data loss, kernel panics, \
or system instability.\n\n\
Do you understand the risks and wish to proceed with the deployment?" 14 70

if [ $? -ne 0 ]; then
    clear
    echo "Operation canceled by the user. The system has not been modified."
    exit 1
fi

# --- 0.5 CPU SELECTION ---
bsddialog --title "CPU SELECTION" --menu "Select your CPU manufacturer:" 10 50 2 \
"AMD" "AMD Processor" \
"Intel" "Intel Processor" 2> /tmp/cpu_choice

if [ $? -ne 0 ]; then
    clear
    echo "Operation canceled during CPU selection."
    rm -f /tmp/cpu_choice
    exit 1
fi
CPU_CHOICE=$(cat /tmp/cpu_choice)
rm -f /tmp/cpu_choice
clear

echo "=== 1. Boot and System Optimizations ==="
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc splash_changer_enable="YES"
sysrc rc_startmsgs="NO"

sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc

grep -q "^kern.sched.preempt_thresh" /etc/sysctl.conf || echo "kern.sched.preempt_thresh=224" >> /etc/sysctl.conf
grep -q "^kern.ipc.shm_allow_removed" /etc/sysctl.conf || echo "kern.ipc.shm_allow_removed=1" >> /etc/sysctl.conf
grep -q "^net.local.stream.recvspace" /etc/sysctl.conf || echo "net.local.stream.recvspace=65536" >> /etc/sysctl.conf
grep -q "^net.local.stream.sendspace" /etc/sysctl.conf || echo "net.local.stream.sendspace=65536" >> /etc/sysctl.conf
grep -q "^vfs.usermount" /etc/sysctl.conf || echo "vfs.usermount=1" >> /etc/sysctl.conf

echo "=== 2. Temperature Management & Microcode ($CPU_CHOICE) ==="
pkg install -y sensors cpu-microcode

if [ "$CPU_CHOICE" = "AMD" ]; then
    sysrc -f /boot/loader.conf amdtemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
elif [ "$CPU_CHOICE" = "Intel" ]; then
    sysrc -f /boot/loader.conf coretemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
fi

echo "=== 3. Utilities, Sudo, and SSH (For Putty) ==="
pkg install -y doas sudo unzip libzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools
sysrc smartd_enable="YES"
[ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf

mkdir -p /usr/local/etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /usr/local/etc/sudoers.d/wheel_nopasswd
chmod 0440 /usr/local/etc/sudoers.d/wheel_nopasswd
sysrc sshd_enable="YES"

echo "=== 4. Aquantia P620 Driver & Dynamic Network Migration ==="
bsddialog --title "AQUANTIA DRIVER INSTALLATION" --yesno \
"Do you want to install the Aquantia P620 network driver and migrate the network configuration to aq0?" 10 70

if [ $? -eq 0 ]; then
    fetch https://raw.githubusercontent.com/msartor99/FreeBSD15-aquantia-P620/da2d1d91b8aff3c0fce658eba7207f64e82ce03d/build_aquantia.sh -o /tmp/build_aquantia.sh
    chmod +x /tmp/build_aquantia.sh
    sh /tmp/build_aquantia.sh

    kldload if_aq 2>/dev/null
    sleep 2

    if ifconfig aq0 2>/dev/null | grep -iq "status: no carrier"; then
        bsddialog --title "HARDWARE ALERT" --msgbox \
"The Aquantia network card (aq0) is successfully installed, but shows 'no carrier' (no signal).\n\n\
This is a known behavior. After this script finishes, you MUST perform a COLD BOOT (physically power off the computer, unplug the power cord for 10 seconds) to initialize the card." 12 70
    fi

    OLD_IF=$(route -n get default 2>/dev/null | grep "interface:" | awk '{print $2}')

    if [ -n "$OLD_IF" ] && [ "$OLD_IF" != "aq0" ]; then
        OLD_CONF=$(sysrc -n ifconfig_${OLD_IF} 2>/dev/null)
        
        bsddialog --title "NETWORK MIGRATION" --yesno \
"The script detected that you are currently using the '$OLD_IF' interface.\n\
Current configuration: $OLD_CONF\n\n\
Do you want to automatically transfer this configuration to the new Aquantia card (aq0) and remove the old card?" 12 70
        
        if [ $? -eq 0 ]; then
            sysrc -x ifconfig_${OLD_IF}
            sed -i '' -E '/if_(ure|axe|axge|cdce|urndt|rue)_load="YES"/d' /boot/loader.conf
            
            if [ -n "$OLD_CONF" ]; then
                sysrc ifconfig_aq0="$OLD_CONF"
            else
                sysrc ifconfig_aq0="inet 192.168.254.3 netmask 255.255.255.0"
            fi
            bsddialog --title "SUCCESS" --msgbox "Configuration successfully transferred to aq0.\nYou can unplug your USB network adapter after rebooting." 8 60
        fi
    fi
else
    echo "Skipping Aquantia driver installation and network migration."
fi

echo "=== 5. Linux Environment ==="
sysrc linux_enable="YES"
sysrc linux64_enable="YES"

echo "=== 6. Language Configuration and Users ==="
if ! grep -q "^french|" /etc/login.conf; then
cat << 'EOF' >> /etc/login.conf
french|French Users Accounts:\
        :charset=UTF-8:\
        :lang=fr_FR.UTF-8:\
        :lc_all=fr_FR:\
        :lc_collate=fr_FR:\
        :lc_ctype=fr_FR:\
        :lc_messages=fr_FR:\
        :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
echo 'defaultclass=french' > /etc/adduser.conf

pw usermod administrateur -G wheel,operator,video -L french 2>/dev/null
pw usermod root -L french

echo "=== 7. Hardware Permissions (devfs) ==="
if ! grep -q "\[localrules=5\]" /etc/devfs.rules 2>/dev/null; then
cat >> /etc/devfs.rules << 'EOF'
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
add path "drm" mode 0775 group video
add path "drm/*" mode 0660 group video
add path "dri" mode 0775 group video
add path "dri/*" mode 0660 group video
add path "video*" mode 0660 group video
add path "pci*" mode 0660 group video
EOF
fi
sysrc devfs_system_ruleset="localrules"

echo "=== 8. Printers & File Systems ==="
pkg install -y cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
sysrc cupsd_enable="YES"
sysrc kld_list+="fusefs ext2fs"

echo "=== 9. Xorg, DBUS, and Keyboard ==="
pkg install -y xorg dbus avahi signal-cli seatd
sysrc dbus_enable="YES"
sysrc avahi_enable="YES"
sysrc seatd_enable="YES"

grep -q "^proc" /etc/fstab || echo "proc        /proc      procfs      rw      0       0" >>/etc/fstab
grep -q "^fdesc" /etc/fstab || echo "fdesc      /dev/fd    fdescfs     rw      0       0" >>/etc/fstab

mkdir -p /usr/local/etc/X11/xorg.conf.d/
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << 'EOF'
Section "ServerFlags"
                 Option "DontZap" "false"
EndSection
Section     "InputClass"
           Identifier     "All Keyboards"
           MatchIsKeyboard    "yes"
           Option     "XkbLayout" "ch"
           Option     "XkbVariant" "fr"
           Option     "XkbOptions" "terminate:ctrl_alt_bksp" 
EndSection
EOF

echo "=== 10. Audio & Multimedia ==="
pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme
sysrc sound_load="YES"
sysrc snd_hda_load="YES"
grep -q "^hw.snd.default_unit" /etc/sysctl.conf || echo "hw.snd.default_unit=1" >> /etc/sysctl.conf

echo "=== 11. NVIDIA Drivers & KMS ==="
pkg install -y nvidia-driver linux-nvidia-libs nvidia-settings nvidia-xconfig wayland xwayland

sysrc kld_list+="nvidia-drm nvidia-modeset"
sysrc nvidia_modeset_enable="YES"
sysrc -f /boot/loader.conf hw.nvidiadrm.modeset="1"
sysrc -f /boot/loader.conf hw.nvidia.registry.EnableGpuFirmware="1"

cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
EndSection
EOF
nvidia-xconfig

echo "=== 12. Applications, Video Acceleration & Fonts ==="
pkg install -y firefox thunderbird vlc ffmpeg libva-vdpau-driver libva-utils vdpauinfo libdvdread libdvdnav signal-cli xdg-user-dirs octopkg multimedia/mpv gstreamer1-plugins-all gstreamer1-libav libbluray
pkg install -y cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf \
chinese/arphicttf chinese/font-std hebrew/culmus hebrew/elmar-fonts japanese/font-ipa japanese/font-ipa-uigothic japanese/font-ipaex japanese/font-kochi japanese/font-migmix japanese/font-migu japanese/font-mona-ipa japanese/font-motoya-al japanese/font-mplus-ipa japanese/font-sazanami japanese/font-shinonome japanese/font-takao japanese/font-ume japanese/font-vlgothic x11-fonts/hanazono-fonts-ttf japanese/font-mikachan korean/aleefonts-ttf korean/nanumfonts korean/unfonts-core x11-fonts/anonymous-pro x11-fonts/artwiz-aleczapka x11-fonts/dejavu x11-fonts/isabella x11-fonts/junicode x11-fonts/khmeros x11-fonts/padauk x11-fonts/stix-fonts x11-fonts/charis x11-fonts/urwfonts-ttf russian/koi8r-ps x11-fonts/geminifonts x11-fonts/cyr-rfx x11-fonts/paratype x11-fonts/nerd-fonts \
twemoji-color-font-ttf textproc/ibus-uniemoji
pkg install -y x11-themes/papirus-icon-theme x11-themes/cursor-neutral-white-theme x11-themes/qogir-icon-themes x11-themes/win98se-icon-theme

echo "=== 13. SDDM & NASA Theme ==="
pkg install -y sddm
sysrc sddm_enable="YES"
sysrc sddm_lang="ch_FR"
pw groupmod video -m sddm

git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14_assets
if [ -d "/usr/local/share/sddm/themes" ]; then
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/ 2>/dev/null
    cp /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/
    cp /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/
    rm -f /usr/local/share/sddm/themes/nasa/background.jpg
    cp /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
fi

mkdir -p /usr/local/share/xsessions
mkdir -p /usr/local/share/wayland-sessions

cat > /usr/local/etc/sddm.conf << 'EOF'
[Theme]
Current=nasa
[General]
background=background.jpg
displayFont="Montserrat"
EOF

cp -r /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/
cp -r /tmp/fb14_assets/freebsd-logo-rev.png  /boot/images/
cp -r /tmp/fb14_assets/nasa1920.png  /boot/images/splash.png
sysrc -f /boot/loader.conf splash="/boot/images/splash.png"

echo "=== 14. KDE Plasma 6 & Trojan Horse Wayland Fix ==="
pkg install -y --g "plasma6-*" "kf6*" pavucontrol kate konsole ark remmina dolphin Kvantum

mkdir -p /usr/local/bin
cat > /usr/local/bin/startplasma-nvidia.sh << 'EOF'
#!/bin/sh
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR
fi

export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export KWIN_DRM_USE_EGL_STREAMS=0
export LIBSEAT_BACKEND=seatd
export WLR_NO_HARDWARE_CURSORS=1
export XDG_SESSION_TYPE=wayland

exec dbus-run-session startplasma-wayland
EOF
chmod +x /usr/local/bin/startplasma-nvidia.sh

# The Trojan Horse: Putting the Wayland launcher directly in the X11 folder
cat > /usr/local/share/xsessions/plasma-nvidia-wayland.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/startplasma-nvidia.sh
DesktopNames=KDE
Name=Plasma (NVIDIA Wayland)
Comment=KDE Wayland Session optimized for NVIDIA
EOF


echo "=== 15. Warrior Tools: Powerd, NTP & ZFS Boot Environment ==="

# 15.1 CPU Frequency Scaling (Powerd)
sysrc powerd_enable="YES"
sysrc powerd_flags="-a hiadaptive -b adaptive"

# 15.2 Time Synchronization (NTPd) - Fixed for DNS Boot Delays
sysrc ntpd_enable="YES"
sysrc ntpd_sync_on_start="NO"
sysrc ntpd_flags="-g"

# 15.3 ZFS Boot Environment (Immortality Snapshot)
if mount | grep -q 'on / (zfs'; then
    echo "Creating ZFS Boot Environment snapshot (post-install-clean)..."
    bectl create post-install-clean
    echo "Snapshot created. You can rollback to this exact state anytime from the boot menu."
fi


echo "=== 16. System Upgrade (Quarterly to Latest) ==="
bsddialog --title "PACKAGE REPOSITORY UPGRADE" --yesno \
"Base installation and Warrior Tools are complete!\n\n\
Do you want to switch the FreeBSD package repository from 'quarterly' to 'latest' and upgrade the system now?\n\n\
This is highly recommended for KDE Plasma 6 and Wayland to ensure you have the absolute newest patches." 12 70

if [ $? -eq 0 ]; then
    echo "Switching repository to 'latest' branch..."
    mkdir -p /usr/local/etc/pkg/repos
    if [ ! -f /usr/local/etc/pkg/repos/FreeBSD.conf ]; then
        cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf
    fi
    sed -i '' 's/quarterly/latest/g' /usr/local/etc/pkg/repos/FreeBSD.conf
    
    echo "Updating package catalog and upgrading system (this may take a while)..."
    pkg update -f
    pkg upgrade -y
else
    echo "Keeping the 'quarterly' repository branch. No full upgrade performed."
fi


clear
bsddialog --title "INSTALLATION COMPLETE" --msgbox \
"The WARRIOR post-deployment installation is officially complete!\n\n\
- Time Sync (NTP without boot delay) and CPU Scaling are active.\n\
- A ZFS Boot Environment (snapshot) has been safely created.\n\
- Aquantia, SDDM, X11, and the Wayland Trojan Horse are set.\n\n\
If Aquantia showed 'no carrier' earlier, do not forget to perform a Cold Boot (physically power off and unplug for 10 seconds).\n\n\
You may now close this setup and manually 'reboot' when ready." 16 70
