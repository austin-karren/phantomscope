# Phantomscope

Stream a 16:9 Steam Remote Play session from an ultrawide (or any
awkwardly-shaped) KDE Plasma host, without touching the monitor you are
actually sitting in front of.

It does two things:

- **Phantom display** — forces a fake EDID onto an unused display connector,
  so a real output of your chosen size exists in the compositor. Nothing is
  plugged into it.
- **Gamescope launcher** — runs Steam inside a nested gamescope at a fixed
  resolution and places that window on the phantom display, 1:1.

## Why

Steam's host-side **"Streaming display resolution → Match Client"** does not
exist on Linux. The setting is in the client, but `steamui/sp.js` gates the
whole block on `Cn.length > 1`, where `Cn` is built from `RefreshMonitorInfo()`
— and the Linux host enumerates zero monitors. The same code special-cases
`SUDOVDA`, Sunshine's Windows-only virtual display driver, which tells you
what platform the feature was written for.

So a 3440×1440 host streaming to a 16:9 TV sends 21:9, and the client
letterboxes and squashes it.

Two things turned out to matter, in this order:

1. **gamescope must be 1:1.** Running it fullscreen (`-f`) fits its internal
   surface into the host window, and *that rescale reaches the client*.
   Borderless (`-b`) at exactly the internal size does not.
2. **The window needs somewhere to live.** A 4K borderless window on a
   3440×1440 panel works, but it overflows your desktop. The phantom display
   gives it a home off-screen.

Point 1 is what fixes the stream. Point 2 is ergonomics — which is why `lite`
mode, with no phantom display at all, is a legitimate install.

## Requirements

- **KDE Plasma 6 on Wayland.** Uses `kscreen-doctor` and `kdotool`; there is
  no X11 or GNOME path.
- `gamescope`, `python3-pyside6`, `kscreen`, `kdotool`
- Steam, launched with `-pipewire` (see *Steam and Wayland* below)
- A spare display connector, for `full` mode
- Root once, for `full` mode

Developed and used on **Nobara 44 (KDE), Plasma 6.7.5, kernel 7.2, AMD**.

```
sudo dnf install gamescope python3-pyside6 kscreen kdotool
```

## Install

```
git clone https://github.com/austin-karren/phantomscope
cd phantomscope
./install.sh
```

The installer asks two things:

**Which install**

- `full` — phantom display + gamescope. Installs a small root helper and a
  NOPASSWD sudoers rule scoped to that one program, because the EDID override
  lives in `debugfs` and is root-only.
- `lite` — gamescope only. No phantom display, no root, no sudoers. The GUI
  shows just the **This desktop** section.

**Which connector** (full only) — it lists every connector on the machine with
its current state and recommends the disconnected ones. Pick a port you do not
use. `HDMI-A-2`, a second DisplayPort, anything idle.

## Use

<img width="675" height="675" alt="image" src="https://github.com/user-attachments/assets/0b07d29c-570e-4109-8b37-81509ae5f173" />


Launch **Phantomscope**.

- **Start phantom** brings the fake output up. The fixed resolutions are
  greyed out until it is running, because they have nowhere to go without it.
- **1080p / 2K / 4K / mobile** shut Steam down and restart it inside gamescope
  at that size, on the phantom.
- **native** runs gamescope on your real desktop at its current mode and
  refresh rate, read live — no phantom involved.
- **Stop gamescope and close Steam** stops all three: gamescope, Steam, and
  the phantom display.

Then stream to the client as usual. The client sees whatever gamescope is.

## Uninstall

```
./uninstall.sh
```

It resets the connector *before* removing the helper that can reset it, then
removes the root helper, the sudoers rule, the EDID, both binaries, the
desktop entry and the config. The EDID override was never persistent anyway —
a reboot clears it regardless.

## What it installs

