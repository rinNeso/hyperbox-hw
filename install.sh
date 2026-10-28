#!/usr/bin/env bash
# Apply this repo to the running system. Idempotent -- safe to re-run.
#   sudo ./install.sh
set -euo pipefail

R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

# The desktop override belongs to the invoking user, not root.
USER_NAME="${SUDO_USER:-}"
USER_HOME="$(getent passwd "${USER_NAME:-root}" | cut -d: -f6)"

say() { printf '\n== %s\n' "$*"; }

say "udev rules"
install -Dm644 "$R/udev/81-egpu-no-runtime-pm.rules"  /etc/udev/rules.d/81-egpu-no-runtime-pm.rules
install -Dm644 "$R/udev/82-egpu-pin-pm-trigger.rules" /etc/udev/rules.d/82-egpu-pin-pm-trigger.rules
# 0-byte file masking cachyos-settings' audio PM rule. Must stay empty.
install -Dm644 /dev/null /etc/udev/rules.d/20-audio-pm.rules
udevadm control --reload

say "modprobe: keep snd_hda_intel out of runtime PM"
install -Dm644 "$R/modprobe/hda-egpu-pm.conf" /etc/modprobe.d/hda-egpu-pm.conf

say "eGPU D0 pin service"
install -Dm755 "$R/bin/egpu-pin-pm"            /usr/local/bin/egpu-pin-pm
install -Dm644 "$R/systemd/egpu-pin-pm.service" /etc/systemd/system/egpu-pin-pm.service
systemctl daemon-reload
systemctl enable --now egpu-pin-pm.service

say "ollama iGPU/Vulkan override"
install -Dm644 "$R/services/ollama-override.conf" /etc/systemd/system/ollama.service.d/override.conf
systemctl daemon-reload
# The override binds ollama to the LAN for HeilandBay's /summary bot. Ollama has
# no auth, so this rule is the only thing keeping the rest of the LAN out.
ufw allow proto tcp from 192.168.0.69 to any port 11434 comment 'ollama for HeilandBay summary bot'

say "journal retention"
# cachyos-settings caps the journal at 50M (~1 day). Same basename in /etc wins.
install -Dm644 "$R/systemd/journald-size.conf" /etc/systemd/journald.conf.d/00-journal-size.conf
systemctl restart systemd-journald

say "diagnostics"
install -Dm755 "$R/bin/egpu-check.sh"        /usr/local/bin/egpu-check
install -Dm755 "$R/bin/hdmi-capture.sh"      /usr/local/bin/hdmi-capture
install -Dm755 "$R/bin/cachy-update-window"  /usr/local/bin/cachy-update-window

say "pacman hardware watchlist"
install -Dm755 "$R/pacman/bin/hw-watchlist-check"     /usr/local/bin/hw-watchlist-check
install -Dm755 "$R/pacman/bin/hw-verify"              /usr/local/bin/hw-verify
install -Dm644 "$R/pacman/hw-watchlist.conf"          /etc/pacman.d/hw-watchlist.conf
install -Dm644 "$R/pacman/hooks/00-hw-watchlist.hook" /etc/pacman.d/hooks/00-hw-watchlist.hook
install -Dm644 "$R/pacman/hooks/99-hw-verify.hook"    /etc/pacman.d/hooks/99-hw-verify.hook

if [[ -n $USER_NAME && -d $USER_HOME ]]; then
    say "kitty override for the update tray (user: $USER_NAME)"
    install -Dm644 -o "$USER_NAME" -g "$USER_NAME" \
        "$R/desktop/arch-update.desktop" \
        "$USER_HOME/.local/share/applications/arch-update.desktop"

    say "open-webui user unit (user: $USER_NAME)"
    install -Dm644 -o "$USER_NAME" -g "$USER_NAME" \
        "$R/services/open-webui.service" \
        "$USER_HOME/.config/systemd/user/open-webui.service"

    # The tray resolves arch-update.desktop ONCE at startup and caches it, so a
    # tray that was already running keeps launching konsole no matter what the
    # file says. Installing the override without this is a silent no-op for the
    # rest of the session -- that is exactly how it went unnoticed for 2 days.
    say "restart the update tray so it picks up the kitty override"
    pkill -u "$USER_NAME" -f '/arch-update-tray' || true
    sleep 1
    # The tray is a GUI client: without WAYLAND_DISPLAY it cannot reach the
    # compositor and exits immediately, leaving no tray until next login.
    # Take the whole display env from the running session rather than guessing.
    _uid=$(id -u "$USER_NAME")
    _sess=$(pgrep -u "$USER_NAME" -x plasmashell | head -1)
    if [[ -n $_sess ]]; then
        _wl=$(tr '\0' '\n' < "/proc/$_sess/environ" | grep -m1 '^WAYLAND_DISPLAY=' || echo WAYLAND_DISPLAY=wayland-0)
        _dp=$(tr '\0' '\n' < "/proc/$_sess/environ" | grep -m1 '^DISPLAY=' || true)
        runuser -u "$USER_NAME" -- env \
            XDG_RUNTIME_DIR="/run/user/$_uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$_uid/bus" \
            "$_wl" ${_dp:+"$_dp"} \
            setsid arch-update --tray >/dev/null 2>&1 &
        sleep 2
        pgrep -u "$USER_NAME" -f '/arch-update-tray' >/dev/null \
            && echo "   tray restarted" \
            || echo "   WARNING: tray did not come back -- start it from the session"
    else
        echo "   no graphical session found; tray will start at next login"
    fi
fi

cat <<'NOTE'

== manual steps not automated here ==
  1. Kernel parameters -- see kernel/cmdline.md. Edit /etc/default/limine,
     then: sudo limine-update      (nothing else in this repo works without these)
  2. If ddcutil 3.0.1+ is still not in the repos, hold it:
       pacman -U /var/cache/pacman/pkg/ddcutil-2.2.7-*.pkg.tar.zst
       add  IgnorePkg = ddcutil  to /etc/pacman.conf
  3. Reboot, then verify:  ./check.sh  &&  egpu-check 0
NOTE
