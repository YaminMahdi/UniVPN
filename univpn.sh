#!/bin/bash
# UniVPN Portable Launcher for Linux

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
