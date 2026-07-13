#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Erreur : Ce script doit être exécuté en tant que root." >&2
    exit 1
fi

echo "=== Configuration Idempotente FreeBSD 15.1 + Style Windows 11 ==="

# 1. BASE CONFIG & SSH
if ! grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    service sshd restart
fi
freebsd-update fetch install --not-running-from-cron

# 2. LOADER CONFIGURATION (SPLASH SCREEN VT PNG CORRECTION)
touch /boot/loader.conf
add_to_loader() {
    if ! grep -q "^$1=" /boot/loader.conf; then
        echo "$1=\"$2\"" >> /boot/loader.conf
    else
        sed -i '' "s|^$1=.*|$1=\"$2\"|" /boot/loader.conf
    fi
}
sed -i '' '/hw.vga.textmode/d' /boot/loader.conf

add_to_loader "kern.vty" "vt"
add_to_loader "boot_mute" "YES"
add_to_loader "autoboot_delay" "3"
add_to_loader "efi_max_resolution" "1920x1080"
add_to_loader "kern.vt.fb.default_mode" "1920x1080"
add_to_loader "tmpfs_load" "YES"
add_to_loader "aio_load" "YES"
add_to_loader "coretemp_load" "YES"
add_to_loader "cpu_microcode_name" "/boot/firmware/intel-ucode.bin"
add_to_loader "splash" "/boot/images/splash.png"
add_to_loader "shutdown_splash" "/boot/images/splash.png"
add_to_loader "hw.nvidiadrm.modeset" "1"
add_to_loader "hw.nvidia.registry.EnableGpuFirmware" "1"
add_to_loader "nvidia-drm.modeset" "1"

sysrc -q rc_startmsgs=NO

# 3. SYSCTL CONFIGURATION
touch /etc/sysctl.conf
add_to_sysctl() {
    if ! grep -q "^$1" /etc/sysctl.conf; then echo "$1" >> /etc/sysctl.conf; fi
}
add_to_sysctl "kern.sched.preempt_thresh=224"
add_to_sysctl "kern.ipc.shm_allow_removed=1"
add_to_sysctl "net.local.stream.recvspace=65536"
add_to_sysctl "net.local.stream.sendspace=65536"
add_to_sysctl "vfs.usermount=1"
add_to_sysctl "hw.snd.default_unit=1"

# 4. INTEL CPU & MICROCODE
pkg install -y cpu-microcode devices-sensors 2>/dev/null || pkg install -y cpu-microcode sensors
sysrc -q microcode_update_enable="YES"
service microcode_update start 2>/dev/null || true

# 5. LINUX & NVIDIA GRAPHICS DRIVERS
sysrc -q linux_enable="YES"
sysrc -q linux_mounts_enable="YES"
service linux start 2>/dev/null || true

pkg install -y nvidia-driver-580 linux-nvidia-libs-580 nvidia-kmod-580 nvidia-drm-kmod-580 libc6-shim nvidia-settings nvidia-xconfig
sysrc -q nvidia_modeset_enable="YES"

if [ ! -f /etc/X11/xorg.conf ] && [ ! -f /usr/local/etc/X11/xorg.conf ]; then
    nvidia-xconfig
fi

