#!/usr/bin/env bash
# blocked-module-popup.sh - desktop popup on every blocked module load.
#
# Source: contributed by @teou1 (GitHub issue #12, 2026-05-24).
# Cherry-picked into the modulejail repo with the author's explicit
# permission. See: https://github.com/jnuyens/modulejail/issues/12
#
# What it does: tails `journalctl -t modulejail` and fires a `notify-send`
# popup for each line. modulejail emits one such line per blocked module-
# load attempt when syslog visibility is enabled (the v1.2.0 default; see
# `man 8 modulejail` -> SYSLOG VISIBILITY).
#
# Why it's an example, not a modulejail feature: a popup means a longer-
# running thing watching the journal, which would cross the v1 "no
# daemons" line in CLAUDE.md / PROJECT.md. The popup itself is on the
# v2.0-alpha "Managed Mode" roadmap. This script side-steps the contract
# by being separately operator-launched (typically as a user-session
# unit or a desktop autostart entry), not started by modulejail itself.
#
# Requirements: bash, journalctl, libnotify (notify-send). All standard
# on systemd + desktop-environment hosts.
#
# Usage:
#   ./blocked-module-popup.sh &              # one-shot foreground/background
#   systemctl --user enable --now \         # persistent user-session unit
#       modulejail-popup.service             # (operator writes the unit)
#
# initial sleep so that a bunch of blocked modules at boot are not showed
sleep 37

journalctl -f -t modulejail --since "1 sec ago" -o cat | while read -r LINE; do
#    if echo "$LINE" | grep -E "blocked" --ignore-case; then
        notify-send "Modulejail" "$LINE" --icon=dialog-warning
#    fi
done
