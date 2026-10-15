#!/usr/bin/env bash
# Remove Phantomscope and hand the connector back to the kernel.
set -euo pipefail

PREFIX=${PREFIX:-$HOME/.local}
BIN=$PREFIX/bin
APPS=$PREFIX/share/applications
CONFDIR=${XDG_CONFIG_HOME:-$HOME/.config}/phantomscope
SYSBIN=/usr/local/sbin
SYSSHARE=/usr/local/share/phantomscope
SUDOERS=/etc/sudoers.d/phantomscope

# Root is needed a few times. Prefer a graphical prompt when there is no
# terminal to type a password into (launched from a file manager, piped, ...).
if [ -t 0 ]; then
    SUDO=(sudo)
else
    ASKPASS=${SUDO_ASKPASS:-/usr/bin/ksshaskpass}
    if [ -x "$ASKPASS" ] && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
        SUDO=(env "SUDO_ASKPASS=$ASKPASS" sudo -A)
    else
        SUDO=(sudo)
    fi
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

MODE=full
CONNECTOR=""
# shellcheck disable=SC1090
[ -r "$CONFDIR/config" ] && . "$CONFDIR/config"

bold "Removing Phantomscope"

# Stop the GUI so it cannot re-raise anything mid-uninstall.
pkill -f "^python3 .*${BIN}/phantomscope" 2>/dev/null && echo "  stopped running app" || true

# Hand the port back first -- while the helper that can do it still exists.
if [ -n "$CONNECTOR" ] && [ -x "$SYSBIN/phantom-display-helper" ]; then
    echo "  restoring $CONNECTOR"
    if [ -x "$BIN/phantom-display" ]; then
        "$BIN/phantom-display" off >/dev/null 2>&1 || true
    fi
    "${SUDO[@]}" "$SYSBIN/phantom-display-helper" off "$CONNECTOR" >/dev/null 2>&1 \
        || warn "  could not reset $CONNECTOR; a reboot clears it regardless"
    for s in /sys/class/drm/*-"$CONNECTOR"/status; do
        state=$(cat "$s" 2>/dev/null || echo unknown)
        echo "  $CONNECTOR now reports: $state"
        break
    done
fi

if [ -e "$SYSBIN/phantom-display-helper" ] || [ -e "$SUDOERS" ] || [ -d "$SYSSHARE" ]; then
    echo "  (root) removing helper, sudoers rule and EDID"
    "${SUDO[@]}" rm -f "$SYSBIN/phantom-display-helper" "$SUDOERS"
    "${SUDO[@]}" rm -rf "$SYSSHARE"
fi

rm -f "$BIN/phantomscope" "$BIN/phantom-display" "$APPS/phantomscope.desktop"
rm -rf "$CONFDIR"
echo "  removed user files"

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true

bold "Done"
echo "  Nothing of Phantomscope remains. The EDID override was never"
echo "  persistent, so the connector is back to normal either way."
