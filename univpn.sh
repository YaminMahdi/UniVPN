#!/bin/bash
# UniVPN Portable Launcher for Linux

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Installed as /usr/local/bin/univpn by install.sh: run the /opt/UniVPN tree.
[ -x "$DIR/UniVPN" ] || DIR=/opt/UniVPN
cd "$DIR"

export DISPLAY="${DISPLAY:-:0}"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$DIR/plugins"
unset KDE_FULL_SESSION
unset KDE_SESSION_VERSION
export XDG_CURRENT_DESKTOP='X-Generic'
export DESKTOP_SESSION='X-Generic'
export QT_STYLE_OVERRIDE='Fusion'

BIN="$DIR/UniVPN"

if [ -f "$DIR/theme.qss" ]; then
    exec "$BIN" -stylesheet "$DIR/theme.qss" "$@"
else
    exec "$BIN" "$@"
fi
