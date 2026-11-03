#!/bin/sh
#
# FreeBSD 15.1 Workstation Deployment Script
# Display Server : XLibre (Prior X.Org complete purge) + Optional Wayland stack for Intel/AMD
# GPU Auto-detection : NVIDIA (470/580/latest), Intel Graphics, AMD Radeon (amdgpu / radeonkms)
# User Management : Dynamic probe (UID >= 1000) with interactive 'adduser' prompt if absent
# Internationalization : System Locales (FR, DE, IT, ES, PT) & Corresponding Keyboards
# Splash Screen : Dedicated Persistent Configuration (Kamila / NASA / Standard) with BMP + PNG
# TUI Framework : bsddialog (FreeBSD Base System)
# Shell : /bin/sh - Fully Idempotent
#

set -u

# ==============================================================================
# ROOT PRIVILEGES & BSDDIALOG PREREQUISITES CHECK
# ==============================================================================
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

if ! command -v bsddialog >/dev/null 2>&1; then
    echo "bsddialog not found in base system. Installing fallback package..."
    pkg install -y bsddialog || exit 1
fi

# ==============================================================================
# DYNAMIC DETECTION / CREATION OF PRIMARY OPERATOR (UID >= 1000)
# ==============================================================================
find_target_user() {
    TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
    TARGET_UID=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $3; exit }' /etc/passwd)
}

find_target_user

while [ -z "$TARGET_USER" ]; do
    NO_USER_MSG="No regular operator account (UID >= 1000) was detected on this system.\n\nA primary non-root user is required to configure user privileges, desktop sessions, and multimedia groups.\n\nWould you like to run 'adduser' now to create one?"
    if bsddialog --title " USER ACCOUNT REQUIRED " \
        --yes-label "Create User (adduser)" \
        --no-label "Abort Installation" \
        --yesno "$NO_USER_MSG" 14 74; then
        clear
        echo "==> Launching FreeBSD interactive user creation utility (adduser)..."
        echo "------------------------------------------------------------------"
        adduser
        echo "------------------------------------------------------------------"
        find_target_user
        if [ -z "$TARGET_USER" ]; then
            bsddialog --title " WARNING " \
                --msgbox "No regular user account was found after running adduser. Please create one or abort." 8 68
        fi
    else
        clear
        echo "Error: Installation aborted. A non-root user account is required." >&2
        exit 1
    fi
done

# Temporary files for TUI dialogue responses
LANG_CHOICE_FILE=$(mktemp -t bsd_lang_choice.XXXXXX)
KBD_CHOICE_FILE=$(mktemp -t bsd_kbd_choice.XXXXXX)
CPU_CHOICE_FILE=$(mktemp -t bsd_cpu_choice.XXXXXX)
SPLASH_CHOICE_FILE=$(mktemp -t bsd_splash_choice.XXXXXX)
CHOICES_FILE=$(mktemp -t bsd_install_choices.XXXXXX)

trap 'rm -f "$LANG_CHOICE_FILE" "$KBD_CHOICE_FILE" "$CPU_CHOICE_FILE" "$SPLASH_CHOICE_FILE" "$CHOICES_FILE"' EXIT INT TERM

# ==============================================================================
# PRELIMINARY GPU HARDWARE DETECTION (FOR WAYLAND MENU)
# ==============================================================================
HAS_NVIDIA=0; HAS_INTEL=0; HAS_AMD=0
NVIDIA_DRIVER_VERSION=""; INTEL_DRIVER_NAME=""; AMD_DRIVER_TYPE=""; AMD_DRIVER_NAME=""

