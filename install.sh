#!/usr/bin/env bash
# Interactive installer for Phantomscope.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src
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
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
bold "Checking prerequisites"
missing=()
for c in gamescope python3 kscreen-doctor; do
    command -v "$c" >/dev/null || missing+=("$c")
done
python3 -c 'import PySide6' 2>/dev/null || missing+=("python3-pyside6")
[ ${#missing[@]} -eq 0 ] || die "missing: ${missing[*]}
On Fedora/Nobara: sudo dnf install gamescope python3-pyside6 kscreen"

command -v kdotool >/dev/null || warn "  kdotool not found -- needed to place gamescope on the phantom display"
command -v steam   >/dev/null || warn "  steam not found -- Phantomscope launches Steam inside gamescope"
[ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ] || warn "  this is a KDE Plasma tool; XDG_CURRENT_DESKTOP is '${XDG_CURRENT_DESKTOP:-unset}'"
echo "  ok"
echo

# --------------------------------------------------------------- choose mode
bold "Which install?"
cat <<'MENU'
  1) full  - phantom display + gamescope. Adds a fake output on an unused
             connector so the session has somewhere to live that is not your
             monitor. Needs root once (a helper plus a NOPASSWD sudoers rule).
  2) lite  - gamescope only. No phantom display, no root, no sudoers. The GUI
             shows just "This desktop".
MENU
read -rp "Choice [1/2]: " choice
case ${choice:-} in
    1) MODE=full ;;
    2) MODE=lite ;;
    *) die "pick 1 or 2" ;;
esac
echo

# ---------------------------------------------------- choose a connector
CONNECTOR=""
if [ "$MODE" = full ]; then
    bold "Which connector should the phantom display use?"
    echo "  Pick a port you do not use. Its EDID is overridden while running,"
    echo "  and restored on uninstall."
    echo
    mapfile -t conns < <(for s in /sys/class/drm/card*-*/status; do
        d=${s%/status}; n=${d##*/}; n=${n#*-}
        case $n in Writeback*) continue ;; esac
        printf '%s\t%s\n' "$n" "$(cat "$s")"
    done | sort -u)
    [ ${#conns[@]} -gt 0 ] || die "no display connectors found"
    i=0
    for row in "${conns[@]}"; do
        i=$((i + 1))
        name=${row%%$'\t'*}; state=${row##*$'\t'}
        if [ "$state" = connected ]; then
            printf '  %d) %-12s %s  <- in use, not recommended\n' "$i" "$name" "$state"
        else
            printf '  %d) %-12s %s\n' "$i" "$name" "$state"
        fi
    done
    read -rp "Choice [1-$i]: " pick
    [[ $pick =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ] || die "pick 1-$i"
    row=${conns[$((pick - 1))]}
    CONNECTOR=${row%%$'\t'*}
    if [ "${row##*$'\t'}" = connected ]; then
        read -rp "$CONNECTOR has a real display attached. Use it anyway? [y/N]: " yes
        [[ ${yes:-} =~ ^[Yy]$ ]] || die "aborted"
    fi
    echo "  using $CONNECTOR"
    echo
fi

# ------------------------------------------------------------------ install
bold "Installing"
install -d "$BIN" "$APPS" "$CONFDIR"
install -m 755 "$SRC/phantomscope" "$BIN/phantomscope"
echo "  $BIN/phantomscope"

if [ "$MODE" = full ]; then
    install -m 755 "$SRC/phantom-display" "$BIN/phantom-display"
    echo "  $BIN/phantom-display"

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    python3 -I "$SRC/make-edid.py" > "$tmp/edid.bin"
    python3 -I "$SRC/verify-edid.py" "$tmp/edid.bin" >/dev/null || die "generated EDID failed validation"

    echo "  (root) $SYSSHARE/edid.bin, $SYSBIN/phantom-display-helper, $SUDOERS"
    "${SUDO[@]}" install -d -m 755 -o root -g root "$SYSSHARE"
    "${SUDO[@]}" install -m 644 -o root -g root "$tmp/edid.bin" "$SYSSHARE/edid.bin"
    "${SUDO[@]}" install -m 755 -o root -g root "$SRC/phantom-display-helper" "$SYSBIN/phantom-display-helper"
    printf '%s ALL=(root) NOPASSWD: %s\n' "$USER" "$SYSBIN/phantom-display-helper" > "$tmp/sudoers"
    "${SUDO[@]}" install -m 440 -o root -g root "$tmp/sudoers" "$SUDOERS"
    "${SUDO[@]}" visudo -c -f "$SUDOERS" >/dev/null || { "${SUDO[@]}" rm -f "$SUDOERS"; die "sudoers rule rejected"; }
fi

sed -e "s|@BIN@|$BIN|g" "$SRC/phantomscope.desktop.in" > "$APPS/phantomscope.desktop"
echo "  $APPS/phantomscope.desktop"

cat > "$CONFDIR/config" <<CONF
# Written by Phantomscope's installer. Safe to edit.
MODE=$MODE
CONNECTOR=$CONNECTOR
CONF
echo "  $CONFDIR/config"

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
echo

bold "Done"
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) warn "  $BIN is not on your PATH" ;;
esac
if [ "$MODE" = full ]; then
    echo "  Launch 'Phantomscope', press Start phantom, then pick a resolution."
else
    echo "  Launch 'Phantomscope' and use the 'This desktop' option."
fi
echo "  Uninstall with ./uninstall.sh"
