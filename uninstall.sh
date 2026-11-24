#!/bin/sh
# UniVPN uninstaller: removes UniVPN completely from this computer.
#
#   sudo /opt/UniVPN/uninstall.sh          # asks before removing
#   sudo /opt/UniVPN/uninstall.sh --yes    # no question
#   /opt/UniVPN/uninstall.sh --keep-certificates   # keep a copy of *.p12/*.pfx
#
# Run without root it re-runs itself through pkexec (or sudo).
set -u

INSTALL_DIR=/opt/UniVPN
# The service (UniVPNCS) reads certificates and certinfo.txt from the UOS
# layout; installs point it at INSTALL_DIR with a symlink.
UOS_DIR=/opt/apps/cn.com.huawei-security-commercial-alliance.univpn
LEGACY_DIR=/usr/local/UniVPN

yes=0
keep=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) yes=1 ;;
        -k|--keep-certificates) keep=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    # Keep the invoking user's home for --keep-certificates.
    self=$(readlink -f "$0")
    if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        exec pkexec env UNIVPN_UNINSTALL_USER="$(id -un)" /bin/sh "$self" "$@"
    fi
    exec sudo UNIVPN_UNINSTALL_USER="$(id -un)" /bin/sh "$self" "$@"
fi

if [ "$yes" -eq 0 ]; then
    if [ -t 0 ]; then
        printf 'Remove UniVPN (%s) and all its settings? [y/N] ' "$INSTALL_DIR"
        read -r answer
        case "$answer" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
    fi
    # No terminal (pkexec from a menu): the authorization prompt is the question.
fi

user=${UNIVPN_UNINSTALL_USER:-${SUDO_USER:-${PKEXEC_UID:+$(id -un "$PKEXEC_UID" 2>/dev/null)}}}

if [ "$keep" -eq 1 ]; then
    home=$(getent passwd "${user:-root}" | cut -d: -f6)
    dest="${home:-/root}/UniVPN-certificates"
    found=0
    for f in "$INSTALL_DIR"/certificate/*.p12 "$INSTALL_DIR"/certificate/*.pfx \
             "$LEGACY_DIR"/certificate/*.p12 "$LEGACY_DIR"/certificate/*.pfx; do
        [ -f "$f" ] || continue
        mkdir -p "$dest"
        cp -p "$f" "$dest/"
        found=1
    done
    if [ "$found" -eq 1 ]; then
        [ -n "$user" ] && chown -R "$user" "$dest" 2>/dev/null
        chmod 700 "$dest"
        echo "Certificates kept in $dest"
    fi
fi

echo "Stopping UniVPN..."
for p in UniVPN UniVPNCS UniVPNPromoteService UniVPNUpdate; do
    pkill -x "$p" 2>/dev/null
done
sleep 1
for p in UniVPN UniVPNCS UniVPNPromoteService UniVPNUpdate; do
    pkill -9 -x "$p" 2>/dev/null
done

echo "Removing files..."
rm -rf "$INSTALL_DIR" "$LEGACY_DIR"
rm -rf "$UOS_DIR"
rmdir /opt/apps 2>/dev/null
rm -f /tmp/UniVPN
rm -f /usr/local/bin/univpn /usr/bin/univpn
for d in /usr/local/share/applications /usr/share/applications /etc/xdg/autostart; do
    rm -f "$d/univpn.desktop" "$d/UniVPN.desktop"
done
for d in /usr/local/share/icons/hicolor /usr/share/icons/hicolor; do
    rm -f "$d"/*/apps/univpn.png "$d"/*/apps/univpn.svg
done

# Per-user leftovers: UniVPN's own "start at login" entry and its settings.
for home in /root /home/*; do
    [ -d "$home" ] || continue
    rm -f "$home/.config/autostart/UniVPNA.desktop" \
          "$home/.local/share/applications/univpn.desktop" \
          "$home/.local/share/applications/UniVPN.desktop" \
          "$home/.local/bin/univpn"
    rm -rf "$home/.config/cn.com.huawei-security-commercial-alliance.univpn"
done

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/local/share/applications 2>/dev/null
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d /usr/local/share/icons/hicolor ]; then
    gtk-update-icon-cache -q -t /usr/local/share/icons/hicolor 2>/dev/null
fi

echo "UniVPN has been removed."
exit 0