DISPLAY_DEVICES=$(pciconf -lv | awk '
BEGIN { RS=""; FS="\n" }
/class=0x03/ {
    for (i=1; i<=NF; i++) {
        if ($i ~ /vendor[ \t]*=/) v = $i;
        if ($i ~ /device[ \t]*=/) d = $i;
        if ($i ~ /class=0x03/) c = $i;
    }
    print c " | " v " | " d;
}')

if echo "$DISPLAY_DEVICES" | grep -qi "10de\|NVIDIA"; then HAS_NVIDIA=1; fi
if echo "$DISPLAY_DEVICES" | grep -qi "8086\|Intel"; then HAS_INTEL=1; fi
if echo "$DISPLAY_DEVICES" | grep -qi "1002\|Advanced Micro Devices\|ATI"; then HAS_AMD=1; fi

# ==============================================================================
# SCREEN 1: OPERATOR DISCLAIMER & RISK ACKNOWLEDGMENT
# ==============================================================================
DISCLAIMER_TEXT="WARNING - SYSTEM-LEVEL CONFIGURATION CHANGES:

This script automates critical system changes on FreeBSD 15.1:
  - Target Workstation Operator : ${TARGET_USER} (UID: ${TARGET_UID})
  - Complete removal of legacy X.Org packages and xf86 drivers
  - Deployment of XLibre display server and hardware GPU configuration:
      * NVIDIA (Kepler 470, Maxwell/Pascal/Volta 580, Turing+ latest)
      * Intel Graphics (i915kms + Glamor modesetting)
      * AMD Radeon Modern / RDNA (amdgpu + Glamor modesetting)
      * AMD / ATI Radeon Legacy (radeonkms + Glamor modesetting)
  - Optional Wayland & seatd stack proposal if Intel/AMD GPU is present
  - Language environment (/etc/login.conf) & keyboard layout setup
  - Custom boot splash screen injection (Kamila, NASA, or Standard)
  - Direct modifications to /boot/loader.conf, /etc/rc.conf, /etc/sysctl.conf
  - /etc/fstab updates (procfs, fdescfs) and devfs ruleset reload

An interruption or hardware mismatch could cause system instability,
display server launch failures, or boot issues.

This script is provided 'AS IS', WITHOUT WARRANTIES OF ANY KIND.
The operator assumes full responsibility for all changes performed.

Do you accept these terms and wish to proceed?"

if ! bsddialog --title " DISCLAIMER / SYSTEM MODIFICATION NOTICE " \
    --yes-label "Accept and Continue" \
    --no-label "Cancel and Exit" \
    --yesno "$DISCLAIMER_TEXT" 23 76; then
    clear
    echo "Installation canceled by operator. No changes were made."
    exit 0
fi

# ==============================================================================
# SCREEN 2: WAYLAND PROPOSAL (IF INTEL OR AMD GRAPHICS DETECTED)
# ==============================================================================
INSTALL_WAYLAND=0
if [ "$HAS_INTEL" -eq 1 ] || [ "$HAS_AMD" -eq 1 ] || [ "$HAS_NVIDIA" -eq 0 ]; then
    DETECTED_GPU_NAMES=""
    [ "$HAS_INTEL" -eq 1 ] && DETECTED_GPU_NAMES="Intel Graphics "
    [ "$HAS_AMD" -eq 1 ] && DETECTED_GPU_NAMES="${DETECTED_GPU_NAMES}AMD Radeon "
    [ -z "$DETECTED_GPU_NAMES" ] && DETECTED_GPU_NAMES="Generic KMS-compatible GPU "

    WAYLAND_PROMPT="Compatible graphics hardware detected (${DETECTED_GPU_NAMES}).\n\nUnlike NVIDIA, this hardware natively supports modern Wayland sessions on FreeBSD.\n\nEnabling Wayland applies a dedicated, hardened configuration:\n  - seatd session manager and direct evdev/uinput permissions\n  - pam_xdg module integration for strict \$XDG_RUNTIME_DIR handling\n  - XWayland compatibility layer for legacy X11 client apps\n  - KDE Plasma 6 Wayland session and native Qt6/GTK/Firefox integration\n\nWould you like to install and configure Wayland alongside XLibre?"

    if bsddialog --title " WAYLAND COMPOSITING STACK AVAILABLE " \
        --yes-label "Enable Wayland" \
        --no-label "Keep XLibre Only" \
        --yesno "$WAYLAND_PROMPT" 19 76; then
        INSTALL_WAYLAND=1
    fi
fi

# ==============================================================================
# SCREEN 3: SYSTEM LANGUAGE SELECTION
# ==============================================================================
bsddialog --title " SYSTEM LANGUAGE SELECTION " \
    --radiolist "Select primary system language (UTF-8 locale & login class):" \
    16 74 5 \
    "FR" "French     (fr_FR.UTF-8)" on \
    "DE" "German     (de_DE.UTF-8)" off \
    "IT" "Italian    (it_IT.UTF-8)" off \
    "ES" "Spanish    (es_ES.UTF-8)" off \
    "PT" "Portuguese (pt_PT.UTF-8)" off \
    2> "$LANG_CHOICE_FILE"

if [ $? -ne 0 ]; then
    clear
    echo "Canceled during language selection."
    exit 0
fi

SELECTED_LANG=$(cat "$LANG_CHOICE_FILE" | tr -d '"')

case "$SELECTED_LANG" in
    "DE")
        LANG_CODE="de_DE.UTF-8"; CLASS_NAME="german"; CLASS_DESC="German Users Accounts"; KBD_DEFAULT="CH_DE" ;;
    "IT")
        LANG_CODE="it_IT.UTF-8"; CLASS_NAME="italian"; CLASS_DESC="Italian Users Accounts"; KBD_DEFAULT="IT" ;;
    "ES")
        LANG_CODE="es_ES.UTF-8"; CLASS_NAME="spanish"; CLASS_DESC="Spanish Users Accounts"; KBD_DEFAULT="ES" ;;
    "PT")
        LANG_CODE="pt_PT.UTF-8"; CLASS_NAME="portuguese"; CLASS_DESC="Portuguese Users Accounts"; KBD_DEFAULT="PT" ;;
    *)
        LANG_CODE="fr_FR.UTF-8"; CLASS_NAME="french"; CLASS_DESC="French Users Accounts"; KBD_DEFAULT="CH_FR" ;;
esac

# ==============================================================================
# SCREEN 4: KEYBOARD LAYOUT SELECTION
# ==============================================================================
CH_FR_STATE="off"; CH_DE_STATE="off"; FR_STATE="off"; DE_STATE="off"
IT_STATE="off"; ES_STATE="off"; PT_STATE="off"

case "$KBD_DEFAULT" in
    "CH_DE") CH_DE_STATE="on" ;;
    "FR")    FR_STATE="on" ;;
    "DE")    DE_STATE="on" ;;
    "IT")    IT_STATE="on" ;;
    "ES")    ES_STATE="on" ;;
    "PT")    PT_STATE="on" ;;
    *)       CH_FR_STATE="on" ;;
esac

bsddialog --title " KEYBOARD LAYOUT SELECTION " \
    --radiolist "Select keyboard layout for console and XLibre/Wayland/SDDM:\n(Pre-selected based on chosen language)" \
    18 76 7 \
    "CH_FR" "Swiss French  (layout: ch, variant: fr)" "$CH_FR_STATE" \
    "CH_DE" "Swiss German  (layout: ch, variant: de)" "$CH_DE_STATE" \
    "FR"    "French        (layout: fr, azerty)"      "$FR_STATE" \
    "DE"    "German        (layout: de, qwertz)"      "$DE_STATE" \
    "IT"    "Italian       (layout: it, qwerty)"      "$IT_STATE" \
    "ES"    "Spanish       (layout: es, qwerty)"      "$ES_STATE" \
    "PT"    "Portuguese    (layout: pt, qwerty)"      "$PT_STATE" \
    2> "$KBD_CHOICE_FILE"

if [ $? -ne 0 ]; then
    clear
    echo "Canceled during keyboard selection."
    exit 0
fi

SELECTED_KBD=$(cat "$KBD_CHOICE_FILE" | tr -d '"')

