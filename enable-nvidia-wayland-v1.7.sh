#!/bin/sh
# ==============================================================================
# SCRIPT NAME : enable-nvidia-wayland-v1.7.sh
# VERSION     : 1.7
# TARGET      : FreeBSD 15.x-RELEASE / 16-CURRENT (amd64)
# PURPOSE     : Pure system-level KDE Plasma 6 (Wayland) enabler for NVIDIA GPUs
#               on an existing X11 workstation (No user, locale, or kbd changes).
#               Includes hardware speaker beep notifications (1 = OK, 3 = Error).
# STANDARDS   : Strict POSIX sh, Idempotent, Auto-detection,
#               Per-package source compilation verification.
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. PRIVILEGE & AUDIO BEEP HELPERS
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "[Error] This script must be run as root (superuser)." 1>&2
    exit 1
fi

# Emit a single hardware/console beep
emit_single_beep() {
    # 1. Try FreeBSD hardware PC speaker (/dev/speaker)
    if [ ! -c /dev/speaker ]; then
        kldload -n speaker >/dev/null 2>&1 || true
    fi
    if [ -c /dev/speaker ]; then
        echo "O3L8C" > /dev/speaker 2>/dev/null || true
    fi
    # 2. Emit ASCII BEL to physical console and active terminal
    printf "\a" > /dev/ttyv0 2>/dev/null || true
    printf "\a" > /dev/tty 2>/dev/null || true
}

# 1 beep on success
beep_success() {
    emit_single_beep
}

# 3 beeps on failure/error
beep_error() {
    emit_single_beep
    sleep 0.25
    emit_single_beep
    sleep 0.25
    emit_single_beep
}

cleanup() {
    stty sane 2>/dev/null || true
}

on_interrupt() {
    cleanup
    echo ""
    echo "[Error] Script interrupted!"
    beep_error
    exit 1
}
trap cleanup EXIT
trap on_interrupt INT TERM

add_line_if_missing() {
    LINE="$1"
    FILE="$2"
    [ ! -f "$FILE" ] && touch "$FILE"
    grep -qF -- "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

# Check if a package was already compiled from ports by this script (or locked from ports)
is_pkg_compiled() {
    PKG_NAME="$1"
    if ! pkg info -e "$PKG_NAME" >/dev/null 2>&1; then
        return 1
    fi
    # Check custom annotation set after successful ports build
    if pkg query "%At:%Av" "$PKG_NAME" 2>/dev/null \vert{} grep -q "^wayland_egl_built:yes$"; then
        return 0
    fi
    # Fallback: check if package has no remote repository annotation AND is locked
    if ! pkg query "%R" "$PKG_NAME" 2>/dev/null | grep -q "FreeBSD" && pkg query "%k" "$PKG_NAME" 2>/dev/null \vert{} grep -q "^1$"; then
        return 0
    fi
    return 1
}

mark_pkg_compiled() {
    PKG_NAME="$1"
    pkg annotate -y -A "$PKG_NAME" wayland_egl_built "yes" >/dev/null 2>&1 || \
    pkg annotate -y -M "$PKG_NAME" wayland_egl_built "yes" >/dev/null 2>&1 || true
    pkg lock -y "$PKG_NAME" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# 1. AUTOMATIC GPU & BUILD STATUS DETECTION
# ------------------------------------------------------------------------------
NVIDIA_MODEL=$(pciconf -lv 2>/dev/null | grep -i -A 2 "vendor.*'NVIDIA" | grep "device" | cut -d"'" -f2 | head -n 1 || true)
[ -z "$NVIDIA_MODEL" ] && NVIDIA_MODEL="NVIDIA GPU"

if pkg info -e nvidia-driver-550 >/dev/null 2>&1; then
    NVIDIA_BRANCH="550"
elif pkg info -e nvidia-driver-580 >/dev/null 2>&1; then
    NVIDIA_BRANCH="580"
elif pkg info -e nvidia-driver >/dev/null 2>&1; then
    NVIDIA_BRANCH="latest"
elif echo "$NVIDIA_MODEL" | grep -qiE "GTX 10|Quadro P|P[0-9]{3,4}|TITAN X"; then
    NVIDIA_BRANCH="550"
else
    NVIDIA_BRANCH="latest"
fi

case "$NVIDIA_BRANCH" in
    550)
        PORT_NVIDIA="x11/nvidia-driver-550"
        PORT_NVIDIA_DRM="graphics/nvidia-drm-550-kmod"
        NV_PKG="nvidia-driver-550"
        NV_DRM_PKG="nvidia-drm-550-kmod"
        ;;
    580)
        PORT_NVIDIA="x11/nvidia-driver-580"
        PORT_NVIDIA_DRM="graphics/nvidia-drm-kmod-580"
        NV_PKG="nvidia-driver-580"
        NV_DRM_PKG="nvidia-drm-kmod-580"
        ;;
    *)
        PORT_NVIDIA="x11/nvidia-driver"
        PORT_NVIDIA_DRM="graphics/nvidia-drm-kmod"
        NV_PKG="nvidia-driver"
        NV_DRM_PKG="nvidia-drm-kmod"
        ;;
