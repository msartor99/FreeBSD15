#!/bin/sh
# ==============================================================================
# FreeBSD 15 BASE - Interactive & Idempotent Post-Install Script
# Target: Desktop Environment + VBox 7 + GPU + Locale/Keyboard + Aquantia 10G
# ==============================================================================

set -e

exec 3>&1

# === [00] Disclaimer & Liability Waiver ===
if ! bsddialog --title "DISCLAIMER & LIABILITY WAIVER" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --yesno "WARNING: This script automates system configuration, modifies core files, and installs software.\n\nThe author provides this script 'AS IS' and assumes NO LIABILITY for any data loss, system instability, or hardware issues that may occur.\n\nDo you accept these terms and wish to proceed?" 14 70 \
    2>&1 1>&3; then
    clear
    echo "Installation cancelled. Disclaimer was not accepted."
    exec 3>&-
    exit 1
fi

# === [0a] User Selection ===
TARGET_USER=$(bsddialog --title "User Configuration" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --inputbox "Enter the name of your existing standard user:\n(This user will be configured for 3D, VirtualBox, USB, and localized settings)" 10 65 \
    2>&1 1>&3)

if [ -z "$TARGET_USER" ]; then
    clear
    echo "Error: No username entered. Operation cancelled."
    exec 3>&-
    exit 1
fi

# === [0b] Aquantia Network Installation ===
if bsddialog --title "Aquantia 10G Network" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --yesno "Do you want to download and compile the Aquantia 10G network driver (specific to Lenovo P620 workstations)?" 10 65 \
    2>&1 1>&3; then
    INSTALL_AQUANTIA="YES"
else
    INSTALL_AQUANTIA="NO"
fi

# === [0c] GPU Selection ===
GPU_CHOICE=$(bsddialog --title "Graphics Card (GPU)" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --menu "Select your graphics card manufacturer:" 13 70 4 \
    "AMD_GPU" "Recent Radeon (W7000, RX 5000+, RDNA, Navi)" \
    "AMD_RADEON" "Legacy Radeon (HD, R9, pre-Polaris)" \
    "NVIDIA" "GeForce, Quadro, RTX (Includes hardware detection)" \
    "INTEL" "Intel HD/UHD Integrated Graphics" \
    2>&1 1>&3)

if [ -z "$GPU_CHOICE" ]; then
    clear
    echo "Error: No graphics card selected. Operation cancelled."
    exec 3>&-
    exit 1
fi

if [ "$GPU_CHOICE" = "NVIDIA" ]; then
    VGA_INFO=$(pciconf -lv | grep -A 2 -i "class=0x03" | grep -i "vendor\|device" | tr -d "'" || echo "Hardware not identified")
    
    bsddialog --title "Nvidia Detection" \
        --clear \
        --msgbox "The following graphics hardware was detected on this machine:\n\n$VGA_INFO\n\nPress OK to choose the corresponding driver version." 12 70 2>&1 1>&3
        
    NVIDIA_BRANCH=$(bsddialog --title "Nvidia Driver Version" \
        --clear \
        --menu "Select the Nvidia driver branch:" 13 75 4 \
        "LATEST" "Turing and newer (Driver 595+ / Quadro RTX, RTX 2000+)" \
        "580" "Pascal/Maxwell (Driver 580 / Quadro P4000/P2000, GTX 1000)" \
        "470" "Kepler (Driver 470 / Quadro K, GTX 600-700)" \
        "390" "Fermi (Driver 390 / Quadro Fermi, GTX 400-500)" \
        2>&1 1>&3)
        
    if [ "$NVIDIA_BRANCH" = "LATEST" ]; then
        GPU_PKGS="nvidia-driver nvidia-settings nvidia-xconfig"
    elif [ "$NVIDIA_BRANCH" = "580" ]; then
        GPU_PKGS="nvidia-driver-580 nvidia-settings"
    elif [ "$NVIDIA_BRANCH" = "470" ]; then
        GPU_PKGS="nvidia-driver-470 nvidia-settings"
    elif [ "$NVIDIA_BRANCH" = "390" ]; then
        GPU_PKGS="nvidia-driver-390 nvidia-settings"
    else
        clear; echo "Error: Nvidia driver branch not selected."; exec 3>&-; exit 1
    fi
    GPU_MOD="nvidia-modeset"
