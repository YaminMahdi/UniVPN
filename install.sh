#!/bin/sh
# UniVPN installer: installs this (patched) UniVPN tree to /opt/UniVPN.
#
#   ./install.sh               # install or update, add menu entry and icon
#   ./install.sh --autostart   # also start UniVPN at login
#
# Run without root it re-runs itself through pkexec (or sudo). Certificates,
# settings and logs already in /opt/UniVPN are kept. Remove with uninstall.sh.
set -eu

INSTALL_DIR=/opt/UniVPN
# UniVPNCS (the root service) reads the Login dialog's certificate list and the
# certificate passwords (certinfo.txt) only from this UOS layout.
UOS_DIR=/opt/apps/cn.com.huawei-security-commercial-alliance.univpn
LEGACY_DIR=/usr/local/UniVPN

autostart=0
for arg in "$@"; do
    case "$arg" in
        -a|--autostart) autostart=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

SRC=$(cd "$(dirname "$0")" && pwd -P)
if [ ! -x "$SRC/UniVPN" ] || [ ! -f "$SRC/serviceclient/UniVPNCS" ]; then
    echo "error: $SRC is not a UniVPN tree" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        exec pkexec env UNIVPN_INSTALL_USER="$(id -un)" /bin/sh "$SRC/install.sh" "$@"
    fi
    exec sudo UNIVPN_INSTALL_USER="$(id -un)" /bin/sh "$SRC/install.sh" "$@"
fi

# The user who owns the folders the UniVPN window writes to.
user=${UNIVPN_INSTALL_USER:-${SUDO_USER:-}}
if [ -z "$user" ] && [ -n "${PKEXEC_UID:-}" ]; then
    user=$(id -un "$PKEXEC_UID")
fi
user=${user:-root}
group=$(id -gn "$user")

echo "Stopping UniVPN..."
for p in UniVPN UniVPNCS UniVPNPromoteService UniVPNUpdate; do
    pkill -x "$p" 2>/dev/null || true
done

if [ "$SRC" != "$INSTALL_DIR" ]; then
    echo "Copying to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    # Everything but git metadata, the user's data and logs.
    tar -C "$SRC" --exclude=./.git --exclude=./.gitignore --exclude='./log/*' \
        --exclude='./certificate/*' --exclude='./config/*' --exclude=./sysconfig.ini \
        --exclude=./certinfo.txt -cf - . | tar -C "$INSTALL_DIR" --no-same-owner -xf -
    [ -f "$INSTALL_DIR/sysconfig.ini" ] || cp "$SRC/sysconfig.ini" "$INSTALL_DIR/"
    # Certificates shipped next to the source tree (never overwrite).
    for f in "$SRC"/certificate/*.p12 "$SRC"/certificate/*.pfx; do
        [ -f "$f" ] && [ ! -e "$INSTALL_DIR/certificate/${f##*/}" ] && cp -p "$f" "$INSTALL_DIR/certificate/" || true
    done
fi
chown -R root:root "$INSTALL_DIR"

# The service runs as root without pkexec (as the upstream package does).
chmod 4755 "$INSTALL_DIR/serviceclient/UniVPNCS"
chmod 755 "$INSTALL_DIR/UniVPN" "$INSTALL_DIR/univpn.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh"

# Folders and files the UniVPN window writes to as the user.
mkdir -p "$INSTALL_DIR/certificate" "$INSTALL_DIR/config" "$INSTALL_DIR/log"
touch "$INSTALL_DIR/sysconfig.ini" "$INSTALL_DIR/certinfo.txt"
chown -R "$user:$group" "$INSTALL_DIR/certificate" "$INSTALL_DIR/config" "$INSTALL_DIR/log" \
    "$INSTALL_DIR/sysconfig.ini" "$INSTALL_DIR/certinfo.txt"

# Certificates exported to the old /usr/local location.
for f in "$LEGACY_DIR"/certificate/*.p12 "$LEGACY_DIR"/certificate/*.pfx; do
    [ -f "$f" ] && [ ! -e "$INSTALL_DIR/certificate/${f##*/}" ] \
        && install -m600 -o "$user" -g "$group" "$f" "$INSTALL_DIR/certificate/" || true
done

# Point the service's UOS path at /opt/UniVPN.
mkdir -p "$UOS_DIR"
if [ -d "$UOS_DIR/files" ] && [ ! -L "$UOS_DIR/files" ]; then
    cp -an "$UOS_DIR/files/certificate/." "$INSTALL_DIR/certificate/" 2>/dev/null || true
    rm -rf "$UOS_DIR/files"
fi
ln -sfn "$INSTALL_DIR" "$UOS_DIR/files"

echo "Registering launcher, icon and menu entry..."
install -Dm755 "$INSTALL_DIR/univpn.sh" /usr/local/bin/univpn
install -Dm644 "$INSTALL_DIR/image/logo.png" /usr/local/share/icons/hicolor/128x128/apps/univpn.png
mkdir -p /usr/local/share/applications
cat > /usr/local/share/applications/univpn.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=UniVPN
Comment=UniVPN VPN client
Exec=/usr/local/bin/univpn
Icon=univpn
Terminal=false
Categories=Network;RemoteAccess;
StartupWMClass=UniVPN
DESKTOP
if [ "$autostart" -eq 1 ]; then
    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/univpn.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=UniVPN
Comment=UniVPN VPN client
Exec=/usr/local/bin/univpn
Icon=univpn
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/local/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t /usr/local/share/icons/hicolor || true

echo "UniVPN installed to $INSTALL_DIR. Put .p12 certificates in $INSTALL_DIR/certificate/."