case "$SELECTED_KBD" in
    "CH_DE")
        XKB_LAYOUT="ch"; XKB_VARIANT="de"; SDDM_KBD="setxkbmap ch de"; CONSOLE_KEYMAP="swissgerman.iso.kbd" ;;
    "FR")
        XKB_LAYOUT="fr"; XKB_VARIANT="";   SDDM_KBD="setxkbmap fr";    CONSOLE_KEYMAP="fr.iso.kbd" ;;
    "DE")
        XKB_LAYOUT="de"; XKB_VARIANT="";   SDDM_KBD="setxkbmap de";    CONSOLE_KEYMAP="de.kbd" ;;
    "IT")
        XKB_LAYOUT="it"; XKB_VARIANT="";   SDDM_KBD="setxkbmap it";    CONSOLE_KEYMAP="it.iso.kbd" ;;
    "ES")
        XKB_LAYOUT="es"; XKB_VARIANT="";   SDDM_KBD="setxkbmap es";    CONSOLE_KEYMAP="es.iso.kbd" ;;
    "PT")
        XKB_LAYOUT="pt"; XKB_VARIANT="";   SDDM_KBD="setxkbmap pt";    CONSOLE_KEYMAP="pt.iso.kbd" ;;
    *)
        XKB_LAYOUT="ch"; XKB_VARIANT="fr"; SDDM_KBD="setxkbmap ch fr"; CONSOLE_KEYMAP="swissfrench.iso.kbd" ;;
esac

# ==============================================================================
# SCREEN 5: CPU ARCHITECTURE SELECTION (INTEL / AMD)
# ==============================================================================
DETECTED_VENDOR=$(sysctl -n machdep.cpu_vendor 2>/dev/null || echo "Unknown")
INTEL_DEFAULT="off"; AMD_DEFAULT="off"
case "$DETECTED_VENDOR" in
    AuthenticAMD*) AMD_DEFAULT="on" ;;
    *)            INTEL_DEFAULT="on" ;;
esac

bsddialog --title " PROCESSOR ARCHITECTURE " \
    --radiolist "Select CPU architecture for microcode updates and thermal drivers:\n(Pre-selected based on hardware probe)" \
    14 74 2 \
    "INTEL" "Intel Processor (coretemp.ko + intel-ucode)" "$INTEL_DEFAULT" \
    "AMD"   "AMD Processor   (amdtemp.ko + amd-ucode)"   "$AMD_DEFAULT" \
    2> "$CPU_CHOICE_FILE"

if [ $? -ne 0 ]; then
    clear
    echo "Canceled during processor selection."
    exit 0
fi

SELECTED_CPU=$(cat "$CPU_CHOICE_FILE" | tr -d '"')

# ==============================================================================
# SCREEN 6: BOOT SPLASH SCREEN SELECTION
# ==============================================================================
bsddialog --title " BOOT SPLASH SCREEN " \
    --radiolist "Choose boot splash graphic displayed during FreeBSD kernel initialization:" \
    15 74 3 \
    "KAMILA"   "Kamila Blue Theme (v2-blue.png)"            on \
    "NASA"     "NASA Exploration Theme (nasa1920.png)"      off \
    "STANDARD" "FreeBSD Default Boot Logo (no splash image)" off \
    2> "$SPLASH_CHOICE_FILE"

if [ $? -ne 0 ]; then
    clear
    echo "Canceled during boot splash selection."
    exit 0
fi

SELECTED_SPLASH=$(cat "$SPLASH_CHOICE_FILE" | tr -d '"')

# ==============================================================================
# SCREEN 7: OPTIONAL COMPONENTS CHECKLIST
# ==============================================================================
bsddialog --title " OPTIONAL COMPONENTS SELECTION " \
    --checklist "Select/deselect components using [Space] key:\n(X.Org purge, base XLibre, GPU auto-config, and splash are mandatory)" \
    21 78 10 \
    "LINUX"       "Linux binary compatibility layer (RL9 & kernel modules)" on \
    "CUPS_USB"    "CUPS printing service, devfs rules, and FUSE/USB storage"  on \
    "AUDIO"       "Audio subsystem (PipeWire, PulseAudio, ALSA, OSS)"       on \
    "SDDM"        "SDDM display manager"                                    on \
    "THEME_NASA"  "SDDM NASA theme (nasa2560login.jpg)"                     on \
    "PLASMA6"     "KDE Plasma 6 desktop environment (KF6, Dolphin...)"      on \
    "XFCE"        "XFCE 4 desktop environment and goodies"                  off \
    "MATE"        "MATE desktop environment"                                off \
    "APPS"        "Essential desktop applications (Firefox, VLC, MPV...)"   on \
    "VBOX"        "VirtualBox 7 (kernel drivers & permissions)"             on \
    2> "$CHOICES_FILE"

if [ $? -ne 0 ]; then
    clear
    echo "Configuration canceled in components menu."
    exit 0
fi

CHOICES=$(cat "$CHOICES_FILE")
clear