# 6. BASE UTILITIES & SMARTD
pkg install -y doas unzip libzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools
sysrc -q smartd_enable="YES"
if [ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi
service smartd start 2>/dev/null || true

# 7. FRENCH (SUISSE) LOCALIZATION
if ! grep -q "^french|French Users Accounts:" /etc/login.conf; then
    cat >> /etc/login.conf << 'EOF'
french|French Users Accounts:\
     :charset=UTF-8:\
     :lang=fr_CH.UTF-8:\
      lc_all=fr_CH.UTF-8:\
     :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
echo 'defaultclass=french' > /etc/adduser.conf

if pw user show administrateur >/dev/null 2>&1; then
    pw usermod administrateur -G wheel,operator,video -L french
fi
pw usermod root -L french

# 8. SKEL USER PROFILE (AUTOMATIC USER SETTINGS VA-API/VDPAU FOR NVIDIA)
inject_user_profile() {
    touch "$1"
    if ! grep -q "export VDPAU_DRIVER" "$1"; then
        cat >> "$1" << 'EOF'
# --- Accélération matérielle NVIDIA ---
export VDPAU_DRIVER="nvidia"
export LIBVA_DRIVER_NAME="vdpau"
alias vlc="vlc --avcodec-hw=vdpau"
EOF
    fi
}
inject_user_profile "/usr/share/skel/dot.shrc"
if [ -d /home/administrateur ]; then
    inject_user_profile "/home/administrateur/.shrc"
    chown administrateur:administrateur /home/administrateur/.shrc
fi
inject_user_profile "/root/.shrc"

# 9. PRINTER & USB MOUNTS
if [ ! -f /etc/devfs.rules ] || ! grep -q "\[localrules=5\]" /etc/devfs.rules; then
    cat >> /etc/devfs.rules << 'EOF'
[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'uscanner*' mode 0660 group operator
add path 'xpt*' mode 0660 group operator
add path 'pass*' mode 0660 group operator
add path 'md*' mode 0660 group operator
add path 'msdosfs/*' mode 0660 group operator
add path 'ext2fs/*' mode 0660 group operator
add path 'ntfs/*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF
fi

pkg install -y cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
sysrc -q cupsd_enable="YES"
sysrc -q devfs_system_ruleset="localrules"
service devfs restart 2>/dev/null || true
sysrc -q kld_list="fusefs ext2fs nvidia-modeset"

# 10. AUDIO, DESKTOP APPS & MULTIMEDIA
pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme
pkg install -y firefox vlc ffmpeg libva-vdpau-driver libva-utils libdvdread libdvdnav signal-cli xdg-user-dirs octopkg multimedia/mpv gstreamer1-plugins-all gstreamer1-libav libbluray

# 11. INTERNATIONAL FONTS & THEMES
pkg install -y cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
pkg install -y chinese/arphicttf chinese/font-std hebrew/culmus hebrew/elmar-fonts japanese/font-ipa japanese/font-ipa-uigothic japanese/font-ipaex japanese/font-kochi japanese/font-migmix japanese/font-migu japanese/font-mona-ipa japanese/font-motoya-al japanese/font-mplus-ipa japanese/font-sazanami japanese/font-shinonome japanese/font-takao japanese/font-ume japanese/font-vlgothic x11-fonts/hanazono-fonts-ttf japanese/font-mikachan korean/aleefonts-ttf korean/nanumfonts korean/unfonts-core x11-fonts/anonymous-pro x11-fonts/artwiz-aleczapka x11-fonts/dejavu x11-fonts/doulos x11-fonts/isabella x11-fonts/junicode x11-fonts/khmeros x11-fonts/padauk x11-fonts/stix-fonts x11-fonts/charis x11-fonts/urwfonts-ttf russian/koi8r-ps x11-fonts/geminifonts x11-fonts/cyr-rfx x11-fonts/paratype x11-fonts/gentium-plus-compact x11-fonts/nerd-fonts
pkg install -y twemoji-color-font-ttf textproc/ibus-uniemoji x11-themes/papirus-icon-theme x11-themes/cursor-neutral-white-theme x11-themes/qogir-icon-themes x11-themes/win98se-icon-theme

# 12. X11 & KEYBOARD CONFIG
pkg install -y xorg dbus avahi seatd
sysrc -q dbus_enable="YES"
sysrc -q avahi_enable="YES"

add_to_fstab() {
    if ! grep -q "$1" /etc/fstab; then echo "$2" >> /etc/fstab; fi
}
add_to_fstab "procfs" "proc       proc       procfs       rw       0       0"
add_to_fstab "fdescfs" "fdesc     /dev/fd      fdescfs       rw       0       0"

mkdir -p /usr/local/etc/X11/xorg.conf.d
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

# 13. DISPLAY MANAGER (SDDM) & WINDOWS 11 LOGIN THEME
pkg install -y sddm
sysrc -q sddm_enable="YES"
sysrc -q sddm_lang="fr_CH.UTF-8"

touch /usr/local/share/sddm/scripts/Xsetup
if ! grep -q "setxkbmap ch fr" /usr/local/share/sddm/scripts/Xsetup; then
    echo "setxkbmap ch fr" >> /usr/local/share/sddm/scripts/Xsetup
fi

cat > /usr/local/etc/sddm.conf << 'EOF'
[Autoinstall]
InputMethod=""
EOF

mkdir -p /usr/local/share/sddm/themes
if [ ! -d /usr/local/share/sddm/themes/Win11 ]; then
    cd /tmp
    wget -q https://github.com
    unzip -q main.zip
    cp -r Win11-SDDM-main/Win11 /usr/local/share/sddm/themes/
    rm -rf main.zip Win11-SDDM-main
fi

mkdir -p /usr/local/etc/sddm.conf.d
cat > /usr/local/etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=Win11
EOF

# 14. PNG SPLASH SCREEN CONVERSION (NATIVE RGBA CORRIGÉ)
mkdir -p /boot/images
cd /tmp
# Utilisation d'un user-agent pour forcer le téléchargement du binaire PNG propre
wget -q -U "Mozilla/5.0" -O v2.png https://kamila.is

# Syntaxe IMv7 corrigée ("magick" sans l'argument déprécié "convert")
magick v2.png -resize 1920x1080 -strip -type TrueColorAlpha /boot/images/splash.png
rm -f v2.png

# 15. CINNAMON DESKTOP ENVIRONMENT & WINDOWS 11 (FLUENT) GRAPHICS THEME
pkg install -y cinnamon

mkdir -p /usr/local/share/themes /usr/local/share/icons

if [ ! -d /usr/local/share/themes/Win11-dark ]; then
    cd /tmp
    wget -q https://github.com
    unzip -q master.zip
    cp -r Win11-gtk-theme-master/release/Win11-dark /usr/local/share/themes/
    cp -r Win11-gtk-theme-master/release/Win11-light /usr/local/share/themes/
    rm -rf master.zip Win11-gtk-theme-master
fi

if [ ! -d /usr/local/share/icons/Fluent-dark ]; then
    cd /tmp
    wget -q https://github.com
    unzip -q master.zip
    cp -r Fluent-icon-theme-master/Fluent /usr/local/share/icons/
    cp -r Fluent-icon-theme-master/Fluent-dark /usr/local/share/icons/
    rm -rf master.zip Fluent-icon-theme-master
fi

echo "=== Configuration complete ! ==="
pciconf -lv | grep -B4 "VGA" || true
echo "================================"
cd
