#!/bin/sh
# ==============================================================================
# SCRIPT NAME : enable-nvidia-wayland-v2.4.sh
# VERSION     : 2.4
# TARGET      : FreeBSD 15.x-RELEASE / 16-CURRENT (amd64)
# PURPOSE     : Pure system-level KDE Plasma 6 (Wayland) enabler for NVIDIA GPUs
#               Fixes GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT (KWIN_DRM_NO_MODIFIERS=1,
#               unset KWIN_DRM_NO_AMS) and strictly verifies local ports builds
#               via pkg repository origin (%R == unknown-repository).
# STANDARDS   : Strict POSIX sh, Idempotent, Auto-detection,
#               True repository-origin compilation verification.
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. PRIVILEGE & NON-BLOCKING AUDIO BEEP HELPERS
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "[Error] This script must be run as root (superuser)." 1>&2
    exit 1
fi

emit_single_beep() {
    if [ ! -c /dev/speaker ]; then
        kldload -n speaker </dev/null >/dev/null 2>&1 || true
    fi
    if [ -c /dev/speaker ]; then
        timeout 2 sh -c 'echo "O3L8C" > /dev/speaker' </dev/null >/dev/null 2>&1 || true
    fi
    timeout 1 sh -c 'printf "\a" > /dev/ttyv0' </dev/null >/dev/null 2>&1 || true
    timeout 1 sh -c 'printf "\a" > /dev/tty' </dev/null >/dev/null 2>&1 || true
}

beep_success() {
    emit_single_beep
}

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

# Strict check: a package is ONLY considered compiled from ports if its
# repository origin (%R) is "unknown-repository" (i.e. built locally via make install)
is_pkg_compiled() {
    PKG_NAME="$1"
    if ! pkg info -e "$PKG_NAME" >/dev/null 2>&1; then
        return 1
    fi
    REPO_ORIGIN=$(pkg query "%R" "$PKG_NAME" 2>/dev/null || echo "")
    if [ "$REPO_ORIGIN" = "unknown-repository" ]; then
        return 0
    fi
    return 1
}