is_selected() {
    _tag="$1"
    case " $CHOICES " in
        *" \"${_tag}\" "*|*" ${_tag} "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ==============================================================================
# GLOBAL VARIABLES & PATHS
# ==============================================================================
ASSETS_DIR="/var/cache/fb14_assets"
FORCE_NVIDIA_DRIVER=""

# ==============================================================================
# IDEMPOTENCY HELPER FUNCTIONS
# ==============================================================================
append_line_if_missing() {
    _file="$1"
    _line="$2"
    [ -f "$_file" ] || touch "$_file"
    if ! grep -Fxq "$_line" "$_file" 2>/dev/null; then
        printf "%s\n" "$_line" >> "$_file"
    fi
}

set_sysctl_conf() {
    _key="$1"
    _val="$2"
    _file="/etc/sysctl.conf"
    [ -f "$_file" ] || touch "$_file"
    _escaped_key=$(printf '%s' "$_key" | sed 's/[.[\*^$]/\\&/g')
    if grep -Eq "^[[:space:]]*${_escaped_key}=" "$_file" 2>/dev/null; then
        sed -i '' "s|^[[:space:]]*${_escaped_key}=.*|${_key}=${_val}|" "$_file"
    else
        printf "%s=%s\n" "$_key" "$_val" >> "$_file"
    fi
    sysctl "${_key}=${_val}" >/dev/null 2>&1 || true
}

set_loader_conf() {
    _key="$1"
    _val="$2"
    _file="/boot/loader.conf"
    [ -f "$_file" ] || touch "$_file"
    _escaped_key=$(printf '%s' "$_key" | sed 's/[.[\*^$]/\\&/g')
    if grep -Eq "^[[:space:]]*${_escaped_key}=" "$_file" 2>/dev/null; then
        sed -i '' "s|^[[:space:]]*${_escaped_key}=.*|${_key}=\"${_val}\"|" "$_file"
    else
        printf '%s="%s"\n' "$_key" "$_val" >> "$_file"
    fi
}

unset_loader_conf() {
    _key="$1"
    _file="/boot/loader.conf"
    if [ -f "$_file" ]; then
        _escaped_key=$(printf '%s' "$_key" | sed 's/[.[\*^$]/\\&/g')
        sed -i '' "/^[[:space:]]*${_escaped_key}=/d" "$_file"
    fi
}

add_to_kld_list() {
    _mod="$1"
    case " $(sysrc -n kld_list 2>/dev/null) " in
        *" ${_mod} "*) ;;
        *) sysrc kld_list+="$_mod" ;;
    esac
}

safe_kldload() {
    _mod="$1"
    if ! kldstat -q -m "$_mod" && ! kldstat -q -n "$_mod.ko" 2>/dev/null; then
        kldload "$_mod" 2>/dev/null || true
    fi
}

# ==============================================================================
# 1. COMPLETE DETECTION AND PURGE OF X.ORG PACKAGES
# ==============================================================================
echo "==> [1/17] Checking for legacy X.Org packages and xf86 drivers..."
pkg update -f

XORG_PKGS=$(pkg query "%n" 2>/dev/null | grep -E '^(xorg$|xorg-server|xorg-drivers|xorg-apps|xf86-input-|xf86-video-)' || true)

if [ -n "$XORG_PKGS" ]; then
    echo "--> Legacy X.Org components detected:"
    echo "$XORG_PKGS" | sed 's/^/    - /'
    echo "--> Forcing complete uninstallation of X.Org..."
    echo "$XORG_PKGS" | xargs pkg delete -y -f
    echo "--> Purging orphaned dependencies..."
    pkg autoremove -y
    echo "--> X.Org purge successfully finished."
else
    echo "--> Clean system: No legacy X.Org components found."
fi

# ==============================================================================
# 2. BASE SYSTEM CORE: SSH, SUDO, KERNEL TUNABLES, SILENT BOOT
# ==============================================================================
echo "==> [2/17] Installing core administrative tools and setting up SSH..."
pkg install -y sudo doas wget git ImageMagick7

if grep -q "^[#]*PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i '' 's/^[#]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
else
    append_line_if_missing /etc/ssh/sshd_config "PermitRootLogin yes"
fi
service sshd restart 2>/dev/null || true

echo "==> [3/17] Applying kernel tuning and silent boot configurations..."
set_loader_conf "boot_mute" "YES"
set_loader_conf "autoboot_delay" "3"
set_loader_conf "tmpfs_load" "YES"
set_loader_conf "aio_load" "YES"

sysrc rc_startmsgs=NO
sysrc splash_changer_enable=YES

if ! grep -q 'run_rc_script ${_rc_elem} ${_boot} > /dev/null' /etc/rc; then
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
fi

set_sysctl_conf "kern.sched.preempt_thresh" "224"
set_sysctl_conf "kern.ipc.shm_allow_removed" "1"
set_sysctl_conf "net.local.stream.recvspace" "65536"
set_sysctl_conf "net.local.stream.sendspace" "65536"
set_sysctl_conf "vfs.usermount" "1"

sysrc keymap="$CONSOLE_KEYMAP"

# ==============================================================================
# 3. LOCALE CLASS AND USER ACCOUNTS
# ==============================================================================
echo "==> [4/17] Configuring login class '${CLASS_NAME}' (${LANG_CODE}) for '${TARGET_USER}'..."
if ! grep -q "^${CLASS_NAME}|" /etc/login.conf 2>/dev/null; then
    cat >> /etc/login.conf << EOF

${CLASS_NAME}|${CLASS_DESC}:\\
	:charset=UTF-8:\\
	:lang=${LANG_CODE}:\\
	:lc_all=${LANG_CODE}:\\
	:lc_collate=${LANG_CODE}:\\
	:lc_ctype=${LANG_CODE}:\\
	:lc_messages=${LANG_CODE}:\\
	:tc=default:
EOF
    cap_mkdb /etc/login.conf
fi

if [ -f /etc/adduser.conf ]; then
    if grep -q '^defaultclass=' /etc/adduser.conf; then
        sed -i '' "s/^defaultclass=.*/defaultclass=${CLASS_NAME}/" /etc/adduser.conf
    else
        append_line_if_missing /etc/adduser.conf "defaultclass=${CLASS_NAME}"
    fi
else
    echo "defaultclass=${CLASS_NAME}" > /etc/adduser.conf
fi

# Ensure seatd group exists
pw groupadd seatd 2>/dev/null || true

# Apply groups and login class to detected primary operator
pw usermod "$TARGET_USER" -G wheel,operator,video,seatd -L "$CLASS_NAME" 2>/dev/null || true
pw usermod root -L "$CLASS_NAME" 2>/dev/null || true

# ==============================================================================
# 4. CPU MICROCODE & THERMAL SENSORS
# ==============================================================================
echo "==> [5/17] Applying CPU optimizations for $SELECTED_CPU..."
pkg install -y cpu-microcode sensors