esac

STATUS_QT6="NEEDS COMPILATION"
STATUS_KWIN="NEEDS COMPILATION"
STATUS_SDDM="NEEDS COMPILATION"

is_pkg_compiled "qt6-wayland" && STATUS_QT6="ALREADY COMPILED (SKIP)"
is_pkg_compiled "plasma6-kwin" && STATUS_KWIN="ALREADY COMPILED (SKIP)"
is_pkg_compiled "sddm" && STATUS_SDDM="ALREADY COMPILED (SKIP)"

# ------------------------------------------------------------------------------
# 2. SINGLE CONFIRMATION DIALOG (OR "-y" FLAG FOR UNATTENDED RUN)
# ------------------------------------------------------------------------------
if [ "$1" != "-y" ] && command -v bsddialog >/dev/null 2>&1; then
    SUMMARY_MSG="Auto-detected system configuration:\n\n- GPU Detected   : ${NVIDIA_MODEL}\n- NVIDIA Branch  : ${NVIDIA_BRANCH} (${NV_PKG} + ${NV_DRM_PKG})\n\nPorts Source Build Status:\n- qt6-wayland    :${STATUS_QT6}\n- plasma6-kwin   : ${STATUS_KWIN}\n- sddm           :${STATUS_SDDM}\n\nAudio notification: 1 beep on completion, 3 beeps on error.\nProceed with automatic Wayland configuration?"

    bsddialog --title "NVIDIA WAYLAND AUTO-ENABLER (v1.7)" --yesno "$SUMMARY_MSG" 19 76 </dev/tty >/dev/tty
    if [ $? -ne 0 ]; then
        clear
        echo "Operation cancelled by the operator."
        exit 0
    fi
    clear
fi

LOG_FILE="/var/log/enable_nvidia_wayland.log"
STATUS_FILE=$(mktemp /tmp/wayland_status.XXXXXX)
echo "0" > "$STATUS_FILE"

