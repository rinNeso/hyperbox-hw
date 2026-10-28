#!/usr/bin/env bash
# Report drift between this repo and the running system. Read-only; no sudo needed.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok=0; bad=0
green=$'\e[32m'; red=$'\e[31m'; yel=$'\e[33m'; dim=$'\e[2m'; rst=$'\e[0m'
pass() { echo "  ${green}ok${rst}   $*"; ok=$((ok+1)); }
fail() { echo "  ${red}DRIFT${rst} $*"; bad=$((bad+1)); }
warn() { echo "  ${yel}warn${rst} $*"; }

same() { # repo_file live_file label
    if [[ ! -e $2 ]]; then fail "$3 -- missing on system"
    elif diff -q "$1" "$2" >/dev/null 2>&1; then pass "$3"
    else fail "$3 -- differs from repo"; fi
}

echo "== kernel cmdline =="
for p in amdgpu.runpm=0 snd_hda_intel.power_save=0 \
         snd_hda_intel.power_save_controller=N pcie_port_pm=off; do
    grep -qw -- "$p" /proc/cmdline && pass "$p" || fail "$p -- NOT ACTIVE"
done

echo "== udev =="
same "$R/udev/81-egpu-no-runtime-pm.rules"  /etc/udev/rules.d/81-egpu-no-runtime-pm.rules  "81-egpu-no-runtime-pm.rules"
same "$R/udev/82-egpu-pin-pm-trigger.rules" /etc/udev/rules.d/82-egpu-pin-pm-trigger.rules "82-egpu-pin-pm-trigger.rules"
if [[ -e /etc/udev/rules.d/20-audio-pm.rules && ! -s /etc/udev/rules.d/20-audio-pm.rules ]]; then
    pass "20-audio-pm.rules mask (0 bytes)"
else
    fail "20-audio-pm.rules mask missing or non-empty -- audio runtime PM may be live"
fi

same "$R/modprobe/hda-egpu-pm.conf" /etc/modprobe.d/hda-egpu-pm.conf "hda-egpu-pm.conf"

echo "== eGPU power pinning (live state) =="
for d in 0000:00:03.1 0000:c2:00.0 0000:c3:00.0 0000:c4:00.0 0000:c4:00.1; do
    [[ -e /sys/bus/pci/devices/$d ]] || { warn "$d not present"; continue; }
    c=$(cat "/sys/bus/pci/devices/$d/power/control" 2>/dev/null)
    z=$(cat "/sys/bus/pci/devices/$d/d3cold_allowed" 2>/dev/null)
    [[ $c == on && $z == 0 ]] && pass "$d control=$c d3cold=$z" \
                              || fail "$d control=$c d3cold=$z (want on/0)"
done
systemctl is-active --quiet egpu-pin-pm.service && pass "egpu-pin-pm.service active" \
                                                || fail "egpu-pin-pm.service not active"

echo "== journal retention =="
same "$R/systemd/journald-size.conf" /etc/systemd/journald.conf.d/00-journal-size.conf "journald-size.conf"
cap=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' | tail -1)
oldest=$(journalctl --list-boots 2>/dev/null | awk 'NR==2{print $3}')
[[ -n $oldest ]] && warn "journal reaches back to $oldest (using $cap)"

echo "== update tray (kitty override) =="
tray_desktop="$HOME/.local/share/applications/arch-update.desktop"
same "$R/desktop/arch-update.desktop" "$tray_desktop" "arch-update.desktop"
# The override only takes effect for a tray started AFTER it was written --
# the applet reads the desktop file once at startup. A stale tray silently
# keeps using konsole.
# kitty --hold reopens at an interactive $SHELL (zsh -> p10k wizard here).
# The launcher must use the wrapper, never --hold.
if grep -q -- '--hold' "$tray_desktop" 2>/dev/null; then
    fail "arch-update.desktop uses kitty --hold -- it will drop to a zsh prompt and run the p10k wizard"
elif [[ -x /usr/local/bin/cachy-update-window ]]; then
    pass "update window uses the no-shell wrapper"