if [ "$SELECTED_CPU" = "AMD" ]; then
    echo "--> Loading AMD thermal sensors and microcode update..."
    set_loader_conf "amdtemp_load" "YES"
    set_loader_conf "cpu_microcode_load" "YES"
    set_loader_conf "cpu_microcode_name" "/boot/firmware/amd-ucode.bin"
    sed -i '' '/^[[:space:]]*coretemp_load=/d' /boot/loader.conf 2>/dev/null || true
else
    echo "--> Loading Intel thermal sensors and microcode update..."
    set_loader_conf "coretemp_load" "YES"
    set_loader_conf "cpu_microcode_load" "YES"
    set_loader_conf "cpu_microcode_name" "/boot/firmware/intel-ucode.bin"
    sed -i '' '/^[[:space:]]*amdtemp_load=/d' /boot/loader.conf 2>/dev/null || true
fi

# ==============================================================================
# 5. XLIBRE DISPLAY SERVER & KEYBOARD SETUP
# ==============================================================================
echo "==> [6/17] Deploying XLibre and seatd session services..."
pkg install -y xlibre dbus avahi signal-cli seatd

sysrc dbus_enable=YES
sysrc avahi_daemon_enable=YES
sysrc seatd_enable=YES

mkdir -p /proc
if ! grep -q '[[:space:]]procfs[[:space:]]' /etc/fstab 2>/dev/null; then
    printf "%-10s %-12s %-12s %-10s %-5s %s\n" "proc" "/proc" "procfs" "rw" "0" "0" >> /etc/fstab
fi
if ! grep -q '[[:space:]]fdescfs[[:space:]]' /etc/fstab 2>/dev/null; then
    printf "%-10s %-12s %-12s %-10s %-5s %s\n" "fdesc" "/dev/fd" "fdescfs" "rw" "0" "0" >> /etc/fstab
fi

mount -p | grep -q '[[:space:]]/proc[[:space:]]' || mount /proc 2>/dev/null || true
mount -p | grep -q '[[:space:]]/dev/fd[[:space:]]' || mount /dev/fd 2>/dev/null || true

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier     "All Keyboards"
    MatchIsKeyboard "yes"
    Option         "XkbLayout" "${XKB_LAYOUT}"
EOF

if [ -n "$XKB_VARIANT" ]; then
    cat >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
    Option         "XkbVariant" "${XKB_VARIANT}"
EOF
fi

cat >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
    Option         "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

# ==============================================================================
# 6. GPU HARDWARE CONFIGURATION
# ==============================================================================
echo "==> [7/17] Configuring display drivers based on detected hardware..."

if [ "$HAS_NVIDIA" -eq 1 ]; then
    NVIDIA_INFO=$(echo "$DISPLAY_DEVICES" | grep -Ei "10de|NVIDIA")
    if [ -n "$FORCE_NVIDIA_DRIVER" ]; then
        NVIDIA_DRIVER_VERSION="$FORCE_NVIDIA_DRIVER"
    else
        if echo "$NVIDIA_INFO" | grep -Eqi "GK[0-9]|Quadro K|GeForce (GTX )?(6[0-9]{2}|7[0-4][0-9]|760|770|780|Titan( Z)?$)"; then
            NVIDIA_DRIVER_VERSION="470"
        elif echo "$NVIDIA_INFO" | grep -Eqi "GM[0-9]|GP[0-9]|GV[0-9]|Quadro (M|P|V|GP|GV)|GeForce (GTX )?(750|9[0-9]{2}|10[0-9]{2})|Titan (X|V)"; then
            NVIDIA_DRIVER_VERSION="580"
        else
            NVIDIA_DRIVER_VERSION="latest"
        fi
    fi

    echo "--> Detected NVIDIA GPU: Selected driver branch = $NVIDIA_DRIVER_VERSION"
    set_loader_conf "efi_max_resolution" "1440p"
    set_loader_conf "kern.vt.fb.default_mode" "2560x1440"
    set_loader_conf "hw.nvidiadrm.modeset" "1"
    set_loader_conf "hw.nvidia.registry.EnableGpuFirmware" "1"
    set_loader_conf "nvidia-drm.modeset" "1"

    add_to_kld_list "nvidia-modeset"
    add_to_kld_list "nvidia-drm"

    case "$NVIDIA_DRIVER_VERSION" in
        "470")
            pkg install -y nvidia-driver-470 linux-nvidia-libs-470 nvidia-kmod-470 nvidia-drm-kmod-470 libc6-shim nvidia-settings nvidia-xconfig
            ;;
        "580")
            pkg install -y nvidia-driver-580 linux-nvidia-libs-580 nvidia-kmod-580 nvidia-drm-kmod-580 libc6-shim nvidia-settings nvidia-xconfig
            ;;
        *)
            pkg install -y nvidia-driver linux-nvidia-libs nvidia-kmod nvidia-drm-kmod libc6-shim nvidia-settings nvidia-xconfig
            ;;
    esac

    cat > /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf << 'EOF'
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    Option         "ModeValidation" "NoMaxResolutionCheck"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    VendorName     "Unknown"
    ModelName      "Unknown"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "NVIDIA Card"
    Monitor        "Monitor0"
    DefaultDepth    24
    Option         "MetaModes" "2560x1440 +0+0"
    SubSection "Display"
        Depth       24
        Modes      "2560x1440"
    EndSubSection
EndSection
EOF
fi

if [ "$HAS_INTEL" -eq 1 ]; then
    echo "--> Detected Intel GPU: Installing drm-kmod and configuring KMS..."
    pkg install -y drm-kmod
    add_to_kld_list "i915kms"
    INTEL_DRIVER_NAME="i915kms (KMS) + modesetting"

    cat > /usr/local/etc/X11/xorg.conf.d/10-intel.conf << 'EOF'
Section "Device"
    Identifier     "Intel Graphics"
    Driver         "modesetting"
    Option         "AccelMethod" "glamor"
    Option         "TearFree"    "true"
    Option         "DRI"         "3"
EndSection
EOF
fi