# ==============================================================================
# MAIN EXECUTION FUNCTION
# ==============================================================================
execute_wayland_setup() {
    echo "=========================================================================="
    echo " Starting Automated NVIDIA + KDE Plasma 6 Wayland Setup (v1.7)"
    echo " GPU Branch: $NVIDIA_BRANCH ($NV_PKG +$NV_DRM_PKG)"
    echo " Log file: $LOG_FILE"
    echo "=========================================================================="

    # --------------------------------------------------------------------------
    # STEP 1: INSTALL REQUIRED WAYLAND & BUILD PACKAGES
    # --------------------------------------------------------------------------
    echo "[1/5] Ensuring required binary dependencies are installed..."

    for req_pkg in wayland xwayland seatd dbus consolekit2 plasma6-plasma git cmake ninja pkgconf; do
        if ! pkg info -e "$req_pkg" >/dev/null 2>&1; then
            echo " -> Installing missing package: $req_pkg"
            if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$req_pkg"; then
                echo "[Error] Failed to install required package: $req_pkg"
                return 1
            fi
        fi
    done

    if ! pkg info -e linux-nvidia-libs >/dev/null 2>&1; then
        env ASSUME_ALWAYS_YES=YES pkg install -y linux-nvidia-libs 2>/dev/null || true
    fi

    if ! pkg info -e "$NV_PKG" >/dev/null 2>&1; then
        echo " -> Installing $NV_PKG..."
        if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$NV_PKG"; then
            echo "[Error] Failed to install $NV_PKG"
            return 1
        fi
    fi

    NEED_DRM_PORT_BUILD="no"
    if ! pkg info -e "$NV_DRM_PKG" >/dev/null 2>&1; then
        echo " -> Installing $NV_DRM_PKG..."
        if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$NV_DRM_PKG"; then
            echo " -> Binary $NV_DRM_PKG unavailable or failed; scheduling build from ports."
            NEED_DRM_PORT_BUILD="yes"
        fi
    fi

    # Clean up legacy conflicting environment scripts
    rm -f /home/*/.config/plasma-workspace/env/nvidia-wayland.sh 2>/dev/null || true
    rm -f /root/.config/plasma-workspace/env/nvidia-wayland.sh 2>/dev/null || true
    rm -f /usr/local/etc/sddm.conf.d/20-wayland.conf 2>/dev/null || true

    # --------------------------------------------------------------------------
    # STEP 2: KERNEL MODULES, KMS & SPLASH PANIC PREVENTION
    # --------------------------------------------------------------------------
    echo "[2/5] Configuring NVIDIA DRM KMS and disabling boot splash screens..."

    mkdir -p /proc
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab
    mount -a 2>/dev/null || true

    sysrc dbus_enable="YES"
    sysrc seatd_enable="YES"
    sysrc sddm_enable="YES"
    sysrc linux_enable="YES"
    sysrc linux64_enable="YES"

    # Configure Late KMS loading in /etc/rc.conf (nvidia-modeset & nvidia-drm)
    CURRENT_KLD=$(sysrc -n kld_list 2>/dev/null || echo "")
    CLEAN_KLD=$(echo "$CURRENT_KLD" \vert{} sed -E 's/(nvidia-modeset\vert{}nvidia-drm\vert{}nvidia)//g' \vert{} tr -s ' ' \vert{} sed 's/^ *//;s/ *$//')
    if [ -n "$CLEAN_KLD" ]; then
        sysrc kld_list="$CLEAN_KLD nvidia-modeset nvidia-drm"
    else
        sysrc kld_list="nvidia-modeset nvidia-drm"
    fi

    # Configure /boot/loader.conf for NVIDIA DRM KMS
    add_line_if_missing 'hw.nvidiadrm.modeset="1"' /boot/loader.conf
    add_line_if_missing 'nvidia-drm.modeset="1"' /boot/loader.conf
    add_line_if_missing 'hw.nvidia.registry.EnableGpuFirmware="1"' /boot/loader.conf

    # Remove splash screens to prevent Page Fault Kernel Panics with NVIDIA DRM
    sed -i '' '/^splash_changer_enable/d' /etc/rc.conf 2>/dev/null || true
    sed -i '' '/^splash/d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/^shutdown_splash/d' /boot/loader.conf 2>/dev/null || true

    add_line_if_missing "export NVIDIA_DRM_MODESET=1" /etc/profile
    add_line_if_missing "export WLR_NO_HARDWARE_CURSORS=1" /etc/profile

    # --------------------------------------------------------------------------
    # STEP 3: DEVFS RULES & SDDM SYSTEM PERMISSIONS
    # --------------------------------------------------------------------------
    echo "[3/5] Configuring DevFS rules (DRM/TTY) and SDDM daemon permissions..."

    DEVFS_FILE="/etc/devfs.rules"
    if ! grep -q "^\[localrules=10\]" "$DEVFS_FILE" 2>/dev/null; then
        cat << 'EOF' >> "$DEVFS_FILE"

[localrules=10]
add path 'drm/*' mode 0660 group video
add path 'video*' mode 0660 group video
add path 'ttyv*' mode 0660 group video
EOF
    else
        add_line_if_missing "add path 'drm/*' mode 0660 group video" "$DEVFS_FILE"
        add_line_if_missing "add path 'video*' mode 0660 group video" "$DEVFS_FILE"
        add_line_if_missing "add path 'ttyv*' mode 0660 group video" "$DEVFS_FILE"
    fi

    sysrc devfs_system_ruleset="localrules"
    service devfs restart 2>/dev/null || true
    service seatd restart 2>/dev/null || service seatd start 2>/dev/null || true

    for grp in video tty; do
        if pw groupshow "$grp" >/dev/null 2>&1; then
            pw groupmod "$grp" -m sddm 2>/dev/null || true
        fi
    done

    # --------------------------------------------------------------------------
    # STEP 4: VERIFY & COMPILE WAYLAND PACKAGES FROM PORTS (ONLY IF NEEDED)
    # --------------------------------------------------------------------------
    echo "[4/5] Checking source compilation status for Wayland/EGL ports..."

    if ! grep -q "OPTIONS_SET.*WAYLAND" /etc/make.conf 2>/dev/null; then
        echo "OPTIONS_SET+=WAYLAND NVIDIA EGL" >> /etc/make.conf
    fi

    NEED_PORTS_SYNC="no"
    if [ "$NEED_DRM_PORT_BUILD" = "yes" ] || ! is_pkg_compiled "qt6-wayland" || ! is_pkg_compiled "plasma6-kwin" || ! is_pkg_compiled "sddm"; then
        NEED_PORTS_SYNC="yes"
    fi

    if [ "$NEED_PORTS_SYNC" = "yes" ]; then
        echo " -> Synchronizing /usr/ports tree..."
        if [ ! -d /usr/ports/.git ]; then
            rm -rf /usr/ports
            git clone --depth 1 https://git.freebsd.org/ports.git /usr/ports || return 1
        else
            git -C /usr/ports clean -fdx || return 1
            git -C /usr/ports reset --hard HEAD || return 1
            git -C /usr/ports pull || return 1
        fi
    else
        echo " -> All target packages (qt6-wayland, plasma6-kwin, sddm) are already compiled from ports. Skipping Ports sync!"
    fi

    # 4.1 Optional NVIDIA DRM build if binary was missing
    if [ "$NEED_DRM_PORT_BUILD" = "yes" ]; then
        if [ ! -f /usr/src/sys/conf/newvers.sh ]; then
            REL_BRANCH="releng/$(uname -r | cut -d'-' -f1)"
            echo " -> Fetching /usr/src ($REL_BRANCH) for kernel module build..."
            git clone --depth 1 -b "$REL_BRANCH" https://git.freebsd.org/src.git /usr/src || \
            git clone --depth 1 https://git.freebsd.org/src.git /usr/src || return 1
        fi
        echo " -> Compiling $PORT_NVIDIA_DRM from ports..."
        pkg unlock -yq "$NV_DRM_PKG" 2>/dev/null || true
        make -C "/usr/ports/$PORT_NVIDIA_DRM" BATCH=yes deinstall install clean || return 1
        mark_pkg_compiled "$NV_DRM_PKG"
    fi

    # 4.2 qt6-wayland
    if is_pkg_compiled "qt6-wayland"; then
        echo " -> [SKIP] qt6-wayland is already compiled from ports and locked."
    else
        echo " -> [BUILD] Compiling graphics/qt6-wayland from ports with EGL..."
        pkg unlock -yq qt6-wayland 2>/dev/null || true
        pkg delete -y -f qt6-wayland 2>/dev/null || true
        make -C /usr/ports/graphics/qt6-wayland clean || return 1
        make -C /usr/ports/graphics/qt6-wayland BATCH=yes CMAKE_ARGS+="-DQT_NO_PACKAGE_VERSION_CHECK=TRUE" install clean || return 1
        mark_pkg_compiled "qt6-wayland"
    fi

    # 4.3 plasma6-kwin
    if is_pkg_compiled "plasma6-kwin"; then
        echo " -> [SKIP] plasma6-kwin is already compiled from ports and locked."
    else
        echo " -> [BUILD] Compiling x11-wm/plasma6-kwin from ports with EGL..."
        pkg unlock -yq plasma6-kwin 2>/dev/null || true
        pkg delete -y -f plasma6-kwin 2>/dev/null || true
        make -C /usr/ports/x11-wm/plasma6-kwin clean || return 1
        make -C /usr/ports/x11-wm/plasma6-kwin BATCH=yes install clean || return 1
        mark_pkg_compiled "plasma6-kwin"
    fi

    # 4.4 sddm
    if is_pkg_compiled "sddm"; then
        echo " -> [SKIP] sddm is already compiled from ports and locked."
    else
        echo " -> [BUILD] Compiling x11/sddm from ports..."
        pkg unlock -yq sddm 2>/dev/null || true
        pkg delete -y -f sddm 2>/dev/null || true
        make -C /usr/ports/x11/sddm clean || return 1
        make -C /usr/ports/x11/sddm BATCH=yes install clean || return 1
        mark_pkg_compiled "sddm"
    fi

    # --------------------------------------------------------------------------
    # STEP 5: SDDM & WAYLAND SESSION WRAPPERS
    # --------------------------------------------------------------------------
    echo "[5/5] Configuring SDDM X11 Greeter and Plasma 6 Wayland session wrappers..."

    mkdir -p /usr/local/etc/sddm.conf.d
    mkdir -p /usr/local/share/sddm/scripts
    mkdir -p /usr/local/bin
    mkdir -p /usr/local/share/xsessions

    cat > /usr/local/etc/sddm.conf.d/10-x11-backend.conf << 'EOF'
[General]
DisplayServer=x11
EOF

    if [ ! -f /usr/local/etc/sddm.conf.d/20-theme.conf ]; then
        cat > /usr/local/etc/sddm.conf.d/20-theme.conf << 'EOF'
[Theme]
Current=breeze
EOF
    fi

    cat > /usr/local/share/sddm/scripts/wayland-session << 'EOF'
#!/bin/sh
export KWIN_FORCE_SW_CURSOR=1
export WLR_NO_HARDWARE_CURSORS=1
export NVIDIA_DRM_MODESET=1
export QT_QPA_PLATFORM=wayland
export LIBSEAT_BACKEND=seatd

export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u)
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f /tmp/wayland-* 2>/dev/null || true