else
    warn "cachy-update-window wrapper not installed"
fi

tray_pid=$(pgrep -f '/arch-update-tray' | head -1)
if [[ -z $tray_pid ]]; then
    warn "no arch-update tray running"
elif [[ ! -e $tray_desktop ]]; then
    :  # already reported by same() above
elif [[ $(stat -c %Y "/proc/$tray_pid") -ge $(stat -c %Y "$tray_desktop") ]]; then
    pass "tray (pid $tray_pid) started after the override"
else
    fail "tray (pid $tray_pid) predates the override -- still launching konsole; pkill -f /arch-update-tray"
fi

echo "== pacman watchlist =="
same "$R/pacman/bin/hw-watchlist-check"     /usr/local/bin/hw-watchlist-check      "hw-watchlist-check"
same "$R/pacman/bin/hw-verify"              /usr/local/bin/hw-verify               "hw-verify"
same "$R/pacman/hw-watchlist.conf"          /etc/pacman.d/hw-watchlist.conf        "hw-watchlist.conf"
same "$R/pacman/hooks/00-hw-watchlist.hook" /etc/pacman.d/hooks/00-hw-watchlist.hook "00-hw-watchlist.hook"
same "$R/pacman/hooks/99-hw-verify.hook"    /etc/pacman.d/hooks/99-hw-verify.hook   "99-hw-verify.hook"
# A PreTransaction hook cannot skip one package -- AbortOnFail there kills the
# whole transaction. It must stay out of 00-hw-watchlist.hook.
if grep -q '^AbortOnFail' /etc/pacman.d/hooks/00-hw-watchlist.hook 2>/dev/null; then
    fail "00-hw-watchlist.hook has AbortOnFail -- it will abort entire transactions"
else
    pass "watchlist pre-hook is advisory (no AbortOnFail)"
fi

echo "== local LLM stack =="
same "$R/services/ollama-override.conf" /etc/systemd/system/ollama.service.d/override.conf "ollama override"
same "$R/services/open-webui.service"   "$HOME/.config/systemd/user/open-webui.service"      "open-webui.service"
if ollama list 2>/dev/null | tail -n +2 | grep -qiE 'cloud|remote'; then
    fail "a cloud-backed ollama model is present -- this stack is local-only"
else
    pass "ollama models are local-only"
fi
ext=$(ss -tnp 2>/dev/null | grep open-webui | grep -vcE '127\.0\.0\.1|\[::1\]|192\.168\.')
[[ ${ext:-0} -eq 0 ]] && pass "open-webui has no external connections" \
                      || fail "open-webui has $ext external connection(s)"
# ollama listens on the LAN for the HeilandBay /summary bot and has no auth, so
# ufw is the only gate: 11434 must be open to 192.168.0.69 and nothing wider.
o=$(grep -E '^### tuple ### allow (tcp|any) 11434 ' /etc/ufw/user.rules 2>/dev/null)
if [[ -z $o ]]; then
    fail "no ufw rule for ollama :11434 -- HeilandBay's summary bot can't reach it"
elif grep -vqE ' 192\.168\.0\.69 in' <<<"$o"; then
    fail "ufw opens ollama :11434 wider than HeilandBay (192.168.0.69)"
else
    pass "ollama :11434 reachable from HeilandBay only"
fi

echo "== package holds =="
if grep -qE '^\s*IgnorePkg.*\bddcutil\b' /etc/pacman.conf 2>/dev/null; then
    pass "ddcutil pinned via IgnorePkg ($(pacman -Q ddcutil 2>/dev/null))"
else
    v=$(pacman -Q ddcutil 2>/dev/null | awk '{print $2}')
    case $v in
        3.0.0*) fail "ddcutil $v installed and NOT pinned -- see incidents/2026-09-13" ;;
        *)      warn "ddcutil not pinned (currently $v) -- fine if >= 3.0.1" ;;
    esac
fi

echo
echo "${dim}$ok ok, $bad drifted${rst}"
[[ $bad -eq 0 ]]
