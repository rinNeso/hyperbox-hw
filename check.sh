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

echo "== pacman watchlist =="
same "$R/pacman/bin/hw-watchlist-check"     /usr/local/bin/hw-watchlist-check      "hw-watchlist-check"
same "$R/pacman/hw-watchlist.conf"          /etc/pacman.d/hw-watchlist.conf        "hw-watchlist.conf"
same "$R/pacman/hooks/00-hw-watchlist.hook" /etc/pacman.d/hooks/00-hw-watchlist.hook "00-hw-watchlist.hook"

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
