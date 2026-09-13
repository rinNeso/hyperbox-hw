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

say "diagnostics"
install -Dm755 "$R/bin/egpu-check.sh" /usr/local/bin/egpu-check

say "pacman hardware watchlist"
install -Dm755 "$R/pacman/bin/hw-watchlist-check"    /usr/local/bin/hw-watchlist-check
install -Dm644 "$R/pacman/hw-watchlist.conf"         /etc/pacman.d/hw-watchlist.conf
install -Dm644 "$R/pacman/hooks/00-hw-watchlist.hook" /etc/pacman.d/hooks/00-hw-watchlist.hook

if [[ -n $USER_NAME && -d $USER_HOME ]]; then
    say "kitty override for the update tray (user: $USER_NAME)"
    install -Dm644 -o "$USER_NAME" -g "$USER_NAME" \
        "$R/desktop/arch-update.desktop" \
        "$USER_HOME/.local/share/applications/arch-update.desktop"

    say "open-webui user unit (user: $USER_NAME)"
    install -Dm644 -o "$USER_NAME" -g "$USER_NAME" \
        "$R/services/open-webui.service" \
        "$USER_HOME/.config/systemd/user/open-webui.service"
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