if [ "$HAS_AMD" -eq 1 ]; then
    AMD_INFO=$(echo "$DISPLAY_DEVICES" | grep -Ei "1002|Advanced Micro Devices|ATI")
    if echo "$AMD_INFO" | grep -Eqi "HD [2-8][0-9]{3}|Radeon HD|Mobility Radeon HD|FirePro [MV]|RV[0-9]|R[1-9]00|TeraScale"; then
        AMD_DRIVER_TYPE="radeonkms"
        AMD_DRIVER_NAME="radeonkms (KMS Legacy) + modesetting"
        echo "--> Detected AMD Radeon Legacy GPU: Loading radeonkms..."
        pkg install -y drm-kmod
        add_to_kld_list "radeonkms"

        cat > /usr/local/etc/X11/xorg.conf.d/10-radeon.conf << 'EOF'
Section "Device"
    Identifier     "Radeon Legacy Graphics"
    Driver         "modesetting"
    Option         "AccelMethod" "glamor"
    Option         "TearFree"    "true"
    Option         "DRI"         "3"
EndSection
EOF
    else
        AMD_DRIVER_TYPE="amdgpu"
        AMD_DRIVER_NAME="amdgpu (Modern KMS / RDNA / GCN) + modesetting"
        echo "--> Detected Modern AMD Radeon GPU: Loading amdgpu..."
        pkg install -y drm-kmod
        add_to_kld_list "amdgpu"

        cat > /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf << 'EOF'
Section "Device"
    Identifier     "AMD Radeon Graphics"
    Driver         "modesetting"
    Option         "AccelMethod" "glamor"
    Option         "TearFree"    "true"
    Option         "DRI"         "3"
EndSection
EOF
    fi
fi

# ==============================================================================
# 7. ADVANCED WAYLAND STACK CONFIGURATION (IF REQUESTED)
# ==============================================================================
if [ "$INSTALL_WAYLAND" -eq 1 ]; then
    echo "==> [8/17] Deploying Wayland ecosystem, seatd, and XWayland..."
    pkg install -y wayland wayland-protocols xwayland seatd pam_xdg wl-clipboard

    # Load uinput module for virtual inputs
    set_loader_conf "uinput_load" "YES"
    safe_kldload uinput
    add_to_kld_list "uinput"

    # Enable seatd service
    sysrc seatd_enable=YES

    # PAM module configuration for automated XDG_RUNTIME_DIR handling
    if [ -f /etc/pam.d/system ]; then
        if ! grep -q "pam_xdg.so" /etc/pam.d/system; then
            echo "session    optional    pam_xdg.so" >> /etc/pam.d/system
        fi
    fi

    # Global environment profiles for Wayland
    mkdir -p /usr/local/etc/profile.d
    cat > /usr/local/etc/profile.d/wayland.sh << 'EOF'
# Global Wayland environment variables on FreeBSD
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/var/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        mkdir -m 0700 -p "$XDG_RUNTIME_DIR"
        chown "$(id -u):$(id -g)" "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
fi
export LIBSEAT_BACKEND=seatd
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export MOZ_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER="wayland,x11"
export CLUTTER_BACKEND=wayland
EOF
    chmod 0755 /usr/local/etc/profile.d/wayland.sh

    if ! grep -q '/usr/local/etc/profile.d/wayland.sh' /etc/profile 2>/dev/null; then
        cat >> /etc/profile << 'EOF'
if [ -f /usr/local/etc/profile.d/wayland.sh ]; then
    . /usr/local/etc/profile.d/wayland.sh
fi
EOF
    fi

    # Console fallback launcher
    cat > /usr/local/bin/start-wayland-plasma << 'EOF'
#!/bin/sh
if [ -f /usr/local/etc/profile.d/wayland.sh ]; then
    . /usr/local/etc/profile.d/wayland.sh
fi
exec /usr/local/bin/startplasma-wayland
EOF
    chmod 0755 /usr/local/bin/start-wayland-plasma
fi

# ==============================================================================
# 8. DEVFS SECURITY & PERMISSION RULES (DRI, EVDEV, USB, STORAGE)
# ==============================================================================
echo "==> [9/17] Updating devfs rules for DRI, evdev, uinput, and storage..."
if ! grep -q '\[localrules=5\]' /etc/devfs.rules 2>/dev/null; then
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
add path 'video*' mode 0660 group operator
add path 'dri*' mode 0666 group video
add path 'drm*' mode 0666 group video
add path 'input*' mode 0660 group operator
add path 'uinput' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF
fi

sysrc devfs_system_ruleset=localrules
service devfs restart

# ==============================================================================
# 9. PERSISTENT ASSETS REPOSITORY (NON-VOLATILE CACHE)
# ==============================================================================
if [ "$SELECTED_SPLASH" != "STANDARD" ] || is_selected "THEME_NASA"; then
    echo "==> [10/17] Synchronizing theme graphics in persistent cache ($ASSETS_DIR)..."
    mkdir -p /var/cache
    if [ ! -d "$ASSETS_DIR" ]; then
        git clone https://github.com/msartor99/FreeBSD14 "$ASSETS_DIR"
    else
        git -C "$ASSETS_DIR" pull 2>/dev/null || true
    fi
fi

# ==============================================================================
# 10. BOOT SPLASH SCREEN DEPLOYMENT (BMP + PNG DUAL SUPPORT)
# ==============================================================================
mkdir -p /boot/images

SPLASH_SRC=""
case "$SELECTED_SPLASH" in
    "KAMILA")
        SPLASH_SRC="$ASSETS_DIR/v2-blue.png"
        echo "==> [11/17] Installing Kamila Blue boot splash..."
        ;;
    "NASA")
        SPLASH_SRC="$ASSETS_DIR/nasa1920.png"
        echo "==> [11/17] Installing NASA boot splash..."
        ;;
    *)
        echo "==> [11/17] Restoring standard FreeBSD boot logo..."
        unset_loader_conf "splash"
        unset_loader_conf "shutdown_splash"
        unset_loader_conf "splash_bmp_load"
        unset_loader_conf "bitmap_load"
        unset_loader_conf "bitmap_name"
        unset_loader_conf "bitmap_type"
        set_loader_conf "loader_logo" "beastie"
        ;;