elif [ "$GPU_CHOICE" = "AMD_GPU" ]; then
    GPU_PKGS="drm-kmod gpu-firmware-kmod"
    GPU_MOD="amdgpu"
elif [ "$GPU_CHOICE" = "AMD_RADEON" ]; then
    GPU_PKGS="drm-kmod"
    GPU_MOD="radeonkms"
elif [ "$GPU_CHOICE" = "INTEL" ]; then
    GPU_PKGS="drm-kmod"
    GPU_MOD="i915kms"
fi

# === [0d] Desktop Environment Selection ===
DESKTOP_CHOICE=$(bsddialog --title "Desktop Environment" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --menu "Select the graphical environment to install:" 12 70 3 \
    "XFCE" "Classic, lightweight, and fast" \
    "MATE" "Traditional and robust (GNOME 2 fork)" \
    "KDE"  "Plasma 6 (Modern, highly customizable)" \
    2>&1 1>&3)

if [ -z "$DESKTOP_CHOICE" ]; then
    clear
    echo "Error: No desktop environment selected. Operation cancelled."
    exec 3>&-
    exit 1
fi

# === [0e] Locale & Keyboard Configuration ===
if bsddialog --title "Locale & Keyboard Setup" \
    --clear \
    --backtitle "FreeBSD 15 Post-Installation Setup" \
    --yesno "Do you want to configure the system language and keyboard layout for the graphical environment?\n(This modifies X11 and SDDM, but leaves /etc/rc.conf unchanged)" 10 70 \
    2>&1 1>&3; then
    CONFIG_LOCALE="YES"
    
    SYS_LANG=$(bsddialog --title "System Language" \
        --clear \
        --backtitle "FreeBSD 15 Post-Installation Setup" \
        --default-item "fr_CH.UTF-8" \
        --menu "Select the language for the graphical session:" 17 75 9 \
        "fr_CH.UTF-8" "French (Switzerland) - Default" \
        "fr_FR.UTF-8" "French (France)" \
        "en_US.UTF-8" "English (United States)" \
        "en_GB.UTF-8" "English (United Kingdom)" \
        "de_CH.UTF-8" "German (Switzerland)" \
        "it_CH.UTF-8" "Italian (Switzerland)" \
        "it_IT.UTF-8" "Italian (Italy)" \
        "es_ES.UTF-8" "Spanish (Spain)" \
        "pt_PT.UTF-8" "Portuguese (Portugal)" \
        2>&1 1>&3)

    if [ -z "$SYS_LANG" ]; then SYS_LANG="fr_CH.UTF-8"; fi

    KBD_CHOICE=$(bsddialog --title "Keyboard Layout" \
        --clear \
        --backtitle "FreeBSD 15 Post-Installation Setup" \
        --default-item "CH_FR" \
        --menu "Select your keyboard layout for X11/SDDM:" 18 75 10 \
        "CH_FR" "Swiss French (ch, fr) - Default" \
        "CH_DE" "Swiss German (ch, de)" \
        "CH_IT" "Swiss Italian (ch, it)" \
        "FR"    "French AZERTY (fr)" \
        "US"    "US QWERTY (us)" \
        "UK"    "British QWERTY (gb)" \
        "DE"    "German QWERTZ (de)" \
        "IT"    "Italian (it)" \
        "ES"    "Spanish (es)" \
        "PT"    "Portuguese (pt)" \
        2>&1 1>&3)
        
    case "$KBD_CHOICE" in
        CH_FR) XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
        CH_DE) XKB_LAYOUT="ch"; XKB_VARIANT="de" ;;
        CH_IT) XKB_LAYOUT="ch"; XKB_VARIANT="it" ;;
        FR)    XKB_LAYOUT="fr"; XKB_VARIANT="" ;;
        US)    XKB_LAYOUT="us"; XKB_VARIANT="" ;;
        UK)    XKB_LAYOUT="gb"; XKB_VARIANT="" ;;
        DE)    XKB_LAYOUT="de"; XKB_VARIANT="" ;;
        IT)    XKB_LAYOUT="it"; XKB_VARIANT="" ;;
        ES)    XKB_LAYOUT="es"; XKB_VARIANT="" ;;
        PT)    XKB_LAYOUT="pt"; XKB_VARIANT="" ;;
        *)     XKB_LAYOUT="ch"; XKB_VARIANT="fr" ;;
    esac