mark_pkg_compiled() {
    PKG_NAME="$1"
    pkg annotate -y -A "$PKG_NAME" wayland_egl_built "yes" >/dev/null 2>&1 || true
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

STATUS_QT6="NEEDS PORTS BUILD (Currently binary or missing)"
STATUS_KWIN="NEEDS PORTS BUILD (Currently binary or missing)"
STATUS_SDDM="NEEDS PORTS BUILD (Currently binary or missing)"

is_pkg_compiled "qt6-wayland" && STATUS_QT6="BUILT FROM PORTS (SKIP)"
is_pkg_compiled "plasma6-kwin" && STATUS_KWIN="BUILT FROM PORTS (SKIP)"
is_pkg_compiled "sddm" && STATUS_SDDM="BUILT FROM PORTS (SKIP)"

# ------------------------------------------------------------------------------
# 2. SINGLE CONFIRMATION DIALOG (OR "-y" FLAG FOR UNATTENDED RUN)
# ------------------------------------------------------------------------------
if [ "$1" != "-y" ] && command -v bsddialog >/dev/null 2>&1; then
    SUMMARY_MSG="Auto-detected system configuration:\n\n- GPU Detected   : ${NVIDIA_MODEL}\n- NVIDIA Branch  : ${NVIDIA_BRANCH} (${NV_PKG} + ${NV_DRM_PKG})\n\nTrue Ports Build Verification (%R == unknown-repository):\n- qt6-wayland    : ${STATUS_QT6}\n- plasma6-kwin   : ${STATUS_KWIN}\n- sddm           : ${STATUS_SDDM}\n\nFixes GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT & Atomic KMS.\nProceed with configuration?"

    bsddialog --title "NVIDIA WAYLAND AUTO-ENABLER (v2.4)" --yesno "$SUMMARY_MSG" 19 78 </dev/tty >/dev/tty
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
    echo " Starting Automated NVIDIA + KDE Plasma 6 Wayland Setup (v2.4)"
    echo " GPU Branch: $NVIDIA_BRANCH ($NV_PKG + $NV_DRM_PKG)"
    echo " Log file: $LOG_FILE"
    echo "=========================================================================="

    # --------------------------------------------------------------------------
    # STEP 1: INSTALL REQUIRED WAYLAND & BUILD PACKAGES
    # --------------------------------------------------------------------------
    echo "[1/5] Ensuring required runtime and build dependencies are installed..."

    for req_pkg in wayland xwayland seatd dbus consolekit2 plasma6-plasma; do
        if ! pkg info -e "$req_pkg" >/dev/null 2>&1; then
            echo " -> Installing missing runtime package: $req_pkg"
            if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$req_pkg" </dev/null; then
                echo "[Error] Failed to install required package: $req_pkg"
                return 1
            fi
        fi
    done

    command -v git >/dev/null 2>&1     || env ASSUME_ALWAYS_YES=YES pkg install -y git </dev/null || return 1
    command -v cmake >/dev/null 2>&1   || env ASSUME_ALWAYS_YES=YES pkg install -y cmake-core </dev/null || return 1
    command -v ninja >/dev/null 2>&1   || env ASSUME_ALWAYS_YES=YES pkg install -y ninja </dev/null || return 1
    command -v pkgconf >/dev/null 2>&1 || env ASSUME_ALWAYS_YES=YES pkg install -y pkgconf </dev/null || return 1

    if ! pkg info -e linux-nvidia-libs >/dev/null 2>&1; then
        env ASSUME_ALWAYS_YES=YES pkg install -y linux-nvidia-libs </dev/null 2>/dev/null || true
    fi

    if ! pkg info -e "$NV_PKG" >/dev/null 2>&1; then
        echo " -> Installing $NV_PKG..."
        if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$NV_PKG" </dev/null; then
            echo "[Error] Failed to install $NV_PKG"
            return 1
        fi
    fi

    NEED_DRM_PORT_BUILD="no"
    if ! pkg info -e "$NV_DRM_PKG" >/dev/null 2>&1; then
        echo " -> Installing $NV_DRM_PKG..."
        if ! env ASSUME_ALWAYS_YES=YES pkg install -y "$NV_DRM_PKG" </dev/null; then
            echo " -> Binary $NV_DRM_PKG unavailable or failed; scheduling build from ports."
            NEED_DRM_PORT_BUILD="yes"
        fi
    fi

    # Clean up any legacy environment scripts that might inject KWIN_DRM_NO_AMS
    rm -f /home/*/.config/plasma-workspace/env/*.sh 2>/dev/null || true
    rm -f /root/.config/plasma-workspace/env/*.sh 2>/dev/null || true
    rm -f /usr/local/etc/sddm.conf.d/20-wayland.conf 2>/dev/null || true
    rm -f /usr/local/share/xsessions/plasma-wayland-wrapper.desktop 2>/dev/null || true
    sed -i '' '/KWIN_DRM_NO_AMS/d' /etc/profile 2>/dev/null || true

    # --------------------------------------------------------------------------
    # STEP 2: KERNEL MODULES, KMS & SPLASH PANIC PREVENTION
    # --------------------------------------------------------------------------
    echo "[2/5] Configuring NVIDIA DRM KMS and disabling boot splash screens..."

    mkdir -p /proc
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab
    mount -a </dev/null >/dev/null 2>&1 || true

    sysrc dbus_enable="YES"
    sysrc seatd_enable="YES"
    sysrc sddm_enable="YES"
    sysrc linux_enable="YES"
    sysrc linux64_enable="YES"

    CURRENT_KLD=$(sysrc -n kld_list 2>/dev/null || echo "")
    CLEAN_KLD=$(echo "$CURRENT_KLD" | sed -E 's/(nvidia-modeset|nvidia-drm|nvidia)//g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    if [ -n "$CLEAN_KLD" ]; then
        sysrc kld_list="$CLEAN_KLD nvidia-modeset nvidia-drm"
    else
        sysrc kld_list="nvidia-modeset nvidia-drm"
    fi

    kldstat -qm nvidia_modeset || kldload nvidia-modeset </dev/null >/dev/null 2>&1 || true
    kldstat -qm nvidia_drm || kldload nvidia-drm </dev/null >/dev/null 2>&1 || true
    sysctl hw.nvidiadrm.modeset=1 </dev/null >/dev/null 2>&1 || true

    add_line_if_missing 'hw.nvidiadrm.modeset="1"' /boot/loader.conf
    add_line_if_missing 'nvidia-drm.modeset="1"' /boot/loader.conf
    add_line_if_missing 'hw.nvidia.registry.EnableGpuFirmware="1"' /boot/loader.conf

    sed -i '' '/^splash_changer_enable/d' /etc/rc.conf 2>/dev/null || true
    sed -i '' '/^splash/d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/^shutdown_splash/d' /boot/loader.conf 2>/dev/null || true

    add_line_if_missing "export NVIDIA_DRM_MODESET=1" /etc/profile
    add_line_if_missing "export WLR_NO_HARDWARE_CURSORS=1" /etc/profile

    # --------------------------------------------------------------------------
    # STEP 3: DEVFS RULES & DYNAMIC GROUP PERMISSIONS (SDDM + WORKSTATION USERS)
    # --------------------------------------------------------------------------
    echo "[3/5] Configuring DevFS rules (DRM/TTY/Seatd) and group permissions..."

    DEVFS_FILE="/etc/devfs.rules"
    if ! grep -q "^\[localrules=10\]" "$DEVFS_FILE" 2>/dev/null; then
        cat << 'EOF' >> "$DEVFS_FILE"

[localrules=10]
add path 'dri/*' mode 0660 group video
add path 'drm/*' mode 0660 group video
add path 'video*' mode 0660 group video
add path 'ttyv*' mode 0660 group video
EOF
    else
        add_line_if_missing "add path 'dri/*' mode 0660 group video" "$DEVFS_FILE"
        add_line_if_missing "add path 'drm/*' mode 0660 group video" "$DEVFS_FILE"
        add_line_if_missing "add path 'video*' mode 0660 group video" "$DEVFS_FILE"
        add_line_if_missing "add path 'ttyv*' mode 0660 group video" "$DEVFS_FILE"
    fi

    sysrc devfs_system_ruleset="localrules"

    for grp in video tty seatd; do
        if pw groupshow "$grp" >/dev/null 2>&1; then
            pw groupmod "$grp" -m sddm 2>/dev/null || true
            for usr in $(awk -F: '$3 >= 1000 && $3 < 65000 { print $1 }' /etc/passwd); do
                pw groupmod "$grp" -m "$usr" 2>/dev/null || true
            done
        fi
    done

    service devfs restart </dev/null >/dev/null 2>&1 || true
    service seatd restart </dev/null >/dev/null 2>&1 || service seatd start </dev/null >/dev/null 2>&1 || true

    # --------------------------------------------------------------------------
    # STEP 4: VERIFY & COMPILE WAYLAND PACKAGES FROM PORTS (ONLY IF NEEDED)
    # --------------------------------------------------------------------------
    echo "[4/5] Checking true source compilation status (%R == unknown-repository)..."

    add_line_if_missing "OPTIONS_SET+=WAYLAND NVIDIA EGL" /etc/make.conf
    add_line_if_missing "CMAKE_ARGS+=-DQT_NO_PACKAGE_VERSION_CHECK=TRUE" /etc/make.conf

    NEED_PORTS_SYNC="no"
    if [ "$NEED_DRM_PORT_BUILD" = "yes" ] || ! is_pkg_compiled "qt6-wayland" || ! is_pkg_compiled "plasma6-kwin" || ! is_pkg_compiled "sddm"; then
        NEED_PORTS_SYNC="yes"
    fi

    if [ "$NEED_PORTS_SYNC" = "yes" ]; then
        echo " -> Ensuring /usr/ports tree is available..."
        if [ ! -d /usr/ports/.git ]; then
            rm -rf /usr/ports
            git clone --depth 1 https://git.freebsd.org/ports.git /usr/ports </dev/null || return 1
        fi
    else
        echo " -> All target packages (qt6-wayland, plasma6-kwin, sddm) are already compiled from ports. Skipping!"
    fi

    if [ "$NEED_DRM_PORT_BUILD" = "yes" ]; then
        if [ ! -f /usr/src/sys/conf/newvers.sh ]; then
            REL_BRANCH="releng/$(uname -r | cut -d'-' -f1)"
            echo " -> Fetching /usr/src ($REL_BRANCH) for kernel module build..."
            git clone --depth 1 -b "$REL_BRANCH" https://git.freebsd.org/src.git /usr/src </dev/null || \
            git clone --depth 1 https://git.freebsd.org/src.git /usr/src </dev/null || return 1
        fi
        echo " -> Compiling $PORT_NVIDIA_DRM from ports..."
        pkg unlock -yq "$NV_DRM_PKG" 2>/dev/null || true
        make -C "/usr/ports/$PORT_NVIDIA_DRM" BATCH=yes deinstall install clean </dev/null || return 1
        mark_pkg_compiled "$NV_DRM_PKG"
    fi

    if is_pkg_compiled "qt6-wayland"; then
        echo " -> [SKIP] qt6-wayland is already compiled from ports."
        mark_pkg_compiled "qt6-wayland"
    else
        echo " -> [BUILD] Compiling graphics/qt6-wayland from ports with EGL..."
        pkg unlock -yq qt6-wayland 2>/dev/null || true
        pkg delete -y -f qt6-wayland 2>/dev/null || true
        make -C /usr/ports/graphics/qt6-wayland clean </dev/null || return 1
        make -C /usr/ports/graphics/qt6-wayland BATCH=yes install clean </dev/null || return 1
        mark_pkg_compiled "qt6-wayland"
    fi

    if is_pkg_compiled "plasma6-kwin"; then
        echo " -> [SKIP] plasma6-kwin is already compiled from ports."
        mark_pkg_compiled "plasma6-kwin"
    else
        echo " -> [BUILD] Compiling x11-wm/plasma6-kwin from ports with EGL..."
        pkg unlock -yq plasma6-kwin 2>/dev/null || true
        pkg delete -y -f plasma6-kwin 2>/dev/null || true
        make -C /usr/ports/x11-wm/plasma6-kwin clean </dev/null || return 1
        make -C /usr/ports/x11-wm/plasma6-kwin BATCH=yes install clean </dev/null || return 1
        mark_pkg_compiled "plasma6-kwin"
    fi

    if is_pkg_compiled "sddm"; then
        echo " -> [SKIP] sddm is already compiled from ports."
        mark_pkg_compiled "sddm"
    else
        echo " -> [BUILD] Compiling x11/sddm from ports..."
        pkg unlock -yq sddm 2>/dev/null || true
        pkg delete -y -f sddm 2>/dev/null || true
        make -C /usr/ports/x11/sddm clean </dev/null || return 1
        make -C /usr/ports/x11/sddm BATCH=yes install clean </dev/null || return 1
        mark_pkg_compiled "sddm"
    fi

    # --------------------------------------------------------------------------
    # STEP 5: SDDM & NATIVE WAYLAND SESSION CONFIGURATION
    # --------------------------------------------------------------------------
    echo "[5/5] Configuring SDDM and native Plasma 6 Wayland session..."

    mkdir -p /usr/local/etc/sddm.conf.d
    mkdir -p /usr/local/share/sddm/scripts
    mkdir -p /usr/local/bin
    mkdir -p /usr/local/share/wayland-sessions

    cat > /usr/local/etc/sddm.conf.d/10-x11-backend.conf << 'EOF'
[General]
DisplayServer=x11
EOF

    if [ ! -f /usr/local/etc/sddm.conf.d/20-theme.conf ] || grep -q "maldives" /usr/local/etc/sddm.conf.d/20-theme.conf 2>/dev/null; then
        cat > /usr/local/etc/sddm.conf.d/20-theme.conf << 'EOF'
[Theme]
Current=breeze
EOF
    fi

    if [ -f /usr/local/share/wayland-sessions/plasma.desktop ]; then
        sed -i '' 's|^Exec=.*|Exec=/usr/local/bin/startplasma-wayland|' /usr/local/share/wayland-sessions/plasma.desktop
    fi

    # SDDM Wayland session script:
    # - Explicitly unsets KWIN_DRM_NO_AMS (NVIDIA DRM requires Atomic Mode Setting!)
    # - Sets KWIN_DRM_NO_MODIFIERS=1 to fix GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT on NVIDIA
    # - Uses ck-launch-session + dbus-run-session for proper ConsoleKit2 session & VT switch
    cat > /usr/local/share/sddm/scripts/wayland-session << 'EOF'
#!/bin/sh
unset DISPLAY
unset XAUTHORITY
unset KWIN_DRM_NO_AMS

case "${LANG:-}" in
    *.UTF-8|*.utf8) ;;
    *) export LANG="C.UTF-8" ;;
esac

export KWIN_FORCE_SW_CURSOR=1
export WLR_NO_HARDWARE_CURSORS=1
export KWIN_DRM_NO_MODIFIERS=1
export NVIDIA_DRM_MODESET=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export QT_QPA_PLATFORM="wayland;xcb"
export LIBSEAT_BACKEND=seatd

export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u)
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f /tmp/wayland-* 2>/dev/null || true

exec /usr/local/bin/ck-launch-session /usr/local/bin/dbus-run-session /usr/local/bin/startplasma-wayland > /tmp/plasma-wayland.log 2>&1
EOF
    chmod 555 /usr/local/share/sddm/scripts/wayland-session

    cat > /usr/local/etc/sddm.conf.d/wayland-session.conf << 'EOF'
[Wayland]
SessionCommand=/usr/local/share/sddm/scripts/wayland-session
SessionScript=/usr/local/share/sddm/scripts/wayland-session
SessionDir=/usr/local/share/wayland-sessions
EOF

    cat > /usr/local/bin/start-plasma-wayland.sh << 'EOF'
#!/bin/sh
unset DISPLAY
unset XAUTHORITY
unset KWIN_DRM_NO_AMS

case "${LANG:-}" in
    *.UTF-8|*.utf8) ;;
    *) export LANG="C.UTF-8" ;;
esac

export KWIN_FORCE_SW_CURSOR=1
export WLR_NO_HARDWARE_CURSORS=1
export KWIN_DRM_NO_MODIFIERS=1
export NVIDIA_DRM_MODESET=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export QT_QPA_PLATFORM="wayland;xcb"
export LIBSEAT_BACKEND=seatd

export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u)
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f /tmp/wayland-* 2>/dev/null || true

exec /usr/local/bin/ck-launch-session /usr/local/bin/dbus-run-session /usr/local/bin/startplasma-wayland > /tmp/plasma-wayland.log 2>&1
EOF
    chmod 555 /usr/local/bin/start-plasma-wayland.sh

    # Terminate any stuck background Wayland session from earlier attempts
    killall -9 kwin_wayland startplasma-wayland </dev/null >/dev/null 2>&1 || true

    echo "=========================================================================="
    echo " Native Wayland configuration (v2.4) complete!"
    echo " Run 'reboot' (recommended so loader.conf DRM modeset is active)"
    echo " or 'service sddm restart', then select 'Plasma (Wayland)'."
    echo "=========================================================================="
    return 0
}

# Run setup and capture exit code reliably across pipeline
{
    if execute_wayland_setup; then
        echo "0" > "$STATUS_FILE"
    else
        echo "1" > "$STATUS_FILE"
    fi
} 2>&1 | tee -a "$LOG_FILE"

EXEC_RES=$(cat "$STATUS_FILE" 2>/dev/null || echo "1")
rm -f "$STATUS_FILE"

if [ "$EXEC_RES" -eq 0 ]; then
    beep_success
    exit 0
else
    echo "[Error] An error occurred during execution. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
    beep_error
    exit 1
fi