| Path | Mode | Purpose |
|---|---|---|
| `~/.local/bin/phantomscope` | both | the GUI |
| `~/.local/bin/phantom-display` | full | `on` / `off` / `status` / `is-up` |
| `~/.local/share/applications/phantomscope.desktop` | both | menu entry |
| `~/.config/phantomscope/config` | both | mode + connector |
| `/usr/local/sbin/phantom-display-helper` | full | the debugfs writes, root-owned |
| `/usr/local/share/phantomscope/edid.bin` | full | the fake EDID |
| `/etc/sudoers.d/phantomscope` | full | NOPASSWD for that one program |

The sudoers rule grants passwordless root for a single fixed program that
takes no caller-supplied paths and only accepts a connector the kernel already
knows about. It is needed because the GUI toggles the display while you are
using it, and a password prompt per toggle is unusable.

## Notes and limitations

**Immutable Fedora (Silverblue, Kinoite, Bazzite) is untested and
unsupported.** It may well work — `/etc` is writable and `/usr/local` is a
symlink into `/var`, so nothing the installer writes lands on the read-only
deployment — but none of it has been tried, and the project does not support
it. The EDID override itself is pure runtime `debugfs` and is unaffected by
image immutability.

**The EDID override is runtime-only.** It never writes to your bootloader or
`/etc/modprobe.d`. A reboot always clears it.

**The fake EDID advertises 3840×2160 and 1920×1080.** The kernel derives the
intermediate CVT modes from the range-limit descriptor, which is why 2560×1440
works too. It uses CVT reduced blanking at 533 MHz rather than the 594 MHz CEA
timing a real 4K TV reports — both are legal, and 594 sits exactly at the
HDMI 2.0 TMDS ceiling with no headroom if the driver validates strictly.
Nothing is ever transmitted; there is no cable.

**Do not move a gamescope window that already has Steam rendering in it.**
Phantomscope places the window within a second of launch, while gamescope is
still empty. Relocating a live session across outputs coincided with
`failed to create drawable` and a dead session.

**The phantom must not become primary.** KWin makes a freshly hotplugged
output primary on its own, which drags Plasma's panels and desktop containment
onto a screen you cannot see. `phantom-display` pins the previous primary back
in a *separate* `kscreen-doctor` call — set in the same atomic call as the
enable, priority is silently ignored.

**While the phantom is up, KWin puts new windows on it.** Default placement is
centred-on-active-screen and the phantom tends to win, so a game launched
locally can open on a screen you cannot see. This is the main reason the
display is manual: raise it for a session, drop it after.

**There is no automatic mode, deliberately.** An earlier version watched
Steam's `streaming_log.txt` and raised the display when a client connected. It
thrashed — every connect/disconnect cycle raised and dropped the output, and
each drop relocated whatever was sitting on it. Manual control is the fix, not
a missing feature.

### Steam and Wayland

Steam needs `-pipewire` or desktop capture silently falls back to black
frames, logging `WARNING: Desktop capture unavailable`. To make it stick:

```
cp /usr/share/applications/steam.desktop ~/.local/share/applications/
sed -i 's|^Exec=/usr/bin/steam |Exec=/usr/bin/steam -pipewire |' \
    ~/.local/share/applications/steam.desktop
```

Working capture logs `CDesktopCapturePipeWire: Opening DRM render node`. The
first capture raises a KDE portal prompt asking which screen to share; choose
the phantom display, and the grant persists.

## Troubleshooting

**Nothing appears when I start the phantom.** Check `debugfs` is mounted
(`ls /sys/kernel/debug/dri`) and that the connector exists:
`phantom-display status`.

**Everything renders tiny on the phantom.** KDE's DPI heuristic picked a
fractional scale. `phantom-display` pins scale to 1; if you changed it in
System Settings, set it back.

**My panels moved to the phantom.** Something made it primary. Drop the
phantom and set your real monitor back to priority 1 in System Settings.

**The stream is still the wrong shape.** Confirm gamescope is borderless and
1:1 — `pgrep -a gamescope` should show `-b` and the same `-W`/`-H` as the
window size. `-f` is the failure mode.

## License

MIT