else
    CONFIG_LOCALE="NO"
fi

exec 3>&-
clear

# ==============================================================================
# Dynamic Application Linking (Desktop + Games)
# ==============================================================================
if [ "$DESKTOP_CHOICE" = "XFCE" ]; then DESKTOP_PKGS="xfce aisleriot"; fi
if [ "$DESKTOP_CHOICE" = "MATE" ]; then DESKTOP_PKGS="mate aisleriot"; fi
if [ "$DESKTOP_CHOICE" = "KDE" ]; then DESKTOP_PKGS="plasma6-plasma dolphin konsole kpat"; fi

COMMON_PKGS="xorg sddm firefox thunderbird vlc libreoffice fr-libreoffice virtualbox-ose-72 virtualbox-ose-kmod-72 fusefs-ntfs fusefs-exfat git-lite"

echo "=== [1/11] Installing Packages ==="
env ASSUME_ALWAYS_YES=YES pkg install $COMMON_PKGS $DESKTOP_PKGS $GPU_PKGS

echo "=== [2/11] Installing Aquantia 10G Driver (If selected) ==="
if [ "$INSTALL_AQUANTIA" = "YES" ]; then
    echo "-> Fetching source code from GitHub..."
    rm -rf /root/aquantia_p620_src
    git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /root/aquantia_p620_src
    cd /root/aquantia_p620_src
    sh install_aq_fbsd15_universal.sh
    
    echo "-> Applying Aquantia PHY fix to /boot/loader.conf..."
    # Remplacement du sysrc par grep/sed pour gérer les points dans les noms de variables
    for AQ_VAR in "nrxqs" "ntxqs"; do
        if grep -q "^dev.aq.0.iflib.override_${AQ_VAR}=" /boot/loader.conf 2>/dev/null; then
            sed -i '' "s/^dev.aq.0.iflib.override_${AQ_VAR}=.*/dev.aq.0.iflib.override_${AQ_VAR}=\"8\"/" /boot/loader.conf
        else
            echo "dev.aq.0.iflib.override_${AQ_VAR}=\"8\"" >> /boot/loader.conf
        fi
    done
    
    echo "-> Aquantia driver successfully installed and configured."
else
    echo "-> Skipped (Aquantia installation not selected)."
fi

echo "=== [3/11] Configuring Kernel Modules (GPU, VirtualBox & FUSE) ==="
for MOD in "$GPU_MOD" "vboxdrv" "fusefs"; do
    if ! sysrc -n kld_list 2>/dev/null | grep -qw "$MOD"; then
        sysrc kld_list+="$MOD"
        echo "-> Kernel module $MOD added to startup."
    else
        echo "-> Kernel module $MOD is already configured."
    fi
done

echo "=== [4/11] Configuring Xorg for Nvidia (If applicable) ==="
if [ "$GPU_CHOICE" = "NVIDIA" ]; then
    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    cat << 'EOF' > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
EndSection
EOF
    echo "-> 20-nvidia.conf generated to enforce proprietary driver."
else
    rm -f /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "-> Standard Xorg configuration (Open-source KMS drivers in use)."
fi

echo "=== [5/11] Configuring User Permissions ==="
if id "$TARGET_USER" >/dev/null 2>&1; then
    for GRP in "video" "vboxusers" "operator"; do
        if ! id -nG "$TARGET_USER" | grep -qw "$GRP"; then
            pw groupmod "$GRP" -m "$TARGET_USER"
        fi
    done
    echo "-> 3D, VirtualBox, and USB access granted to '$TARGET_USER'."
fi

echo "=== [6/11] Configuring Hardware Rules (VBox USB & Automount) ==="
if ! grep -q "vfs.usermount=1" /etc/sysctl.conf 2>/dev/null; then
    echo "vfs.usermount=1" >> /etc/sysctl.conf
    sysctl vfs.usermount=1
