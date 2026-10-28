# 2026-09-15 — the hardware watchlist aborted a 40-package update

## What happened

`cachy-update` queued 40 packages. The PreTransaction watchlist hook printed
three `warn` lines and one `BLOCK limine`, then the terminal appeared to hang.
Enter was pressed. The transaction aborted; nothing installed.

From `/var/log/pacman.log`:

```
17:27:17 [ALPM] running '00-hw-watchlist.hook'...
17:27:17 [ALPM-SCRIPTLET]   BLOCK limine
17:30:05 [ALPM-SCRIPTLET] Proceed with the blocked package(s)? [y/N]
17:30:05 [ALPM-SCRIPTLET] Transaction aborted by hardware watchlist.
```

Note the timestamps: the prompt and the abort are logged in the same second,
~3 minutes after the BLOCK line. The prompt was never visible while it waited.

## Two separate defects

**1. The prompt was invisible.** The script wrote it with

```bash
printf '%s' "...[y/N] " >&2      # no trailing newline
read -r ans < /dev/tty
echo >&2                          # the newline that finally flushed it
```

pacman relays hook stderr through a pipe, line-buffered, as `[ALPM-SCRIPTLET]`
records. A partial line with no newline sits unflushed. So the terminal looked
hung with no indication it wanted input; the Enter used to probe it was
consumed by `read` as empty, which is the `[y/N]` default N; and the prompt text
only surfaced afterwards, flushed by the `echo` that followed. The keystroke
used to investigate was the one that answered destructively.

**2. "block one package" is not expressible.** A pacman PreTransaction hook is
all-or-nothing: a non-zero exit aborts the *entire* transaction. There is no
mechanism to drop a single target from it. `block|limine` could therefore only
ever mean "block all 40". The surgical tool is `IgnorePkg` in `/etc/pacman.conf`
— which was working correctly in the same run:

```
warning: ddcutil: ignoring package upgrade (2.2.7-1.1 => 3.0.1-1)
```

One package skipped, the rest proceeding. That is the behavior the `block`
severity was reaching for and structurally could not provide.

## Root cause

Severity was conflated. All three `block` entries read, in their own notes, as
*post*-upgrade verification tasks — limine said "Verify /proc/cmdline **after**
upgrading", cachyos-settings said "**After upgrading**, re-check the mask". Only
ddcutil was genuinely must-never-install, and `IgnorePkg` already enforced that.
"This package can hurt this machine" had been encoded as "stop everything",
before a single byte was downloaded, at the one moment when nothing is yet
checkable.

## Fix

- `block` severity removed. There is `warn` (advisory) and `verify` (advisory
  now, real check afterwards).
- `00-hw-watchlist.hook` lost `AbortOnFail`; `hw-watchlist-check` always exits 0
  and no longer prompts. `check.sh` fails if `AbortOnFail` reappears there.
- New `99-hw-verify.hook` → `hw-verify`, PostTransaction, which does the actual
  checking: limine's four cmdline params still in `/etc/default/limine` (and no
  `.pacnew` silently dropping them), no unmasked audio-PM udev rule, ddcutil not
  sitting at 3.0.0. Exits 0 always — the transaction is already committed.
- Must-never-install stays with `IgnorePkg`.

`hw-verify` takes `LIMINE_DEFAULT` / `UDEV_LIB` / `UDEV_ETC` / `PROC_CMDLINE`
overrides so its failure branches are testable. They were tested: stripped
params, a planted `.pacnew`, and an audio-PM rule under a new filename all
report FAIL; the live system reports ok.

One bug was caught that way and is worth keeping in mind — the first draft
filtered candidate udev rules on content matching `snd|audio|hda`, which misses
a rule that says `SUBSYSTEM=="sound"` and never contains those strings. That is
precisely the rule this check exists to catch. It now matches filename and
content, including `sound`.