esac

if [ -n "$SPLASH_SRC" ]; then
    if [ -f "$SPLASH_SRC" ]; then
        cp -f "$SPLASH_SRC" /boot/images/splash.png
        
        # Convert to 24-bit uncompressed BMP for splash_bmp kernel loader module
        if command -v magick >/dev/null 2>&1; then
            magick /boot/images/splash.png -type TrueColor BMP3:/boot/images/splash.bmp 2>/dev/null || true
        elif command -v convert >/dev/null 2>&1; then
            convert /boot/images/splash.png -type TrueColor BMP3:/boot/images/splash.bmp 2>/dev/null || true
        fi

        set_loader_conf "boot_mute" "YES"
        set_loader_conf "loader_logo" "none"
        set_loader_conf "splash" "/boot/images/splash.png"
        set_loader_conf "shutdown_splash" "/boot/images/splash.png"
        
        if [ -f /boot/images/splash.bmp ]; then
            set_loader_conf "splash_bmp_load" "YES"
            set_loader_conf "bitmap_load" "YES"
            set_loader_conf "bitmap_name" "/boot/images/splash.bmp"
            set_loader_conf "bitmap_type" "splash_image"
        fi
        echo "--> Splash screen successfully configured (BMP and PNG synced)."
    else
        echo "Warning: Source image $SPLASH_SRC not found. Preserving current boot graphic." >&2
    fi
fi

# ==============================================================================
# 11. SDDM DISPLAY MANAGER & THEMES
# ==============================================================================
if is_selected "SDDM" || is_selected "THEME_NASA"; then
    echo "==> [12/17] Setting up SDDM session display manager..."
    pkg install -y sddm
    sysrc sddm_enable=YES
    sysrc sddm_lang="${LANG_CODE}"

    mkdir -p /usr/local/share/sddm/scripts
    append_line_if_missing /usr/local/share/sddm/scripts/Xsetup "${SDDM_KBD}"

    mkdir -p /usr/local/etc/sddm.conf.d

    if [ "$INSTALL_WAYLAND" -eq 1 ]; then
        cat > /usr/local/etc/sddm.conf.d/wayland.conf << 'EOF'
[Wayland]
EnableHiDPI=true
SessionDir=/usr/local/share/wayland-sessions
EOF
    fi

    if is_selected "THEME_NASA"; then
        echo "--> Applying SDDM NASA custom theme..."
        mkdir -p /usr/local/share/sddm/themes/nasa
        if [ -d /usr/local/share/sddm/themes/maldives ]; then
            cp -n /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/ 2>/dev/null || true
        fi

        if [ -f "$ASSETS_DIR/nasa2560login.jpg" ]; then
            cp -f "$ASSETS_DIR/nasa2560login.jpg" /usr/local/share/sddm/themes/nasa/background.jpg
        fi

        cat > /usr/local/etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=nasa

[General]
InputMethod=""
displayFont="Montserrat"
EOF
    else
        cat > /usr/local/etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=maldives

[General]
InputMethod=""
EOF
    fi
fi

# ==============================================================================
# 12. LINUX EMULATION SUBSYSTEM
# ==============================================================================
if is_selected "LINUX"; then
    echo "==> [13/17] Enabling Linux binary compatibility (RL9)..."
    sysrc linux_enable=YES
    sysrc linux64_enable=YES
    sysrc linux_mounts_enable=YES

    safe_kldload linux
    safe_kldload linux64
    service linux status >/dev/null 2>&1 || service linux start

    pkg install -y linux-rl9
fi

# ==============================================================================
# 13. CUPS PRINTING & STORAGE MANAGEMENT
# ==============================================================================
if is_selected "CUPS_USB"; then
    echo "==> [14/17] Installing CUPS and storage/FUSE tools..."
    pkg install -y cups gutenprint cups-filters hplip system-config-printer \
        fusefs-ntfs fusefs-ext2 fusefs-hfsfuse smartmontools

    sysrc cupsd_enable=YES
    sysrc smartd_enable=YES
    if [ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ]; then
        cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
    fi
    service smartd status >/dev/null 2>&1 || service smartd start

    safe_kldload fusefs
    safe_kldload ext2fs
    add_to_kld_list fusefs
    add_to_kld_list ext2fs
fi

# ==============================================================================
# 14. AUDIO SUBSYSTEM (PIPEWIRE / PULSEAUDIO)
# ==============================================================================
if is_selected "AUDIO"; then
    echo "==> [15/17] Configuring audio services and PipeWire..."
    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme pavucontrol

    set_loader_conf "sound_load" "YES"
    set_loader_conf "snd_hda_load" "YES"
    set_sysctl_conf "hw.snd.default_unit" "1"
fi

# ==============================================================================
# 15. DESKTOP ENVIRONMENTS (PLASMA 6, XFCE, MATE)
# ==============================================================================
if is_selected "PLASMA6"; then
    echo "==> Installing KDE Plasma 6 desktop and KF6 frameworks..."
    pkg install -y -g "plasma6-*" "kf6-*"
    pkg install -y kate konsole ark remmina dolphin kvantum-qt6
fi

if is_selected "XFCE"; then
    echo "==> Installing XFCE 4 desktop and goodies..."
    pkg install -y xfce xfce4-goodies
fi

if is_selected "MATE"; then
    echo "==> Installing MATE desktop..."
    pkg install -y -g "mate-*"
fi

# ==============================================================================
# 16. DESKTOP APPLICATIONS & VIRTUALBOX 7
# ==============================================================================
if is_selected "APPS"; then
    echo "==> [16/17] Installing standard desktop applications..."
    pkg install -y unzip libzip htop neofetch python3 bashtop \
        firefox vlc ffmpeg libva-vdpau-driver libva-utils \
        libdvdread libdvdnav xdg-user-dirs octopkg multimedia/mpv \
        gstreamer1-plugins-all gstreamer1-libav libbluray