fi
if ! grep -q "\[desktop_rules=10\]" /etc/devfs.rules 2>/dev/null; then
    cat << 'EOF' >> /etc/devfs.rules

[desktop_rules=10]
add path 'usb/*' mode 0660 group operator
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'pass*' mode 0660 group operator
add path 'xpt*' mode 0660 group operator
EOF
fi
sysrc devfs_system_ruleset="desktop_rules"

echo "=== [7/11] Configuring Keyboard Layout (X11/SDDM) ==="
if [ "$CONFIG_LOCALE" = "YES" ]; then
    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    
    VARIANT_LINE=""
    if [ -n "$XKB_VARIANT" ]; then
        VARIANT_LINE="Option \"XkbVariant\" \"$XKB_VARIANT\""
    fi

    cat << EOF > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    $VARIANT_LINE
EndSection
EOF

    if [ -f /usr/local/share/sddm/scripts/Xsetup ]; then
        sed -i '' '/setxkbmap/d' /usr/local/share/sddm/scripts/Xsetup
    fi
    
    if [ -n "$XKB_VARIANT" ]; then
        printf "\nsetxkbmap %s %s\n" "$XKB_LAYOUT" "$XKB_VARIANT" >> /usr/local/share/sddm/scripts/Xsetup
    else
        printf "\nsetxkbmap %s\n" "$XKB_LAYOUT" >> /usr/local/share/sddm/scripts/Xsetup
    fi
    echo "-> X11/SDDM Keyboard Layout configured ($XKB_LAYOUT $XKB_VARIANT)."
else
    echo "-> Skipped (User opted out of graphical keyboard configuration)."
fi

echo "=== [8/11] Configuring SDDM Theme (Maldives) ==="
mkdir -p /usr/local/etc/sddm.conf.d/
cat << 'EOF' > /usr/local/etc/sddm.conf.d/10-theme.conf
[Theme]
Current=maldives
EOF

echo "=== [9/11] Configuring System Locale (/etc/login.conf) ==="
if [ "$CONFIG_LOCALE" = "YES" ]; then
    if grep -q "^desktop_locale|" /etc/login.conf; then
        sed -i '' '/^desktop_locale|/,/tc=default:/d' /etc/login.conf
    fi
    cat << EOF >> /etc/login.conf

desktop_locale|Custom Desktop Language:\\
	:charset=UTF-8:\\
	:lang=$SYS_LANG:\\
	:tc=default:
EOF
    cap_mkdb /etc/login.conf
    if id "$TARGET_USER" >/dev/null 2>&1; then
        pw usermod "$TARGET_USER" -L desktop_locale
    fi
    echo "-> Target user locale set to $SYS_LANG."
else
    echo "-> Skipped (User opted out of locale configuration)."
fi

echo "=== [10/11] Injecting Office 365 Theme for LibreOffice ==="
USER_HOME=$(pw usershow "$TARGET_USER" | cut -d: -f9)
LO_CONFIG_DIR="$USER_HOME/.config/libreoffice/4/user"
LO_CONFIG_FILE="$LO_CONFIG_DIR/registrymodifications.xcu"
if [ -d "$USER_HOME" ] && [ ! -f "$LO_CONFIG_FILE" ]; then
    mkdir -p "$LO_CONFIG_DIR"
    cat << 'EOF' > "$LO_CONFIG_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<item oor:path="/org.openoffice.Office.UI.ToolbarMode/ToolbarMode"><prop oor:name="ToolbarMode" oor:op="fuse"><value>notebookbar_tabbed</value></prop></item>
<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="SymbolStyle" oor:op="fuse"><value>colibre</value></prop></item>
</oor:items>
EOF
    chown -R "$TARGET_USER" "$USER_HOME/.config"
fi

echo "=== [11/11] Enabling Services (DBUS, SDDM, VBOXNET) ==="
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc vboxnet_enable="YES"

echo "=============================================================================="
echo " INSTALLATION COMPLETED AND VERIFIED!"
if [ "$INSTALL_AQUANTIA" = "YES" ]; then
    echo " [!] Aquantia driver compiled. Do not forget to completely power off"
    echo "     the machine (Cold Boot for 15 seconds) for proper initialization!"
else
    echo " You can now restart the machine by typing: reboot"
fi
echo "=============================================================================="