exec ck-launch-session dbus-run-session "$@"
EOF
    chmod 555 /usr/local/share/sddm/scripts/wayland-session

    cat > /usr/local/etc/sddm.conf.d/wayland-session.conf << 'EOF'
[Wayland]
SessionScript=/usr/local/share/sddm/scripts/wayland-session
EOF

    cat > /usr/local/bin/start-plasma-wayland.sh << 'EOF'
#!/bin/sh
export KWIN_FORCE_SW_CURSOR=1
export WLR_NO_HARDWARE_CURSORS=1
export NVIDIA_DRM_MODESET=1
export QT_QPA_PLATFORM=wayland
export LIBSEAT_BACKEND=seatd

export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u)
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f /tmp/wayland-* 2>/dev/null || true

exec ck-launch-session dbus-run-session startplasma-wayland > /tmp/plasma-wayland.log 2>&1
EOF
    chmod 555 /usr/local/bin/start-plasma-wayland.sh

    cat > /usr/local/share/xsessions/plasma-wayland-wrapper.desktop << 'EOF'
[Desktop Entry]
Name=Plasma (Wayland via Wrapper)
Comment=Plasma 6 Wayland Session via DBus/CK Wrapper
Exec=/usr/local/bin/start-plasma-wayland.sh
Type=Application
EOF

    echo "=========================================================================="
    echo " System-wide Wayland configuration complete! Please reboot your system."
    echo " At the SDDM login screen, select 'Plasma (Wayland)' or"
    echo " 'Plasma (Wayland via Wrapper)' before