fi

if is_selected "VBOX"; then
    echo "==> Installing VirtualBox 7 and host kernel modules..."
    pkg install -y virtualbox-ose

    safe_kldload vboxdrv
    safe_kldload vboxnetflt
    safe_kldload vboxnetadp

    set_loader_conf "vboxdrv_load" "YES"
    set_loader_conf "vboxnet_load" "YES"
    sysrc vboxnet_enable=YES

    pw groupmod vboxusers -m root 2>/dev/null || true
    pw groupmod vboxusers -m "$TARGET_USER" 2>/dev/null || true
    pw usermod "$TARGET_USER" -G wheel,operator,video,seatd,vboxusers 2>/dev/null || true

    append_line_if_missing /etc/devfs.conf "own     vboxnetctl root:vboxusers"
    append_line_if_missing /etc/devfs.conf "perm    vboxnetctl 0660"

    service devfs restart
fi

# ==============================================================================
# 17. PACKAGE REPOSITORY BRANCH SWITCH: QUARTERLY TO LATEST
# ==============================================================================
echo "==> [17/17] Checking package repository branch preferences..."
SWITCHED_TO_LATEST=0
PKG_LATEST_PROMPT="FreeBSD defaults to the 'quarterly' package branch for long-term stability.\n\nWould you like to switch to the 'latest' package branch (continuous rolling updates with the newest packages) and run an immediate system-wide upgrade?"

if bsddialog --title " PACKAGE REPOSITORY BRANCH (QUARTERLY / LATEST) " \
    --yes-label "Switch to Latest" \
    --no-label "Keep Quarterly" \
    --yesno "$PKG_LATEST_PROMPT" 14 74; then
    clear
    echo "--> Configuring pkg repository to use 'latest' branch..."
    mkdir -p /usr/local/etc/pkg/repos
    cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
  url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest"
}
EOF
    echo "--> Forcing package repository index refresh..."
    pkg update -f
    echo "--> Running full package upgrade..."
    pkg upgrade -y
    SWITCHED_TO_LATEST=1
else
    clear
    echo "--> Keeping default 'quarterly' package branch."
fi

# ==============================================================================
# FINAL DEPLOYMENT SUMMARY REPORT
# ==============================================================================
echo ""
echo "=============================================================================="
echo "                   INSTALLATION SUMMARY REPORT                                "
echo "=============================================================================="
echo "Primary Workstation Operator : ${TARGET_USER} (UID: ${TARGET_UID})"
echo "Configured Language          : ${CLASS_DESC} (${LANG_CODE})"
echo "Selected Keyboard Layout     : ${SELECTED_KBD} (Console: ${CONSOLE_KEYMAP}, XLibre: ${XKB_LAYOUT} ${XKB_VARIANT})"
echo "Processor Architecture       : $SELECTED_CPU"
echo "Boot Splash Screen           : $SELECTED_SPLASH"
if [ "$SWITCHED_TO_LATEST" -eq 1 ]; then
    echo "Package Repository (PKG)     : latest (active and updated)"
else
    echo "Package Repository (PKG)     : quarterly (FreeBSD default)"
fi
echo ""
echo "Display Environment & Graphic Stacks:"
echo "  - X11 Display Server       : XLibre (Legacy X.Org completely removed)"
if [ "$INSTALL_WAYLAND" -eq 1 ]; then
    echo "  - Wayland Compositing      : ENABLED (seatd, uinput, pam_xdg, XWayland)"
    echo "    Console Launcher         : Available via /usr/local/bin/start-wayland-plasma"
    echo "    SDDM Display Session     : Wayland profile active"
else
    echo "  - Wayland Compositing      : DISABLED (XLibre only)"
fi
echo ""
echo "Graphics Hardware & Drivers Configured:"
if [ "$HAS_NVIDIA" -eq 1 ]; then
    echo "  - [NVIDIA] Driver          : nvidia-driver (${NVIDIA_DRIVER_VERSION})"
    echo "             Modules         : nvidia-modeset, nvidia-drm"
    echo "             Config          : /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf"
fi
if [ "$HAS_INTEL" -eq 1 ]; then
    echo "  - [INTEL]  Driver          : drm-kmod (${INTEL_DRIVER_NAME})"
    echo "             Module          : i915kms"
    echo "             Config          : /usr/local/etc/X11/xorg.conf.d/10-intel.conf (Glamor / TearFree)"
fi
if [ "$HAS_AMD" -eq 1 ]; then
    if [ "$AMD_DRIVER_TYPE" = "radeonkms" ]; then
        echo "  - [RADEON] Driver          : drm-kmod (${AMD_DRIVER_NAME})"
        echo "             Module          : radeonkms"
        echo "             Config          : /usr/local/etc/X11/xorg.conf.d/10-radeon.conf (Glamor / TearFree)"
    else
        echo "  - [AMD]    Driver          : drm-kmod (${AMD_DRIVER_NAME})"
        echo "             Module          : amdgpu"
        echo "             Config          : /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf (Glamor / TearFree)"
    fi
fi
if [ "$HAS_NVIDIA" -eq 0 ] && [ "$HAS_INTEL" -eq 0 ] && [ "$HAS_AMD" -eq 0 ]; then
    echo "  - [GENERIC] No specific hardware accelerated GPU identified (fallback VESA/SCFB)"
fi

echo ""
echo "Installed Optional Modules:"
for _item in LINUX CUPS_USB AUDIO SDDM THEME_NASA PLASMA6 XFCE MATE APPS VBOX; do
    if is_selected "$_item"; then
        echo "  - [X] $_item"
    fi
done
echo "=============================================================================="
echo "Reboot the workstation to initialize the kernel modules and graphical session."
echo "=============================================================================="